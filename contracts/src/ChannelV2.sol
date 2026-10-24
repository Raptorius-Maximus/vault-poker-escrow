// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ristretto} from "./Ristretto.sol";
import {Dleq} from "./Dleq.sol";
import {Evidence} from "./Evidence.sol";
import {BettingReplay} from "./BettingReplay.sol";
import {Evaluator7} from "./Evaluator7.sol";

/// ChannelV2 — the cash-game money frame for heads-up poker escrow.
/// See docs/superpowers/plans/2026-08-17-v2-cash-settlement/ for the design
/// record: `phase-2-money-frame.md` (this contract's build brief),
/// `decisions.md` (cross-phase ledger, cited as D<n> below), and
/// `artifact-formats.md` (the normative byte layouts, cited as formats §n).
///
/// This is a *new*, separate contract from V1's `Channel.sol` (D11/D13):
/// V1 stays untouched and live; this ships the declared-depth Session
/// interface, the per-player deposit ledger, raw-digest session-key
/// receipt/marker verification, the `final` good ending with its burn-ledger
/// irrevocability hook, and a dispute *shell* — `openDispute` plus
/// `resolve()`'s never-started/zero-filings/per-duty-bond-fate branches are
/// real; everything richer (in-window misconduct, phase 2 banks, the §5.3
/// marked-live-hand resolution table) is stubbed `NotYetBuilt()` so a later
/// phase fills bodies without interface churn.
///
/// Storage note, worth flagging for the next reader: several per-session
/// fields that could have lived inside the `Session` struct are instead
/// separate top-level mappings keyed by `session` — `markedHand`,
/// `everReceipted`, `hostFiledInWindow`, `guestFiledInWindow`, `burned`,
/// `paidOut`, `receiptAt`. Every design doc that touches these writes them
/// in bracket-mapping notation (`markedHand[session]`, `burned[session]`,
/// ...), and the phase's own build-verification gate greps for the literal
/// text `markedHand[session] > 0` inside `resolve()` — so the mapping form
/// is not just cosmetic, it is what the gate checks against. Everything
/// else (host/guest, session keys, max/bond/deposited, status, the cached
/// highest-`final` fields, per-player burn flags) lives in the `Session`
/// struct.
contract ChannelV2 {
    // ------------------------------------------------------------ D9 / §9
    enum Status {
        None,
        AwaitingGuest,
        Active,
        Disputed,
        Closed
    }

    /// A signed receipt (formats §3). `isFinal` stands in for the wire
    /// field named `final` in the spec/formats prose — `final` is a
    /// reserved word in Solidity, so the struct field is renamed; the
    /// preimage still encodes it as a single 0x00/0x01 byte, unchanged.
    struct Receipt {
        uint64 hand;
        uint32 subseq;
        uint256 hostStack;
        uint256 guestStack;
        uint256 hostDeposit;
        uint256 guestDeposit;
        bool isFinal;
    }

    /// A signed hand-start marker (formats §4), 14 signed fields (AF-32
    /// amendment: `startingChips` appended after `bb` -- the both-signed
    /// chip<->wei anchor; see `_chipBaseline`).
    struct Marker {
        uint64 hand;
        bytes32 receiptHash;
        bytes32 deckRoot;
        bytes32 hostShareRoot;
        bytes32 guestShareRoot;
        bytes32 hostCardPk;
        bytes32 guestCardPk;
        uint8 button;
        uint256 sb;
        uint256 bb;
        uint256 startingChips;
    }

    /// A signed action's preimage fields (formats §5). Not spelled out
    /// verbatim in artifact-formats §9's interface pseudocode — derived
    /// here from §5's field list, per task 5 step 4's instruction. The
    /// signature bytes are a separate parameter on every function that
    /// takes an `Act`, matching §9's shape.
    struct Act {
        uint64 hand;
        uint64 seq;
        uint8 action;
        uint256 amount;
        bytes32 prev;
    }

    /// A posted decryption share plus its triple-check witnesses
    /// (formats §9, spelled out verbatim there).
    struct SharePost {
        uint8 pos;
        bytes32 shareEnc;
        uint256 c;
        uint256 s;
        bytes32[] shareProof;
        bytes32 c1Enc;
        bytes32 c2Enc;
        bytes32[] deckProof;
    }

    /// Per-session storage. Declared complete up front (task 1 step 3) so
    /// later tasks only add behavior, never restructure this.
    struct Session {
        address host;
        address guest;
        address sessionKeyHost;
        address sessionKeyGuest;
        uint256 maxHost;
        uint256 maxGuest;
        uint256 bondHost;
        uint256 bondGuest;
        uint256 depositedHost;
        uint256 depositedGuest;
        Status status;
        uint256 disputeOpenedAt;
        // Cached highest-(hand,subseq) `final` receipt (decision 6: the
        // floor check lives in resolve(), not at filing time — fileReceipt
        // stores unconditionally, resolve() decides if it clears the floor).
        uint64 highestFinalHand;
        uint32 highestFinalSubseq;
        bytes32 highestFinalHash;
        uint256 highestFinalHostStack;
        uint256 highestFinalGuestStack;
        uint256 highestFinalHostDeposit;
        uint256 highestFinalGuestDeposit;
        // Per-player idempotent burn flags (decision 8) — the counters
        // `_burnBond` guards so a caller can never double-burn one bond.
        bool hostBurned;
        bool guestBurned;
    }

    // ------------------------------------------------------------ constants
    // Same literal V1 already uses (Channel.sol:42) for the low-s
    // malleability check — reused verbatim, not re-derived.
    uint256 private constant SECP256K1N_HALF =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    // ------------------------------------------------------------ D15: durations are constructor params
    uint256 public immutable window;
    uint256 public immutable bank;
    uint256 public immutable grace;

    // ------------------------------------------------------------ storage
    // `internal`, not `public`: the `Session` struct has 21 fields, and
    // Solidity's auto-generated public-mapping getter returns the whole
    // struct as one tuple — with this many fields that getter alone blows
    // the legacy (non-IR) codegen's stack budget ("stack too deep") before
    // any of this contract's own logic even runs. This repo's
    // foundry.toml does not set `via_ir`, so the fix is visibility, not a
    // build flag. Narrow, grouped view functions below (`sessionCore`,
    // `sessionBonds`, etc.) provide the same read access in stack-safe
    // slices.
    mapping(bytes32 => Session) internal sessions;

    /// (host, guest, status, maxHost, maxGuest) — the open()/join() shape.
    function sessionCore(bytes32 session)
        external
        view
        returns (address host, address guest, Status status, uint256 maxHost, uint256 maxGuest)
    {
        Session storage s = sessions[session];
        return (s.host, s.guest, s.status, s.maxHost, s.maxGuest);
    }

    /// (sessionKeyHost, sessionKeyGuest) — the registered session-key
    /// addresses (formats §6).
    function sessionKeys(bytes32 session) external view returns (address sessionKeyHost, address sessionKeyGuest) {
        Session storage s = sessions[session];
        return (s.sessionKeyHost, s.sessionKeyGuest);
    }

    /// (bondHost, bondGuest, hostBurned, guestBurned) — decision 1's bond
    /// formula outputs plus decision 8's per-player burn flags.
    function sessionBonds(bytes32 session)
        external
        view
        returns (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned)
    {
        Session storage s = sessions[session];
        return (s.bondHost, s.bondGuest, s.hostBurned, s.guestBurned);
    }

    /// (depositedHost, depositedGuest) — the running deposit ledger.
    function sessionDeposits(bytes32 session) external view returns (uint256 depositedHost, uint256 depositedGuest) {
        Session storage s = sessions[session];
        return (s.depositedHost, s.depositedGuest);
    }

    /// disputeOpenedAt — 0 if no dispute has ever been opened.
    function sessionDisputeOpenedAt(bytes32 session) external view returns (uint256) {
        return sessions[session].disputeOpenedAt;
    }

    /// The cached highest-(hand,subseq) `final` receipt (decision 6) —
    /// what resolve()'s floor check and payout arithmetic read.
    function sessionHighestFinal(bytes32 session)
        external
        view
        returns (
            uint64 hand,
            uint32 subseq,
            bytes32 hash,
            uint256 hostStack,
            uint256 guestStack,
            uint256 hostDeposit,
            uint256 guestDeposit
        )
    {
        Session storage s = sessions[session];
        return (
            s.highestFinalHand,
            s.highestFinalSubseq,
            s.highestFinalHash,
            s.highestFinalHostStack,
            s.highestFinalGuestStack,
            s.highestFinalHostDeposit,
            s.highestFinalGuestDeposit
        );
    }

    // receiptAt[session][hand] = hash of the current highest-subseq receipt
    // filed for that hand (decision 5's continuity dependency).
    mapping(bytes32 => mapping(uint64 => bytes32)) public receiptAt;
    // Internal bookkeeping only (not a signed/wire field, formats.md does
    // not own it): the subseq that produced the entry above, so a later
    // filing at a lower subseq for the same hand does not overwrite a
    // higher one already on file.
    mapping(bytes32 => mapping(uint64 => uint32)) private _receiptSubseqAt;

    /// P3 extension (decision 7, task 3 step 1): the replay engine's
    /// baseline needs the *actual* stacks/deposits of the highest-subseq
    /// receipt at hand N-1, not just its hash — `resolve(session)` takes no
    /// extra parameters and cannot have the caller re-supply the receipt.
    struct ReceiptStacks {
        uint256 hostStack;
        uint256 guestStack;
        uint256 hostDeposit;
        uint256 guestDeposit;
    }

    mapping(bytes32 => mapping(uint64 => ReceiptStacks)) public receiptStacksAt;

    /// P3 extension (decision 7-adjacent — NOT one of decision 7's named
    /// two; disclosed here and flagged as a decision-conflict finding in
    /// this dispatch's completion notes). P2's `_fileMarkerCore` verifies
    /// every marker field against the signed hash but never persists
    /// anything beyond `markedHand` — the hand number alone. Tasks 4
    /// (postShares' triple check needs deckRoot/shareRoots/cardPks) and 6
    /// (consolidation needs button/sb/bb) cannot function without these
    /// fields on chain, since neither function's external signature (§9)
    /// takes the marker as a parameter. Necessary, not optional.
    struct MarkerData {
        bytes32 deckRoot;
        bytes32 hostShareRoot;
        bytes32 guestShareRoot;
        bytes32 hostCardPk;
        bytes32 guestCardPk;
        uint8 button;
        uint256 sb;
        uint256 bb;
        /// AF-32: the both-signed chip<->wei anchor (`_chipBaseline` reads
        /// this instead of re-deriving `200 * bb`).
        uint256 startingChips;
    }

    mapping(bytes32 => mapping(uint64 => MarkerData)) public markerAt;

    mapping(bytes32 => uint64) public markedHand;
    mapping(bytes32 => bool) public everReceipted;
    // Per-duty presence tracking (decision 7 / AF-4): who actually
    // submitted a filing transaction during a dispute window, as distinct
    // from who is named in a jointly-signed artifact's signatures.
    mapping(bytes32 => bool) public hostFiledInWindow;
    mapping(bytes32 => bool) public guestFiledInWindow;

    mapping(bytes32 => uint256) public burned;
    mapping(bytes32 => uint256) public paidOut;

    // Pull-payment ledger (D9): global across sessions, ETH is fungible;
    // the per-session invariant is carried by `paidOut`/`burned` instead,
    // never by this mapping or by `address(this).balance`.
    mapping(address => uint256) public credits;

    // ------------------------------------------------------------ events
    event Opened(
        bytes32 indexed session,
        address indexed host,
        address indexed guest,
        uint256 maxHost,
        uint256 maxGuest,
        uint256 bondHost,
        uint256 bondGuest
    );
    event Joined(bytes32 indexed session);
    event Cancelled(bytes32 indexed session);
    event Deposited(bytes32 indexed session, address indexed who, uint256 amount, uint256 newTotal);
    event ReceiptFiled(bytes32 indexed session, uint64 hand, uint32 subseq, bool isFinal);
    event MarkerFiled(bytes32 indexed session, uint64 hand);
    event DisputeOpened(bytes32 indexed session, address indexed by, uint256 timestamp);
    event Settled(bytes32 indexed session, address host, uint256 hostPayout, address guest, uint256 guestPayout);

    // ------------------------------------------------------------ stub error (decision 10)
    error NotYetBuilt();

    /// Decision 8: terminal-vs-pending routing uses a new, named error, not
    /// `NotYetBuilt` — thrown only when the replay engine's result is
    /// neither FOLD nor COMPLETE (task 7). Only P4's phase-2 machinery
    /// clears this.
    error PendingContinuation();

    constructor(uint256 _window, uint256 _bank, uint256 _grace) {
        require(_window > 0, "duration required");
        require(_bank > 0, "duration required");
        require(_grace > 0, "duration required");
        window = _window;
        bank = _bank;
        grace = _grace;
    }

    // =====================================================================
    // Task 1 — signature recovery, binding, bond formula
    // =====================================================================

    /// The universal binding rule (formats §1): every signed artefact binds
    /// `contract(20) . chainid(32) . session(32)` right after its domain
    /// string.
    function _binding(bytes32 session) internal view returns (bytes memory) {
        return abi.encodePacked(address(this), block.chainid, session);
    }

    /// Raw-digest recovery, no EIP-191 prefix — used for receipts and
    /// markers, verified against the *registered session key*, not the
    /// wallet. This is new code, not a reuse of V1's `_recover`
    /// (`Channel.sol:177`), per formats §1's explicit note (AF-2): V1 has
    /// no raw-digest path at all.
    function _recoverRaw(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig length");
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "bad v");
        require(uint256(s) <= SECP256K1N_HALF, "bad s");
        address signer = ecrecover(digest, v, r, s);
        require(signer != address(0), "bad sig");
        return signer;
    }

    /// EIP-191-prefixed recovery — identical in shape to V1's `_recover`
    /// (`Channel.sol:177-190`). Used only for session-key registration
    /// inside open()/join(), verified against the wallet address.
    function _recoverEIP191(bytes32 digest, bytes calldata sig) internal pure returns (address) {
        require(sig.length == 65, "bad sig length");
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "bad v");
        require(uint256(s) <= SECP256K1N_HALF, "bad s");
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        address signer = ecrecover(ethHash, v, r, s);
        require(signer != address(0), "bad sig");
        return signer;
    }

    /// Session-key registration preimage (formats §6):
    /// `0x04 . "vault/sessionkey/v2" . binding . player(20) . sessionKey(20)`.
    function _registrationHash(bytes32 session, address player, address sessionKey)
        internal
        view
        returns (bytes32)
    {
        return keccak256(abi.encodePacked(bytes1(0x04), "vault/sessionkey/v2", _binding(session), player, sessionKey));
    }

    /// `ceilDiv(a, b) = (a + b - 1) / b`, standard Solidity idiom, b > 0.
    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    /// Bond formula (decision 1 / D4, spec §2): both rounding steps round
    /// UP, so `bond_i` is never below the real-numbered
    /// `1.1 x max((M_h+M_g)/2, M_i)` — coverage never loses to truncation.
    /// Worked example (decision 1, matches the parking doc exactly):
    /// M_host=1500, M_guest=500 -> avgCeil=1000 -> bondHost=1650,
    /// bondGuest=1100.
    function _computeBonds(uint256 mHost, uint256 mGuest) internal pure returns (uint256 bondHost, uint256 bondGuest) {
        uint256 avgCeil = _ceilDiv(mHost + mGuest, 2);
        uint256 baseHost = avgCeil > mHost ? avgCeil : mHost;
        uint256 baseGuest = avgCeil > mGuest ? avgCeil : mGuest;
        bondHost = _ceilDiv(11 * baseHost, 10);
        bondGuest = _ceilDiv(11 * baseGuest, 10);
    }

    /// Shared registration-signature check (formats §6): pulled into its
    /// own function, not inlined in open()/join(), purely to keep each
    /// caller's live-variable count low enough for legacy (non-IR)
    /// codegen — this repo's foundry.toml does not set `via_ir`, so a
    /// function with too many simultaneously-live locals hits "stack too
    /// deep" at build time. No behavior change from inlining it.
    function _verifyRegistration(bytes32 session, address player, address sessionKey, bytes calldata walletSig)
        internal
        view
    {
        require(
            _recoverEIP191(_registrationHash(session, player, sessionKey), walletSig) == player,
            "bad registration sig"
        );
    }

    /// The host proposes the whole table (decision 2): both `bondHost` and
    /// `bondGuest` are derived and stored here, from the host-declared
    /// `maxHost`/`maxGuest`; join() only reads the pre-stored `bondGuest`.
    function open(
        bytes32 session,
        address opponent,
        uint256 maxHost,
        uint256 maxGuest,
        address sessionKey,
        bytes calldata walletSig
    ) external payable {
        Session storage s = sessions[session];
        require(s.status == Status.None, "session exists");
        require(opponent != address(0) && opponent != msg.sender, "bad opponent");
        require(maxHost > 0 && maxGuest > 0, "max required");

        _verifyRegistration(session, msg.sender, sessionKey, walletSig);

        (s.bondHost, s.bondGuest) = _computeBonds(maxHost, maxGuest);

        // decision 3: msg.value splits into bond + initial deposit.
        require(msg.value >= s.bondHost, "below bond");
        uint256 depositHost0 = msg.value - s.bondHost;
        require(depositHost0 <= maxHost, "past declared max");

        s.host = msg.sender;
        s.guest = opponent;
        s.sessionKeyHost = sessionKey;
        s.maxHost = maxHost;
        s.maxGuest = maxGuest;
        s.depositedHost = depositHost0;
        s.status = Status.AwaitingGuest;

        emit Opened(session, msg.sender, opponent, maxHost, maxGuest, s.bondHost, s.bondGuest);
    }

    function join(bytes32 session, address sessionKey, bytes calldata walletSig) external payable {
        Session storage s = sessions[session];
        require(s.status == Status.AwaitingGuest, "not awaiting guest");
        require(msg.sender == s.guest, "not invited");

        _verifyRegistration(session, msg.sender, sessionKey, walletSig);

        // decision 2: no recomputation — bondGuest was already fixed at
        // open() time from the host-declared maxGuest.
        require(msg.value >= s.bondGuest, "below bond");
        uint256 depositGuest0 = msg.value - s.bondGuest;
        require(depositGuest0 <= s.maxGuest, "past declared max");

        s.sessionKeyGuest = sessionKey;
        s.depositedGuest = depositGuest0;
        s.status = Status.Active;

        emit Joined(session);
    }

    function cancelOpen(bytes32 session) external {
        Session storage s = sessions[session];
        require(s.status == Status.AwaitingGuest, "not cancellable");
        require(msg.sender == s.host, "not host");

        // V1 parity (Channel.sol:84-93), but refunding the bond too since
        // nothing was ever risked (task 1 step 9).
        uint256 refund = s.depositedHost + s.bondHost;
        s.status = Status.Closed;
        emit Cancelled(session);
        credits[s.host] += refund;
    }

    /// Idempotent burn primitive (decision 8), pre-declared here per the
    /// task-ordering note (checker-caught build-order fix) so resolve()
    /// (task 5) can call it without a forward reference, even though
    /// Solidity itself does not require declaration order within one
    /// contract. No-ops if that player's burn flag is already set for this
    /// session; otherwise sets the flag and moves their bond from
    /// "returnable" into `burned[session]`.
    ///
    /// This is the contract surface P3/P4 build their misconduct-driven
    /// burn sources against (equivocation, missed grace, ...) — the only
    /// P2-owned *caller* of it is decision 7's per-duty branch in
    /// resolve(); there is no both-burn caller (AF-4 struck that path).
    function _burnBond(bytes32 session, bool isHost) internal {
        Session storage s = sessions[session];
        if (isHost) {
            if (s.hostBurned) return;
            s.hostBurned = true;
            burned[session] += s.bondHost;
        } else {
            if (s.guestBurned) return;
            s.guestBurned = true;
            burned[session] += s.bondGuest;
        }
    }

    // =====================================================================
    // Task 2 — deposit ledger
    // =====================================================================

    function deposit(bytes32 session) external payable {
        Session storage s = sessions[session];
        require(s.status == Status.Active || s.status == Status.Disputed, "not open for deposits");
        require(msg.sender == s.host || msg.sender == s.guest, "not a player");

        uint256 newTotal;
        if (msg.sender == s.host) {
            newTotal = s.depositedHost + msg.value;
            require(newTotal <= s.maxHost, "past declared max");
            s.depositedHost = newTotal;
        } else {
            newTotal = s.depositedGuest + msg.value;
            require(newTotal <= s.maxGuest, "past declared max");
            s.depositedGuest = newTotal;
        }

        emit Deposited(session, msg.sender, msg.value, newTotal);

        // Load-bearing (spec §3): "An un-receipted deposit is not chips."
        // deposit() only ever grows depositedX; it never touches stacks,
        // and the contract never credits a receipt on its own. Crediting
        // happens only inside a receipt both players signed (fileReceipt).
    }

    // =====================================================================
    // Task 3 — receipt filing and verification
    // =====================================================================

    /// Receipt preimage (formats §3):
    /// `0x01 . "vault/receipt/v2" . binding . hand(8) . subseq(4) .
    ///  hostStack(32) . guestStack(32) . hostDeposit(32) . guestDeposit(32) .
    ///  final(1)`. All four amount fields are wei (formats §1 amendment B1).
    function _receiptHash(bytes32 session, Receipt calldata r) internal view returns (bytes32) {
        // Staged concatenation, not one flat abi.encodePacked(...) call:
        // this many packed arguments in one expression overflows the
        // legacy codegen's stack-slot budget ("stack too deep") without
        // --via-ir, which this repo's foundry.toml does not enable.
        bytes memory head = abi.encodePacked(bytes1(0x01), "vault/receipt/v2", _binding(session));
        bytes memory tail = abi.encodePacked(
            r.hand,
            r.subseq,
            r.hostStack,
            r.guestStack,
            r.hostDeposit,
            r.guestDeposit,
            r.isFinal ? bytes1(0x01) : bytes1(0x00)
        );
        return keccak256(abi.encodePacked(head, tail));
    }

    /// `public`, not `external`: fileMarkerWithReceipt (task 4) calls this
    /// directly to co-file a receipt and a marker in one transaction.
    /// Track the highest-subseq receipt filed for this hand (decision 5) —
    /// per-hand, not a single session-wide cursor, since disputes may file
    /// segments out of filing-order. Split out of fileReceipt purely to
    /// keep that function's live-variable count low (stack-depth reasons,
    /// see _verifyRegistration's comment).
    function _trackReceiptContinuity(bytes32 session, Receipt calldata r, bytes32 digest) internal {
        bool neverFiledThisHand = receiptAt[session][r.hand] == bytes32(0);
        if (neverFiledThisHand || r.subseq >= _receiptSubseqAt[session][r.hand]) {
            receiptAt[session][r.hand] = digest;
            _receiptSubseqAt[session][r.hand] = r.subseq;
            // P3 extension (decision 7): caches full stacks, not just the
            // hash, for the replay engine's baseline lookup.
            receiptStacksAt[session][r.hand] = ReceiptStacks(r.hostStack, r.guestStack, r.hostDeposit, r.guestDeposit);
        }
    }

    /// Decision 6: no floor-check here — resolve() decides at settlement
    /// time whether the stored highest final clears the floor. Store
    /// unconditionally, tracked by (hand, subseq) order. Split out of
    /// fileReceipt for the same stack-depth reason as the helper above.
    function _trackHighestFinal(bytes32 session, Receipt calldata r, bytes32 digest) internal {
        Session storage s = sessions[session];
        bool isHigher = s.highestFinalHash == bytes32(0) || r.hand > s.highestFinalHand
            || (r.hand == s.highestFinalHand && r.subseq > s.highestFinalSubseq);
        if (isHigher) {
            s.highestFinalHand = r.hand;
            s.highestFinalSubseq = r.subseq;
            s.highestFinalHash = digest;
            s.highestFinalHostStack = r.hostStack;
            s.highestFinalGuestStack = r.guestStack;
            s.highestFinalHostDeposit = r.hostDeposit;
            s.highestFinalGuestDeposit = r.guestDeposit;
        }
    }

    function fileReceipt(bytes32 session, Receipt calldata r, bytes calldata sigHost, bytes calldata sigGuest)
        public
    {
        Session storage s = sessions[session];
        require(s.status == Status.Active || s.status == Status.Disputed, "not open for filing");

        bytes32 digest = _receiptHash(session, r);
        require(_recoverRaw(digest, sigHost) == s.sessionKeyHost, "bad host receipt sig");
        require(_recoverRaw(digest, sigGuest) == s.sessionKeyGuest, "bad guest receipt sig");

        // spec §1.1 verbatim equation.
        require(r.hostStack + r.guestStack == r.hostDeposit + r.guestDeposit, "stacks/deposits mismatch");
        // Checked against the current cumulative total — the only thing
        // observable on chain; deposits are monotonic non-decreasing.
        require(r.hostDeposit <= s.depositedHost && r.guestDeposit <= s.depositedGuest, "deposit exceeds received");

        _trackReceiptContinuity(session, r, digest);
        everReceipted[session] = true;

        // Presence tracking for decision 7's per-duty branch (AF-4): only
        // meaningful once a dispute window is running.
        if (s.status == Status.Disputed) {
            if (msg.sender == s.host) hostFiledInWindow[session] = true;
            if (msg.sender == s.guest) guestFiledInWindow[session] = true;
        }

        if (r.isFinal) {
            _trackHighestFinal(session, r, digest);
        }

        emit ReceiptFiled(session, r.hand, r.subseq, r.isFinal);
    }

    // =====================================================================
    // Task 4 — marker filing, acceptance, deal-gate getter
    // =====================================================================

    /// Marker preimage (formats §4), 14 signed fields (AF-32 amendment):
    /// `0x02 . "vault/marker/v2" . binding . hand(8) . receiptHash(32) .
    ///  deckRoot(32) . hostShareRoot(32) . guestShareRoot(32) .
    ///  hostCardPk(32) . guestCardPk(32) . button(1) . sb(32) . bb(32) .
    ///  startingChips(32)`.
    /// P4 amendment (task 1's dispatch-time re-verification): widened from
    /// `Marker calldata` to `Marker memory` — calldata cannot be
    /// synthesized in-memory, and P4's own genesis chain-link check
    /// (formats §5: `prev₀ = markerHash`) needs to recompute a hand's
    /// markerHash from stored `markerAt`/`receiptAt` data, not a fresh
    /// calldata argument. Purely a parameter-type widening (a calldata
    /// struct still auto-converts to `memory` at every existing call
    /// site) — zero behavior change for `_fileMarkerCore`'s own call.
    function _markerHash(bytes32 session, Marker memory m) internal view returns (bytes32) {
        // Staged concatenation for the same stack-depth reason as
        // _receiptHash above — 14 fields in one abi.encodePacked call is
        // well past what legacy codegen can hold live at once.
        bytes memory head = abi.encodePacked(bytes1(0x02), "vault/marker/v2", _binding(session));
        bytes memory mid = abi.encodePacked(m.hand, m.receiptHash, m.deckRoot, m.hostShareRoot, m.guestShareRoot);
        bytes memory tail =
            abi.encodePacked(m.hostCardPk, m.guestCardPk, m.button, m.sb, m.bb, m.startingChips);
        return keccak256(abi.encodePacked(head, mid, tail));
    }

    /// Sequential acceptance (decision 5): `hand == markedHand[session] + 1`
    /// is *both* duplicate-rejection and "first marker always admissible
    /// during the window" at once — a genuine design addition beyond the
    /// pinned interface shape (artifact-formats §9 permits additive
    /// fields/rules, not removals or retypes). This same single rule is
    /// also what makes marker catch-up sound: nothing here caps how many
    /// sequential markers land in one window.
    function _fileMarkerCore(bytes32 session, Marker calldata m, bytes calldata sigHost, bytes calldata sigGuest)
        internal
    {
        Session storage s = sessions[session];
        require(s.status == Status.Active || s.status == Status.Disputed, "not open for filing");
        require(m.hand == markedHand[session] + 1, "not next hand");

        bytes32 digest = _markerHash(session, m);
        require(_recoverRaw(digest, sigHost) == s.sessionKeyHost, "bad host marker sig");
        require(_recoverRaw(digest, sigGuest) == s.sessionKeyGuest, "bad guest marker sig");

        require(receiptAt[session][m.hand - 1] == m.receiptHash, "continuity");

        markedHand[session] = m.hand;
        // P3 extension (decision 7-adjacent, see markerAt's own comment):
        // persists the marker's crypto fields, which P2 verified but never
        // stored, for postShares' triple check (task 4) and consolidation's
        // replay engine (task 6).
        markerAt[session][m.hand] = MarkerData(
            m.deckRoot, m.hostShareRoot, m.guestShareRoot, m.hostCardPk, m.guestCardPk, m.button, m.sb, m.bb, m.startingChips
        );
        emit MarkerFiled(session, m.hand);
    }

    /// Used when the referenced receipt is already on file from an earlier
    /// filing.
    function fileMarker(bytes32 session, Marker calldata m, bytes calldata sigHost, bytes calldata sigGuest)
        external
    {
        _fileMarkerCore(session, m, sigHost, sigGuest);
    }

    /// The routine per-hand transaction (decision 5): bundles the marker
    /// with the receipt it needs for continuity in one call — this is what
    /// reproduces the ~61,740-gas shape measured in spec §11.2(a).
    function fileMarkerWithReceipt(
        bytes32 session,
        Marker calldata m,
        bytes calldata sigHostM,
        bytes calldata sigGuestM,
        Receipt calldata r,
        bytes calldata sigHostR,
        bytes calldata sigGuestR
    ) external {
        fileReceipt(session, r, sigHostR, sigGuestR);
        _fileMarkerCore(session, m, sigHostM, sigGuestM);
    }

    /// The entire client deal-gate surface (spec §4): "hand N+1 deals only
    /// after marker N confirms." 0 = no hand ever dealt on chain. Catch-up
    /// (decision 5) needs no separate batched entry point — a client that
    /// fell behind just calls fileMarker/fileMarkerWithReceipt repeatedly.
    function liveHand(bytes32 session) external view returns (uint64) {
        return markedHand[session];
    }

    // =====================================================================
    // Task 5 — dispute shell: openDispute, resolve() routing, P3 stubs
    // =====================================================================

    function openDispute(bytes32 session) external {
        Session storage s = sessions[session];
        require(s.status == Status.Active, "not open for dispute");
        require(msg.sender == s.host || msg.sender == s.guest, "not a player");
        s.status = Status.Disputed;
        s.disputeOpenedAt = block.timestamp;
        emit DisputeOpened(session, msg.sender, block.timestamp);
    }

    /// Split out of resolve() into its own function purely to keep the
    /// caller's live-variable count low under legacy (non-IR) codegen —
    /// resolve() has enough branches that inlining every branch's locals
    /// into one function body hits "stack too deep" at build time. No
    /// behavior change from the split.
    function _settleFinal(bytes32 session) internal {
        Session storage s = sessions[session];
        // Deposits are monotonic, and the cached deposit field is always
        // <= the total at filing time, itself <= the total now — these
        // subtractions never underflow.
        uint256 unaccountedHost = s.depositedHost - s.highestFinalHostDeposit;
        uint256 unaccountedGuest = s.depositedGuest - s.highestFinalGuestDeposit;

        uint256 hostPayout = s.highestFinalHostStack + unaccountedHost + (s.hostBurned ? 0 : s.bondHost);
        uint256 guestPayout = s.highestFinalGuestStack + unaccountedGuest + (s.guestBurned ? 0 : s.bondGuest);

        credits[s.host] += hostPayout;
        credits[s.guest] += guestPayout;
        paidOut[session] += hostPayout + guestPayout;

        s.status = Status.Closed;
        emit Settled(session, s.host, hostPayout, s.guest, guestPayout);
    }

    /// Decision 7 row 2 (AF-4): zero filings at window close —
    /// never-started semantics, full refund of deposits and both bonds,
    /// no burn.
    function _settleZeroFilings(bytes32 session) internal {
        Session storage s = sessions[session];
        uint256 hostPayout = s.depositedHost + s.bondHost;
        uint256 guestPayout = s.depositedGuest + s.bondGuest;
        credits[s.host] += hostPayout;
        credits[s.guest] += guestPayout;
        paidOut[session] += hostPayout + guestPayout;

        s.status = Status.Closed;
        emit Settled(session, s.host, hostPayout, s.guest, guestPayout);
    }

    /// Decision 7 row 3 (AF-4): one or more filings, markedHand == 0 —
    /// per-duty bond fate, NOT a both-burn. The only reachable receipt
    /// here is (0,0), where stack == deposit, so the deposit credit is a
    /// plain wash, not a redistribution.
    function _settlePerDutyBonds(bytes32 session) internal {
        Session storage s = sessions[session];
        uint256 hostCredited = s.depositedHost;
        uint256 guestCredited = s.depositedGuest;

        if (hostFiledInWindow[session]) {
            hostCredited += s.bondHost;
        } else {
            _burnBond(session, true);
        }
        if (guestFiledInWindow[session]) {
            guestCredited += s.bondGuest;
        } else {
            _burnBond(session, false);
        }

        credits[s.host] += hostCredited;
        credits[s.guest] += guestCredited;
        paidOut[session] += hostCredited + guestCredited;

        s.status = Status.Closed;
        emit Settled(session, s.host, hostCredited, s.guest, guestCredited);
    }

    /// Lazy: consolidates + settles when due (artifact-formats §9's own
    /// phrase). Filing never moves money by itself (decision 4) — this is
    /// the single payout executor. Precedence (D9): final > receipt+overlay
    /// > never-started/per-duty unwind. The three substantial branches are
    // =====================================================================
    // Task 6 (P3) — consolidation: the lazy wrapper around the replay
    // engine (decision 4). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    /// Builds task 5's `Cand[]` array from task 3's storage, filtered to
    /// candidates filed strictly before the window closes (decision 2's
    /// window boundary, applied uniformly here to equivocating and
    /// non-equivocating candidates alike), seq-ascending, stopping at the
    /// first seq with no in-window candidate at all — building further is
    /// wasted work, never a correctness issue (task 6 step 3). Also filters
    /// out a syntactically-stored but wire-invalid `action` byte (outside
    /// 0..3, formats §5's 4-value alphabet) — not specified by name in the
    /// task doc, but necessary: `BettingReplay.ActionKind(...)`'s enum cast
    /// reverts on an out-of-range value, and `fileActions` (task 3) does
    /// not itself bound-check `act.action` before storing (it only checks
    /// the *signature*). Treating an out-of-range action as "no candidate
    /// at this seq" — never a permanent revert of `resolve()` — matches
    /// decision 3's own "fails legality -> chain stops here" philosophy for
    /// every other kind of illegal action.
    function _buildOrdered(bytes32 session, uint64 hand) internal view returns (BettingReplay.Cand[] memory ordered) {
        Session storage s = sessions[session];
        uint256 cutoff = s.disputeOpenedAt + window;
        uint8 maxAction = uint8(BettingReplay.ActionKind.Bet);

        uint256 total = 0;
        uint64 seq = 0;
        while (true) {
            ActCandidate[2] storage slots = actionsAt[_actionSlotKey(session, hand, seq)];
            uint256 atSeq = 0;
            for (uint256 i = 0; i < 2; i++) {
                if (slots[i].exists && slots[i].filedAt < cutoff && slots[i].action <= maxAction) atSeq++;
            }
            if (atSeq == 0) break;
            total += atSeq;
            seq++;
        }

        ordered = new BettingReplay.Cand[](total);
        uint256 idx = 0;
        for (uint64 sq = 0; sq < seq; sq++) {
            ActCandidate[2] storage slots = actionsAt[_actionSlotKey(session, hand, sq)];
            for (uint256 i = 0; i < 2; i++) {
                if (slots[i].exists && slots[i].filedAt < cutoff && slots[i].action <= maxAction) {
                    ordered[idx] = BettingReplay.Cand({
                        seq: sq,
                        signerIsHost: slots[i].signer == s.sessionKeyHost,
                        action: BettingReplay.ActionKind(slots[i].action),
                        amount: slots[i].amount,
                        filedAt: slots[i].filedAt
                    });
                    idx++;
                }
            }
        }
    }

    /// decision 3a's wei<->chip rate plus the converted baseline stacks,
    /// split out of `_consolidate` purely to keep that function's own
    /// live-variable count under the legacy (non-IR) codegen's stack-slot
    /// ceiling — same stack-depth reason as `_trackReceiptContinuity`/
    /// `_trackHighestFinal`'s split out of `fileReceipt`, no behavior
    /// change from the split.
    function _chipBaseline(bytes32 session, uint64 hand)
        internal
        view
        returns (uint256 weiPerChip, uint256 chipStackHost, uint256 chipStackGuest)
    {
        // AF-32: read the both-signed anchor off the stored marker rather
        // than re-deriving it from bb (the old `200 * bb` guess disagreed
        // with the client's real starting stack -- formats §4, D6 amendment).
        uint256 startingChips = markerAt[session][hand].startingChips;
        require(startingChips > 0, "bad marker startingChips");
        ReceiptStacks storage baseline0 = receiptStacksAt[session][0];
        require(baseline0.hostDeposit % startingChips == 0, "chip/wei rate mismatch");
        weiPerChip = baseline0.hostDeposit / startingChips;
        require(weiPerChip > 0, "bad wei/chip rate");

        ReceiptStacks storage baseline = receiptStacksAt[session][hand - 1];
        require(baseline.hostStack % weiPerChip == 0, "chip/wei rate mismatch");
        require(baseline.guestStack % weiPerChip == 0, "chip/wei rate mismatch");
        chipStackHost = baseline.hostStack / weiPerChip;
        chipStackGuest = baseline.guestStack / weiPerChip;
    }

    /// `_consolidate`'s replay half, split out purely for stack-depth
    /// reasons (same rationale as `_chipBaseline`'s split) — a single
    /// function assigning both `BettingReplay.replay`'s 5-value return AND
    /// `_chipBaseline`'s 3-value return into six of its own named returns
    /// overflows the legacy codegen's stack-slot budget.
    function _replayHand(bytes32 session, uint64 hand, uint256 chipStackHost, uint256 chipStackGuest)
        internal
        view
        returns (
            BettingReplay.TermKind kind,
            bool folderIsHost,
            BettingReplay.State memory finalState,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        )
    {
        MarkerData storage mk = markerAt[session][hand];
        BettingReplay.Cand[] memory ordered = _buildOrdered(session, hand);
        (kind, folderIsHost, finalState, lastAcceptedSeq, completingFiledAt) =
            BettingReplay.replay(mk.button == 0, mk.sb, mk.bb, chipStackHost, chipStackGuest, ordered);
    }

    /// Decision 4: genuinely lazy — `view`, no storage write of its own.
    /// Reads the marker's button/sb/bb (chip-space, decision 3a) and the
    /// cached receipt-stacks baseline (task 3's extension, wei), converts
    /// wei -> chips once (decision 3a's `weiPerChip`, via `_chipBaseline`),
    /// and calls `BettingReplay.replay` fresh every time (via `_replayHand`).
    function _consolidate(bytes32 session)
        internal
        view
        returns (
            BettingReplay.TermKind kind,
            address folder,
            BettingReplay.State memory finalState,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt,
            uint256 weiPerChip
        )
    {
        uint64 hand = markedHand[session];
        uint256 chipStackHost;
        uint256 chipStackGuest;
        (weiPerChip, chipStackHost, chipStackGuest) = _chipBaseline(session, hand);

        bool folderIsHost;
        (kind, folderIsHost, finalState, lastAcceptedSeq, completingFiledAt) =
            _replayHand(session, hand, chipStackHost, chipStackGuest);

        // AF-28: BettingReplay.replay is pure/address-free and returns only
        // `bool folderIsHost`; this is where the plan's `address folder`
        // signature is honored — translated via this session's own
        // host/guest storage, exactly as AF-28 instructs.
        folder = folderIsHost ? sessions[session].host : sessions[session].guest;
    }

    // =====================================================================
    // Task 7 (P3) — wire resolve()'s markedHand > 0 branch: terminal-vs-
    // pending routing (decision 8). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    // =====================================================================
    // Part B tasks 9-11 — §5.3's resolution table. Files:
    // contracts/src/ChannelV2.sol (this section), contracts/src/Evidence.sol
    // (task 9's `decode`).
    // =====================================================================

    /// Task 9 (decision 6): combine the deck ciphertext's `c2` with both
    /// posted shares (`Evidence.combine`, task 1 step 5) and match against
    /// the 52-card table (`Evidence.CARD_POINTS`, task 1 step 4) via
    /// `Ristretto.encode`. Kept here, inside `ChannelV2`, rather than as a
    /// new `Evidence.decode` library entry point — a deliberate deviation
    /// from the phase doc's own Files list for task 9 (which names
    /// `Evidence.sol`), disclosed in this dispatch's completion notes as a
    /// decision-conflict: this dispatch's side-effect boundary forbids
    /// touching `Evidence.sol`/`BettingReplay.sol` (crypto/replay modules
    /// owned by an earlier task), and `Evidence.combine`/`CARD_POINTS` are
    /// already `internal` library functions this file can call without any
    /// change to that file — so the same combine-and-match logic is
    /// achievable entirely from this side with zero edits to `Evidence.sol`.
    /// `ok == false` is not an error — it is the fourth row's trigger
    /// (task 11 step 5): every upstream check already passed (both shares'
    /// DLEQs, both Merkle inclusions — postShares' triple check, task 4)
    /// and the combined point still isn't one of the 52 protocol cards.
    ///
    /// Also returns `ok = false` WITHOUT combining/encoding at all when
    /// either side never posted this position — the muck condition, kept
    /// distinct from the fourth row's "both posted, decode still fails"
    /// condition by every caller, never conflated here.
    function decodeAt(bytes32 session, uint64 hand, uint8 pos) internal view returns (bool ok, uint8 card) {
        Session storage s = sessions[session];
        if (!sharePosted[session][hand][pos][s.host] || !sharePosted[session][hand][pos][s.guest]) {
            return (false, 0);
        }
        Ristretto.Pt memory combined = Evidence.combine(
            deckC2At[session][hand][pos], postedShare[session][hand][pos][s.host], postedShare[session][hand][pos][s.guest]
        );
        bytes32 enc = Ristretto.encode(combined);
        bytes32[52] memory table = Evidence.CARD_POINTS();
        for (uint256 i = 0; i < 52; i++) {
            if (table[i] == enc) {
                return (true, uint8(i));
            }
        }
        return (false, 0);
    }

    /// Task 11 step 1 (B2, fix round 1): birth-anchored duty deadline,
    /// `max(hour 24, birth + 6h)`. `completingFiledAt` is always the
    /// caller's own already-in-hand value (from `_consolidate`/
    /// `BettingReplay.replay`) — never re-derived or re-read from storage
    /// here. Called at exactly one gating site (task 10 step 2 / task 11
    /// step 2) plus task 12's crystallization mirror — never duplicated.
    function dueAt(bytes32 session, uint256 completingFiledAt) internal view returns (uint256) {
        uint256 windowClose = sessions[session].disputeOpenedAt + window;
        uint256 birthDeadline = completingFiledAt + grace;
        return windowClose > birthDeadline ? windowClose : birthDeadline;
    }

    /// Required decode positions for a COMPLETE chain's final street
    /// (`protocol.ts:52-58`'s `POS` constant — a fixed protocol convention,
    /// not this phase's invention). In practice, per `BettingReplay`'s own
    /// termination rule, `TermKind.COMPLETE` is returned only when
    /// `closeAndAdvance` finds the street already River (see
    /// `BettingReplay._cascade`) — so `street == River` always holds here,
    /// and this always returns all 9 positions. Implemented against the
    /// general street conditional anyway (task 10 step 2's own wording),
    /// not hardcoded to the reachable case, since the completeness CHECK
    /// (unlike the evaluator wiring below) costs nothing extra to keep
    /// general.
    function _requiredPositions(BettingReplay.Street street) internal pure returns (uint8[] memory positions) {
        uint256 count = 4;
        if (street >= BettingReplay.Street.Flop) count += 3;
        if (street >= BettingReplay.Street.Turn) count += 1;
        if (street == BettingReplay.Street.River) count += 1;

        positions = new uint8[](count);
        uint256 idx = 0;
        positions[idx++] = 0; // host hole
        positions[idx++] = 1;
        positions[idx++] = 2; // guest hole
        positions[idx++] = 3;
        if (street >= BettingReplay.Street.Flop) {
            positions[idx++] = 5;
            positions[idx++] = 6;
            positions[idx++] = 7;
        }
        if (street >= BettingReplay.Street.Turn) {
            positions[idx++] = 9;
        }
        if (street == BettingReplay.Street.River) {
            positions[idx++] = 11;
        }
    }

    /// Task 10 step 2 / task 11 step 3's completeness check: does EVERY
    /// required position carry a passing post from EACH side (decoding is
    /// joint — a player owes their own contribution to every required
    /// position, not just their own hole cards, so this checks both
    /// directions explicitly, never assuming symmetry). Shared between
    /// `_resolveComplete` (task 10/11) and `_crystallizeMaturedDuties`
    /// (task 12) so the two never diverge on what "missing" means.
    function _completeness(bytes32 session, uint64 hand, uint8[] memory positions)
        internal
        view
        returns (bool hostMissing, bool guestMissing)
    {
        Session storage s = sessions[session];
        for (uint256 i = 0; i < positions.length; i++) {
            uint8 pos = positions[i];
            if (!sharePosted[session][hand][pos][s.host]) hostMissing = true;
            if (!sharePosted[session][hand][pos][s.guest]) guestMissing = true;
        }
    }

    /// Task 9's two `decodeAt`-failure causes, resolved here: decodes every
    /// required position (only ever called once completeness above already
    /// held) and separately flags a duplicate-card deck (task 11 step 5's
    /// second, independent malformed-deck signal) — either one routes to
    /// the fourth row.
    function _decodeRequired(bytes32 session, uint64 hand, uint8[] memory positions)
        internal
        view
        returns (bool allOk, bool hasDuplicate, uint8[] memory cards)
    {
        cards = new uint8[](positions.length);
        for (uint256 i = 0; i < positions.length; i++) {
            (bool ok, uint8 card) = decodeAt(session, hand, positions[i]);
            if (!ok) {
                return (false, false, cards);
            }
            cards[i] = card;
        }
        allOk = true;
        for (uint256 i = 0; i < cards.length && !hasDuplicate; i++) {
            for (uint256 j = i + 1; j < cards.length; j++) {
                if (cards[i] == cards[j]) {
                    hasDuplicate = true;
                    break;
                }
            }
        }
    }

    /// Ported `settle()` (`betting.ts:204-223`): the uncalled-excess refund
    /// plus contested-pot distribution, in chip-space. Used by the fold row
    /// (task 10 step 1, `isSplit = false`, winner = non-folder) and the
    /// cards-decide row (task 10 step 3, `isSplit` only on an exact
    /// evaluator tie). NOT used by the muck rows (task 11 step 3) — those
    /// award the WHOLE pot to the complete poster with no excess-refund
    /// carve-out, a deliberately different (punitive, misconduct-driven)
    /// rule from a betting outcome's uncalled-bet return.
    function _settleChips(BettingReplay.State memory finalState, bool winnerIsHost, bool isSplit)
        internal
        pure
        returns (uint256 hostChips, uint256 guestChips)
    {
        uint256 investedHost = finalState.investedHost;
        uint256 investedGuest = finalState.investedGuest;
        uint256 potTotal = investedHost + investedGuest;
        uint256 excess = investedHost > investedGuest ? investedHost - investedGuest : investedGuest - investedHost;
        uint256 contested = potTotal - excess;

        if (excess > 0) {
            if (investedHost > investedGuest) {
                hostChips += excess;
            } else {
                guestChips += excess;
            }
        }

        if (isSplit) {
            uint256 half = contested / 2;
            hostChips += half;
            guestChips += contested - half;
        } else if (winnerIsHost) {
            hostChips += contested;
        } else {
            guestChips += contested;
        }
    }

    /// Decision 3a's chips->wei crossing (multiplication, always exact) plus
    /// D9's general settlement rule (spec §1.2): "a receipt for hand N-1
    /// plus an adjudicated outcome for hand N settles at the receipt's
    /// stacks moved by the adjudicated pot. Deposits not accounted for by
    /// the settling state are refunded to whoever made them" — the same
    /// unaccounted-deposit handling `_settleFinal` already applies to the
    /// final receipt, applied here to the baseline receipt at hand-1
    /// instead. `burnHost`/`burnGuest` (applied by each caller, below) run
    /// via the idempotent `_burnBond` before this function reads
    /// `hostBurned`/`guestBurned`, so a single call always reflects its own
    /// burn. Split out of `_settleWithPot`/`_settleAtBaseline` purely for
    /// stack-depth reasons (same rationale as every other split in this
    /// file) — it is also what keeps those two rows' bond-fate and
    /// receipt-baseline logic from diverging on this shared payout tail.
    function _creditSettlement(bytes32 session, uint256 hostStackWei, uint256 guestStackWei)
        internal
        returns (bool)
    {
        Session storage s = sessions[session];
        ReceiptStacks storage baseline = receiptStacksAt[session][markedHand[session] - 1];

        uint256 hostPayout = hostStackWei + (s.depositedHost - baseline.hostDeposit) + (s.hostBurned ? 0 : s.bondHost);
        uint256 guestPayout =
            guestStackWei + (s.depositedGuest - baseline.guestDeposit) + (s.guestBurned ? 0 : s.bondGuest);

        credits[s.host] += hostPayout;
        credits[s.guest] += guestPayout;
        paidOut[session] += hostPayout + guestPayout;

        s.status = Status.Closed;
        emit Settled(session, s.host, hostPayout, s.guest, guestPayout);
        return true;
    }

    function _settleWithPot(
        bytes32 session,
        BettingReplay.State memory finalState,
        uint256 hostChipsWon,
        uint256 guestChipsWon,
        uint256 weiPerChip,
        bool burnHost,
        bool burnGuest
    ) internal returns (bool) {
        if (burnHost) _burnBond(session, true);
        if (burnGuest) _burnBond(session, false);
        uint256 hostStackWei = (finalState.stackHost + hostChipsWon) * weiPerChip;
        uint256 guestStackWei = (finalState.stackGuest + guestChipsWon) * weiPerChip;
        return _creditSettlement(session, hostStackWei, guestStackWei);
    }

    /// Symmetric muck (task 11 step 4) and the fourth row (task 11 step 5):
    /// "settle at the receipt baseline alone" — literally the baseline
    /// receipt's own wei stacks, unmoved by any pot (the disputed hand's
    /// betting is voided outright, not partially credited), plus the same
    /// unaccounted-deposit refund every other row applies.
    function _settleAtBaseline(bytes32 session, bool burnHost, bool burnGuest) internal returns (bool) {
        if (burnHost) _burnBond(session, true);
        if (burnGuest) _burnBond(session, false);
        ReceiptStacks storage baseline = receiptStacksAt[session][markedHand[session] - 1];
        return _creditSettlement(session, baseline.hostStack, baseline.guestStack);
    }

    /// Task 10 step 1: the fold row. Folding is a completed decision, not
    /// misconduct (spec §5.3) — the folder's bond returns, no `_burnBond`
    /// call at all. AF-28: `folder` already arrived as a wallet address
    /// (translated by `_consolidate`); re-derive `folderIsHost` here via the
    /// session's own host/guest storage for `_settleChips`'s winner arg.
    function _resolveFold(bytes32 session, address folder, BettingReplay.State memory finalState, uint256 weiPerChip)
        internal
        returns (bool)
    {
        bool folderIsHost = (folder == sessions[session].host);
        (uint256 hostChips, uint256 guestChips) = _settleChips(finalState, !folderIsHost, false);
        return _settleWithPot(session, finalState, hostChips, guestChips, weiPerChip, false, false);
    }

    /// Task 11 step 3's one-sided muck: the WHOLE pot (chips already
    /// invested by both sides this hand) goes to the complete poster — no
    /// excess-refund carve-out (contrast `_settleChips`, used only by
    /// betting-outcome rows). The incomplete side's bond burns; the
    /// complete side's bond returns.
    function _resolveMuck(bytes32 session, BettingReplay.State memory finalState, uint256 weiPerChip, bool completeIsHost)
        internal
        returns (bool)
    {
        uint256 potChips = finalState.investedHost + finalState.investedGuest;
        uint256 hostChips = completeIsHost ? potChips : 0;
        uint256 guestChips = completeIsHost ? 0 : potChips;
        return _settleWithPot(session, finalState, hostChips, guestChips, weiPerChip, !completeIsHost, completeIsHost);
    }

    /// Task 10 steps 2-3: both sides fully posted, all required positions
    /// decoded to real cards with no duplicate — genuine showdown. `cards`
    /// is `_decodeRequired`'s output over `_requiredPositions(River)`'s
    /// fixed ordering (`_resolveComplete`'s only reachable call site, per
    /// `_requiredPositions`'s own comment): [hostHole0, hostHole1,
    /// guestHole0, guestHole1, flop0, flop1, flop2, turn, river].
    function _resolveCardsDecide(
        bytes32 session,
        BettingReplay.State memory finalState,
        uint256 weiPerChip,
        uint8[] memory cards
    ) internal returns (bool) {
        uint8[7] memory hostHand = [cards[0], cards[1], cards[4], cards[5], cards[6], cards[7], cards[8]];
        uint8[7] memory guestHand = [cards[2], cards[3], cards[4], cards[5], cards[6], cards[7], cards[8]];
        uint256 hostScore = Evaluator7.evaluate(hostHand);
        uint256 guestScore = Evaluator7.evaluate(guestHand);

        bool isSplit = hostScore == guestScore;
        bool hostWins = hostScore > guestScore;
        (uint256 hostChips, uint256 guestChips) = _settleChips(finalState, hostWins, isSplit);
        return _settleWithPot(session, finalState, hostChips, guestChips, weiPerChip, false, false);
    }

    /// Task 10 step 2 / task 11 steps 2-5: the COMPLETE branch's own
    /// routing among cards-decide, one-sided muck, symmetric muck, and the
    /// fourth row. Split out of `_resolveTerminal` for stack-depth reasons
    /// (same rationale as every other split in this file).
    function _resolveComplete(
        bytes32 session,
        BettingReplay.State memory finalState,
        uint256 completingFiledAt,
        uint256 weiPerChip
    ) internal returns (bool) {
        uint64 hand = markedHand[session];
        uint8[] memory positions = _requiredPositions(finalState.street);
        (bool hostMissing, bool guestMissing) = _completeness(session, hand, positions);

        if (hostMissing || guestMissing) {
            // Task 11 step 2: the birth-anchored duty deadline gates every
            // incomplete-showdown row — a player who still has time to post
            // cannot be mucked early. NOT PendingContinuation (that means
            // "no action filed for the next node," a different situation).
            require(block.timestamp >= dueAt(session, completingFiledAt), "window open");
            if (hostMissing && guestMissing) {
                return _settleAtBaseline(session, true, true); // task 11 step 4
            }
            return _resolveMuck(session, finalState, weiPerChip, !hostMissing); // task 11 step 3
        }

        (bool allOk, bool hasDuplicate, uint8[] memory cards) = _decodeRequired(session, hand, positions);
        if (!allOk || hasDuplicate) {
            // Task 11 step 5: the fourth row. Total — no revert path.
            return _settleAtBaseline(session, true, true);
        }

        return _resolveCardsDecide(session, finalState, weiPerChip, cards); // task 10 step 3
    }

    /// Declared in task 7 so Part A's gate could build and test the routing
    /// without Part B's body existing yet. This is Part B's task 10 body:
    /// dispatches to the fold row (task 10 step 1) or the COMPLETE branch's
    /// own routing (task 10 steps 2-3, task 11's muck/symmetric-muck/fourth
    /// row). No other task redeclares or moves this function.
    function _resolveTerminal(
        bytes32 session,
        BettingReplay.TermKind kind,
        address folder,
        BettingReplay.State memory finalState,
        uint256 completingFiledAt,
        uint256 weiPerChip
    ) internal returns (bool) {
        if (kind == BettingReplay.TermKind.FOLD) {
            return _resolveFold(session, folder, finalState, weiPerChip);
        }
        return _resolveComplete(session, finalState, completingFiledAt, weiPerChip);
    }

    // =====================================================================
    // Task 12 — crystallize-on-any-resolve: extend resolve()'s
    // finalEligible branch (decision 7's second disclosed extension).
    // Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    /// F16.1/F16.3: a `final`'s short-circuit in `resolve()` must not
    /// "launder" a matured-but-uncrystallized missed-duty burn — proof is
    /// the filings, never the computation event. Deliberately duplicates
    /// task 11's own burn-decision logic in miniature (stated plainly, per
    /// task 12 step 1's own reasoning) rather than making `_resolveTerminal`
    /// itself idempotent and callable from both branches — `_resolveTerminal`
    /// also pays out, and the `finalEligible` branch must pay out at the
    /// final's own stacks, not the dispute table's; two payout computations
    /// cannot both run for one `resolve()` call. This function burns only,
    /// never pays.
    function _crystallizeMaturedDuties(bytes32 session) internal {
        if (markedHand[session] == 0) return;

        (BettingReplay.TermKind kind,, BettingReplay.State memory finalState,, uint256 completingFiledAt,) =
            _consolidate(session);

        if (kind == BettingReplay.TermKind.COMPLETE) {
            _crystallizeAt(session, finalState, completingFiledAt);
            return;
        }
        if (kind != BettingReplay.TermKind.NONE) return; // FOLD: a fold never burns, nothing to crystallize

        // P4 extension (decision 6): crystallizes matured phase-2-born
        // duty burns before a final can pay out around them (F16.1/F16.3,
        // generalized to phase-2 births). A TermKind.FOLD result from
        // _consolidatePhase2 needs no crystallization either — bank-fold
        // is a fold (decision: folding is never misconduct), only a
        // missed POSTING duty (reached only via TermKind.COMPLETE) burns.
        (BettingReplay.TermKind kind2,, BettingReplay.State memory finalState2, uint256 effCompletingFiledAt,) =
            _consolidatePhase2(session);
        if (kind2 != BettingReplay.TermKind.COMPLETE) return;
        _crystallizeAt(session, finalState2, effCompletingFiledAt);
    }

    /// Split out of `_crystallizeMaturedDuties` (stack-depth reasons, same
    /// rationale as every split in this file) — the shared burn-decision
    /// body both the phase-1-only COMPLETE branch and this phase's
    /// phase-2-derived COMPLETE branch call, so the two paths can never
    /// diverge on what "missing"/"matured" means.
    function _crystallizeAt(bytes32 session, BettingReplay.State memory finalState, uint256 completingFiledAt)
        internal
    {
        if (block.timestamp < dueAt(session, completingFiledAt)) return;

        uint64 hand = markedHand[session];
        uint8[] memory positions = _requiredPositions(finalState.street);
        (bool hostMissing, bool guestMissing) = _completeness(session, hand, positions);

        if (hostMissing) _burnBond(session, true);
        if (guestMissing) _burnBond(session, false);

        if (!hostMissing && !guestMissing) {
            (bool allOk, bool hasDuplicate,) = _decodeRequired(session, hand, positions);
            if (!allOk || hasDuplicate) {
                _burnBond(session, true);
                _burnBond(session, false);
            }
        }
    }

    /// P4 task 7: the markedHand>0 branch's own TermKind.NONE continuation
    /// — split out of resolve() purely for stack-depth reasons (same
    /// rationale as every other split in this file). Replaces P3's
    /// `revert PendingContinuation();` (decision 2): phase-2 machinery now
    /// exists, so a purely-frozen NONE proceeds into `_consolidatePhase2`
    /// instead of reverting outright; only a genuinely-still-running
    /// phase-2 clock (no bank exhausted yet, no fold/complete reached)
    /// reverts, with this phase's own new "still running" error (declared
    /// task 1, thrown below).
    function _resolvePendingPhase2(bytes32 session) internal {
        (
            BettingReplay.TermKind kind2,
            address folder2,
            BettingReplay.State memory finalState2,
            uint256 effCompletingFiledAt,
            uint256 weiPerChip2
        ) = _consolidatePhase2(session);
        if (kind2 == BettingReplay.TermKind.NONE) {
            revert Phase2InProgress();
        }
        _resolveTerminal(session, kind2, folder2, finalState2, effCompletingFiledAt, weiPerChip2);
    }

    /// split into internal helpers above purely for stack-depth reasons
    /// (see their comments) — this function only routes.
    function resolve(bytes32 session) external {
        Session storage s = sessions[session];
        require(s.status == Status.Active || s.status == Status.Disputed, "nothing to resolve");

        // Decision 6's floor check, evaluated here, not at filing time.
        bool finalEligible = s.highestFinalHash != bytes32(0) && s.highestFinalHand >= markedHand[session];

        if (finalEligible) {
            // P3 extension (decision 7): crystallizes matured duty burns
            // before a final can pay out around them (F16.1, F16.3).
            _crystallizeMaturedDuties(session);
            _settleFinal(session);
            return;
        }

        // No eligible final: only a Disputed session with its window
        // closed has anything left to resolve.
        require(s.status == Status.Disputed, "nothing to resolve");
        require(block.timestamp >= s.disputeOpenedAt + window, "window open");

        // The marked-live-hand table (spec §5.3) is P3/P4's — check this
        // first, since the branches below apply only at markedHand == 0.
        if (markedHand[session] > 0) {
            (
                BettingReplay.TermKind kind,
                address folder,
                BettingReplay.State memory finalState,
                ,
                uint256 completingFiledAt,
                uint256 weiPerChip
            ) = _consolidate(session);
            if (kind == BettingReplay.TermKind.NONE) {
                _resolvePendingPhase2(session);
                return;
            }
            _resolveTerminal(session, kind, folder, finalState, completingFiledAt, weiPerChip);
            return;
        }

        if (!everReceipted[session]) {
            _settleZeroFilings(session);
            return;
        }

        _settlePerDutyBonds(session);
    }

    // =====================================================================
    // Task 3 (P3) — fileActions: storage, eager in-window equivocation burn
    // (decisions 1, 2). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    /// Per (hand, seq), up to two stored candidates — one per possible
    /// signer (decision 2). `exists` distinguishes an empty slot from a
    /// zero-valued one; index is decided at insertion, not fixed in advance.
    struct ActCandidate {
        address signer;
        uint8 action;
        uint256 amount;
        bytes32 prev;
        bytes32 actionHash;
        uint40 filedAt;
        bool exists;
    }

    // keyed keccak256(session, hand, seq) -> up to 2 candidates.
    mapping(bytes32 => ActCandidate[2]) public actionsAt;

    event ActionsFiled(bytes32 indexed session, uint256 count);

    function _actionSlotKey(bytes32 session, uint64 hand, uint64 seq) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(session, hand, seq));
    }

    /// Action preimage (formats §5): `0x03 . "vault/act/v2" . binding .
    /// hand(8) . seq(8) . action(1) . amount(32) . prev(32)`.
    function _actionHash(bytes32 session, Act calldata a) internal view returns (bytes32) {
        bytes memory head = abi.encodePacked(bytes1(0x03), "vault/act/v2", _binding(session));
        bytes memory tail = abi.encodePacked(a.hand, a.seq, a.action, a.amount, a.prev);
        return keccak256(abi.encodePacked(head, tail));
    }

    /// One (act, sig) entry of a `fileActions` batch. Neither-key ->
    /// silently ignored (decision 1); same-signer identical -> dedup
    /// (F14.4); same-signer distinct -> eager, window-gated equivocation
    /// burn, earliest-filed stands (decision 2, AF-6's first-stored-wins
    /// ruling — EVM intra-block execution is already a total order, no hash
    /// tiebreak needed); other-signer, free slot -> store normally.
    function _fileOneAction(bytes32 session, Act calldata a, bytes calldata sig) internal {
        Session storage s = sessions[session];
        bytes32 actionHash = _actionHash(session, a);
        address signer = _recoverRaw(actionHash, sig);
        if (signer != s.sessionKeyHost && signer != s.sessionKeyGuest) {
            return;
        }

        bytes32 slotKey = _actionSlotKey(session, a.hand, a.seq);
        ActCandidate[2] storage slots = actionsAt[slotKey];

        for (uint256 i = 0; i < 2; i++) {
            if (slots[i].exists && slots[i].signer == signer) {
                if (slots[i].actionHash == actionHash) {
                    return; // F14.4: identical duplicate, silent dedup
                }
                // decision 2: equivocation. Eager, window-gated burn; the
                // earliest-filed candidate stands regardless — never
                // overwrite the stored slot.
                if (block.timestamp < s.disputeOpenedAt + window) {
                    _burnBond(session, signer == s.sessionKeyHost);
                }
                return;
            }
        }

        for (uint256 i = 0; i < 2; i++) {
            if (!slots[i].exists) {
                slots[i] = ActCandidate(signer, a.action, a.amount, a.prev, actionHash, uint40(block.timestamp), true);
                return;
            }
        }
        // Unreachable: only two distinct signers are possible per session
        // (sessionKeyHost/sessionKeyGuest, decision 1's require above), so
        // both slots being occupied by signers other than this one cannot
        // happen — if both are occupied, one of them IS this signer, and
        // the loop above already returned.
    }

    /// "Any segment, any order" (formats §9): one bad/foreign-signer entry
    /// never fails the whole batch (decision 1) — a malformed *signature*
    /// (wrong length/v/s) still reverts via `_recoverRaw`, matching every
    /// other signature-consuming function in this contract.
    function fileActions(bytes32 session, Act[] calldata acts, bytes[] calldata sigs) external {
        Session storage s = sessions[session];
        require(s.status == Status.Disputed, "not disputed");
        require(acts.length == sigs.length, "length mismatch");
        for (uint256 i = 0; i < acts.length; i++) {
            _fileOneAction(session, acts[i], sigs[i]);
        }
        emit ActionsFiled(session, acts.length);
    }

    // =====================================================================
    // Task 4 (P3) — postShares: the triple check at file time (decisions 5,
    // 10). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    // Two mappings rather than one struct-valued one (task 4 step 1's
    // explicit either-is-fine allowance). Nested-mapping form rather than a
    // keccak256(session,hand) compressed key — implementer's choice, same
    // doc allowance — reads identically to task 9/10/11's own literal
    // `sharePosted[...][pos][host]` usage.
    mapping(bytes32 => mapping(uint64 => mapping(uint8 => mapping(address => Ristretto.Pt)))) public postedShare;
    mapping(bytes32 => mapping(uint64 => mapping(uint8 => mapping(address => bool)))) public sharePosted;
    mapping(bytes32 => mapping(uint64 => mapping(uint8 => Ristretto.Pt))) public deckC2At;

    event SharePosted(bytes32 indexed session, uint64 hand, uint8 pos, address owner);

    /// One `SharePost`'s triple check, formats §7's exact order: share
    /// Merkle (self-authenticating, decision 1 — whichever root the proof
    /// verifies against fixes ownership), deck Merkle at the SAME position
    /// (decision 10 — the ciphertext is taken from this proof, never from
    /// the filer's word), then DLEQ against the owner's cardPk. Any failure
    /// -> skip, no revert (decision 5); only a fully-passing post writes
    /// storage.
    function _postOneShare(bytes32 session, uint64 hand, Session storage s, MarkerData storage mk, SharePost calldata post)
        internal
    {
        bytes32 shareLf = Evidence.shareLeaf(post.pos, post.shareEnc);

        address owner;
        if (Evidence.merkleVerify(shareLf, post.shareProof, mk.hostShareRoot)) {
            owner = s.host;
        } else if (Evidence.merkleVerify(shareLf, post.shareProof, mk.guestShareRoot)) {
            owner = s.guest;
        } else {
            return; // neither root -> worthless, skip
        }

        bytes32 deckLf = Evidence.deckLeaf(post.pos, post.c1Enc, post.c2Enc);
        if (!Evidence.merkleVerify(deckLf, post.deckProof, mk.deckRoot)) {
            return; // decision 10: ciphertext must include at the SAME pos
        }

        (bool c2Ok, Ristretto.Pt memory c2Pt) = Ristretto.decode(post.c2Enc);
        if (!c2Ok) {
            return; // Merkle-included bytes are not a valid encoding at all
        }

        bytes32 cardPkEnc = (owner == s.host) ? mk.hostCardPk : mk.guestCardPk;
        if (!Dleq.verify(cardPkEnc, post.c1Enc, post.shareEnc, post.c, post.s)) {
            return;
        }

        (bool shareOk, Ristretto.Pt memory sharePt) = Ristretto.decode(post.shareEnc);
        if (!shareOk) {
            return; // unreachable in practice (Dleq.verify already decoded
                // this same encoding internally to pass) — kept explicit so
                // this function is total, per decision 5's spirit.
        }

        // All three checks passed.
        deckC2At[session][hand][post.pos] = c2Pt;
        postedShare[session][hand][post.pos][owner] = sharePt;
        sharePosted[session][hand][post.pos][owner] = true;
        // P4 extension (decision 8): timestamp cache for the phase-2 bank
        // clock's sole-obstacle computation.
        postedAt[session][hand][post.pos][owner] = block.timestamp;
        emit SharePosted(session, hand, post.pos, owner);
    }

    function postShares(bytes32 session, SharePost[] calldata posts) external {
        Session storage s = sessions[session];
        require(s.status == Status.Disputed, "not disputed");
        uint64 hand = markedHand[session];
        MarkerData storage mk = markerAt[session][hand];
        for (uint256 i = 0; i < posts.length; i++) {
            _postOneShare(session, hand, s, mk, posts[i]);
        }
    }

    // =====================================================================
    // P4 task 1 — phase-2 storage + shared helpers (dispatch-time
    // re-verification run first; see completion notes for the two
    // discrepancies it found against this doc's Inputs section:
    // `_consolidate`/`_resolveTerminal` both carry an extra `weiPerChip`
    // return/parameter beyond what the phase-4 plan's Inputs section
    // described, and `disputeOpenedAt` is `sessions[session].disputeOpenedAt`
    // — a `Session` struct field, not a standalone top-level mapping as
    // some of this phase's own prose assumed. Both are threaded through
    // correctly below.)
    // Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    /// A single accepted phase-2 on-chain action (decision 1 / task 1 step
    /// 1): field-identical to P3's `ActCandidate` MINUS `exists` and MINUS
    /// `seq` — every entry here is already a successfully-validated
    /// on-chain transaction (phase2Act, task 4), never a stored-but-
    /// possibly-wrong guess, so P3's dual-candidate-per-slot equivocation
    /// flag has no meaning here (no equivocation-shaped misconduct
    /// category exists in phase 2). `seq` is not stored either: it is
    /// fully determined at read time (`_phase2Setup`'s `baseSeq` plus this
    /// entry's own index in the array) because `phase2Act`'s own
    /// chain-link check (task 4) accepts an action only when its `seq`
    /// equals the then-current chain's `lastAcceptedSeq + 1` — so
    /// successive entries are always `baseSeq, baseSeq+1, baseSeq+2, ...`
    /// by construction, never gapped or reordered.
    struct Phase2Cand {
        address signer;
        uint8 action;
        uint256 amount;
        bytes32 prev;
        bytes32 actionHash;
        uint40 filedAt;
    }

    /// Append-only, ordered by seq, written only by a successful
    /// `phase2Act` call (task 4). No dual-slot storage: the turn/chain-link
    /// check rejects anything but the single next legal action before it
    /// is ever stored, so there is no second candidate to collide with at
    /// any seq (task 1 step 1, task 8 step 8's regression fixture).
    mapping(bytes32 => mapping(uint64 => Phase2Cand[])) public phase2ActionsAt;

    /// Birth timestamps (decision 6): index by `uint8(BettingReplay.Street)`
    /// — 1=Flop, 2=Turn, 3=River (index 0 unused, Preflop has no birth
    /// event). Stamped the instant a live `phase2Act` (task 4) transitions
    /// the hand INTO that street; an all-in cascade crossing several
    /// streets in one call stamps each crossed street with the same
    /// `block.timestamp` (born together). `showdownBirthAt` is stamped the
    /// instant `TermKind.COMPLETE` is reached live (mirrors P3's
    /// `completingFiledAt`, just possibly a live phase-2 timestamp instead
    /// of a frozen-evidence one) — kept as its own mapping rather than
    /// `birthAt`'s unused index 3, an explicit implementer's-choice this
    /// task doc allows.
    mapping(bytes32 => mapping(uint64 => uint256[4])) public birthAt;
    mapping(bytes32 => mapping(uint64 => uint256)) public showdownBirthAt;

    /// Task 1 step 4: the disclosed extension's own timestamp cache
    /// (`postShares`, task 2 writes it) — keyed `session => hand => pos =>
    /// player => timestamp`. Read by `_readyTime`'s sole-obstacle check.
    mapping(bytes32 => mapping(uint64 => mapping(uint8 => mapping(address => uint256)))) public postedAt;

    /// Decision 2: thrown only from `_resolvePendingPhase2` (task 7) when
    /// `_consolidatePhase2` itself still finds the hand pending — evidence
    /// exists, phase 2 is genuinely running, nobody's bank has emptied yet.
    /// Distinct from `PendingContinuation` (P3's meaning: "phase 1 alone
    /// doesn't terminate," never thrown by this phase — its one throw site
    /// is replaced, task 7).
    error Phase2InProgress();

    event Phase2ActFiled(bytes32 indexed session, uint64 hand, uint64 seq, uint8 action);

    /// P3 task 6 step 2's own filter, reused by direct alias rather than
    /// duplicated (decision 1): `_buildOrdered` already IS "the frozen,
    /// in-window prefix" this phase starts every phase-2 continuation
    /// from — walking `actionsAt` from seq 0, in-window candidates only,
    /// stopping at the first gap. Calling it here under this phase's own
    /// vocabulary name, not re-deriving its loop.
    function _frozenPrefix(bytes32 session, uint64 hand) internal view returns (BettingReplay.Cand[] memory) {
        return _buildOrdered(session, hand);
    }

    /// Decision 8's own helper: board-only required positions for a
    /// to-act player's bank clock — deliberately NOT P3's terminal-
    /// completeness set (`_requiredPositions`, which always additionally
    /// requires hole positions). Hole shares are never postable before a
    /// completing action births `showdownBirthAt` (§5.2) — gating the
    /// clock on them would deadlock every pre-showdown decision. Reuses
    /// the exact `protocol.ts:52-58` position constants `_requiredPositions`
    /// already cites, board-only.
    function _requiredBoardPositions(BettingReplay.Street street) internal pure returns (uint8[] memory positions) {
        uint256 count = 0;
        if (street >= BettingReplay.Street.Flop) count += 3;
        if (street >= BettingReplay.Street.Turn) count += 1;
        if (street == BettingReplay.Street.River) count += 1;

        positions = new uint8[](count);
        uint256 idx = 0;
        if (street >= BettingReplay.Street.Flop) {
            positions[idx++] = 5;
            positions[idx++] = 6;
            positions[idx++] = 7;
        }
        if (street >= BettingReplay.Street.Turn) {
            positions[idx++] = 9;
        }
        if (street == BettingReplay.Street.River) {
            positions[idx++] = 11;
        }
    }

    /// Bundles every "replay this hand's phase-2 continuation" input
    /// behind one memory pointer — split out purely for stack-depth
    /// reasons (same rationale as every other split in this file):
    /// `phase2Act`/`_bankSpent`/`_consolidatePhase2` each need all seven
    /// of these fields, and passing them as loose parameters (7 stack
    /// slots each call) is exactly what pushes this file's other
    /// multi-return functions over the legacy codegen's stack-slot
    /// ceiling without `--via-ir`.
    struct Phase2Ctx {
        BettingReplay.Cand[] frozen;
        uint256 baseSeq;
        bool buttonIsHost;
        uint256 sb;
        uint256 bb;
        uint256 chipStackHost;
        uint256 chipStackGuest;
    }

    /// Task-ordering note's own pattern (a real, adversarial-tested unit
    /// resequenced ahead of `phase2Act`): the frozen prefix, the chip-space
    /// replay inputs, and `baseSeq` — the seq at which phase-2 candidates
    /// begin, derived (never stored) by replaying the frozen prefix ALONE
    /// once to learn its own `lastAcceptedSeq`.
    function _phase2Setup(bytes32 session, uint64 hand) internal view returns (Phase2Ctx memory ctx) {
        MarkerData storage mk = markerAt[session][hand];
        ctx.buttonIsHost = mk.button == 0;
        ctx.sb = mk.sb;
        ctx.bb = mk.bb;
        (, ctx.chipStackHost, ctx.chipStackGuest) = _chipBaseline(session, hand);
        ctx.frozen = _frozenPrefix(session, hand);

        (,,, uint256 lastAcceptedSeq,) =
            BettingReplay.replay(ctx.buttonIsHost, ctx.sb, ctx.bb, ctx.chipStackHost, ctx.chipStackGuest, ctx.frozen);
        ctx.baseSeq = (lastAcceptedSeq == BettingReplay.NO_SEQ) ? 0 : lastAcceptedSeq + 1;
    }

    /// Decision 1: builds ONE array — the frozen prefix followed by the
    /// first `count` entries of `phase2ActionsAt[session][hand]` (cast to
    /// `BettingReplay.Cand`, seq assigned as `ctx.baseSeq + i` per this
    /// phase's own seq-derivation, task 1 step 1's struct comment) — never
    /// a second copy of `BettingReplay`'s own loop.
    function _combinePhase2(bytes32 session, uint64 hand, Phase2Ctx memory ctx, uint256 count)
        internal
        view
        returns (BettingReplay.Cand[] memory combined)
    {
        Phase2Cand[] storage hist = phase2ActionsAt[session][hand];
        Session storage s = sessions[session];
        combined = new BettingReplay.Cand[](ctx.frozen.length + count);
        for (uint256 i = 0; i < ctx.frozen.length; i++) {
            combined[i] = ctx.frozen[i];
        }
        for (uint256 i = 0; i < count; i++) {
            Phase2Cand storage c = hist[i];
            combined[ctx.frozen.length + i] = BettingReplay.Cand({
                seq: uint64(ctx.baseSeq + i),
                signerIsHost: c.signer == s.sessionKeyHost,
                action: BettingReplay.ActionKind(c.action),
                amount: c.amount,
                filedAt: c.filedAt
            });
        }
    }

    /// `_combinePhase2` plus the `BettingReplay.replay` call on the result
    /// — split out for stack-depth reasons, and because both `phase2Act`
    /// and `_consolidatePhase2` need exactly this pair of calls.
    function _replayPhase2(bytes32 session, uint64 hand, Phase2Ctx memory ctx, uint256 count)
        internal
        view
        returns (
            BettingReplay.TermKind kind,
            bool folderIsHost,
            BettingReplay.State memory finalState,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        )
    {
        BettingReplay.Cand[] memory combined = _combinePhase2(session, hand, ctx, count);
        (kind, folderIsHost, finalState, lastAcceptedSeq, completingFiledAt) =
            BettingReplay.replay(ctx.buttonIsHost, ctx.sb, ctx.bb, ctx.chipStackHost, ctx.chipStackGuest, combined);
    }

    /// Decision 8's `H0`-or-last-handoff baseline, as a function of "how
    /// many phase-2 candidates existed at this node" (`priorCount`) rather
    /// than always reading the live/full array — this is what lets
    /// `_bankSpent` (below) ask for a HISTORICAL node's own baseline, not
    /// only the current one.
    function _phase2Baseline(bytes32 session, uint64 hand, uint256 priorCount) internal view returns (uint256) {
        if (priorCount == 0) {
            return sessions[session].disputeOpenedAt + window;
        }
        return phase2ActionsAt[session][hand][priorCount - 1].filedAt;
    }

    /// Decision 8's sole-obstacle readyTime, as a pure function of a
    /// caller-supplied `baseline` and `street` — deliberately NOT
    /// re-deriving either from stored arrays itself, so this same function
    /// serves both the live to-act node (caller passes the current
    /// baseline/street) and `_bankSpent`'s own historical per-node
    /// re-derivation (caller passes each node's own baseline/street)
    /// without this function needing to know which case it is in. (This
    /// is a disclosed signature deviation from the phase-4 plan doc's own
    /// drafted `_readyTime(..., Phase2Cand[] memory combined,
    /// BettingReplay.State memory finalState)` — that draft's `combined`
    /// parameter is typed inconsistently across the doc's own task 3 (a
    /// `Phase2Cand[]`) and task 5 (a `BettingReplay.Cand[]`, used for a
    /// DIFFERENT purpose entirely), and neither draft actually needs
    /// anything from that array beyond the baseline/street this signature
    /// takes directly. Recorded as a completion-notes finding, not
    /// papered over.)
    ///
    /// `started == false` iff any required board position lacks its
    /// COUNTERPARTY's posting (decision 8: a player's own missing posting
    /// never pauses their own clock — the lookup below structurally
    /// excludes it by only ever reading `counterparty`'s entry).
    function _readyTime(bytes32 session, uint64 hand, bool forHost, uint256 baseline, BettingReplay.Street street)
        internal
        view
        returns (bool started, uint256 readyTime)
    {
        Session storage s = sessions[session];
        address counterparty = forHost ? s.guest : s.host;
        uint8[] memory positions = _requiredBoardPositions(street);

        readyTime = baseline;
        for (uint256 i = 0; i < positions.length; i++) {
            uint256 t = postedAt[session][hand][positions[i]][counterparty];
            if (t == 0) {
                return (false, 0);
            }
            if (t > readyTime) readyTime = t;
        }
        started = true;
    }

    /// Decision 9: re-walks `phase2ActionsAt`, summing THIS player's own
    /// candidates' contribution `filedAt(i) - readyTimeAtNode(i)` — a
    /// `view` re-derivation, nothing stored (decision 3's laziness).
    /// Chosen implementation (task 3 step 2's own "implementer's choice"):
    /// replay `BettingReplay.replay` fresh on each successive prefix
    /// (frozen chain plus the phase-2 candidates strictly before node i)
    /// to learn that node's own street — the identical cost shape
    /// `phase2Act` itself already pays per call, not optimized further
    /// (decision 3). A node reached while the clock had not yet started
    /// (`started == false` — an "acting blind" decision, decision 5/8)
    /// contributes zero: nothing retroactively penalizes an action taken
    /// before its own clock could ever have begun.
    function _bankSpent(bytes32 session, uint64 hand, bool forHost) internal view returns (uint256 spent) {
        Phase2Cand[] storage hist = phase2ActionsAt[session][hand];
        uint256 n = hist.length;
        if (n == 0) return 0;

        Phase2Ctx memory ctx = _phase2Setup(session, hand);
        address playerKey = forHost ? sessions[session].sessionKeyHost : sessions[session].sessionKeyGuest;

        for (uint256 i = 0; i < n; i++) {
            if (hist[i].signer != playerKey) continue;

            (,, BettingReplay.State memory stAtNode,,) = _replayPhase2(session, hand, ctx, i);
            uint256 baseline = _phase2Baseline(session, hand, i);
            (bool started, uint256 rt) = _readyTime(session, hand, forHost, baseline, stAtNode.street);
            if (started && hist[i].filedAt > rt) {
                spent += hist[i].filedAt - rt;
            }
        }
    }

    /// Formats §5: `prev₀ = markerHash` of this hand — recomputed from
    /// stored `markerAt`/`receiptAt` (task 1's dispatch-time
    /// re-verification finding: `MarkerData` caches everything the marker
    /// preimage needs except `receiptHash`, itself separately available as
    /// `receiptAt[session][hand-1]`, which the marker's own acceptance
    /// check already pinned equal to `m.receiptHash` at filing time).
    function _markerHashForHand(bytes32 session, uint64 hand) internal view returns (bytes32) {
        MarkerData storage mk = markerAt[session][hand];
        Marker memory m = Marker({
            hand: hand,
            receiptHash: receiptAt[session][hand - 1],
            deckRoot: mk.deckRoot,
            hostShareRoot: mk.hostShareRoot,
            guestShareRoot: mk.guestShareRoot,
            hostCardPk: mk.hostCardPk,
            guestCardPk: mk.guestCardPk,
            button: mk.button,
            sb: mk.sb,
            bb: mk.bb,
            startingChips: mk.startingChips
        });
        return _markerHash(session, m);
    }

    /// The frozen realm's own disambiguation: at most one stored candidate
    /// per signer exists at any seq (`_fileOneAction`'s slot rule — a
    /// same-signer resubmission never creates a second slot), so knowing
    /// WHICH signer was actually accepted at `seq` (via a one-time-per-hand
    /// sub-replay of the strict sub-prefix, `.seq < seq` — its own
    /// `finalState.toActIsHost` is exactly that signer, since nothing past
    /// `seq` was ever applied) is enough to pick the right slot's
    /// `actionHash` with no ambiguity. Reuses `BettingReplay.replay`
    /// unmodified (decision 1) rather than re-deriving the walk loop; paid
    /// at most once per hand's phase-2 continuation (only the very first
    /// `phase2Act` call for a hand ever needs a frozen-realm `prev`— every
    /// later call's `prev` is a direct `phase2ActionsAt` index, task 1
    /// step 1's struct comment).
    function _frozenActionHashAt(bytes32 session, uint64 hand, uint256 seq, Phase2Ctx memory ctx)
        internal
        view
        returns (bytes32)
    {
        uint256 subCount = 0;
        for (uint256 i = 0; i < ctx.frozen.length; i++) {
            if (ctx.frozen[i].seq < seq) subCount++;
        }
        BettingReplay.Cand[] memory subPrefix = new BettingReplay.Cand[](subCount);
        uint256 j = 0;
        for (uint256 i = 0; i < ctx.frozen.length; i++) {
            if (ctx.frozen[i].seq < seq) subPrefix[j++] = ctx.frozen[i];
        }
        (,, BettingReplay.State memory stBefore,,) =
            BettingReplay.replay(ctx.buttonIsHost, ctx.sb, ctx.bb, ctx.chipStackHost, ctx.chipStackGuest, subPrefix);
        bool wantHostSigner = stBefore.toActIsHost;

        Session storage s = sessions[session];
        uint256 cutoff = s.disputeOpenedAt + window;
        ActCandidate[2] storage slots = actionsAt[_actionSlotKey(session, hand, uint64(seq))];
        for (uint256 i = 0; i < 2; i++) {
            bool isHostSigner = slots[i].signer == s.sessionKeyHost;
            if (slots[i].exists && slots[i].filedAt < cutoff && isHostSigner == wantHostSigner) {
                return slots[i].actionHash;
            }
        }
        return bytes32(0); // unreachable: the sub-replay already proved a candidate exists here
    }

    /// Task 4 step 4's chain-link check target: the actionHash the new
    /// action's own `prev` field must equal. Three cases: no candidate
    /// accepted anywhere yet (genesis, formats §5's `prev₀ = markerHash`);
    /// the last accepted seq is itself phase-2 (direct array index, no
    /// ambiguity); the last accepted seq is still in the frozen realm
    /// (one-time disambiguation, `_frozenActionHashAt`).
    function _expectedPrev(bytes32 session, uint64 hand, uint256 lastAcceptedSeq, Phase2Ctx memory ctx)
        internal
        view
        returns (bytes32)
    {
        if (lastAcceptedSeq == BettingReplay.NO_SEQ) {
            return _markerHashForHand(session, hand);
        }
        if (lastAcceptedSeq >= ctx.baseSeq) {
            return phase2ActionsAt[session][hand][lastAcceptedSeq - ctx.baseSeq].actionHash;
        }
        return _frozenActionHashAt(session, hand, lastAcceptedSeq, ctx);
    }

    /// Decision 6's own reduction: `max(showdownBirthAt, birthAt[c] for
    /// every board class c this street's own thresholds include)` — the
    /// SAME three Flop/Turn/River thresholds `_requiredBoardPositions`
    /// uses (decision 6's explicit note: deliberately this phase's own
    /// board-only set, never P3's terminal-completeness set), fed through
    /// unmodified into `dueAt(session, completingFiledAt)` exactly where
    /// P3 already declared that parameter. When no live phase-2 street
    /// transition ever happened (a purely-frozen COMPLETE — every
    /// `birthAt`/`showdownBirthAt` entry still zero for this hand), every
    /// `max` here is a no-op and `frozenCompletingFiledAt` (P3's own
    /// value) survives unchanged.
    function _effectiveCompletingFiledAt(
        bytes32 session,
        uint64 hand,
        uint256 frozenCompletingFiledAt,
        BettingReplay.Street street
    ) internal view returns (uint256 result) {
        result = frozenCompletingFiledAt;
        uint256 sbAt = showdownBirthAt[session][hand];
        if (sbAt > result) result = sbAt;
        if (street >= BettingReplay.Street.Flop) {
            uint256 b = birthAt[session][hand][uint8(BettingReplay.Street.Flop)];
            if (b > result) result = b;
        }
        if (street >= BettingReplay.Street.Turn) {
            uint256 b = birthAt[session][hand][uint8(BettingReplay.Street.Turn)];
            if (b > result) result = b;
        }
        if (street == BettingReplay.Street.River) {
            uint256 b = birthAt[session][hand][uint8(BettingReplay.Street.River)];
            if (b > result) result = b;
        }
    }

    // =====================================================================
    // P4 task 5 — _consolidatePhase2: the combined-array wrapper and
    // bank-fold discovery (decisions 1, 3). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    /// Decision 3: genuinely lazy, like `_consolidate` — `view`, no
    /// storage write, a bank-fold is discovered here, never recorded. Note
    /// the return tuple carries `weiPerChip` as a 5th value beyond the
    /// phase-4 plan doc's drafted 4-value signature — task 1 step 0's
    /// dispatch-time re-verification found `_resolveTerminal` (P3-shipped)
    /// takes `weiPerChip` as an explicit 6th parameter, so this function
    /// must produce one for `resolve()`/`_crystallizeMaturedDuties` (task
    /// 7) to pass through; recorded as a completion-notes finding.
    function _consolidatePhase2(bytes32 session)
        internal
        view
        returns (
            BettingReplay.TermKind kind,
            address folder,
            BettingReplay.State memory finalState,
            uint256 effectiveCompletingFiledAt,
            uint256 weiPerChip
        )
    {
        uint64 hand = markedHand[session];
        Phase2Ctx memory ctx = _phase2Setup(session, hand);
        (weiPerChip,,) = _chipBaseline(session, hand);

        uint256 priorCount = phase2ActionsAt[session][hand].length;
        (BettingReplay.TermKind k, bool folderIsHost, BettingReplay.State memory st,, uint256 completingFiledAt) =
            _replayPhase2(session, hand, ctx, priorCount);

        if (k != BettingReplay.TermKind.NONE) {
            if (k == BettingReplay.TermKind.COMPLETE) {
                effectiveCompletingFiledAt = _effectiveCompletingFiledAt(session, hand, completingFiledAt, st.street);
            }
            address f = folderIsHost ? sessions[session].host : sessions[session].guest;
            return (k, f, st, effectiveCompletingFiledAt, weiPerChip);
        }

        (kind, folder) = _consolidatePhase2Pending(session, hand, priorCount, st);
        finalState = st;
    }

    /// Split out of `_consolidatePhase2` purely for stack-depth reasons
    /// (same rationale as every other split in this file): the
    /// still-pending branch's own bank-fold discovery (decision 3/9).
    /// `effectiveCompletingFiledAt` stays 0 for both possible outcomes
    /// here (NONE and FOLD never owe a share-duty birth), matching
    /// `_consolidatePhase2`'s own original single-function behavior.
    function _consolidatePhase2Pending(bytes32 session, uint64 hand, uint256 priorCount, BettingReplay.State memory st)
        internal
        view
        returns (BettingReplay.TermKind kind, address folder)
    {
        uint256 baseline = _phase2Baseline(session, hand, priorCount);
        (bool started, uint256 rt) = _readyTime(session, hand, st.toActIsHost, baseline, st.street);
        if (!started) {
            return (BettingReplay.TermKind.NONE, address(0));
        }

        uint256 spent = _bankSpent(session, hand, st.toActIsHost);
        uint256 elapsed = block.timestamp > rt ? block.timestamp - rt : 0;
        // Decision 9's boundary: strictly exceeding the bank folds; equal
        // is still accepted (the actor-favoring convention this arc uses
        // uniformly for every deadline).
        if (spent + elapsed > bank) {
            address foldedPlayer = st.toActIsHost ? sessions[session].host : sessions[session].guest;
            return (BettingReplay.TermKind.FOLD, foldedPlayer);
        }
        return (BettingReplay.TermKind.NONE, address(0));
    }

    // =====================================================================
    // P4 task 4 — phase2Act: signature, turn/chain checks, open-fold,
    // canonical amounts (decisions 4, 5). Files: contracts/src/ChannelV2.sol.
    // =====================================================================

    function phase2Act(bytes32 session, Act calldata a, bytes calldata sig) external {
        Session storage s = sessions[session];
        require(s.status == Status.Disputed, "not disputed");
        // The frozen prefix (P3's own filter, `_frozenPrefix`) is only
        // genuinely frozen once phase 1's window has closed — accepting a
        // phase-2 action before then would let more in-window `fileActions`
        // evidence change `_phase2Setup`'s own `baseSeq` retroactively out
        // from under an already-accepted phase-2 candidate. Not one of the
        // phase-4 doc's own enumerated steps; added here as a correctness
        // necessity this implementation's seq-derivation design depends on
        // (flagged in completion notes).
        require(block.timestamp >= s.disputeOpenedAt + window, "window open");

        uint64 hand = markedHand[session];
        require(hand > 0, "no marked hand");
        require(a.hand == hand, "wrong hand");
        require(a.action <= uint8(BettingReplay.ActionKind.Bet), "bad action");
        if (BettingReplay.ActionKind(a.action) != BettingReplay.ActionKind.Bet) {
            require(a.amount == 0, "amount must be 0");
        }

        bytes32 actionHash = _actionHash(session, a);
        address signer = _recoverRaw(actionHash, sig);
        require(signer == s.sessionKeyHost || signer == s.sessionKeyGuest, "bad signer");

        (Phase2Ctx memory ctx, BettingReplay.State memory finalState) =
            _phase2ActValidate(session, hand, a, signer == s.sessionKeyHost);

        _phase2ActApply(session, hand, a, actionHash, signer, ctx, finalState);
    }

    /// Split out of `phase2Act` purely for stack-depth reasons (same
    /// rationale as every other split in this file — the legacy codegen's
    /// stack-slot ceiling without `--via-ir`): every check up through the
    /// bank check (task 4 steps 2-5), returning the validated `ctx` and
    /// the pre-action `finalState` for `_phase2ActApply` to apply the new
    /// action onto.
    function _phase2ActValidate(bytes32 session, uint64 hand, Act calldata a, bool signerIsHost)
        internal
        view
        returns (Phase2Ctx memory ctx, BettingReplay.State memory finalState)
    {
        ctx = _phase2Setup(session, hand);
        uint256 priorCount = phase2ActionsAt[session][hand].length;

        (BettingReplay.TermKind kind,, BettingReplay.State memory st, uint256 lastAcceptedSeq,) =
            _replayPhase2(session, hand, ctx, priorCount);
        require(kind == BettingReplay.TermKind.NONE, "already terminal");
        require(st.toActIsHost == signerIsHost, "not your turn");

        uint256 expectedSeq = (lastAcceptedSeq == BettingReplay.NO_SEQ) ? 0 : lastAcceptedSeq + 1;
        require(a.seq == expectedSeq, "bad chain link");
        require(a.prev == _expectedPrev(session, hand, lastAcceptedSeq, ctx), "bad chain link");

        _phase2BankCheck(session, hand, signerIsHost, priorCount, st.street);

        finalState = st;
    }

    /// Bank check (decision 9), computed BEFORE applying the new action —
    /// the to-act player's own readyTime/spend as of right now. Split out
    /// purely for stack-depth reasons.
    function _phase2BankCheck(
        bytes32 session,
        uint64 hand,
        bool signerIsHost,
        uint256 priorCount,
        BettingReplay.Street street
    ) internal view {
        uint256 baseline = _phase2Baseline(session, hand, priorCount);
        (bool started, uint256 rt) = _readyTime(session, hand, signerIsHost, baseline, street);
        if (started) {
            uint256 spentSoFar = _bankSpent(session, hand, signerIsHost);
            uint256 remaining = bank > spentSoFar ? bank - spentSoFar : 0;
            uint256 elapsed = block.timestamp > rt ? block.timestamp - rt : 0;
            // This specific revert means the true on-chain state is
            // already a structural bank-fold at this node — the caller
            // should call resolve() instead, which discovers the same
            // fold via _consolidatePhase2 (task 5) and settles it.
            require(elapsed <= remaining, "bank spent");
        }
        // else: the clock never started (a required counterparty posting
        // is still missing) — "acting blind" (decision 5/8) proceeds
        // unconditionally, no bank check at all.
    }

    /// Applies the validated action to `finalState`, runs the street-close
    /// cascade if it round-closed, and appends the new `Phase2Cand`. Split
    /// out of `phase2Act` purely for stack-depth reasons.
    function _phase2ActApply(
        bytes32 session,
        uint64 hand,
        Act calldata a,
        bytes32 actionHash,
        address signer,
        Phase2Ctx memory ctx,
        BettingReplay.State memory finalState
    ) internal {
        BettingReplay.ActionKind actionKind = BettingReplay.ActionKind(a.action);
        // Action application (decision 5): open-fold bypasses
        // BettingReplay's own legality gate entirely; every other action
        // does not.
        if (actionKind == BettingReplay.ActionKind.Fold) {
            finalState.hasFolded = true;
            finalState.foldedIsHost = finalState.toActIsHost;
            finalState.closed = true;
        } else {
            bool ok;
            (finalState, ok) = BettingReplay.applyAction(finalState, finalState.toActIsHost, actionKind, a.amount);
            require(ok, "illegal action");

            // Street-close cascade (task 4 step 7): only for a genuine
            // round closure, never a fold — the fold branch above never
            // reaches here.
            while (finalState.closed) {
                bool stillLive;
                (finalState, stillLive) = BettingReplay.closeAndAdvance(finalState, ctx.buttonIsHost);
                if (!stillLive) {
                    showdownBirthAt[session][hand] = block.timestamp;
                    break;
                }
                uint8 streetIdx = uint8(finalState.street);
                if (streetIdx >= 1 && streetIdx <= 3) {
                    birthAt[session][hand][streetIdx] = block.timestamp;
                }
            }
        }

        phase2ActionsAt[session][hand].push(
            Phase2Cand({
                signer: signer,
                action: a.action,
                amount: a.amount,
                prev: a.prev,
                actionHash: actionHash,
                filedAt: uint40(block.timestamp)
            })
        );

        emit Phase2ActFiled(session, hand, a.seq, a.action);
    }


    // =====================================================================
    // Task 6 — pull-payment
    // =====================================================================

    /// Checks-effects-interactions, same pattern V1's `_pay` uses
    /// (`Channel.sol:172-175`): zero the ledger before the external call,
    /// so a stuck withdrawer never blocks resolve() (spec §9.3's "one
    /// reverting payee kills the whole payout").
    ///
    /// Invariant this whole contract maintains per session, asserted once
    /// a session reaches Closed and never mid-session (spec §1.4):
    /// `depositedHost + depositedGuest + bondHost + bondGuest ==
    ///  paidOut[session] + burned[session]`.
    /// Every code path that credits a payout increments `paidOut[session]`
    /// by the same amount; `_burnBond` (task 1) is the only way
    /// `burned[session]` grows. No other function writes either field.
    function withdraw() external {
        uint256 amt = credits[msg.sender];
        require(amt > 0, "nothing to withdraw");
        credits[msg.sender] = 0;
        (bool ok,) = msg.sender.call{value: amt}("");
        require(ok, "transfer failed");
    }
}
