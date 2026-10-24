// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {ChannelV2} from "../src/ChannelV2.sol";
import {BettingReplay} from "../src/BettingReplay.sol";
import {Ristretto} from "../src/Ristretto.sol";
import {Dleq} from "../src/Dleq.sol";
import {Evidence} from "../src/Evidence.sol";
import {Evaluator7} from "../src/Evaluator7.sol";
import {Vectors} from "./vectors/Vectors.sol";

/// Phase 2 test suite (tasks 8 and 9). See
/// docs/superpowers/plans/2026-08-17-v2-cash-settlement/phase-2-money-frame.md
/// for the build brief this file implements, and `decisions.md` (cited as
/// D<n>) / `review-findings.md` (cited as AF-<n>) for the cross-phase
/// rulings it tests against.
///
/// D16/D18: the happy path (task 8) is built from the committed shared
/// vectors in `test/vectors/{p1-vectors.json,Vectors.sol}` (copied from the
/// poker repo, sha256-gated by `test/vectors/CHECKSUMS.sha256`) — never
/// independently derived. `vm.sign`-built artefacts are used only for
/// negative/mutation tests (task 9), which by construction need an invalid
/// artefact a vector (always valid) cannot supply.
///
/// Recorded deviation from the phase doc's literal instruction to `import
/// {Vectors} from "./vectors/Vectors.sol"`: the copied `Vectors.sol` (byte-
/// identical to the poker repo's committed original — confirmed by the
/// `sha256sum -c` gate) does not compile under Solidity, at any version
/// (0.8.24 and 0.8.35 both tried) — solc's address-checksum-literal
/// validation (error 9429) rejects the un-checksummed lowercase 40-hex
/// `HOST`/`GUEST`/`CONTRACT` address literals in `gen.mts`'s renderer,
/// regardless of the `uint160(...)` wrapper around them. This is a P1-owned
/// defect in the vector generator's Solidity output, not something P2 may
/// fix (editing the copy would break the D18 hash-parity gate, which is the
/// entire point of the gate). `contracts/foundry.toml` gained two small,
/// necessary entries so the file can sit on disk (satisfying the hash gate)
/// without ever being handed to solc: `skip = ["test/vectors/Vectors.sol"]`
/// and `fs_permissions` for reading `./test/vectors` (needed for the
/// approach below). This test file instead consumes the *other* canonical,
/// identically hash-gated vector artefact — `p1-vectors.json` — via
/// `vm.readFile` + `vm.parseJson*`, which carries the exact same data. See
/// this dispatch's completion notes for the full citation and reasoning.
contract ChannelV2Test is Test {
    ChannelV2 channel;

    uint256 constant WINDOW = 24 hours;
    uint256 constant BANK = 6 hours;
    uint256 constant GRACE = 6 hours;

    // ---- D15 short-duration deploy parameters (tasks 8-9, AF-39) ----
    // `bank != grace` is deliberate (fix-round-1 C10, phase-4 doc task 9
    // step 4): the production values make bank and grace numerically
    // identical, which would let a constructor-argument swap compile,
    // deploy, and pass every test that never distinguishes the two by
    // value. These ratios roughly mirror the spec's 24h/6h/6h without
    // copying D15's prose verbatim (D15 pins the pattern, not the numbers).
    uint256 constant SHORT_WINDOW = 100;
    uint256 constant SHORT_BANK = 30;
    uint256 constant SHORT_GRACE = 45;

    // ---- wallet identities (D2: distinct from session keys) ----
    uint256 constant HOST_WALLET_PK = 0xA11CE;
    uint256 constant GUEST_WALLET_PK = 0xB0B;
    address hostWallet;
    address guestWallet;

    // ---- default session-key identities for hand-built (vm.sign) tests ----
    // Distinct from the vector's fixed session keys (1001/2002) purely to
    // keep the two lineages visually separate in test output; either pair
    // would work equally well since state resets between test functions.
    uint256 constant HOST_SESSION_PK = 0xCAFE1;
    uint256 constant GUEST_SESSION_PK = 0xCAFE2;

    // ---- the vector's fixed session-key identities (task 8, D16) ----
    // gen.mts: hostSecretKey = beU256(1001), guestSecretKey = beU256(2002).
    // vm.addr(1001)/vm.addr(2002) reproduce the vector's HOST/GUEST
    // addresses exactly (asserted in setUp against the JSON's keys.host/
    // keys.guest.address fields) — these are session keys (raw-digest
    // signers of receipts/markers), not wallet identities.
    uint256 constant VECTOR_HOST_SESSION_PK = 1001;
    uint256 constant VECTOR_GUEST_SESSION_PK = 2002;

    // AF-32: filler `startingChips` for hand-built (non-vector) marker
    // fixtures whose sessions deposit 0.2 ether each -- 0.2 ether / 2000 =
    // 1e14 weiPerChip, exact, matching the value `200 * bb` (bb=10) used to
    // produce implicitly before the signed field existed (`_setupDisputed-
    // MarkedHand1`'s own comment). Any fixture that reaches `_chipBaseline`
    // (i.e. drives a session through `resolve()`'s consolidation path) with
    // these 0.2-ether-deposit, bb=10 markers depends on this exact value.
    uint256 constant FILLER_STARTING_CHIPS = 2000;

    // Loaded once in setUp() from test/vectors/p1-vectors.json.
    bytes32 vecSession;
    address vecContract;
    uint256 vecChainId;

    function setUp() public {
        string memory json = vm.readFile("test/vectors/p1-vectors.json");
        vecSession = vm.parseJsonBytes32(json, ".binding.session");
        vecContract = vm.parseJsonAddress(json, ".binding.contract");
        vecChainId = vm.parseJsonUint(json, ".binding.chainId");

        // D16: the vectors were generated bound to a fixed contract
        // address, chain id, and session id. Reproduce that exact binding
        // so the vector signatures recover against this contract instance:
        // deploy normally, then etch the runtime bytecode (which already
        // has window/bank/grace baked in as immutables, independent of
        // deployment address) onto the fixed target address. Storage is
        // unused before the etch, so nothing is lost.
        vm.chainId(vecChainId);
        ChannelV2 impl = new ChannelV2(WINDOW, BANK, GRACE);
        vm.etch(vecContract, address(impl).code);
        channel = ChannelV2(vecContract);

        hostWallet = vm.addr(HOST_WALLET_PK);
        guestWallet = vm.addr(GUEST_WALLET_PK);
        vm.deal(hostWallet, 1000 ether);
        vm.deal(guestWallet, 1000 ether);

        address vecHost = vm.parseJsonAddress(json, ".keys.host.address");
        address vecGuest = vm.parseJsonAddress(json, ".keys.guest.address");
        assertEq(vm.addr(VECTOR_HOST_SESSION_PK), vecHost, "vector host session key mismatch");
        assertEq(vm.addr(VECTOR_GUEST_SESSION_PK), vecGuest, "vector guest session key mismatch");
    }

    // =====================================================================
    // JSON vector loader (task 8 step 1/2, D16/D18) — reads
    // test/vectors/p1-vectors.json directly via forge's JSON cheatcodes.
    // `Vectors.sol` (the copied Solidity rendering of the same data) does
    // not compile under any solc version tried (see header comment) and is
    // never imported here; this is the byte-identical, hash-gated twin.
    // =====================================================================

    struct VecReceipt {
        uint64 hand;
        uint32 subseq;
        uint256 hostStack;
        uint256 guestStack;
        uint256 hostDeposit;
        uint256 guestDeposit;
        bool isFinal;
        bytes32 hash;
        bytes hostSig;
        bytes guestSig;
    }

    struct VecMarker {
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
        bytes hostSig;
        bytes guestSig;
    }

    function _vecReceipt(string memory json, uint256 i) internal pure returns (VecReceipt memory r) {
        string memory p = string.concat(".receipts[", vm.toString(i), "]");
        r.hand = uint64(vm.parseJsonUint(json, string.concat(p, ".hand")));
        r.subseq = uint32(vm.parseJsonUint(json, string.concat(p, ".subseq")));
        r.hostStack = vm.parseJsonUint(json, string.concat(p, ".hostStack"));
        r.guestStack = vm.parseJsonUint(json, string.concat(p, ".guestStack"));
        r.hostDeposit = vm.parseJsonUint(json, string.concat(p, ".hostDeposit"));
        r.guestDeposit = vm.parseJsonUint(json, string.concat(p, ".guestDeposit"));
        r.isFinal = vm.parseJsonBool(json, string.concat(p, ".final"));
        r.hash = vm.parseJsonBytes32(json, string.concat(p, ".hash"));
        r.hostSig = vm.parseJsonBytes(json, string.concat(p, ".hostSig"));
        r.guestSig = vm.parseJsonBytes(json, string.concat(p, ".guestSig"));
    }

    function _vecMarker(string memory json) internal pure returns (VecMarker memory m) {
        m.hand = uint64(vm.parseJsonUint(json, ".marker.hand"));
        m.receiptHash = vm.parseJsonBytes32(json, ".marker.receiptHash");
        m.deckRoot = vm.parseJsonBytes32(json, ".marker.deckRoot");
        m.hostShareRoot = vm.parseJsonBytes32(json, ".marker.hostShareRoot");
        m.guestShareRoot = vm.parseJsonBytes32(json, ".marker.guestShareRoot");
        m.hostCardPk = vm.parseJsonBytes32(json, ".marker.hostCardPk");
        m.guestCardPk = vm.parseJsonBytes32(json, ".marker.guestCardPk");
        string memory button = vm.parseJsonString(json, ".marker.button");
        m.button = keccak256(bytes(button)) == keccak256(bytes("host")) ? 0 : 1;
        m.sb = vm.parseJsonUint(json, ".marker.sb");
        m.bb = vm.parseJsonUint(json, ".marker.bb");
        m.startingChips = vm.parseJsonUint(json, ".marker.startingChips");
        m.hostSig = vm.parseJsonBytes(json, ".marker.hostSig");
        m.guestSig = vm.parseJsonBytes(json, ".marker.guestSig");
    }

    function _toReceipt(VecReceipt memory r) internal pure returns (ChannelV2.Receipt memory) {
        return ChannelV2.Receipt(r.hand, r.subseq, r.hostStack, r.guestStack, r.hostDeposit, r.guestDeposit, r.isFinal);
    }

    function _toMarker(VecMarker memory m) internal pure returns (ChannelV2.Marker memory) {
        return ChannelV2.Marker(
            m.hand,
            m.receiptHash,
            m.deckRoot,
            m.hostShareRoot,
            m.guestShareRoot,
            m.hostCardPk,
            m.guestCardPk,
            m.button,
            m.sb,
            m.bb,
            m.startingChips
        );
    }

    // =====================================================================
    // Signing helpers (task 8 step 2) — reused by every negative/mutation
    // test in task 9.
    // =====================================================================

    /// No EIP-191 prefix — signs the raw digest directly, mirroring
    /// `_recoverRaw`. Used for receipts and markers.
    function _sigRaw(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    /// EIP-191-prefixed, mirroring `_recoverEIP191`. Used only for
    /// session-key registration.
    function _sigEIP191(uint256 pk, bytes32 digest) internal pure returns (bytes memory) {
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethHash);
        return abi.encodePacked(r, s, v);
    }

    /// Replicates ChannelV2._binding (formats §1's universal binding rule).
    function _binding(bytes32 session) internal view returns (bytes memory) {
        return abi.encodePacked(address(channel), block.chainid, session);
    }

    /// Replicates ChannelV2._registrationHash (formats §6).
    function _registrationDigest(bytes32 session, address player, address sessionKey) internal view returns (bytes32) {
        return keccak256(abi.encodePacked(bytes1(0x04), "vault/sessionkey/v2", _binding(session), player, sessionKey));
    }

    function _registrationSig(uint256 walletPk, bytes32 session, address player, address sessionKey)
        internal
        view
        returns (bytes memory)
    {
        return _sigEIP191(walletPk, _registrationDigest(session, player, sessionKey));
    }

    /// Replicates ChannelV2._receiptHash (formats §3) for hand-built receipts.
    function _receiptDigest(bytes32 session, ChannelV2.Receipt memory r) internal view returns (bytes32) {
        bytes memory head = abi.encodePacked(bytes1(0x01), "vault/receipt/v2", _binding(session));
        bytes memory tail = abi.encodePacked(
            r.hand, r.subseq, r.hostStack, r.guestStack, r.hostDeposit, r.guestDeposit,
            r.isFinal ? bytes1(0x01) : bytes1(0x00)
        );
        return keccak256(abi.encodePacked(head, tail));
    }

    /// Replicates ChannelV2._markerHash (formats §4, AF-32 amendment: 14
    /// fields) for hand-built markers.
    function _markerDigest(bytes32 session, ChannelV2.Marker memory m) internal view returns (bytes32) {
        bytes memory head = abi.encodePacked(bytes1(0x02), "vault/marker/v2", _binding(session));
        bytes memory mid = abi.encodePacked(m.hand, m.receiptHash, m.deckRoot, m.hostShareRoot, m.guestShareRoot);
        bytes memory tail = abi.encodePacked(m.hostCardPk, m.guestCardPk, m.button, m.sb, m.bb, m.startingChips);
        return keccak256(abi.encodePacked(head, mid, tail));
    }

    function _mkReceipt(
        uint64 hand,
        uint32 subseq,
        uint256 hostStack,
        uint256 guestStack,
        uint256 hostDep,
        uint256 guestDep,
        bool isFinal
    ) internal pure returns (ChannelV2.Receipt memory) {
        return ChannelV2.Receipt(hand, subseq, hostStack, guestStack, hostDep, guestDep, isFinal);
    }

    function _mkMarker(
        uint64 hand,
        bytes32 receiptHash,
        uint8 button,
        uint256 sb,
        uint256 bb,
        uint256 startingChips
    ) internal pure returns (ChannelV2.Marker memory) {
        // deckRoot/shareRoots/cardPks: P2 never inspects their contents
        // (phase doc, task 4 step 1) — filler bytes32 values suffice here.
        return ChannelV2.Marker(
            hand,
            receiptHash,
            keccak256(abi.encodePacked("deck", hand)),
            keccak256(abi.encodePacked("hostShare", hand)),
            keccak256(abi.encodePacked("guestShare", hand)),
            keccak256(abi.encodePacked("hostPk", hand)),
            keccak256(abi.encodePacked("guestPk", hand)),
            button,
            sb,
            bb,
            startingChips
        );
    }

    function _signReceipt(bytes32 session, ChannelV2.Receipt memory r, uint256 hostSessionPk, uint256 guestSessionPk)
        internal
        view
        returns (bytes memory sigHost, bytes memory sigGuest)
    {
        bytes32 digest = _receiptDigest(session, r);
        sigHost = _sigRaw(hostSessionPk, digest);
        sigGuest = _sigRaw(guestSessionPk, digest);
    }

    function _signMarker(bytes32 session, ChannelV2.Marker memory m, uint256 hostSessionPk, uint256 guestSessionPk)
        internal
        view
        returns (bytes memory sigHost, bytes memory sigGuest)
    {
        bytes32 digest = _markerDigest(session, m);
        sigHost = _sigRaw(hostSessionPk, digest);
        sigGuest = _sigRaw(guestSessionPk, digest);
    }

    /// Build, sign (with the default hand-built session keys), and file a
    /// receipt in one call — keeps call sites' live-variable count low
    /// enough for legacy (non-IR) codegen (this repo's foundry.toml does
    /// not set via_ir), mirroring ChannelV2.sol's own stack-depth
    /// workarounds (see its `_receiptHash`/`_markerHash` comments).
    function _fileReceiptQuick(
        bytes32 session,
        uint64 hand,
        uint32 subseq,
        uint256 hostStack,
        uint256 guestStack,
        uint256 hostDep,
        uint256 guestDep,
        bool isFinal
    ) internal returns (ChannelV2.Receipt memory r) {
        r = _mkReceipt(hand, subseq, hostStack, guestStack, hostDep, guestDep, isFinal);
        (bytes memory sh, bytes memory sg) = _signReceipt(session, r, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, r, sh, sg);
    }

    /// Same idea for markers: filler deck/share/pk fields, button/sb/bb
    /// fixed at 0/5/10 (irrelevant to every P2 test — P2 never inspects
    /// their contents). `startingChips` is FILLER_STARTING_CHIPS (AF-32) —
    /// unlike the other filler fields, this one IS inspected, by
    /// `_chipBaseline`, whenever a caller drives the session all the way
    /// through `resolve()`.
    function _fileMarkerQuick(bytes32 session, uint64 hand, bytes32 receiptHash)
        internal
        returns (ChannelV2.Marker memory m)
    {
        m = _mkMarker(hand, receiptHash, 0, 5, 10, FILLER_STARTING_CHIPS);
        (bytes memory mh, bytes memory mg) = _signMarker(session, m, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileMarker(session, m, mh, mg);
    }

    /// Mirrors ChannelV2._computeBonds (decision 1) — the test computes the
    /// same numbers independently to size msg.value; if the contract's own
    /// arithmetic ever diverges, sessionBonds() reads it back and tests
    /// like test_S_bond_coverage_maxima catch the drift directly.
    function _ceilDiv(uint256 a, uint256 b) internal pure returns (uint256) {
        return (a + b - 1) / b;
    }

    function _expectedBonds(uint256 mHost, uint256 mGuest) internal pure returns (uint256 bondHost, uint256 bondGuest) {
        uint256 avgCeil = _ceilDiv(mHost + mGuest, 2);
        uint256 baseHost = avgCeil > mHost ? avgCeil : mHost;
        uint256 baseGuest = avgCeil > mGuest ? avgCeil : mGuest;
        bondHost = _ceilDiv(11 * baseHost, 10);
        bondGuest = _ceilDiv(11 * baseGuest, 10);
    }

    /// Generic open()+join() helper for hand-built (non-vector) tests: fresh
    /// wallets per call so tests can run multiple sessions without balance
    /// collisions, fixed default session keys unless the caller overrides.
    function _openJoin(
        bytes32 session,
        address hWallet,
        uint256 hWalletPk,
        address gWallet,
        uint256 gWalletPk,
        address hSessionKey,
        address gSessionKey,
        uint256 maxHost,
        uint256 maxGuest,
        uint256 hostDep,
        uint256 guestDep
    ) internal returns (uint256 bondHost, uint256 bondGuest) {
        vm.deal(hWallet, 1000 ether);
        vm.deal(gWallet, 1000 ether);
        (bondHost, bondGuest) = _expectedBonds(maxHost, maxGuest);

        _doOpen(session, hWallet, hWalletPk, gWallet, hSessionKey, maxHost, maxGuest, bondHost + hostDep);
        _doJoin(session, gWallet, gWalletPk, gSessionKey, bondGuest + guestDep);
    }

    /// Split out of _openJoin purely for legacy (non-IR) codegen stack
    /// depth — this repo's foundry.toml does not set via_ir, and
    /// _openJoin's 11 parameters plus locals overflow it otherwise. No
    /// behavior change.
    function _doOpen(
        bytes32 session,
        address hWallet,
        uint256 hWalletPk,
        address gWallet,
        address hSessionKey,
        uint256 maxHost,
        uint256 maxGuest,
        uint256 value
    ) internal {
        bytes memory hReg = _registrationSig(hWalletPk, session, hWallet, hSessionKey);
        vm.prank(hWallet);
        channel.open{value: value}(session, gWallet, maxHost, maxGuest, hSessionKey, hReg);
    }

    function _doJoin(bytes32 session, address gWallet, uint256 gWalletPk, address gSessionKey, uint256 value)
        internal
    {
        bytes memory gReg = _registrationSig(gWalletPk, session, gWallet, gSessionKey);
        vm.prank(gWallet);
        channel.join{value: value}(session, gSessionKey, gReg);
    }

    /// Convenience overload: default wallets/session keys, equal deposits.
    function _openJoinDefault(bytes32 session, uint256 maxHost, uint256 maxGuest, uint256 hostDep, uint256 guestDep)
        internal
        returns (uint256 bondHost, uint256 bondGuest)
    {
        return _openJoin(
            session,
            hostWallet,
            HOST_WALLET_PK,
            guestWallet,
            GUEST_WALLET_PK,
            vm.addr(HOST_SESSION_PK),
            vm.addr(GUEST_SESSION_PK),
            maxHost,
            maxGuest,
            hostDep,
            guestDep
        );
    }

    // =====================================================================
    // Task 8 — constructive happy path, built from the committed vectors
    // =====================================================================

    /// open -> join -> (0,0) co-filed with the vector's one marker (hand 1)
    /// -> a mid-game receipt -> a `final` at (2,0) -> resolve() -> withdraw().
    /// D18: every artefact here comes from the committed
    /// `test/vectors/p1-vectors.json` — nothing is vm.sign-built. This is
    /// also the mandated "at least one ChannelV2 test consumes a committed
    /// vector" (D18): both the receipt and marker byte layouts are verified
    /// against the committed vector by construction — the test only passes
    /// if this contract's own `_receiptHash`/`_markerHash` reproduce
    /// exactly the digests the poker repo's `gen.mts` signed against. (See
    /// this file's header comment for why `p1-vectors.json` is consumed via
    /// JSON cheatcodes rather than importing the sibling `Vectors.sol` —
    /// the latter does not compile under any solc version tried.)
    ///
    /// Deviation from the phase doc's literal task 8 step 3, recorded
    /// honestly (not papered over): the doc describes "a second marker for
    /// hand 2, co-filed with a receipt closing hand 1." The shipped vector
    /// set (`p1-vectors.json`'s `marker` key is a single object, not an
    /// array — confirmed by reading the file directly) contains exactly one
    /// marker, for hand 1. `resolve()`'s finalEligible check only requires
    /// `highestFinalHand >= markedHand[session]` (decision 6) — with the
    /// final at hand 2 and markedHand at 1 (2 >= 1), the single vector
    /// marker is sufficient to exercise the real code path without
    /// inventing marker data the vector generator did not ship. The phase
    /// doc's assumption about vector content was wrong on this one point;
    /// this is that correction, not a silent substitution.
    function test_happyPath() public {
        // Split into a helper purely for legacy (non-IR) codegen stack
        // depth (this repo's foundry.toml does not set via_ir) — no
        // behavior change, mirrors ChannelV2.sol's own split-for-stack-depth
        // pattern (see its _receiptHash/_markerHash comments).
        (bytes32 session, uint256 bondHost, uint256 bondGuest, uint256 finalHostStack, uint256 finalGuestStack) =
            _happyPathRun();

        (,,,, ChannelV2.Status status) = _sessionStatusOnly(session);
        assertEq(uint256(status), uint256(ChannelV2.Status.Closed));

        uint256 expectedHostPayout = finalHostStack + bondHost; // unaccounted = 0 (deposit fully named)
        uint256 expectedGuestPayout = finalGuestStack + bondGuest;
        assertEq(channel.credits(hostWallet), expectedHostPayout);
        assertEq(channel.credits(guestWallet), expectedGuestPayout);

        // D9's invariant, asserted at Closed.
        assertEq(channel.paidOut(session), expectedHostPayout + expectedGuestPayout);
        assertEq(channel.burned(session), 0);
        assertEq(
            0.2 ether + 0.2 ether + bondHost + bondGuest,
            channel.paidOut(session) + channel.burned(session),
            "depositsIn+bondsIn == paidOut+burned"
        );

        uint256 hostBalBefore = hostWallet.balance;
        uint256 guestBalBefore = guestWallet.balance;
        vm.prank(hostWallet);
        channel.withdraw();
        vm.prank(guestWallet);
        channel.withdraw();
        assertEq(hostWallet.balance, hostBalBefore + expectedHostPayout);
        assertEq(guestWallet.balance, guestBalBefore + expectedGuestPayout);
    }

    function _happyPathRun()
        internal
        returns (bytes32 session, uint256 bondHost, uint256 bondGuest, uint256 finalHostStack, uint256 finalGuestStack)
    {
        string memory json = vm.readFile("test/vectors/p1-vectors.json");
        session = vecSession;
        // No maxHost/maxGuest values exist in the vector set (confirmed by
        // reading gen.mts: DEPOSIT_WEI is the only money constant it
        // defines; declared maxima are a P2-only concept P1's generator
        // never needed). Round, generous numbers are used instead — the
        // doc's "don't pick independent round numbers" instruction applies
        // to numbers the vector file actually contains (session id,
        // deposits, stacks), which are read below, not invented here.
        (bondHost, bondGuest) = _openJoin(
            session,
            hostWallet,
            HOST_WALLET_PK,
            guestWallet,
            GUEST_WALLET_PK,
            vm.parseJsonAddress(json, ".keys.host.address"),
            vm.parseJsonAddress(json, ".keys.guest.address"),
            1 ether,
            1 ether,
            0.2 ether, // matches receipt(0)'s hostDeposit exactly
            0.2 ether // matches receipt(0)'s guestDeposit exactly
        );
        assertEq(bondHost, 1.1 ether);
        assertEq(bondGuest, 1.1 ether);

        // (0,0) co-filed with the vector's hand-1 marker.
        VecReceipt memory r0 = _vecReceipt(json, 0);
        VecMarker memory mk = _vecMarker(json);
        assertEq(mk.receiptHash, r0.hash, "marker must reference the (0,0) receipt hash");
        channel.fileMarkerWithReceipt(
            session, _toMarker(mk), mk.hostSig, mk.guestSig, _toReceipt(r0), r0.hostSig, r0.guestSig
        );
        assertEq(channel.liveHand(session), 1);
        assertTrue(channel.everReceipted(session));

        // A mid-game, non-final receipt (hand 1) — on file, but irrelevant
        // to settlement once a higher final lands.
        VecReceipt memory r1 = _vecReceipt(json, 1);
        channel.fileReceipt(session, _toReceipt(r1), r1.hostSig, r1.guestSig);

        // The `final` at (2,0).
        VecReceipt memory r2 = _vecReceipt(json, 2);
        assertTrue(r2.isFinal);
        channel.fileReceipt(session, _toReceipt(r2), r2.hostSig, r2.guestSig);
        finalHostStack = r2.hostStack;
        finalGuestStack = r2.guestStack;

        channel.resolve(session);
    }

    /// Small helper isolating just the status read (sessionCore returns 5
    /// values; named this way so the happy path above doesn't need to name
    /// every unused return slot at the call site).
    function _sessionStatusOnly(bytes32 session)
        internal
        view
        returns (address, address, uint256, uint256, ChannelV2.Status)
    {
        (address h, address g, ChannelV2.Status st, uint256 mh, uint256 mg) = channel.sessionCore(session);
        return (h, g, mh, mg, st);
    }

    // =====================================================================
    // Task 9 — negative-require sweep
    // =====================================================================

    // ---- open() ----

    function test_open_sessionExists_reverts() public {
        bytes32 session = keccak256("neg-open-exists");
        _openJoinDefault(session, 1 ether, 1 ether, 0, 0);

        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        vm.expectRevert("session exists");
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_badOpponent_self_reverts() public {
        bytes32 session = keccak256("neg-open-self");
        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        vm.expectRevert("bad opponent");
        channel.open{value: 1.1 ether}(session, hostWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_badOpponent_zero_reverts() public {
        bytes32 session = keccak256("neg-open-zero");
        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        vm.expectRevert("bad opponent");
        channel.open{value: 1.1 ether}(session, address(0), 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_maxRequired_reverts() public {
        bytes32 session = keccak256("neg-open-maxreq");
        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        vm.expectRevert("max required");
        channel.open{value: 1.1 ether}(session, guestWallet, 0, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_badRegistrationSig_reverts() public {
        bytes32 session = keccak256("neg-open-badreg");
        // Signed by the guest wallet key, not the host's — wrong signer.
        bytes memory reg = _registrationSig(GUEST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        vm.expectRevert("bad registration sig");
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_belowBond_reverts() public {
        bytes32 session = keccak256("neg-open-belowbond");
        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        (uint256 bondHost,) = _expectedBonds(1 ether, 1 ether);
        vm.prank(hostWallet);
        vm.expectRevert("below bond");
        channel.open{value: bondHost - 1}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    function test_open_pastDeclaredMax_reverts() public {
        bytes32 session = keccak256("neg-open-pastmax");
        bytes memory reg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        (uint256 bondHost,) = _expectedBonds(1 ether, 1 ether);
        vm.prank(hostWallet);
        vm.expectRevert("past declared max");
        channel.open{value: bondHost + 1 ether + 1}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), reg);
    }

    // ---- join() ----

    function test_join_notAwaitingGuest_reverts() public {
        bytes32 session = keccak256("neg-join-notawaiting");
        _openJoinDefault(session, 1 ether, 1 ether, 0, 0); // already Active
        bytes memory reg = _registrationSig(GUEST_WALLET_PK, session, guestWallet, vm.addr(GUEST_SESSION_PK));
        vm.prank(guestWallet);
        vm.expectRevert("not awaiting guest");
        channel.join{value: 1.1 ether}(session, vm.addr(GUEST_SESSION_PK), reg);
    }

    function test_join_notInvited_reverts() public {
        bytes32 session = keccak256("neg-join-notinvited");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);

        address stranger = vm.addr(0xDEAD);
        vm.deal(stranger, 10 ether);
        bytes memory sReg = _registrationSig(0xDEAD, session, stranger, vm.addr(GUEST_SESSION_PK));
        vm.prank(stranger);
        vm.expectRevert("not invited");
        channel.join{value: 1.1 ether}(session, vm.addr(GUEST_SESSION_PK), sReg);
    }

    function test_join_badRegistrationSig_reverts() public {
        bytes32 session = keccak256("neg-join-badreg");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);

        bytes memory gReg = _registrationSig(HOST_WALLET_PK, session, guestWallet, vm.addr(GUEST_SESSION_PK));
        vm.prank(guestWallet);
        vm.expectRevert("bad registration sig");
        channel.join{value: 1.1 ether}(session, vm.addr(GUEST_SESSION_PK), gReg);
    }

    function test_join_belowBond_reverts() public {
        bytes32 session = keccak256("neg-join-belowbond");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);

        bytes memory gReg = _registrationSig(GUEST_WALLET_PK, session, guestWallet, vm.addr(GUEST_SESSION_PK));
        vm.prank(guestWallet);
        vm.expectRevert("below bond");
        channel.join{value: 1.1 ether - 1}(session, vm.addr(GUEST_SESSION_PK), gReg);
    }

    function test_join_pastDeclaredMax_reverts() public {
        bytes32 session = keccak256("neg-join-pastmax");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);

        bytes memory gReg = _registrationSig(GUEST_WALLET_PK, session, guestWallet, vm.addr(GUEST_SESSION_PK));
        vm.prank(guestWallet);
        vm.expectRevert("past declared max");
        channel.join{value: 1.1 ether + 1 ether + 1}(session, vm.addr(GUEST_SESSION_PK), gReg);
    }

    // ---- cancelOpen() ----

    function test_cancelOpen_notCancellable_reverts() public {
        bytes32 session = keccak256("neg-cancel-notcancellable");
        _openJoinDefault(session, 1 ether, 1 ether, 0, 0);
        vm.prank(hostWallet);
        vm.expectRevert("not cancellable");
        channel.cancelOpen(session);
    }

    function test_cancelOpen_notHost_reverts() public {
        bytes32 session = keccak256("neg-cancel-nothost");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);

        vm.prank(guestWallet);
        vm.expectRevert("not host");
        channel.cancelOpen(session);
    }

    // ---- deposit() ----

    function test_deposit_notOpenForDeposits_reverts() public {
        bytes32 session = keccak256("neg-deposit-notopen");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);
        // Still AwaitingGuest — not Active/Disputed.
        vm.prank(hostWallet);
        vm.expectRevert("not open for deposits");
        channel.deposit{value: 0.1 ether}(session);
    }

    function test_deposit_notAPlayer_reverts() public {
        bytes32 session = keccak256("neg-deposit-notplayer");
        _openJoinDefault(session, 1 ether, 1 ether, 0, 0);
        address stranger = vm.addr(0xDEAD1);
        vm.deal(stranger, 1 ether);
        vm.prank(stranger);
        vm.expectRevert("not a player");
        channel.deposit{value: 0.1 ether}(session);
    }

    /// test_F10_4_declared_depth_rebuys (fixtures-index P2 row).
    function test_F10_4_declared_depth_rebuys() public {
        bytes32 session = keccak256("F10.4");
        uint256 maxHost = 1 ether;
        _openJoinDefault(session, maxHost, 1 ether, 0.5 ether, 0);

        // Deposit up to exactly maxHost succeeds.
        vm.prank(hostWallet);
        channel.deposit{value: 0.5 ether}(session); // total 1.0 ether == maxHost
        (uint256 depositedHost,) = channel.sessionDeposits(session);
        assertEq(depositedHost, maxHost);

        // One wei past it reverts.
        vm.prank(hostWallet);
        vm.expectRevert("past declared max");
        channel.deposit{value: 1}(session);

        // A deposit never named by any filed receipt is refunded at
        // settlement via the unaccounted-deposit path (decision 6 / task 5
        // step 3's _settleFinal). Route to settlement via a final receipt
        // naming a smaller deposit than what's actually on chain.
        uint256 hostSessionPk = HOST_SESSION_PK;
        uint256 guestSessionPk = GUEST_SESSION_PK;
        ChannelV2.Receipt memory r00 = _mkReceipt(0, 0, 0.5 ether, 0, 0.5 ether, 0, false);
        (bytes memory s0h, bytes memory s0g) = _signReceipt(session, r00, hostSessionPk, guestSessionPk);
        channel.fileReceipt(session, r00, s0h, s0g);

        // final: names only the original 0.5 ether host deposit, leaving
        // the rebought 0.5 ether "unaccounted" at settlement time.
        ChannelV2.Receipt memory rFinal = _mkReceipt(1, 0, 0.5 ether, 0, 0.5 ether, 0, true);
        (bytes memory sfh, bytes memory sfg) = _signReceipt(session, rFinal, hostSessionPk, guestSessionPk);
        channel.fileReceipt(session, rFinal, sfh, sfg);

        channel.resolve(session);

        (uint256 bh,) = _expectedBonds(maxHost, 1 ether);
        // hostPayout = finalHostStack(0.5) + unaccountedHost(1.0-0.5=0.5) + bondHost
        uint256 expectedHostPayout = 0.5 ether + 0.5 ether + bh;
        assertEq(channel.credits(hostWallet), expectedHostPayout, "rebought deposit must be refunded as unaccounted");
    }

    // ---- fileReceipt() ----

    function test_fileReceipt_notOpenForFiling_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-notopen");
        bytes memory hReg = _registrationSig(HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), hReg);
        // AwaitingGuest — not Active/Disputed yet.
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0, 0, 0, 0, false);
        (bytes memory sh, bytes memory sg) = _signReceipt(session, r, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("not open for filing");
        channel.fileReceipt(session, r, sh, sg);
    }

    function test_fileReceipt_badHostSig_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-badhost");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        bytes32 digest = _receiptDigest(session, r);
        // sign with the wrong (guest) key for the host slot.
        bytes memory badSig = _sigRaw(GUEST_SESSION_PK, digest);
        bytes memory sg = _sigRaw(GUEST_SESSION_PK, digest);
        vm.expectRevert("bad host receipt sig");
        channel.fileReceipt(session, r, badSig, sg);
    }

    function test_fileReceipt_badGuestSig_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-badguest");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        bytes32 digest = _receiptDigest(session, r);
        bytes memory sh = _sigRaw(HOST_SESSION_PK, digest);
        bytes memory badSig = _sigRaw(HOST_SESSION_PK, digest);
        vm.expectRevert("bad guest receipt sig");
        channel.fileReceipt(session, r, sh, badSig);
    }

    function test_fileReceipt_stacksDepositsMismatch_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-mismatch");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        // hostStack+guestStack (0.5) != hostDeposit+guestDeposit (0.4)
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0.3 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory sh, bytes memory sg) = _signReceipt(session, r, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("stacks/deposits mismatch");
        channel.fileReceipt(session, r, sh, sg);
    }

    function test_fileReceipt_depositExceedsReceived_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-exceeds");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        // hostDeposit (0.5) claimed but only 0.2 actually received.
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0.5 ether, 0.2 ether, 0.5 ether, 0.2 ether, false);
        (bytes memory sh, bytes memory sg) = _signReceipt(session, r, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("deposit exceeds received");
        channel.fileReceipt(session, r, sh, sg);
    }

    /// Raw-digest malleability (decision 9): the high-s counterpart of a
    /// valid receipt signature must be rejected — distinct code path from
    /// V1's EIP-191 malleability test, since `_recoverRaw` is new code.
    function test_fileReceipt_highS_malleability_reverts() public {
        bytes32 session = keccak256("neg-filereceipt-highs");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        bytes32 digest = _receiptDigest(session, r);
        (uint8 v, bytes32 rr, bytes32 s) = vm.sign(HOST_SESSION_PK, digest);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 flippedS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory badSig = abi.encodePacked(rr, flippedS, flippedV);
        bytes memory sg = _sigRaw(GUEST_SESSION_PK, digest);
        vm.expectRevert("bad s");
        channel.fileReceipt(session, r, badSig, sg);
    }

    /// The EIP-191 recovery path's own malleability check, exercised via
    /// registration (decision 9's second routine).
    function test_registration_highS_malleability_reverts() public {
        bytes32 session = keccak256("neg-registration-highs");
        bytes32 digest = _registrationDigest(session, hostWallet, vm.addr(HOST_SESSION_PK));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", digest));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(HOST_WALLET_PK, ethHash);
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 flippedS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory badSig = abi.encodePacked(r, flippedS, flippedV);
        vm.prank(hostWallet);
        vm.expectRevert("bad s");
        channel.open{value: 1.1 ether}(session, guestWallet, 1 ether, 1 ether, vm.addr(HOST_SESSION_PK), badSig);
    }

    /// test_F10_2_marker_blocks_stale_settlement (fixtures-index P2 row;
    /// AF-31 reconciliation — P3's markedHand>0 branch is real now, no
    /// longer a stub). File receipt N-1 as `final` against a confirmed
    /// marker for hand N: resolve() must not settle it — it falls through
    /// to the dispute overlay, reachable here only because markedHand > 0.
    /// No action has ever been filed for the marked hand (hand 2), so
    /// consolidation's replay engine has nothing to walk: `_consolidate`
    /// returns `TermKind.NONE` (a marked hand with zero filed actions IS
    /// pending, decision 8). P4 reconciliation (AF-39): with `phase2Act`
    /// shipped, `resolve()` no longer reverts `PendingContinuation` at
    /// this seam — it proceeds into `_consolidatePhase2` (decision 2),
    /// which itself finds the hand genuinely still pending (no phase-2
    /// action ever filed, bank not exhausted a mere second after `H0`) and
    /// reverts this phase's own `Phase2InProgress` instead. The property
    /// this fixture pins is unchanged: the stale final's stacks never
    /// reach a payout — "blocks stale settlement" now means "routes to the
    /// live continuation," not "reverts outright."
    function test_F10_2_marker_blocks_stale_settlement() public {
        bytes32 session = keccak256("F10.2");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);

        // (0,0)
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);

        // A `final` at (0,0) itself would be trivially at the floor; make
        // the stale final hand 1 (below a confirmed marker for hand 2).
        _fileReceiptQuick(session, 1, 0, 0.1 ether, 0.3 ether, 0.2 ether, 0.2 ether, true);

        // Confirm marker hand 1 (continuity vs receipt 0), then hand 2
        // (continuity vs a fresh, non-final receipt closing hand 1) — so
        // markedHand ends at 2, strictly above the stale final's hand 1.
        _fileMarkerQuick(session, 1, _receiptDigest(session, r0));

        ChannelV2.Receipt memory r1 =
            _fileReceiptQuick(session, 1, 1, 0.1 ether, 0.3 ether, 0.2 ether, 0.2 ether, false);

        _fileMarkerQuick(session, 2, _receiptDigest(session, r1));

        assertEq(channel.liveHand(session), 2);

        // finalEligible = false (highestFinalHand=1 < markedHand=2), so
        // resolve() requires Disputed + window closed, then hits
        // markedHand>0 -> consolidation. No actions were ever filed for
        // hand 2, so the replay engine finds nothing to walk -> NONE ->
        // _consolidatePhase2 -> still no phase-2 action filed, bank barely
        // touched (1 second past H0) -> Phase2InProgress, not a silent
        // settlement of the stale final.
        vm.prank(hostWallet);
        channel.openDispute(session);
        vm.warp(block.timestamp + WINDOW + 1);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);
    }

    /// test_F10_3_final_ordered_terminal (fixtures-index P2 row).
    function test_F10_3_final_ordered_terminal() public {
        bytes32 session = keccak256("F10.3");
        (uint256 bondHost, uint256 bondGuest) =
            _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);

        ChannelV2.Receipt memory rLow = _mkReceipt(5, 0, 0.1 ether, 0.3 ether, 0.2 ether, 0.2 ether, true);
        (bytes memory slh, bytes memory slg) = _signReceipt(session, rLow, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, rLow, slh, slg);

        ChannelV2.Receipt memory rHigh = _mkReceipt(10, 0, 0.05 ether, 0.35 ether, 0.2 ether, 0.2 ether, true);
        (bytes memory shh, bytes memory shg) = _signReceipt(session, rHigh, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, rHigh, shh, shg);

        channel.resolve(session);

        // The (10,0) numbers won, not (5,0)'s.
        assertEq(channel.credits(hostWallet), rHigh.hostStack + bondHost);
        assertEq(channel.credits(guestWallet), rHigh.guestStack + bondGuest);

        // A call to resolve() after Closed reverts.
        vm.expectRevert("nothing to resolve");
        channel.resolve(session);

        // Filing after Closed also reverts.
        (bytes memory slh2, bytes memory slg2) = _signReceipt(session, rLow, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("not open for filing");
        channel.fileReceipt(session, rLow, slh2, slg2);
    }

    /// test_F10_6_never_started_full_refund (fixtures-index P2 row).
    function test_F10_6_never_started_full_refund() public {
        bytes32 session = keccak256("F10.6");
        (uint256 bondHost, uint256 bondGuest) =
            _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);

        vm.prank(hostWallet);
        channel.openDispute(session);
        vm.warp(block.timestamp + WINDOW + 1);
        // No marker, no receipt, ever.
        channel.resolve(session);

        assertEq(channel.credits(hostWallet), 0.2 ether + bondHost);
        assertEq(channel.credits(guestWallet), 0.2 ether + bondGuest);
        assertEq(channel.burned(session), 0);
    }

    // ---- fileMarker() / fileMarkerWithReceipt() ----

    /// test_F11_3_marker_sequencing (fixtures-index P2 row).
    function test_F11_3_marker_sequencing() public {
        bytes32 session = keccak256("F11.3");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);

        ChannelV2.Receipt memory r0 = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory s0h, bytes memory s0g) = _signReceipt(session, r0, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, r0, s0h, s0g);

        ChannelV2.Marker memory m1 = _mkMarker(1, _receiptDigest(session, r0), 0, 5, 10, FILLER_STARTING_CHIPS);
        (bytes memory m1h, bytes memory m1g) = _signMarker(session, m1, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileMarker(session, m1, m1h, m1g);
        assertEq(channel.liveHand(session), 1);

        // Duplicate marker 1 rejected.
        vm.expectRevert("not next hand");
        channel.fileMarker(session, m1, m1h, m1g);

        // Marker 3 before marker 2 exists rejected.
        ChannelV2.Marker memory m3 = _mkMarker(3, bytes32(uint256(0xdead)), 0, 5, 10, FILLER_STARTING_CHIPS);
        (bytes memory m3h, bytes memory m3g) = _signMarker(session, m3, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("not next hand");
        channel.fileMarker(session, m3, m3h, m3g);

        // liveHand() still reflects only the one confirmed marker.
        assertEq(channel.liveHand(session), 1);
    }

    function test_fileMarker_badSig_reverts() public {
        bytes32 session = keccak256("neg-filemarker-badsig");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory s0h, bytes memory s0g) = _signReceipt(session, r0, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, r0, s0h, s0g);

        ChannelV2.Marker memory m1 = _mkMarker(1, _receiptDigest(session, r0), 0, 5, 10, FILLER_STARTING_CHIPS);
        bytes32 digest = _markerDigest(session, m1);
        bytes memory badSig = _sigRaw(GUEST_SESSION_PK, digest); // wrong key for host slot
        bytes memory gSig = _sigRaw(GUEST_SESSION_PK, digest);
        vm.expectRevert("bad host marker sig");
        channel.fileMarker(session, m1, badSig, gSig);
    }

    function test_fileMarker_continuity_reverts() public {
        bytes32 session = keccak256("neg-filemarker-continuity");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 = _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory s0h, bytes memory s0g) = _signReceipt(session, r0, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, r0, s0h, s0g);

        // Wrong receiptHash for hand 0.
        ChannelV2.Marker memory m1 = _mkMarker(1, bytes32(uint256(0xbad)), 0, 5, 10, FILLER_STARTING_CHIPS);
        (bytes memory m1h, bytes memory m1g) = _signMarker(session, m1, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.expectRevert("continuity");
        channel.fileMarker(session, m1, m1h, m1g);
    }

    /// test_S_marker_catchup (fixtures-index P2 row): markers 1-2 confirm
    /// normally, hands 3-5 happen with no on-chain marker, then markers
    /// 3,4,5 are filed in sequence (catch-up) and ALL are accepted.
    function test_S_marker_catchup() public {
        bytes32 session = keccak256("S.marker_catchup");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);

        ChannelV2.Receipt memory prevReceipt =
            _mkReceipt(0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory p0h, bytes memory p0g) = _signReceipt(session, prevReceipt, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, prevReceipt, p0h, p0g);

        // Markers 1 and 2 confirm normally, each co-filed with the receipt
        // that closes the prior hand.
        for (uint64 hand = 1; hand <= 2; hand++) {
            ChannelV2.Marker memory m = _mkMarker(hand, _receiptDigest(session, prevReceipt), 0, 5, 10, FILLER_STARTING_CHIPS);
            (bytes memory mh, bytes memory mg) = _signMarker(session, m, HOST_SESSION_PK, GUEST_SESSION_PK);
            channel.fileMarker(session, m, mh, mg);
            assertEq(channel.liveHand(session), hand);

            prevReceipt = _mkReceipt(hand, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
            (bytes memory rh, bytes memory rg) = _signReceipt(session, prevReceipt, HOST_SESSION_PK, GUEST_SESSION_PK);
            channel.fileReceipt(session, prevReceipt, rh, rg);
        }

        // Hands 3-5 happen off-chain with no marker filed for any of them
        // (a modified client pair skipped routine posting) — then caught up
        // in one sequence, each co-filed with its matching receipt.
        for (uint64 hand = 3; hand <= 5; hand++) {
            ChannelV2.Marker memory m = _mkMarker(hand, _receiptDigest(session, prevReceipt), 0, 5, 10, FILLER_STARTING_CHIPS);
            ChannelV2.Receipt memory rNext =
                _mkReceipt(hand, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
            (bytes memory mh, bytes memory mg) = _signMarker(session, m, HOST_SESSION_PK, GUEST_SESSION_PK);
            (bytes memory rh, bytes memory rg) = _signReceipt(session, rNext, HOST_SESSION_PK, GUEST_SESSION_PK);
            channel.fileMarkerWithReceipt(session, m, mh, mg, rNext, rh, rg);
            assertEq(channel.liveHand(session), hand, "catch-up marker must be accepted immediately");
            prevReceipt = rNext;
        }

        assertEq(channel.liveHand(session), 5);
    }

    // ---- resolve() ----

    function test_resolve_windowOpen_reverts() public {
        bytes32 session = keccak256("neg-resolve-windowopen");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        vm.prank(hostWallet);
        channel.openDispute(session);
        vm.expectRevert("window open");
        channel.resolve(session);
    }

    function test_resolve_nothingToResolve_activeNoFinal_reverts() public {
        bytes32 session = keccak256("neg-resolve-nothing");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        // Active, no dispute opened, no eligible final on file.
        vm.expectRevert("nothing to resolve");
        channel.resolve(session);
    }

    // ---- P3-owned stub surfaces ----

    /// AF-31 reconciliation: fileActions is real now (task 3) — it no
    /// longer stubs NotYetBuilt. Its actual precondition is `status ==
    /// Disputed` (task 3 step 4); an unopened session (`bytes32(0)`,
    /// never even open()'d) is `Status.None`, so this reverts the real
    /// "not disputed" require, not the old stub error.
    function test_fileActions_notDisputed_reverts() public {
        ChannelV2.Act[] memory acts = new ChannelV2.Act[](0);
        bytes[] memory sigs = new bytes[](0);
        vm.expectRevert("not disputed");
        channel.fileActions(bytes32(0), acts, sigs);
    }

    /// AF-31 reconciliation: postShares is real now (task 4) — same
    /// `status == Disputed` precondition, same real revert.
    function test_postShares_notDisputed_reverts() public {
        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](0);
        vm.expectRevert("not disputed");
        channel.postShares(bytes32(0), posts);
    }

    /// P4 reconciliation (AF-39): phase2Act is real now (task 4) -- no
    /// longer stubs NotYetBuilt. Its actual first precondition is
    /// `status == Disputed` (mirrors fileActions/postShares' own
    /// "not disputed" gate); an unopened session (`bytes32(0)`, never even
    /// open()'d) is `Status.None`, so this reverts the real "not disputed"
    /// require, not the old stub error.
    function test_phase2Act_notDisputed_reverts() public {
        ChannelV2.Act memory a;
        vm.expectRevert("not disputed");
        channel.phase2Act(bytes32(0), a, "");
    }

    // ---- withdraw() ----

    function test_withdraw_nothingToWithdraw_reverts() public {
        vm.expectRevert("nothing to withdraw");
        channel.withdraw();
    }

    // =====================================================================
    // AF-4 fixtures — zero filings / one filing per-duty bond fate
    // =====================================================================

    /// test_S_zero_filings_full_refund (fixtures-index P2 row, AF-4).
    /// Replaces the struck test_S_unwind_never_pays (§1.3 both-burn branch
    /// is unreachable dead code in V2 — do not implement or test it).
    function test_S_zero_filings_full_refund() public {
        bytes32 session = keccak256("S.zero_filings");
        (uint256 bondHost, uint256 bondGuest) =
            _openJoinDefault(session, 1000, 1000, 1000, 1000); // wei-denominated toy numbers, matches decision 1's worked case shape
        assertEq(bondHost, 1100);
        assertEq(bondGuest, 1100);

        vm.prank(hostWallet);
        channel.openDispute(session);
        vm.warp(block.timestamp + WINDOW + 1);
        // Nobody files anything at all — no (0,0), no marker.
        channel.resolve(session);

        assertEq(channel.credits(hostWallet), 1000 + 1100);
        assertEq(channel.credits(guestWallet), 1000 + 1100);
        assertEq(channel.burned(session), 0);
    }

    /// test_S_one_filing_perduty_bonds (fixtures-index P2 row, AF-4, fix
    /// round 1 M3: both seat directions in one test function sharing the
    /// same assertions helper, so a host-favoring bug in resolve()'s branch
    /// cannot hide behind only ever testing one seat as "the filer").
    function test_S_one_filing_perduty_bonds() public {
        // (a) host files, guest silent.
        _oneFilingPerDutyCase(keccak256("S.one_filing.a"), true);
        // (b) guest files, host silent (the swap).
        _oneFilingPerDutyCase(keccak256("S.one_filing.b"), false);
    }

    /// Split into a run phase + an assert phase purely for legacy (non-IR)
    /// codegen stack depth (this repo's foundry.toml does not set via_ir)
    /// — no behavior change.
    function _oneFilingPerDutyCase(bytes32 session, bool hostFiles) internal {
        (uint256 bondHost, uint256 bondGuest, uint256 hostDelta, uint256 guestDelta, uint256 burnedAmt) =
            _runOneFilingCase(session, hostFiles);
        _assertOneFilingCase(session, hostFiles, bondHost, bondGuest, hostDelta, guestDelta, burnedAmt);
    }

    function _runOneFilingCase(bytes32 session, bool hostFiles)
        internal
        returns (uint256 bondHost, uint256 bondGuest, uint256 hostDelta, uint256 guestDelta, uint256 burnedAmt)
    {
        (bondHost, bondGuest) = _openJoin(
            session,
            hostWallet,
            HOST_WALLET_PK,
            guestWallet,
            GUEST_WALLET_PK,
            vm.addr(HOST_SESSION_PK),
            vm.addr(GUEST_SESSION_PK),
            1000,
            1000,
            1000,
            1000
        );

        address filerWallet = hostFiles ? hostWallet : guestWallet;

        // `credits` is a GLOBAL, cross-session mapping (D9) — this helper
        // runs twice against the SAME wallets (fix round 1 M3's two
        // directions), so credits accumulate across the two sub-cases.
        // Capture the "before" snapshot and return the delta this
        // session's resolve() produces, not the cumulative total.
        uint256 hostBefore = channel.credits(hostWallet);
        uint256 guestBefore = channel.credits(guestWallet);

        vm.prank(filerWallet);
        channel.openDispute(session);

        // The only reachable receipt at markedHand==0 is (0,0), where
        // stack == deposit by construction (task 3 step 3's invariant) --
        // literally true here since both fields are the same literal 1000,
        // which is exactly task 9 step 9's "no stack disparity reachable at
        // this state" structural point, not something to assert at runtime.
        ChannelV2.Receipt memory r00 = _mkReceipt(0, 0, 1000, 1000, 1000, 1000, false);
        (bytes memory s0h, bytes memory s0g) = _signReceipt(session, r00, HOST_SESSION_PK, GUEST_SESSION_PK);
        vm.prank(filerWallet);
        channel.fileReceipt(session, r00, s0h, s0g);

        vm.warp(block.timestamp + WINDOW + 1);
        channel.resolve(session);

        hostDelta = channel.credits(hostWallet) - hostBefore;
        guestDelta = channel.credits(guestWallet) - guestBefore;
        burnedAmt = channel.burned(session);
    }

    function _assertOneFilingCase(
        bytes32 session,
        bool hostFiles,
        uint256 bondHost,
        uint256 bondGuest,
        uint256 hostDelta,
        uint256 guestDelta,
        uint256 burnedAmt
    ) internal view {
        assertEq(bondHost, 1100);
        assertEq(bondGuest, 1100);

        // Both players' deposits back (the wash) regardless of who filed.
        // The filer's bond returns in full; the silent side's bond burns.
        if (hostFiles) {
            assertEq(hostDelta, 1000 + 1100, "filer (host) must get deposit+bond");
            assertEq(guestDelta, 1000, "silent guest gets deposit only");
            assertEq(burnedAmt, 1100, "silent guest's bond burns");
        } else {
            assertEq(guestDelta, 1000 + 1100, "filer (guest) must get deposit+bond");
            assertEq(hostDelta, 1000, "silent host gets deposit only");
            assertEq(burnedAmt, 1100, "silent host's bond burns");
        }

        assertEq(
            1000 + 1000 + bondHost + bondGuest,
            channel.paidOut(session) + burnedAmt,
            "depositsIn+bondsIn == paidOut+burned"
        );
    }

    /// test_S_bond_coverage_maxima (fixtures-index P2 row) — decision 1's
    /// worked case, matches the parking doc exactly: no drift here,
    /// recorded as a confirmed-sound pin, not a finding.
    function test_S_bond_coverage_maxima() public {
        bytes32 session = keccak256("S.bond_coverage_maxima");
        (uint256 bondHost, uint256 bondGuest) =
            _openJoinDefault(session, 1500, 500, 0, 0);
        assertEq(bondHost, 1650);
        assertEq(bondGuest, 1100);

        (uint256 rBondHost, uint256 rBondGuest,,) = channel.sessionBonds(session);
        assertEq(rBondHost, 1650);
        assertEq(rBondGuest, 1100);
    }

    // =====================================================================
    // test_F15_3_idempotent_burns — via a test-only harness (decision 8)
    // =====================================================================

    /// test_F15_3_idempotent_burns (fixtures-index P2 row). Because P3/P4's
    /// misconduct sources don't exist yet, this exercises idempotence via a
    /// harness contract that subclasses ChannelV2 purely to expose
    /// _burnBond for direct, repeated calls — proving the guard holds
    /// before P3/P4 ever call it for real.
    ///
    /// The "subsequent settlement path correctly excludes that bond exactly
    /// once" half of this fixture is exercised via the `final`-receipt
    /// settlement path (_settleFinal), which is the one P2-owned settlement
    /// branch that reads the per-player burn flag directly
    /// (`hostBurned ? 0 : bondHost`) — deliberately, not via the
    /// zero-filings/per-duty branch (_settlePerDutyBonds), which is the
    /// only P2-owned *caller* of _burnBond and therefore, within P2's
    /// current shipped scope, can never observe a pre-existing burn (see
    /// completion notes: this is flagged as a forward-looking observation
    /// for P3/P4, not a P2 defect).
    function test_F15_3_idempotent_burns() public {
        BurnHarness harness = new BurnHarness(WINDOW, BANK, GRACE);
        bytes32 session = keccak256("F15.3");

        // Seed the harness session with real deposits/bonds via the normal
        // open()/join() path so paidOut/burned accounting is meaningful.
        bytes memory hReg =
            _registrationSigFor(address(harness), HOST_WALLET_PK, session, hostWallet, vm.addr(HOST_SESSION_PK));
        vm.prank(hostWallet);
        harness.open{value: 2100}(session, guestWallet, 1000, 1000, vm.addr(HOST_SESSION_PK), hReg); // bond 1100 + deposit 1000
        bytes memory gReg =
            _registrationSigFor(address(harness), GUEST_WALLET_PK, session, guestWallet, vm.addr(GUEST_SESSION_PK));
        vm.prank(guestWallet);
        harness.join{value: 2100}(session, vm.addr(GUEST_SESSION_PK), gReg); // bond 1100 + deposit 1000

        harness.exposedBurnBond(session, true);
        assertEq(harness.burned(session), 1100);
        (,, bool hostBurned,) = harness.sessionBonds(session);
        assertTrue(hostBurned);

        // Second call: no-op, must not double count.
        harness.exposedBurnBond(session, true);
        assertEq(harness.burned(session), 1100, "burn must not double-count on repeated calls");

        // A subsequent settlement path correctly excludes the burned bond
        // exactly once: file a `final` naming full stacks/deposits and
        // resolve() through _settleFinal, which checks hostBurned directly.
        ChannelV2.Receipt memory rFinal = _mkReceipt(0, 0, 1000, 1000, 1000, 1000, true);
        bytes32 digest = _receiptDigestFor(address(harness), session, rFinal);
        bytes memory sfh = _sigRaw(HOST_SESSION_PK, digest);
        bytes memory sfg = _sigRaw(GUEST_SESSION_PK, digest);
        harness.fileReceipt(session, rFinal, sfh, sfg);
        harness.resolve(session);

        // Host's bond stays excluded (burned once, pre-existing); guest's
        // bond is untouched and paid in full — the burn is subtracted
        // exactly once, nowhere double-counted.
        assertEq(harness.burned(session), 1100);
        assertEq(harness.credits(hostWallet), 1000, "host's stack only -- burned bond excluded exactly once");
        assertEq(harness.credits(guestWallet), 1000 + 1100, "guest's stack plus full bond -- untouched by host's burn");

        assertEq(
            1000 + 1000 + 1100 + 1100,
            harness.paidOut(session) + harness.burned(session),
            "depositsIn+bondsIn == paidOut+burned, burn counted exactly once"
        );
    }

    // Small helpers so the harness test (a different deployed address) can
    // reuse the same digest-building logic as the rest of the file.
    function _registrationSigFor(address channelAddr, uint256 walletPk, bytes32 session, address player, address sessionKey)
        internal
        view
        returns (bytes memory)
    {
        bytes memory binding = abi.encodePacked(channelAddr, block.chainid, session);
        bytes32 digest = keccak256(abi.encodePacked(bytes1(0x04), "vault/sessionkey/v2", binding, player, sessionKey));
        return _sigEIP191(walletPk, digest);
    }

    function _receiptDigestFor(address channelAddr, bytes32 session, ChannelV2.Receipt memory r)
        internal
        view
        returns (bytes32)
    {
        bytes memory binding = abi.encodePacked(channelAddr, block.chainid, session);
        bytes memory head = abi.encodePacked(bytes1(0x01), "vault/receipt/v2", binding);
        bytes memory tail = abi.encodePacked(
            r.hand, r.subseq, r.hostStack, r.guestStack, r.hostDeposit, r.guestDeposit,
            r.isFinal ? bytes1(0x01) : bytes1(0x00)
        );
        return keccak256(abi.encodePacked(head, tail));
    }

    // =====================================================================
    // Task 8 (P3 Part A) — fixtures: fileActions/equivocation, postShares
    // triple-check negatives, consolidation/replay differential coverage,
    // the AF-2 out-of-turn case at the contract level, gas baseline.
    // See phase-3-disputes-evidence.md task 8 and fixtures-index.md (D12)
    // for the fixture class each test below re-derives.
    // =====================================================================

    // ---- Act signing/filing helpers (mirrors ChannelV2._actionHash) ----

    function _actDigest(bytes32 session, ChannelV2.Act memory a) internal view returns (bytes32) {
        bytes memory head = abi.encodePacked(bytes1(0x03), "vault/act/v2", _binding(session));
        bytes memory tail = abi.encodePacked(a.hand, a.seq, a.action, a.amount, a.prev);
        return keccak256(abi.encodePacked(head, tail));
    }

    function _mkAct(uint64 hand, uint64 seq, uint8 action, uint256 amount, bytes32 prev)
        internal
        pure
        returns (ChannelV2.Act memory)
    {
        return ChannelV2.Act(hand, seq, action, amount, prev);
    }

    function _fileOneAct(bytes32 session, ChannelV2.Act memory a, uint256 pk) internal {
        ChannelV2.Act[] memory acts = new ChannelV2.Act[](1);
        acts[0] = a;
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = _sigRaw(pk, _actDigest(session, a));
        channel.fileActions(session, acts, sigs);
    }

    function _actionSlotKey(bytes32 session, uint64 hand, uint64 seq) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(session, hand, seq));
    }

    /// Opens+joins a default session (1 ether/1 ether declared, 0.2 ether
    /// deposits each — matches every other hand-built fixture in this
    /// file), files (0,0), opens the dispute, and files the first marker
    /// (hand 1, button=host/sb=5/bb=10 per `_mkMarker`'s fixed filler
    /// values) — the shared setup every fileActions-side task 8 fixture
    /// below needs. Buy-in works out to `200 * bb` = 2000 chips each side
    /// (decision 3a), `weiPerChip` = 0.2 ether / 2000 = 1e14, both exact.
    /// Returns the digest actions chain from (the marker's own hash).
    function _setupDisputedMarkedHand1(bytes32 session) internal returns (bytes32 prev0) {
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);
        ChannelV2.Marker memory m1 = _fileMarkerQuick(session, 1, _receiptDigest(session, r0));
        prev0 = _markerDigest(session, m1);
    }

    // ---- small 4-leaf Merkle helper (postShares fixtures need real,
    // passing proofs — `_mkMarker`'s filler roots are never inspected by
    // P2/most P3 fixtures, but postShares' triple check inspects them for
    // real). Same sorted-pair arithmetic as Evidence.sol/Evidence.t.sol's
    // own `_pairHash`, just wrapped for a fixed 4-leaf tree. ----

    function _pairHash4(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a <= b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function _merkleRoot4(bytes32[4] memory leaves) internal pure returns (bytes32) {
        return _pairHash4(_pairHash4(leaves[0], leaves[1]), _pairHash4(leaves[2], leaves[3]));
    }

    function _merkleProof4(bytes32[4] memory leaves, uint256 idx) internal pure returns (bytes32[] memory proof) {
        proof = new bytes32[](2);
        if (idx == 0) {
            proof[0] = leaves[1];
            proof[1] = _pairHash4(leaves[2], leaves[3]);
        } else if (idx == 1) {
            proof[0] = leaves[0];
            proof[1] = _pairHash4(leaves[2], leaves[3]);
        } else if (idx == 2) {
            proof[0] = leaves[3];
            proof[1] = _pairHash4(leaves[0], leaves[1]);
        } else {
            proof[0] = leaves[2];
            proof[1] = _pairHash4(leaves[0], leaves[1]);
        }
    }

    /// Custom-crypto marker builder: unlike `_mkMarker` (filler
    /// deck/share/pk fields P2 never inspects), postShares' triple check
    /// genuinely reads these fields, so the postShares fixtures below need
    /// real, caller-chosen values. button/sb/bb/startingChips fixed at
    /// 0/5/10/FILLER_STARTING_CHIPS (unused by postShares) purely to reuse
    /// `_signMarker`'s existing shape.
    function _mkMarkerFull(
        uint64 hand,
        bytes32 receiptHash,
        bytes32 deckRoot,
        bytes32 hostShareRoot,
        bytes32 guestShareRoot,
        bytes32 hostCardPk,
        bytes32 guestCardPk
    ) internal pure returns (ChannelV2.Marker memory) {
        return ChannelV2.Marker(
            hand, receiptHash, deckRoot, hostShareRoot, guestShareRoot, hostCardPk, guestCardPk, 0, 5, 10, FILLER_STARTING_CHIPS
        );
    }

    function _fileMarkerFullQuick(bytes32 session, ChannelV2.Marker memory m) internal {
        (bytes memory mh, bytes memory mg) = _signMarker(session, m, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileMarker(session, m, mh, mg);
    }

    /// test_F12_1_truncation_loses_full_window (fixtures-index Part A row).
    /// Two sessions, same setup, differing only in which chain is on file
    /// when the window closes: a truncated one (host's preflop all-in
    /// shove alone) and the fuller one (the shove plus guest's call, which
    /// completes the hand via the all-in-runout cascade, decision 3's
    /// `closeAndAdvance`). `_consolidate` must use whichever chain is
    /// actually on file — the truncated session stays pending, and P4's
    /// `resolve()` (AF-39 reconciliation) routes that pending frozen-only
    /// NONE into `_consolidatePhase2`, which itself finds no phase-2
    /// action ever filed and the bank barely touched, so it reverts this
    /// phase's own `Phase2InProgress` rather than the old
    /// `PendingContinuation`; the fuller session reaches a real
    /// resolution, proving the FULLER chain is what consolidation used,
    /// not the shorter one.
    function test_F12_1_truncation_loses_full_window() public {
        bytes32 sessionTrunc = keccak256("F12.1-trunc");
        bytes32 prevT = _setupDisputedMarkedHand1(sessionTrunc);
        // host (button, sb=5/bb=10, 2000-chip stacks both sides) shoves:
        // hi = maxRaiseTo = min(5+1995, 10+1990) = 2000 (effective stacks
        // equal after blinds) — the max legal bet.
        _fileOneAct(sessionTrunc, _mkAct(1, 0, 3, 2000, prevT), HOST_SESSION_PK);
        vm.warp(block.timestamp + WINDOW + 1);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(sessionTrunc);

        bytes32 sessionFull = keccak256("F12.1-full");
        bytes32 prevF = _setupDisputedMarkedHand1(sessionFull);
        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prevF);
        _fileOneAct(sessionFull, shove, HOST_SESSION_PK);
        // guest calls the shove — both stacks hit 0, cascading straight to
        // COMPLETE (all-in runout) with no further actions filed at all.
        _fileOneAct(sessionFull, _mkAct(1, 1, 2, 0, _actDigest(sessionFull, shove)), GUEST_SESSION_PK);
        vm.warp(block.timestamp + WINDOW + 1);

        // AF-35 reconciliation (task 13): Part B now ships a real
        // _resolveTerminal, so the fuller chain -- the one consolidation
        // actually used -- reaches a genuine resolution instead of the
        // Part-A stub revert. The property this fixture proves is
        // unchanged by Part B/P4 landing: consolidation used the FULLER
        // chain (COMPLETE), never the truncated prefix (which, per the
        // assertion above, stays Phase2InProgress forever -- no phase-2
        // action is ever filed against it) -- only the *observable proof*
        // of "which chain won" changes, from a stub-revert selector to an
        // actual settlement outcome. No shares were ever posted for this
        // hand, so the COMPLETE branch's completeness check (task 10 step
        // 2) finds both sides missing every required position: symmetric
        // muck (task 11 step 4), not a revert of any kind.
        channel.resolve(sessionFull); // must NOT revert -- the fuller chain resolves for real
        (,, ChannelV2.Status statusAfter,,) = channel.sessionCore(sessionFull);
        assertEq(
            uint8(statusAfter), uint8(ChannelV2.Status.Closed), "the FULL chain reached a real terminal resolution"
        );
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(sessionFull);
        assertTrue(hostBurned && guestBurned, "no shares posted for either side -- symmetric muck, both burn");
        assertEq(channel.burned(sessionFull), bondHost + bondGuest);
        assertEq(channel.credits(hostWallet), 0.2 ether, "symmetric muck settles at the receipt baseline, no pot overlay");
        assertEq(channel.credits(guestWallet), 0.2 ether);
    }

    /// test_F12_3_clamp_parity (fixtures-index Part A row; D18-vector-
    /// backed per task 2's hard gate).
    ///
    /// Two halves, each proving a different half of decision 3's "the
    /// clamp reduces to an integer range check, and the contract never
    /// re-clamps" claim:
    ///
    ///  (1) The REAL committed vector action (`Vectors.act(0)`/
    ///      `actions[0]` in p1-vectors.json: hand 1, seq 0, host bets the
    ///      canonical post-clamp 120, `rawAmountPreClamp: 200` per
    ///      gen.mts's own comment) is filed through the real
    ///      `fileActions` entry point against the vector's own
    ///      marker/session identity, and the exact signed amount
    ///      round-trips into `actionsAt` storage bit-for-bit — proving no
    ///      on-chain reclamping ever happens and that the vector's real
    ///      signature verifies end to end through this contract.
    ///
    ///  (2) A BettingReplay-level differential (task 5 item (f)'s
    ///      permitted methodology — constructed inputs, cross-checked
    ///      against the real betting.ts, not vector data) reproduces the
    ///      SAME clamp boundary the vector's comment describes: with the
    ///      vector's own sb=50/bb=100 and a stack pair {host:200,
    ///      guest:120} (guest short), running the actual betting.ts
    ///      directly (transcript below, not reimplemented from memory)
    ///      gives minRaiseTo(host)=200, maxRaiseTo(host)=120 — so
    ///      amount=120 is exactly the clamp of any raw request >= 120,
    ///      and amount=200 sits strictly above hi and must be rejected.
    ///
    ///        $ node --experimental-strip-types betting-probe.mjs   (poker
    ///          repo, importing src/core/betting.ts directly)
    ///        startHand({me:200,them:120},'me',50,100) ->
    ///          committed {me:50,them:100}, stacks {me:150,them:20}
    ///        minRaiseTo(me) = 200 ; maxRaiseTo(me) = 120
    ///        applyAction(st,'me','bet',200) -> committed.me clamps to 120
    ///
    ///  AF-32 UPDATE (2026-08-18): the marker now carries a both-signed
    ///  `startingChips` field (formats §4 amendment), and `_chipBaseline`
    ///  reads it directly instead of deriving `200 * bb` — so part (3)
    ///  below adds a THIRD half, proving the scale mismatch this comment
    ///  used to describe is actually fixed: reading the vector's own
    ///  on-chain state back, `weiPerChip`/`chipStackHost`/`chipStackGuest`
    ///  now come out to exactly `p1-vectors.json`'s own 200-chip
    ///  convention, not the old `200 * bb` = 20000-chip guess.
    ///
    ///  What is STILL not assertable, and why (documented rather than
    ///  silently dropped, per this test's original discipline): driving
    ///  the vector's real action through `resolve()`/`_consolidate` to
    ///  observe an ACCEPTED, non-reclamped `amount=120` end to end. That
    ///  narrative needs an asymmetric {200,120}-chip baseline (guest
    ///  short) — part (2)'s constructed differential proves the clamp
    ///  boundary exists at exactly that pair — but the vector's own (0,0)
    ///  receipt is symmetric (`hostStack == guestStack == hostDeposit ==
    ///  guestDeposit == DEPOSIT_WEI`), so the REAL on-chain baseline for
    ///  this session is {200,200}, not {200,120}. Against a real {200,200}
    ///  baseline, `BettingReplay.applyAction(..., Bet, 120)` is ILLEGAL
    ///  (`minRaiseTo(host) == maxRaiseTo(host) == 200`, confirmed by probe
    ///  and asserted in part (3)) — `channel.resolve()` reverts
    ///  `PendingContinuation`, the same outcome a still-broken baseline
    ///  would ALSO produce (120 is illegal against a 20000-chip baseline
    ///  too), so that revert alone cannot discriminate "fixed" from
    ///  "still broken" — which is exactly why part (3) asserts the
    ///  baseline NUMBERS directly (white-box, off the contract's own
    ///  storage) rather than inferring correctness from resolve()'s
    ///  outcome. This is a vector self-consistency gap in `gen.mts`
    ///  (hand 1's action amounts were scripted independently of the
    ///  receipt-implied per-hand chip baseline), not a `_chipBaseline`
    ///  bug — fixing it would mean re-deriving the vector's action
    ///  amounts from an asymmetric (0,0) receipt or an intermediate
    ///  hand-1 receipt, a `gen.mts` ripple outside AF-32's side-effect
    ///  boundary (marker format + `_chipBaseline`'s source, not the
    ///  vector's own action-amount scenario).
    function test_F12_3_clamp_parity() public {
        _f12_3_vectorSignatureAndStorageParity();
        _f12_3_bettingReplayDifferential();
        _f12_3_chipBaselineNowMatchesVector();
    }

    /// Split out of test_F12_3_clamp_parity purely for legacy (non-IR)
    /// codegen stack depth (this repo's foundry.toml does not set
    /// via_ir) — no behavior change, mirrors _happyPathRun's own split.
    function _f12_3_vectorSignatureAndStorageParity() internal {
        string memory json = vm.readFile("test/vectors/p1-vectors.json");
        bytes32 session = vecSession;
        _openJoin(
            session,
            hostWallet,
            HOST_WALLET_PK,
            guestWallet,
            GUEST_WALLET_PK,
            vm.parseJsonAddress(json, ".keys.host.address"),
            vm.parseJsonAddress(json, ".keys.guest.address"),
            1 ether,
            1 ether,
            0.2 ether,
            0.2 ether
        );
        VecReceipt memory r0 = _vecReceipt(json, 0);
        VecMarker memory mk = _vecMarker(json);
        channel.fileMarkerWithReceipt(
            session, _toMarker(mk), mk.hostSig, mk.guestSig, _toReceipt(r0), r0.hostSig, r0.guestSig
        );
        vm.prank(hostWallet);
        channel.openDispute(session);

        _f12_3_fileVectorActAndAssert(json, session);
    }

    function _f12_3_fileVectorActAndAssert(string memory json, bytes32 session) internal {
        ChannelV2.Act memory vecAct0 =
            ChannelV2.Act(1, 0, 3, 120, vm.parseJsonBytes32(json, ".actions[0].prev"));
        bytes memory vecSig0 = vm.parseJsonBytes(json, ".actions[0].sig");
        ChannelV2.Act[] memory acts = new ChannelV2.Act[](1);
        acts[0] = vecAct0;
        bytes[] memory sigs = new bytes[](1);
        sigs[0] = vecSig0;
        channel.fileActions(session, acts, sigs);

        address vecHost = vm.parseJsonAddress(json, ".keys.host.address");
        bytes32 slotKey = _actionSlotKey(session, 1, 0);
        (address signer, uint8 action, uint256 amount,,,, bool exists) = channel.actionsAt(slotKey, 0);
        assertTrue(exists);
        assertEq(signer, vecHost);
        assertEq(action, 3);
        assertEq(amount, 120, "the exact signed vector amount, unmodified -- no on-chain reclamping");
    }

    function _f12_3_bettingReplayDifferential() internal pure {
        BettingReplay.State memory st = BettingReplay.startHand(true, 200, 120, 50, 100);
        assertEq(BettingReplay.minRaiseTo(st, true), 200);
        assertEq(BettingReplay.maxRaiseTo(st, true), 120);

        bool okLegal;
        (st, okLegal) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Bet, 120);
        assertTrue(okLegal);
        assertEq(st.committedHost, 120);

        BettingReplay.State memory st2 = BettingReplay.startHand(true, 200, 120, 50, 100);
        bool okIllegal;
        (st2, okIllegal) = BettingReplay.applyAction(st2, true, BettingReplay.ActionKind.Bet, 200);
        assertFalse(okIllegal, "raw pre-clamp 200 sits above hi=120 and must be rejected, not silently reclamped");
    }

    /// AF-32 part (3): proves the 100x scale mismatch this test used to
    /// flag is fixed, by reading the vector's own on-chain state back and
    /// recomputing `_chipBaseline`'s math from it (mirroring the pattern
    /// `_markerDigest`/`_receiptDigest` already use to replicate internal
    /// contract logic for assertion purposes — `_chipBaseline` itself is
    /// `internal`, not callable from a test).
    ///
    /// Must run after `_f12_3_vectorSignatureAndStorageParity` has filed
    /// the vector's marker+receipt for `vecSession`.
    function _f12_3_chipBaselineNowMatchesVector() internal {
        bytes32 session = vecSession;
        string memory json = vm.readFile("test/vectors/p1-vectors.json");
        uint256 vectorStartingChips = vm.parseJsonUint(json, ".marker.startingChips");
        assertEq(vectorStartingChips, 200, "sanity: the vector's own field is 200, per gen.mts's STARTING_CHIPS");

        // White-box: the signed field round-tripped into markerAt exactly.
        (,,,,,,,, uint256 storedStartingChips) = channel.markerAt(session, 1);
        assertEq(storedStartingChips, vectorStartingChips, "AF-32: marker.startingChips round-trips into storage");

        // Recompute `_chipBaseline`'s own arithmetic from public state —
        // same require-guarded division, no ChannelV2.sol source reused.
        // hand=1 here, so baseline (hand-1=0) and baseline0 (hand 0) are
        // the SAME receipt -- one read covers both of `_chipBaseline`'s.
        (uint256 baselineHostStack, uint256 baselineGuestStack, uint256 baseline0HostDeposit,) =
            channel.receiptStacksAt(session, 0);
        assertEq(baseline0HostDeposit % storedStartingChips, 0, "chip/wei rate divides exactly");
        uint256 weiPerChip = baseline0HostDeposit / storedStartingChips;

        uint256 chipStackHost = baselineHostStack / weiPerChip;
        uint256 chipStackGuest = baselineGuestStack / weiPerChip;

        // The fixed value: exactly the vector's own 200-chip convention,
        // not the old `200 * bb` (bb=100) = 20000-chip guess this test's
        // own history flagged as a 100x mismatch (AF-32).
        assertEq(chipStackHost, 200, "AF-32 fixed: baseline matches the vector's startingChips, not 200*bb");
        assertEq(chipStackGuest, 200, "AF-32 fixed: baseline matches the vector's startingChips, not 200*bb");

        // Documented negative (see this test's class comment): against
        // this REAL, now-correct {200,200} baseline, the vector's real
        // amount=120 action is illegal (min==max==200 for symmetric
        // stacks) -- a vector self-consistency gap, not a baseline bug.
        // The illegal action is skipped by the replay engine (never
        // accepted), so _consolidate finds nothing walked -> NONE ->
        // P4's _consolidatePhase2 -> still no phase-2 action ever filed,
        // bank barely touched -> Phase2InProgress. resolve() reaching that
        // revert is consistent with the illegal amount, but -- as the
        // class comment explains -- does not by itself discriminate a
        // fixed baseline from a still-broken one (either produces the same
        // "nothing accepted" outcome), which is why the assertions above
        // (not this revert) are the real proof.
        vm.warp(block.timestamp + WINDOW + 1);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);
    }

    /// test_F12_6_first_marker_in_window (fixtures-index Part A row).
    /// Dispute opens before any marker has ever confirmed; the FIRST-ever
    /// marker (hand 1) is both-signed and filed inside the window (D6:
    /// "first marker admissible during a dispute window"); a fold filed
    /// for that hand routes through consolidation to _resolveTerminal's
    /// stub (NotYetBuilt) — not the markedHand==0 never-started/per-duty
    /// refund branches — proving the in-gap fold is anchored to the real
    /// live hand, not refunded as if hand 1 never began.
    function test_F12_6_first_marker_in_window() public {
        bytes32 session = keccak256("F12.6");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);

        vm.prank(hostWallet);
        channel.openDispute(session);
        assertEq(channel.markedHand(session), 0);

        ChannelV2.Marker memory m1 = _fileMarkerQuick(session, 1, _receiptDigest(session, r0));
        assertEq(channel.markedHand(session), 1);
        assertEq(channel.liveHand(session), 1);

        bytes32 prev0 = _markerDigest(session, m1);
        _fileOneAct(session, _mkAct(1, 0, 0, 0, prev0), HOST_SESSION_PK); // host (button) folds immediately

        vm.warp(block.timestamp + WINDOW + 1);

        // AF-35 reconciliation (task 13): Part B now resolves a FOLD chain
        // directly (task 10 step 1) instead of reverting the Part-A stub.
        // The property this fixture proves survives unchanged: the fold is
        // anchored to the live hand this in-gap marker created
        // (markedHand == 1), so it resolves through the real dispute
        // table -- pot to the non-folder, folder's bond returns -- rather
        // than being refunded as if hand 1 had never begun (the
        // markedHand == 0 branches).
        channel.resolve(session); // must NOT revert
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned, "folding is a completed decision, not misconduct -- the folder's bond returns");
        assertFalse(guestBurned);
        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        // host (button) posted sb=5, guest posted bb=10, host folds
        // immediately: host keeps 1995 chips, guest recovers 1990 plus the
        // forfeited 5 = 2005 -- the pot to the non-folder, spec §5.3's
        // fold row.
        assertEq(
            channel.credits(hostWallet), 1995 * weiPerChip + bondHost, "host loses exactly the folded blind, bond intact"
        );
        assertEq(channel.credits(guestWallet), 2005 * weiPerChip + bondGuest, "pot goes to the non-folder");
    }

    /// test_F13_4_equivocation_burn (fixtures-index Part A row), plus the
    /// F14.4 identical-duplicate sub-case and the AF-6 same-block-tie
    /// sub-case (task 3 step 4's ruling: EVM intra-block execution is
    /// already a total order, so "first stored wins" needs no hash
    /// tiebreak — proven here by never comparing a hash at all).
    function test_F13_4_equivocation_burn() public {
        bytes32 session = keccak256("F13.4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory actA = _mkAct(1, 0, 3, 20, prev0);
        ChannelV2.Act memory actB = _mkAct(1, 0, 3, 999, prev0); // same node, distinct amount

        _fileOneAct(session, actA, HOST_SESSION_PK);
        (,, bool hostBurnedBefore,) = channel.sessionBonds(session);
        assertFalse(hostBurnedBefore);

        // Two separate calls, same block (no vm.roll between them) — the
        // AF-6 same-block-tie case.
        _fileOneAct(session, actB, HOST_SESSION_PK);

        (uint256 bondHost,, bool hostBurnedAfter,) = channel.sessionBonds(session);
        assertTrue(hostBurnedAfter, "eager, window-gated equivocation burn");
        assertEq(channel.burned(session), bondHost);

        bytes32 slotKey = _actionSlotKey(session, 1, 0);
        (address signer,, uint256 amount,,,, bool exists) = channel.actionsAt(slotKey, 0);
        assertTrue(exists);
        assertEq(signer, vm.addr(HOST_SESSION_PK));
        assertEq(amount, 20, "earliest-filed (first-executed) candidate stands -- never a hash comparison");

        // F14.4: an identical duplicate of actA — silent dedup, no
        // additional burn, no storage change.
        _fileOneAct(session, actA, HOST_SESSION_PK);
        assertEq(channel.burned(session), bondHost, "identical duplicate never burns again");
        (,, uint256 amountAfterDup,,,,) = channel.actionsAt(slotKey, 0);
        assertEq(amountAfterDup, 20);
    }

    /// test_F14_3_pair_in_window_only (fixtures-index Part A row). The
    /// equivocating second signature lands strictly after the window
    /// closes: no burn fires (D8's "admissible only if complete
    /// in-window"), and — since decision 2's no-overwrite rule means the
    /// second candidate was never stored at all, in-window or not — it
    /// cannot enter `_consolidate`'s frozen chain either (task 6's filter
    /// reads only what `actionsAt` actually holds).
    function test_F14_3_pair_in_window_only() public {
        bytes32 session = keccak256("F14.3");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        ChannelV2.Act memory actA = _mkAct(1, 0, 3, 20, prev0);
        _fileOneAct(session, actA, HOST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW + 1); // strictly past the window

        ChannelV2.Act memory actB = _mkAct(1, 0, 3, 999, prev0); // same node, distinct
        _fileOneAct(session, actB, HOST_SESSION_PK);

        (,, bool hostBurned,) = channel.sessionBonds(session);
        assertFalse(hostBurned, "second signature landed after the window -- inadmissible as burn proof");
        assertEq(channel.burned(session), 0);

        bytes32 slotKey = _actionSlotKey(session, 1, 0);
        (,, uint256 amount,,,, bool exists) = channel.actionsAt(slotKey, 0);
        assertTrue(exists);
        assertEq(amount, 20, "the late candidate never overwrites the stored one -- it never enters actionsAt at all");
    }

    /// test_F14_5_boundary_conventions (fixtures-index Part A row, window
    /// half only — the duty-deadline half of finding 5b needs task 11's
    /// machinery, deferred to task 13 per the phase doc's own allowance,
    /// task 8 step 6). A candidate filed in the EXACT block whose
    /// timestamp equals `disputeOpenedAt + window` is phase 2 (`<`, not
    /// `<=`) — excluded from consolidation. Proven by contrast: the same
    /// candidate, if it HAD been accepted, would complete an all-in chain
    /// (COMPLETE); excluded, the chain stops at the shove alone, still
    /// pending — P4 reconciliation (AF-39): `resolve()` routes that
    /// pending NONE into `_consolidatePhase2`, which itself finds no
    /// phase-2 action filed and zero elapsed bank time (resolve() is
    /// called at the exact same instant the boundary is reached), so it
    /// reverts `Phase2InProgress`, not the old `PendingContinuation`.
    function test_F14_5_boundary_conventions() public {
        bytes32 session = keccak256("F14.5");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);
        bytes32 prevAfterShove = _actDigest(session, shove);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW); // exactly the boundary

        ChannelV2.Act memory call1 = _mkAct(1, 1, 2, 0, prevAfterShove);
        _fileOneAct(session, call1, GUEST_SESSION_PK);

        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);
    }

    /// test_M1_outOfTurn_contractLevel (AF-2's turn-order property, proven
    /// end-to-end through the real fileActions -> resolve() pipeline —
    /// task 5 item (g) already proves this at BettingReplay's own pure-
    /// library level; this is the contract-level companion). A validly-
    /// signed candidate from the WRONG seat at seq 0 (guest, when host is
    /// button and acts first preflop) is stored unconditionally at filing
    /// time (decision 1: self-authentication only, no turn-order check
    /// there) but the replay engine treats it exactly as "no candidate at
    /// this seq" — never as an accepted action and never as equivocation
    /// (different signer, not a same-key conflict).
    function test_M1_outOfTurn_contractLevel_treatedAsNoCandidate() public {
        bytes32 session = keccak256("M1.contract");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory outOfTurn = _mkAct(1, 0, 2, 0, prev0); // guest "calls" out of turn
        _fileOneAct(session, outOfTurn, GUEST_SESSION_PK);

        bytes32 slotKey = _actionSlotKey(session, 1, 0);
        (address signer,,,,,, bool exists) = channel.actionsAt(slotKey, 0);
        assertTrue(exists, "storage accepts any correctly-signed candidate, regardless of turn order");
        assertEq(signer, vm.addr(GUEST_SESSION_PK));

        // P4 reconciliation (AF-39): the replay engine treats the
        // out-of-turn candidate as no candidate at all, so _consolidate
        // still finds nothing accepted -> NONE -> resolve() now routes
        // into _consolidatePhase2 (no phase2Act stub anymore) rather than
        // reverting PendingContinuation outright; that inner call also
        // finds no phase-2 action ever filed and only a second of elapsed
        // bank time, so it reverts this phase's own Phase2InProgress.
        vm.warp(block.timestamp + WINDOW + 1);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);
    }

    /// test_M2_postShares_positionMismatch_notStored (task 8 step 7, fix
    /// round 1 P3-4). A SharePost whose shareProof genuinely proves
    /// inclusion at position 0, but whose deckProof genuinely proves
    /// inclusion of position 1's real ciphertext — submitted claiming
    /// pos=0 for both. Position-bound leaf hashing (AF-14, decision 10)
    /// means the contract's own recomputed deck leaf (pos=0, position-1's
    /// ciphertext bytes) never matches anything position 1's real proof
    /// authenticates: the check fails, nothing is stored, and postShares
    /// does not revert (decision 5's "a failing post just wastes gas").
    function test_M2_postShares_positionMismatch_notStored() public {
        bytes32 session = keccak256("M2.postShares");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);

        bytes32[4] memory shareLeaves;
        bytes32[4] memory c1s;
        bytes32[4] memory c2s;
        bytes32[4] memory deckLeaves;
        for (uint8 i = 0; i < 4; i++) {
            bytes32 shareEnc = keccak256(abi.encodePacked("shareEnc", i));
            shareLeaves[i] = Evidence.shareLeaf(i, shareEnc);
            c1s[i] = keccak256(abi.encodePacked("c1", i));
            c2s[i] = keccak256(abi.encodePacked("c2", i));
            deckLeaves[i] = Evidence.deckLeaf(i, c1s[i], c2s[i]);
        }
        bytes32 hostShareRoot = _merkleRoot4(shareLeaves);
        bytes32 deckRoot = _merkleRoot4(deckLeaves);

        ChannelV2.Marker memory m1 = _mkMarkerFull(
            1,
            _receiptDigest(session, r0),
            deckRoot,
            hostShareRoot,
            keccak256("guestShareRoot-unused"),
            keccak256("hostCardPk-unused"),
            keccak256("guestCardPk-unused")
        );
        _fileMarkerFullQuick(session, m1);

        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](1);
        posts[0] = ChannelV2.SharePost({
            pos: 0,
            shareEnc: keccak256(abi.encodePacked("shareEnc", uint8(0))),
            c: 0,
            s: 0,
            shareProof: _merkleProof4(shareLeaves, 0),
            c1Enc: c1s[1],
            c2Enc: c2s[1],
            deckProof: _merkleProof4(deckLeaves, 1)
        });

        channel.postShares(session, posts); // must not revert
        assertFalse(
            channel.sharePosted(session, 1, 0, hostWallet), "position-bound leaf hash rejects the pos=0/q=1 mismatch"
        );
        assertFalse(channel.sharePosted(session, 1, 1, hostWallet));
    }

    /// test_F12_2_wrongKeyRoot_dleqRejectsAtFileTime (Part A-scoped half
    /// of fixtures-index's F12.2 — the full "muck against the committer"
    /// resolution needs task 11's machinery, Part B's, and is
    /// `test_F12_2_wrong_key_root_burns_owner` there, task 13. What's
    /// provable now, at the triple-check level alone: a share/deck pair
    /// that genuinely passes both Merkle checks, using a REAL DLEQ proof
    /// (`Vectors.dleq(0)`, valid against the vector's real
    /// `Vectors.marker().hostCardPk`) — but the marker committed to a
    /// DIFFERENT `hostCardPk` (the "wrong-key shareRoot" scenario) — fails
    /// the DLEQ step and is not stored, without reverting.
    function test_F12_2_wrongKeyRoot_dleqRejectsAtFileTime() public {
        bytes32 session = keccak256("F12.2.wrongkey");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);

        Vectors.Dleq memory d = Vectors.dleq(0);
        assertTrue(d.ok);
        bytes32 realHostCardPk = Vectors.marker().hostCardPk;
        assertEq(d.pub, realHostCardPk, "sanity: the vector DLEQ really is built against the vector marker's real key");

        bytes32[4] memory shareLeaves;
        bytes32[4] memory deckLeaves;
        shareLeaves[0] = Evidence.shareLeaf(0, d.point2); // real DLEQ point2 == shareEnc
        bytes32 c2 = Ristretto.encode(Ristretto.base()); // any valid, decodable point
        deckLeaves[0] = Evidence.deckLeaf(0, d.base2, c2); // real DLEQ base2 == c1Enc
        for (uint8 i = 1; i < 4; i++) {
            shareLeaves[i] = keccak256(abi.encodePacked("filler-share", i));
            deckLeaves[i] = keccak256(abi.encodePacked("filler-deck", i));
        }
        bytes32 hostShareRoot = _merkleRoot4(shareLeaves);
        bytes32 deckRoot = _merkleRoot4(deckLeaves);

        // wrong key: the marker commits a DIFFERENT hostCardPk than the
        // one the DLEQ proof was actually built against.
        bytes32 wrongCardPk = Ristretto.encode(Ristretto.mul(Ristretto.base(), 999));
        assertTrue(wrongCardPk != realHostCardPk);

        ChannelV2.Marker memory mWrong = _mkMarkerFull(
            1,
            _receiptDigest(session, r0),
            deckRoot,
            hostShareRoot,
            keccak256("guestShareRoot-unused"),
            wrongCardPk,
            keccak256("guestCardPk-unused")
        );
        _fileMarkerFullQuick(session, mWrong);

        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](1);
        posts[0] = ChannelV2.SharePost({
            pos: 0,
            shareEnc: d.point2,
            c: d.c,
            s: d.s,
            shareProof: _merkleProof4(shareLeaves, 0),
            c1Enc: d.base2,
            c2Enc: c2,
            deckProof: _merkleProof4(deckLeaves, 0)
        });
        channel.postShares(session, posts); // must not revert
        assertFalse(
            channel.sharePosted(session, 1, 0, hostWallet), "DLEQ fails against the marker's wrongly-committed key"
        );
    }

    /// Gas baseline (task 8 step 8): one accepted fileActions candidate,
    /// isolated in its own test so `forge snapshot`'s per-test entry is a
    /// legible single-call figure. Compared informally (not a pass/fail
    /// gate) against the prototype's measured ~3,786-gas Merkle inclusion
    /// figure in this dispatch's completion notes — this call does an
    /// ecrecover plus one storage write, no Merkle/DLEQ at all, so it is
    /// expected to sit well under that figure, not near it.
    function test_gas_fileActions_oneCandidate() public {
        bytes32 session = keccak256("gas.fileActions");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        _fileOneAct(session, _mkAct(1, 0, 3, 20, prev0), HOST_SESSION_PK);
    }

    /// Gas baseline (task 8 step 8): one passing postShares triple check
    /// (real Merkle share, real Merkle deck, real DLEQ against the
    /// vector's real key), isolated in its own test for the same reason
    /// as above. Compared informally against the prototype's measured
    /// ~2,969,269-gas DLEQ figure and ~3,786-gas Merkle inclusion figure
    /// in this dispatch's completion notes.
    function test_gas_postShares_onePassingTripleCheck() public {
        bytes32 session = keccak256("gas.postShares");
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);

        Vectors.Dleq memory d = Vectors.dleq(0);
        bytes32 realHostCardPk = Vectors.marker().hostCardPk;

        bytes32[4] memory shareLeaves;
        bytes32[4] memory deckLeaves;
        shareLeaves[0] = Evidence.shareLeaf(0, d.point2);
        bytes32 c2 = Ristretto.encode(Ristretto.base());
        deckLeaves[0] = Evidence.deckLeaf(0, d.base2, c2);
        for (uint8 i = 1; i < 4; i++) {
            shareLeaves[i] = keccak256(abi.encodePacked("filler-share", i));
            deckLeaves[i] = keccak256(abi.encodePacked("filler-deck", i));
        }
        bytes32 hostShareRoot = _merkleRoot4(shareLeaves);
        bytes32 deckRoot = _merkleRoot4(deckLeaves);

        ChannelV2.Marker memory m1 = _mkMarkerFull(
            1,
            _receiptDigest(session, r0),
            deckRoot,
            hostShareRoot,
            keccak256("guestShareRoot-unused"),
            realHostCardPk,
            keccak256("guestCardPk-unused")
        );
        _fileMarkerFullQuick(session, m1);

        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](1);
        posts[0] = ChannelV2.SharePost({
            pos: 0,
            shareEnc: d.point2,
            c: d.c,
            s: d.s,
            shareProof: _merkleProof4(shareLeaves, 0),
            c1Enc: d.base2,
            c2Enc: c2,
            deckProof: _merkleProof4(deckLeaves, 0)
        });
        channel.postShares(session, posts);
        assertTrue(channel.sharePosted(session, 1, 0, hostWallet), "same material against the real key passes");
    }

    // =====================================================================
    // Task 13 (P3 Part B) — remaining fixtures (F10.1, F11.1, F12.2, F13.6,
    // F14.1, F15.1, F15.2, F16.1, F16.3, S_dead_man_switch), the task-9
    // decode functional coverage (AF-34/AF-35), D12 re-derivation, gas
    // snapshots. See phase-3-disputes-evidence.md task 13 and
    // fixtures-index.md for the fixture class each test below re-derives.
    //
    // Genuine card material (used by the fixtures that need a real
    // showdown, not just routing) is built directly in Solidity against
    // Ristretto.sol/Dleq.sol — not vector-sourced, since the committed
    // vector only samples 4 of the 52 real deck/share positions and these
    // fixtures need arbitrary chosen positions and card indices. The DLEQ
    // proof generator below is Dleq.sol's own verify arithmetic run in
    // reverse (Fiat-Shamir Schnorr): pick a nonce k, compute t1 = G^k,
    // t2 = base2^k, derive the challenge exactly as Dleq.challenge does,
    // then s = k + c*secret (mod L) -- Dleq.verify's own recomputation of
    // t1/t2 from (c, s) reproduces the same points by construction, so the
    // challenge recomputation matches and verify() returns true.
    // =====================================================================

    struct CardMaterial {
        bytes32 c1Enc;
        bytes32 c2Enc;
        bytes32 hostShareEnc;
        bytes32 guestShareEnc;
        uint256 hostC;
        uint256 hostS;
        uint256 guestC;
        uint256 guestS;
    }

    /// One position's full ElGamal material for an ARBITRARY target point
    /// (elgamal.ts:76-79's combine, run forward): c2 = target + hostShare +
    /// guestShare, hostShare = c1^xHost, guestShare = c1^xGuest, c1 = G^r.
    /// Both DLEQ proofs are genuinely generated and genuinely verify.
    function _buildCardMaterialForPoint(Ristretto.Pt memory targetPt, uint256 xHost, uint256 xGuest, uint8 pos)
        internal
        view
        returns (CardMaterial memory cm)
    {
        Ristretto.Pt memory g = Ristretto.base();
        uint256 r = uint256(keccak256(abi.encodePacked("t13-r", pos))) % Ristretto.L;
        Ristretto.Pt memory c1 = Ristretto.mul(g, r);
        Ristretto.Pt memory hostSharePt = Ristretto.mul(c1, xHost);
        Ristretto.Pt memory guestSharePt = Ristretto.mul(c1, xGuest);
        Ristretto.Pt memory c2 = Ristretto.add(Ristretto.add(targetPt, hostSharePt), guestSharePt);

        cm.c1Enc = Ristretto.encode(c1);
        cm.c2Enc = Ristretto.encode(c2);
        cm.hostShareEnc = Ristretto.encode(hostSharePt);
        cm.guestShareEnc = Ristretto.encode(guestSharePt);

        uint256 nonceHost = uint256(keccak256(abi.encodePacked("t13-nh", pos))) % Ristretto.L;
        uint256 nonceGuest = uint256(keccak256(abi.encodePacked("t13-ng", pos))) % Ristretto.L;
        (cm.hostC, cm.hostS) = _genDleqProof(xHost, cm.c1Enc, _cardPkEnc(xHost), cm.hostShareEnc, nonceHost);
        (cm.guestC, cm.guestS) = _genDleqProof(xGuest, cm.c1Enc, _cardPkEnc(xGuest), cm.guestShareEnc, nonceGuest);
    }

    /// Same, for a REAL protocol card (decision 6): target = cardPoint(i).
    function _buildCardMaterial(uint8 cardIndex, uint256 xHost, uint256 xGuest, uint8 pos)
        internal
        view
        returns (CardMaterial memory)
    {
        (, Ristretto.Pt memory cardPt) = Ristretto.decode(Evidence.cardPoint(cardIndex));
        return _buildCardMaterialForPoint(cardPt, xHost, xGuest, pos);
    }

    function _cardPkEnc(uint256 x) internal view returns (bytes32) {
        return Ristretto.encode(Ristretto.mul(Ristretto.base(), x));
    }

    /// Fiat-Shamir DLEQ proof generation, Dleq.sol's verify() run in
    /// reverse -- see this section's header comment.
    function _genDleqProof(uint256 secret, bytes32 base2Enc, bytes32 pubEnc, bytes32 point2Enc, uint256 nonce)
        internal
        view
        returns (uint256 c, uint256 s)
    {
        (, Ristretto.Pt memory base2) = Ristretto.decode(base2Enc);
        Ristretto.Pt memory t1 = Ristretto.mul(Ristretto.base(), nonce);
        Ristretto.Pt memory t2 = Ristretto.mul(base2, nonce);
        c = Dleq.challenge(pubEnc, base2Enc, point2Enc, Ristretto.encode(t1), Ristretto.encode(t2));
        s = addmod(nonce, mulmod(c, secret, Ristretto.L), Ristretto.L);
    }

    // ---- generic power-of-two Merkle (16 leaves easily covers every
    // §5.3-required position index, 0..11) -- `_pairHash4` (task 8) is
    // already leaf-count-agnostic sorted-pair hashing, reused directly. ----

    function _merkleRootN(bytes32[] memory leaves) internal pure returns (bytes32) {
        uint256 n = leaves.length;
        bytes32[] memory level = leaves;
        while (n > 1) {
            bytes32[] memory next = new bytes32[](n / 2);
            for (uint256 i = 0; i < n / 2; i++) {
                next[i] = _pairHash4(level[2 * i], level[2 * i + 1]);
            }
            level = next;
            n = n / 2;
        }
        return level[0];
    }

    function _merkleProofN(bytes32[] memory leaves, uint256 idx) internal pure returns (bytes32[] memory proof) {
        uint256 n = leaves.length;
        uint256 depth = 0;
        {
            uint256 t = n;
            while (t > 1) {
                t /= 2;
                depth++;
            }
        }
        proof = new bytes32[](depth);
        bytes32[] memory level = leaves;
        uint256 levelLen = n;
        uint256 index = idx;
        for (uint256 d = 0; d < depth; d++) {
            proof[d] = level[index ^ 1];
            bytes32[] memory next = new bytes32[](levelLen / 2);
            for (uint256 i = 0; i < levelLen / 2; i++) {
                next[i] = _pairHash4(level[2 * i], level[2 * i + 1]);
            }
            level = next;
            levelLen /= 2;
            index /= 2;
        }
    }

    function _fillerLeaves16(string memory tag) internal pure returns (bytes32[] memory leaves) {
        leaves = new bytes32[](16);
        for (uint256 i = 0; i < 16; i++) {
            leaves[i] = keccak256(abi.encodePacked(tag, i));
        }
    }

    // ---- full 9-position showdown material (§5.3's required positions:
    // host hole 0/1, guest hole 2/3, flop 5/6/7, turn 9, river 11) ----

    function _requiredPos() internal pure returns (uint8[9] memory p) {
        p = [uint8(0), 1, 2, 3, 5, 6, 7, 9, 11];
    }

    struct ShowdownMaterial {
        bytes32 deckRoot;
        bytes32 hostShareRoot;
        bytes32 guestShareRoot;
        bytes32 hostCardPk;
        bytes32 guestCardPk;
        bytes32[] deckLeaves;
        bytes32[] hostLeaves;
        bytes32[] guestLeaves;
        CardMaterial[9] cards;
    }

    function _buildShowdown(uint8[9] memory cardIndices, uint256 xHost, uint256 xGuest)
        internal
        view
        returns (ShowdownMaterial memory sm)
    {
        uint8[9] memory positions = _requiredPos();
        sm.deckLeaves = _fillerLeaves16("t13-filler-deck");
        sm.hostLeaves = _fillerLeaves16("t13-filler-host");
        sm.guestLeaves = _fillerLeaves16("t13-filler-guest");
        for (uint256 i = 0; i < 9; i++) {
            uint8 pos = positions[i];
            CardMaterial memory cm = _buildCardMaterial(cardIndices[i], xHost, xGuest, pos);
            sm.cards[i] = cm;
            sm.deckLeaves[pos] = Evidence.deckLeaf(pos, cm.c1Enc, cm.c2Enc);
            sm.hostLeaves[pos] = Evidence.shareLeaf(pos, cm.hostShareEnc);
            sm.guestLeaves[pos] = Evidence.shareLeaf(pos, cm.guestShareEnc);
        }
        sm.deckRoot = _merkleRootN(sm.deckLeaves);
        sm.hostShareRoot = _merkleRootN(sm.hostLeaves);
        sm.guestShareRoot = _merkleRootN(sm.guestLeaves);
        sm.hostCardPk = _cardPkEnc(xHost);
        sm.guestCardPk = _cardPkEnc(xGuest);
    }

    function _postHost(bytes32 session, ShowdownMaterial memory sm, uint256 i) internal {
        uint8 pos = _requiredPos()[i];
        CardMaterial memory cm = sm.cards[i];
        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](1);
        posts[0] = ChannelV2.SharePost({
            pos: pos,
            shareEnc: cm.hostShareEnc,
            c: cm.hostC,
            s: cm.hostS,
            shareProof: _merkleProofN(sm.hostLeaves, pos),
            c1Enc: cm.c1Enc,
            c2Enc: cm.c2Enc,
            deckProof: _merkleProofN(sm.deckLeaves, pos)
        });
        channel.postShares(session, posts);
    }

    function _postGuest(bytes32 session, ShowdownMaterial memory sm, uint256 i) internal {
        uint8 pos = _requiredPos()[i];
        CardMaterial memory cm = sm.cards[i];
        ChannelV2.SharePost[] memory posts = new ChannelV2.SharePost[](1);
        posts[0] = ChannelV2.SharePost({
            pos: pos,
            shareEnc: cm.guestShareEnc,
            c: cm.guestC,
            s: cm.guestS,
            shareProof: _merkleProofN(sm.guestLeaves, pos),
            c1Enc: cm.c1Enc,
            c2Enc: cm.c2Enc,
            deckProof: _merkleProofN(sm.deckLeaves, pos)
        });
        channel.postShares(session, posts);
    }

    function _postAllHost(bytes32 session, ShowdownMaterial memory sm) internal {
        for (uint256 i = 0; i < 9; i++) {
            _postHost(session, sm, i);
        }
    }

    function _postAllGuest(bytes32 session, ShowdownMaterial memory sm) internal {
        for (uint256 i = 0; i < 9; i++) {
            _postGuest(session, sm, i);
        }
    }

    /// open+join+receipt(0,0)+dispute+marker(real roots)+shove+call --
    /// the shared "genuine COMPLETE hand, real crypto" setup every showdown
    /// fixture below needs. Returns the completing action's own filedAt
    /// (decision 3's birth anchor), read directly off block.timestamp since
    /// no warp happens between filing the call and returning here.
    function _setupCompleteHandWithMaterial(bytes32 session, ShowdownMaterial memory sm)
        internal
        returns (uint256 completingFiledAt)
    {
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);
        ChannelV2.Marker memory m1 = ChannelV2.Marker(
            1,
            _receiptDigest(session, r0),
            sm.deckRoot,
            sm.hostShareRoot,
            sm.guestShareRoot,
            sm.hostCardPk,
            sm.guestCardPk,
            0,
            5,
            10,
            FILLER_STARTING_CHIPS
        );
        _fileMarkerFullQuick(session, m1);
        bytes32 prev0 = _markerDigest(session, m1);
        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);
        ChannelV2.Act memory call = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _fileOneAct(session, call, GUEST_SESSION_PK);
        completingFiledAt = block.timestamp;
    }

    /// test_F10_1_fiction_dies_to_evidence (fixtures-index Part B row).
    /// The loser refuses the true post-hand receipt and instead gets both
    /// signatures on a grossly fictional one for the disputed hand itself
    /// -- something no honest client would counter-sign, but the dispute
    /// machinery has no need to care: a plain (non-final) receipt at the
    /// MARKED hand plays no role at all in the markedHand>0 resolution
    /// table (only receipt N-1's cached baseline and the filed action
    /// chain/shares matter, D9 precedence). Victim files the real chain
    /// plus real shares; cards decide the true result regardless.
    function test_F10_1_fiction_dies_to_evidence() public {
        bytes32 session = keccak256("F10.1");
        // host hole = pair of Kings (11, 24); guest hole = pair of Queens
        // (10, 23); board = unrelated low cards with no pair/straight/
        // flush for either side -- host's kings clean-win over guest's
        // queens, no tie, no board-only chop.
        uint8[9] memory cardIndices = [uint8(11), 24, 10, 23, 30, 45, 3, 47, 20];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 111, 222);
        uint256 completingFiledAt = _setupCompleteHandWithMaterial(session, sm);

        ChannelV2.Receipt memory fiction = _mkReceipt(1, 0, 0.35 ether, 0.05 ether, 0.2 ether, 0.2 ether, false);
        (bytes memory fh, bytes memory fg) = _signReceipt(session, fiction, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, fiction, fh, fg); // files fine; must NOT move the outcome

        _postAllHost(session, sm);
        _postAllGuest(session, sm);

        uint256 hostScore = _evaluateHost(cardIndices);
        uint256 guestScore = _evaluateGuest(cardIndices);
        assertTrue(hostScore != guestScore, "fixture must pick a clean, non-tied winner");

        vm.warp(completingFiledAt + WINDOW + 1);
        channel.resolve(session);

        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned);
        assertFalse(guestBurned);

        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        uint256 winnerStackWei = 4000 * weiPerChip; // shove(2000)+call(2000): pot 4000, no excess
        if (hostScore > guestScore) {
            assertEq(
                channel.credits(hostWallet), winnerStackWei + bondHost, "true cards-decide result, not the fiction's 0.35 ether"
            );
            assertEq(channel.credits(guestWallet), bondGuest);
        } else {
            assertEq(
                channel.credits(guestWallet), winnerStackWei + bondGuest, "true cards-decide result, not the fiction's 0.05 ether"
            );
            assertEq(channel.credits(hostWallet), bondHost);
        }
    }

    function _evaluateHost(uint8[9] memory c) internal pure returns (uint256) {
        return Evaluator7.evaluate([c[0], c[1], c[4], c[5], c[6], c[7], c[8]]);
    }

    function _evaluateGuest(uint8[9] memory c) internal pure returns (uint256) {
        return Evaluator7.evaluate([c[2], c[3], c[4], c[5], c[6], c[7], c[8]]);
    }

    /// test_F11_1_fold_is_final_decision (fixtures-index Part B row). A
    /// signed fold is a completed decision, not misconduct: pot to the
    /// non-folder, folder's bond returns -- the row most likely to be
    /// miscoded as a burn by analogy with the muck rows (task 10's own
    /// warning), so this fixture asserts the bond status explicitly.
    function test_F11_1_fold_is_final_decision() public {
        bytes32 session = keccak256("F11.1");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        _fileOneAct(session, _mkAct(1, 0, 0, 0, prev0), HOST_SESSION_PK); // host (button) folds immediately

        vm.warp(block.timestamp + WINDOW + 1);
        channel.resolve(session);

        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned, "folding is a completed decision -- the folder's bond returns, never burns");
        assertFalse(guestBurned);
        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        assertEq(channel.credits(hostWallet), 1995 * weiPerChip + bondHost);
        assertEq(channel.credits(guestWallet), 2005 * weiPerChip + bondGuest, "pot to the non-folder");
    }

    /// test_F12_2_wrong_key_root_burns_owner (fixtures-index Part B row --
    /// the FULL muck-resolution half; the Part A half,
    /// test_F12_2_wrongKeyRoot_dleqRejectsAtFileTime, already proves the
    /// file-time triple-check reject). Marker commits a WRONG hostCardPk;
    /// host's real shares (built against host's REAL secret) genuinely
    /// pass Merkle (self-consistent leaves) but fail DLEQ against the
    /// wrongly-committed key -- none of host's posts land. Guest's posts,
    /// against the correctly-committed key, all land. One-sided muck at
    /// dueAt: pot to guest, host (the committer of the wrong key) burns.
    function test_F12_2_wrong_key_root_burns_owner() public {
        bytes32 session = keccak256("F12.2.full");
        uint8[9] memory cardIndices = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 555, 666);
        sm.hostCardPk = Ristretto.encode(Ristretto.mul(Ristretto.base(), 999999)); // wrong key, committed
        uint256 completingFiledAt = _setupCompleteHandWithMaterial(session, sm);

        _postAllHost(session, sm); // every host post fails DLEQ silently, nothing stored
        _postAllGuest(session, sm); // guest's posts, against the real key, all land

        uint8[9] memory positions = _requiredPos();
        for (uint256 i = 0; i < 9; i++) {
            assertFalse(channel.sharePosted(session, 1, positions[i], hostWallet), "wrong-key root: none of host's posts land");
            assertTrue(channel.sharePosted(session, 1, positions[i], guestWallet), "guest's posts land fine");
        }

        vm.warp(completingFiledAt + WINDOW + GRACE + 1);
        channel.resolve(session);

        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertTrue(hostBurned, "the committer of the wrong-key root burns");
        assertFalse(guestBurned);
        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        assertEq(channel.credits(guestWallet), 4000 * weiPerChip + bondGuest, "whole pot to the complete poster");
        assertEq(channel.credits(hostWallet), 0, "host's bond burned -- nothing returns, host also loses the whole pot");
    }

    /// test_F13_6_fourth_row_total (fixtures-index Part B row). Both seats
    /// sign a malformed deck: every required position's committed card is
    /// the SAME index (52x-same-card, per the fixture's own framing).
    /// Every individual check passes (real Merkle, real DLEQ, self-
    /// consistent) but the duplicate-card check (task 11 step 5) fires --
    /// both bonds burn, settle at the receipt baseline, total (no revert).
    /// Part B gate 4's four named assertions, all present: (a) no
    /// vm.expectRevert anywhere in this test; (b) credits equal the
    /// receipt-baseline stacks exactly; (c) burned == bondHost+bondGuest;
    /// (d) hostBurned && guestBurned.
    function test_F13_6_fourth_row_total() public {
        bytes32 session = keccak256("F13.6");
        uint8[9] memory cardIndices = [uint8(7), 7, 7, 7, 7, 7, 7, 7, 7]; // malformed: same card everywhere
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 333, 444);
        uint256 completingFiledAt = _setupCompleteHandWithMaterial(session, sm);

        _postAllHost(session, sm);
        _postAllGuest(session, sm);

        vm.warp(completingFiledAt + WINDOW + 1);

        // (a) no vm.expectRevert anywhere in this test -- resolution is total.
        channel.resolve(session);

        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));

        // (b) credits equal the receipt-baseline stacks exactly, no pot overlay.
        assertEq(channel.credits(hostWallet), 0.2 ether);
        assertEq(channel.credits(guestWallet), 0.2 ether);

        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        // (c) burned == bondHost + bondGuest.
        assertEq(channel.burned(session), bondHost + bondGuest);
        // (d) both burned.
        assertTrue(hostBurned && guestBurned);
    }

    /// test_F14_1_birth_anchored_deadline (fixtures-index Part B row). The
    /// completing action lands ONE MINUTE before the window closes (23:59):
    /// the resulting showdown-share duties are born there, due
    /// max(hour 24, birth + 6h) = 29:59, not hour 24 (already passed by
    /// the time the duty exists). The frozen-terminal hand must not
    /// resolve early via a premature muck at hour 24. Symmetric muck
    /// (neither side ever posts) is used deliberately -- the deadline
    /// arithmetic being tested does not depend on which side is missing,
    /// and it lets this fixture skip building real card material (the
    /// filler marker's roots are never inspected, since decode is never
    /// reached on the both-missing path).
    function test_F14_1_birth_anchored_deadline() public {
        bytes32 session = keccak256("F14.1");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);

        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);

        vm.warp(openedAt + 23 hours + 59 minutes); // one minute before window close
        ChannelV2.Act memory call = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _fileOneAct(session, call, GUEST_SESSION_PK);
        uint256 completingFiledAt = block.timestamp;
        assertEq(completingFiledAt, openedAt + 23 hours + 59 minutes);

        uint256 dueAt = openedAt + 29 hours + 59 minutes; // max(open+24h, completingFiledAt+6h)

        vm.warp(dueAt - 1);
        vm.expectRevert(bytes("window open"));
        channel.resolve(session);

        vm.warp(dueAt);
        channel.resolve(session);
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(
            uint8(status),
            uint8(ChannelV2.Status.Closed),
            "frozen-terminal hand resolves at the last grace, not at hour-24 consolidation"
        );
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertTrue(hostBurned && guestBurned, "neither side ever posted -- symmetric muck, gated by the birth-anchored deadline");
    }

    /// test_F15_1_burn_survives_final (fixtures-index Part B row).
    /// Equivocate (the eager burn, task 3, fires immediately inside
    /// fileActions -- well before any final or resolve() call); then both
    /// sign a final. Stacks settle per the final's own numbers, but the
    /// already-proven burn is NEVER restored: the burned bond is excluded
    /// from the final's own payout arithmetic (P2's existing
    /// hostBurned/guestBurned-gated formula, unmodified by this phase).
    function test_F15_1_burn_survives_final() public {
        bytes32 session = keccak256("F15.1");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory actA = _mkAct(1, 0, 3, 20, prev0);
        ChannelV2.Act memory actB = _mkAct(1, 0, 3, 999, prev0); // same node, distinct amount
        _fileOneAct(session, actA, HOST_SESSION_PK);
        _fileOneAct(session, actB, HOST_SESSION_PK);
        (,, bool hostBurnedEarly,) = channel.sessionBonds(session);
        assertTrue(hostBurnedEarly, "eager equivocation burn, well before any final");

        ChannelV2.Receipt memory finalR = _mkReceipt(2, 0, 0.1 ether, 0.3 ether, 0.2 ether, 0.2 ether, true);
        (bytes memory fh, bytes memory fg) = _signReceipt(session, finalR, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, finalR, fh, fg);

        channel.resolve(session);
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (, uint256 bondGuest, bool hostBurnedAfter, bool guestBurnedAfter) = channel.sessionBonds(session);
        assertTrue(hostBurnedAfter, "the proven burn is never restored by a later final");
        assertFalse(guestBurnedAfter);
        assertEq(channel.credits(hostWallet), 0.1 ether, "burned bond excluded from the final's own payout");
        assertEq(channel.credits(guestWallet), 0.3 ether + bondGuest);
    }

    /// test_F15_2_symmetric_muck (fixtures-index Part B row). Both chains
    /// auto-filed by both clients (a genuine COMPLETE all-in), then both
    /// machines die before posting a single share: both bonds burn,
    /// settlement is the receipt baseline alone, no pot overlay at all.
    function test_F15_2_symmetric_muck() public {
        bytes32 session = keccak256("F15.2");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);
        _fileOneAct(session, _mkAct(1, 1, 2, 0, _actDigest(session, shove)), GUEST_SESSION_PK);

        vm.warp(block.timestamp + WINDOW + GRACE + 1);
        channel.resolve(session);

        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertTrue(hostBurned && guestBurned, "both sides missing at least one required position -- symmetric muck");
        assertEq(channel.burned(session), bondHost + bondGuest);
        assertEq(channel.credits(hostWallet), 0.2 ether, "settle at the receipt baseline alone, no pot overlay");
        assertEq(channel.credits(guestWallet), 0.2 ether);
    }

    /// test_F16_1_evidence_window_survives_final (fixtures-index Part B
    /// row). A final is filed FIRST -- before the equivocation pair even
    /// completes -- then the second half of the pair lands, still
    /// in-window (burning eagerly right there); resolve() is called last.
    /// Proves resolve() reflects whatever burn state exists AT RESOLUTION
    /// TIME, not at the (earlier) moment the final happened to be filed --
    /// the evidence window for burn proofs survives a final (§16 pin).
    function test_F16_1_evidence_window_survives_final() public {
        bytes32 session = keccak256("F16.1");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory actA = _mkAct(1, 0, 3, 20, prev0);
        _fileOneAct(session, actA, HOST_SESSION_PK);

        ChannelV2.Receipt memory finalR = _mkReceipt(2, 0, 0.1 ether, 0.3 ether, 0.2 ether, 0.2 ether, true);
        (bytes memory fh, bytes memory fg) = _signReceipt(session, finalR, HOST_SESSION_PK, GUEST_SESSION_PK);
        channel.fileReceipt(session, finalR, fh, fg); // final lands FIRST
        (,, bool hostBurnedAtFinalTime,) = channel.sessionBonds(session);
        assertFalse(hostBurnedAtFinalTime, "no equivocation pair on file yet when the final was filed");

        ChannelV2.Act memory actB = _mkAct(1, 0, 3, 999, prev0); // same node, distinct -- completes the pair
        _fileOneAct(session, actB, HOST_SESSION_PK); // burns eagerly, right here, after the final
        (, uint256 bondGuest, bool hostBurnedAfterPair,) = channel.sessionBonds(session);
        assertTrue(hostBurnedAfterPair, "eager burn fires the instant the pair completes, regardless of the final's earlier filing");

        channel.resolve(session);
        (,, bool hostBurnedFinal, bool guestBurnedFinal) = channel.sessionBonds(session);
        assertTrue(hostBurnedFinal);
        assertFalse(guestBurnedFinal);
        assertEq(channel.credits(hostWallet), 0.1 ether, "the final's short-circuit does not launder a burn proven after it was filed");
        assertEq(channel.credits(guestWallet), 0.3 ether + bondGuest);
    }

    /// test_F16_3_lazy_crystallisation (fixtures-index Part B row). The
    /// duty deadline matures with NO transaction touching this session at
    /// all -- not even a spurious postShares/fileActions call -- until,
    /// much later, resolve() is called exactly once. Proof is the filings,
    /// never a computation event: nothing ever computed or recorded the
    /// missed duty ahead of time, yet the single call still burns and pays
    /// correctly.
    function test_F16_3_lazy_crystallisation() public {
        bytes32 session = keccak256("F16.3");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);
        _fileOneAct(session, _mkAct(1, 1, 2, 0, _actDigest(session, shove)), GUEST_SESSION_PK);

        vm.warp(block.timestamp + 100 days); // a huge gap, no intervening transaction of any kind

        channel.resolve(session); // the single, first-ever call touching this session since filing
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertTrue(hostBurned && guestBurned, "burn crystallises and pays correctly inside this single, first-ever call");
        assertEq(channel.burned(session), bondHost + bondGuest);
        assertEq(channel.credits(hostWallet), 0.2 ether);
        assertEq(channel.credits(guestWallet), 0.2 ether);
    }

    /// test_S_dead_man_switch (fixtures-index verified-sound pin, task 11
    /// step 6's fixture). (a) ON TIME: the slow side posts everything in
    /// the exact block at dueAt -- still fully avoids the muck; the 110%
    /// bond is never at risk for a player who makes the deadline. (b) ONE
    /// SECOND LATE (a fresh session, same construction): the counterparty
    /// calls resolve() at the deadline before the slow side's post lands
    /// -- demonstrating the margin genuinely lost by missing it is the
    /// full muck price (whole pot plus bond), not merely a soft cost.
    function test_S_dead_man_switch() public {
        uint8[9] memory cardIndices = [uint8(11), 12, 25, 26, 0, 1, 2, 3, 4];

        bytes32 sessionOnTime = keccak256("S.deadman.ontime");
        ShowdownMaterial memory sm1 = _buildShowdown(cardIndices, 777, 888);
        uint256 completingFiledAt1 = _setupCompleteHandWithMaterial(sessionOnTime, sm1);
        _postAllHost(sessionOnTime, sm1); // host posts immediately, no urgency
        uint256 dueAt1 = _computeDueAt(sessionOnTime, completingFiledAt1);

        vm.warp(dueAt1); // the exact last legal instant
        _postAllGuest(sessionOnTime, sm1); // guest waits until literally the deadline
        channel.resolve(sessionOnTime); // still safe: cards decide, not muck

        (,, ChannelV2.Status statusOnTime,,) = channel.sessionCore(sessionOnTime);
        assertEq(uint8(statusOnTime), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned1, bool guestBurned1) = channel.sessionBonds(sessionOnTime);
        assertFalse(hostBurned1);
        assertFalse(guestBurned1, "posting at the literal last instant still fully avoids the muck -- the bond is never at risk");

        // hostWallet/guestWallet are the SAME shared addresses reused by
        // every session in this test file, and `credits` accumulates per
        // address, not per session -- snapshot here so the second
        // session's assertions below check its own DELTA, not the total.
        uint256 hostCreditsAfterOnTime = channel.credits(hostWallet);
        uint256 guestCreditsAfterOnTime = channel.credits(guestWallet);

        bytes32 sessionLate = keccak256("S.deadman.late");
        ShowdownMaterial memory sm2 = _buildShowdown(cardIndices, 777, 888);
        uint256 completingFiledAt2 = _setupCompleteHandWithMaterial(sessionLate, sm2);
        _postAllHost(sessionLate, sm2);
        uint256 dueAt2 = _computeDueAt(sessionLate, completingFiledAt2);

        vm.warp(dueAt2);
        channel.resolve(sessionLate); // guest never posted in time -- resolved now, against them

        (,, ChannelV2.Status statusLate,,) = channel.sessionCore(sessionLate);
        assertEq(uint8(statusLate), uint8(ChannelV2.Status.Closed));
        (uint256 bondHost2,, bool hostBurned2, bool guestBurned2) = channel.sessionBonds(sessionLate);
        assertFalse(hostBurned2);
        assertTrue(guestBurned2, "missing the deadline by even one block costs the WHOLE muck price -- pot plus bond");
        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        assertEq(channel.credits(hostWallet) - hostCreditsAfterOnTime, 4000 * weiPerChip + bondHost2);
        assertEq(
            channel.credits(guestWallet) - guestCreditsAfterOnTime, 0, "guest's bond burned -- nothing returns, guest also loses the whole pot"
        );
    }

    function _computeDueAt(bytes32 session, uint256 completingFiledAt) internal view returns (uint256) {
        uint256 windowClose = channel.sessionDisputeOpenedAt(session) + WINDOW;
        uint256 birthDeadline = completingFiledAt + GRACE;
        return windowClose > birthDeadline ? windowClose : birthDeadline;
    }

    // =====================================================================
    // Task-9 decode functional coverage (AF-34/AF-35): decodeAt now lives
    // in ChannelV2, not Evidence.sol -- exercised here via a thin harness
    // exposing the internal function directly (mirrors BurnHarness' own
    // pattern below). A genuine card decodes to its real index; a
    // malformed pair (both shares individually valid, combined point not
    // one of the 52 protocol cards) decodes to ok = false -- the fourth
    // row's decodeAt-level trigger, kept distinct from the muck condition
    // (a position nobody posted at all, task 9 step 2's own distinction).
    // =====================================================================

    function _setupDecodeSession(bytes32 session, CardMaterial memory cm, uint256 xHost, uint256 xGuest) internal {
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);

        bytes32[] memory deckLeaves = _fillerLeaves16("t9-filler-deck");
        bytes32[] memory hostLeaves = _fillerLeaves16("t9-filler-host");
        bytes32[] memory guestLeaves = _fillerLeaves16("t9-filler-guest");
        deckLeaves[0] = Evidence.deckLeaf(0, cm.c1Enc, cm.c2Enc);
        hostLeaves[0] = Evidence.shareLeaf(0, cm.hostShareEnc);
        guestLeaves[0] = Evidence.shareLeaf(0, cm.guestShareEnc);

        ChannelV2.Marker memory m = ChannelV2.Marker(
            1,
            _receiptDigest(session, r0),
            _merkleRootN(deckLeaves),
            _merkleRootN(hostLeaves),
            _merkleRootN(guestLeaves),
            _cardPkEnc(xHost),
            _cardPkEnc(xGuest),
            0,
            5,
            10,
            FILLER_STARTING_CHIPS
        );
        _fileMarkerFullQuick(session, m);

        ChannelV2.SharePost[] memory hp = new ChannelV2.SharePost[](1);
        hp[0] = ChannelV2.SharePost({
            pos: 0,
            shareEnc: cm.hostShareEnc,
            c: cm.hostC,
            s: cm.hostS,
            shareProof: _merkleProofN(hostLeaves, 0),
            c1Enc: cm.c1Enc,
            c2Enc: cm.c2Enc,
            deckProof: _merkleProofN(deckLeaves, 0)
        });
        channel.postShares(session, hp);
        ChannelV2.SharePost[] memory gp = new ChannelV2.SharePost[](1);
        gp[0] = ChannelV2.SharePost({
            pos: 0,
            shareEnc: cm.guestShareEnc,
            c: cm.guestC,
            s: cm.guestS,
            shareProof: _merkleProofN(guestLeaves, 0),
            c1Enc: cm.c1Enc,
            c2Enc: cm.c2Enc,
            deckProof: _merkleProofN(deckLeaves, 0)
        });
        channel.postShares(session, gp);
    }

    function test_task9_decodeAt_genuineCard() public {
        ChannelV2 saved = channel;
        DecodeHarness harness = new DecodeHarness(WINDOW, BANK, GRACE);
        channel = harness;

        bytes32 session = keccak256("task9.decode.genuine");
        uint8 cardIndex = 23;
        CardMaterial memory cm = _buildCardMaterial(cardIndex, 1111, 2222, 0);
        _setupDecodeSession(session, cm, 1111, 2222);

        (bool ok, uint8 card) = harness.exposedDecodeAt(session, 1, 0);
        assertTrue(ok, "a genuine, correctly-posted pair decodes cleanly");
        assertEq(card, cardIndex);

        channel = saved;
    }

    function test_task9_decodeAt_malformedPair() public {
        ChannelV2 saved = channel;
        DecodeHarness harness = new DecodeHarness(WINDOW, BANK, GRACE);
        channel = harness;

        bytes32 session = keccak256("task9.decode.malformed");
        Ristretto.Pt memory target = Ristretto.mul(Ristretto.base(), 9999); // not one of the 52 cards
        CardMaterial memory cm = _buildCardMaterialForPoint(target, 3333, 4444, 0);
        _setupDecodeSession(session, cm, 3333, 4444);

        (bool ok,) = harness.exposedDecodeAt(session, 1, 0);
        assertFalse(ok, "both shares individually valid, combined point is not one of the 52 cards -- the fourth row's decodeAt-level trigger");

        channel = saved;
    }

    // =====================================================================
    // P4 tasks 3, 6, 8, 9 — the deferred test-writing AF-39 routes here:
    // readyTime/bank-spend adversarial fixtures (task 3), the street-runout
    // birth-tracking regression (task 6), the bank/termination/duty fixture
    // set (task 8), and the remaining legality/accounting fixtures plus the
    // D12 re-derivation and D15 short-duration timing tests (task 9). See
    // phase-4-disputes-continuation.md and fixtures-index.md's P4 rows for
    // the fixture class each test below re-derives.
    // =====================================================================

    /// Wraps a signed phase2Act call using whatever `channel` currently
    /// points at (the swap-`channel` idiom `DecodeHarness`/`BurnHarness`
    /// already establish above) -- mirrors `_fileOneAct`'s shape for the
    /// live entry point.
    function _filePhase2Act(bytes32 session, ChannelV2.Act memory a, uint256 pk) internal {
        bytes memory sig = _sigRaw(pk, _actDigest(session, a));
        channel.phase2Act(session, a, sig);
    }

    /// Deploys a fresh D15 short-duration instance (task 9 step 4) --
    /// never the default WINDOW/BANK/GRACE, never vm.warp-only coverage of
    /// a path P7's live sweep will actually exercise.
    function _deployShortDuration() internal returns (ChannelV2) {
        return new ChannelV2(SHORT_WINDOW, SHORT_BANK, SHORT_GRACE);
    }

    /// open+join+receipt(0,0)+dispute+marker(REAL roots, from `sm`) against
    /// whatever `channel` currently points at -- the shared "genuine
    /// showdown material, no chain filed yet" setup several P4 fixtures
    /// below need (unlike `_setupDisputedMarkedHand1`'s filler marker,
    /// postShares' triple check genuinely inspects these fields). Mirrors
    /// `_setupCompleteHandWithMaterial`'s first five steps exactly, minus
    /// the shove+call this variant's callers add themselves (or omit,
    /// for fixtures that never need a chain at all).
    function _setupMarkedHand1WithMaterial(ShowdownMaterial memory sm, bytes32 session)
        internal
        returns (bytes32 prev0, bytes32 rDigest)
    {
        _openJoinDefault(session, 1 ether, 1 ether, 0.2 ether, 0.2 ether);
        ChannelV2.Receipt memory r0 =
            _fileReceiptQuick(session, 0, 0, 0.2 ether, 0.2 ether, 0.2 ether, 0.2 ether, false);
        vm.prank(hostWallet);
        channel.openDispute(session);
        ChannelV2.Marker memory m1 = ChannelV2.Marker(
            1,
            _receiptDigest(session, r0),
            sm.deckRoot,
            sm.hostShareRoot,
            sm.guestShareRoot,
            sm.hostCardPk,
            sm.guestCardPk,
            0,
            5,
            10,
            FILLER_STARTING_CHIPS
        );
        _fileMarkerFullQuick(session, m1);
        prev0 = _markerDigest(session, m1);
        rDigest = _receiptDigest(session, r0);
    }

    // ---- Task 3 (AF-39): readyTime/bank-spend adversarial fixtures ----

    /// test_F13_1_no_private_deadlines (fixtures-index P4 row, thirteenth
    /// check finding 1). A genuine action is withheld and filed just
    /// before the window closes (23:55-style) -- it lands in the FROZEN
    /// chain (still in-window), but the phase-2 baseline for the player now
    /// facing a decision must be the fixed appointment H0 =
    /// disputeOpenedAt+window, never the withheld action's own private
    /// filing time. AF-38 reconciliation: this is `_phase2Baseline`'s own
    /// `priorCount == 0` branch (the shipped code's handoff logic lives
    /// there, not inside `_readyTime` -- see `Phase2Harness`'s own header
    /// comment), so this fixture is a white-box read of that function
    /// alongside a `_readyTime` read confirming the two compose correctly.
    function test_F13_1_no_private_deadlines() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("F13.1-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW - 5);
        ChannelV2.Act memory withheld = _mkAct(1, 0, 3, 100, prev0); // host bets 100, filed just before the window closes
        _fileOneAct(session, withheld, HOST_SESSION_PK);
        uint256 withheldFiledAt = block.timestamp;

        uint256 H0 = openedAt + WINDOW;
        assertTrue(withheldFiledAt != H0, "sanity: the withheld action's own filedAt is a distinct instant from H0");
        assertEq(
            h.phase2BaselineExternal(session, 1, 0),
            H0,
            "baseline is the fixed appointment H0, never a private phase-1 filing time"
        );

        (bool started, uint256 rt) = h.readyTimeExternal(session, 1, false, H0, BettingReplay.Street.Preflop);
        assertTrue(started, "no board positions required preflop -- the clock always starts");
        assertEq(rt, H0, "readyTime is exactly the baseline, not the withheld action's own filedAt");

        channel = saved;
    }

    /// test_F13_2_own_postings_never_pause (fixtures-index P4 row,
    /// thirteenth check finding 2). Host's counterparty (guest) posts
    /// every required flop position; host's OWN flop shares stay
    /// deliberately unposted. Host's own clock still starts -- the
    /// `postedAt[...][counterparty]` lookup structurally excludes a
    /// player's own posting, so withholding it can never suppress their
    /// own clock.
    function test_F13_2_own_postings_never_pause() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("F13.2-P4");
        uint8[9] memory cardIndices = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 111, 222);
        _setupMarkedHand1WithMaterial(sm, session);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 baseline = openedAt + WINDOW;

        _postGuest(session, sm, 4); // pos 5
        _postGuest(session, sm, 5); // pos 6
        _postGuest(session, sm, 6); // pos 7
        assertFalse(channel.sharePosted(session, 1, 5, hostWallet), "host's own flop shares stay unposted throughout");

        (bool started, uint256 rt) = h.readyTimeExternal(session, 1, true, baseline, BettingReplay.Street.Flop);
        assertTrue(started, "host's own missing flop posts never pause host's own clock");
        assertEq(rt, baseline, "readyTime wholly unaffected by host's own missing posts");

        channel = saved;
    }

    /// Boundary probe (task 3 step 7, decision 9's actor-favoring
    /// convention), proven end to end through the real `resolve()` path
    /// rather than a white-box arithmetic read: landing exactly on
    /// `H0+bank` (spend would equal the bank exactly) is still accepted
    /// (still Phase2InProgress); one second later is a real, structural
    /// bank-fold.
    function test_bankBoundary_arithmetic() public {
        bytes32 session = keccak256("bankBoundary-P4");
        _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + WINDOW;

        vm.warp(H0 + BANK);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);

        vm.warp(H0 + BANK + 1);
        channel.resolve(session); // must NOT revert -- a real, structural bank-fold
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned, "a fold never burns, bank-fold included");
        assertFalse(guestBurned);
    }

    /// test_handoffBaseline_notH0 (fixtures-index P4 row, fix-round-1
    /// B6/P4-1 -- the gap a hard-coded `baseline = H0` would pass all of
    /// F13.1/F13.2/the boundary probe above unchanged, while silently
    /// bank-folding both seats six hours after H0 regardless of real play
    /// in between). Three alternating candidates, pushed with genuinely
    /// advancing `block.timestamp` between each: assert `_phase2Baseline`
    /// returns the MOST RECENT candidate's own `filedAt` at every one of
    /// the three handoffs, never H0.
    function test_handoffBaseline_notH0() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("handoffBaseline-P4");
        _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + WINDOW;
        assertEq(h.phase2BaselineExternal(session, 1, 0), H0, "priorCount==0 -> H0");

        address hostKey = vm.addr(HOST_SESSION_PK);
        address guestKey = vm.addr(GUEST_SESSION_PK);

        uint256 t0 = H0 + 1000;
        vm.warp(t0);
        h.pushPhase2Cand(session, 1, hostKey, 3, 100, bytes32(0), keccak256("handoff-n0"), uint40(t0));
        assertEq(h.phase2BaselineExternal(session, 1, 1), t0, "priorCount==1 -> T0, not H0");
        assertTrue(t0 != H0);

        uint256 t1 = t0 + 2000;
        vm.warp(t1);
        h.pushPhase2Cand(session, 1, guestKey, 3, 300, bytes32(0), keccak256("handoff-n1"), uint40(t1));
        assertEq(h.phase2BaselineExternal(session, 1, 2), t1, "priorCount==2 -> T1, not H0");
        assertTrue(t1 != H0);

        uint256 t2 = t1 + 1500;
        vm.warp(t2);
        h.pushPhase2Cand(session, 1, hostKey, 3, 700, bytes32(0), keccak256("handoff-n2"), uint40(t2));
        assertEq(h.phase2BaselineExternal(session, 1, 3), t2, "priorCount==3 -> T2, not H0");
        assertTrue(t2 != H0);

        channel = saved;
    }

    /// test_lateCounterpartyPosting_movesReadyTime (fixtures-index P4 row,
    /// fix-round-1 P4-2 -- "pausing" tested in the direction it actually
    /// pauses). Past baseline with no required counterparty posting on
    /// file, the clock is genuinely paused (`started == false`); once the
    /// required posting lands, `readyTime` becomes the posting's own
    /// instant, strictly later than baseline -- `max(baseline, postedAt)`
    /// resolving to the LATER operand, not merely existing in the formula.
    function test_lateCounterpartyPosting_movesReadyTime() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("lateCounterparty-P4");
        uint8[9] memory cardIndices = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 321, 654);
        _setupMarkedHand1WithMaterial(sm, session);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 B = openedAt + WINDOW;
        assertEq(h.phase2BaselineExternal(session, 1, 0), B);

        vm.warp(B + 500);
        (bool started1,) = h.readyTimeExternal(session, 1, true, B, BettingReplay.Street.Flop);
        assertFalse(started1, "clock genuinely paused -- required counterparty (guest) flop posting missing");

        uint256 tPost = B + 700;
        vm.warp(tPost);
        _postGuest(session, sm, 4);
        _postGuest(session, sm, 5);
        _postGuest(session, sm, 6);

        (bool started2, uint256 rt2) = h.readyTimeExternal(session, 1, true, B, BettingReplay.Street.Flop);
        assertTrue(started2);
        assertEq(rt2, tPost, "readyTime starts at the obstacle's own clearing instant, later than baseline");
        assertTrue(tPost > B);

        channel = saved;
    }

    /// test_bankSpent_attributesOwnActionsOnly (fixtures-index P4 row,
    /// fix-round-1 P4-3). A real, legal alternating host/guest/host/guest
    /// preflop raise/reraise/call sequence (bet-100, raise-to-300,
    /// reraise-to-700, call) with distinct real elapsed gaps between every
    /// node (vm.warp) -- staying at Preflop throughout (the round only
    /// closes on the fourth action, so every `_bankSpent`-internal
    /// per-node replay prefix sees Preflop, where no board position is
    /// ever required, keeping this fixture's own street composition out of
    /// the way of the attribution property it targets). Assert each
    /// player's own `_bankSpent` sums ONLY their own two gaps.
    function test_bankSpent_attributesOwnActionsOnly() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("bankSpentAttribution-P4");
        _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + WINDOW;
        address hostKey = vm.addr(HOST_SESSION_PK);
        address guestKey = vm.addr(GUEST_SESSION_PK);

        uint256 t0 = H0 + 111; // host's own gap #1
        vm.warp(t0);
        h.pushPhase2Cand(session, 1, hostKey, 3, 100, bytes32(0), keccak256("attr-n0"), uint40(t0));

        uint256 t1 = t0 + 222; // guest's own gap #1
        vm.warp(t1);
        h.pushPhase2Cand(session, 1, guestKey, 3, 300, bytes32(0), keccak256("attr-n1"), uint40(t1));

        uint256 t2 = t1 + 333; // host's own gap #2
        vm.warp(t2);
        h.pushPhase2Cand(session, 1, hostKey, 3, 700, bytes32(0), keccak256("attr-n2"), uint40(t2));

        uint256 t3 = t2 + 444; // guest's own gap #2
        vm.warp(t3);
        h.pushPhase2Cand(session, 1, guestKey, 2, 0, bytes32(0), keccak256("attr-n3"), uint40(t3));

        uint256 hostSpent = h.bankSpentExternal(session, 1, true);
        uint256 guestSpent = h.bankSpentExternal(session, 1, false);
        assertEq(hostSpent, 111 + 333, "host's own two gaps only");
        assertEq(guestSpent, 222 + 444, "guest's own two gaps only");
        assertTrue(hostSpent != guestSpent, "distinct sums -- a wrong-attribution bug would not coincidentally match");

        channel = saved;
    }

    // ---- Task 6 (AF-39): street-runout birth-tracking regression ----

    /// test_streetRunoutBirths (phase doc task 6 step 2). A frozen
    /// (phase-1) preflop chain closes and cascades to Flop, pending there;
    /// six live phase2Act check/check pairs then close the flop, the turn,
    /// and the river in turn -- birthAt[Turn] and birthAt[River] are
    /// stamped at genuinely distinct, live phase2Act filedAts, distinct
    /// also from showdownBirthAt (the river's own close). P3's own
    /// required-position derivation (`_requiredPositions`, always
    /// hole+flop+turn+river once street==River) needs no new logic to
    /// compose with a live-reached River -- proven behaviorally by posting
    /// every required position for real and confirming resolve() reaches a
    /// genuine cards-decide, no burn.
    function test_streetRunoutBirths() public {
        bytes32 session = keccak256("streetRunoutBirths-P4");
        uint8[9] memory cardIndices = [uint8(41), 42, 43, 44, 45, 46, 47, 48, 49];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 777, 888);
        (bytes32 prev0,) = _setupMarkedHand1WithMaterial(sm, session);

        // Frozen: host calls the blind difference, guest checks its
        // option -- closes preflop, cascades to Flop (pending there).
        ChannelV2.Act memory a0 = _mkAct(1, 0, 2, 0, prev0);
        _fileOneAct(session, a0, HOST_SESSION_PK);
        ChannelV2.Act memory a1 = _mkAct(1, 1, 1, 0, _actDigest(session, a0));
        _fileOneAct(session, a1, GUEST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        (uint256 turnBirth, uint256 riverBirth, uint256 showdownBirth) =
            _streetRunoutLiveActions(session, _actDigest(session, a1));

        assertEq(channel.birthAt(session, 1, uint256(uint8(BettingReplay.Street.Turn))), turnBirth);
        assertEq(channel.birthAt(session, 1, uint256(uint8(BettingReplay.Street.River))), riverBirth);
        assertEq(channel.showdownBirthAt(session, 1), showdownBirth);
        assertTrue(turnBirth != riverBirth && riverBirth != showdownBirth && turnBirth != showdownBirth);

        _postAllHost(session, sm);
        _postAllGuest(session, sm);
        channel.resolve(session); // must NOT revert
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned);
        assertFalse(guestBurned);
    }

    /// Split out of test_streetRunoutBirths purely for legacy (non-IR)
    /// codegen stack depth -- no behavior change. Six live check/check
    /// pairs closing the flop, the turn, and the river in turn.
    function _streetRunoutLiveActions(bytes32 session, bytes32 prevAfterFrozen)
        internal
        returns (uint256 turnBirth, uint256 riverBirth, uint256 showdownBirth)
    {
        bytes32 prevA = prevAfterFrozen;
        ChannelV2.Act memory flopCheckGuest = _mkAct(1, 2, 1, 0, prevA);
        _filePhase2Act(session, flopCheckGuest, GUEST_SESSION_PK);
        prevA = _actDigest(session, flopCheckGuest);

        vm.warp(block.timestamp + 100);
        ChannelV2.Act memory flopCheckHost = _mkAct(1, 3, 1, 0, prevA);
        _filePhase2Act(session, flopCheckHost, HOST_SESSION_PK);
        turnBirth = block.timestamp;
        prevA = _actDigest(session, flopCheckHost);

        vm.warp(block.timestamp + 200);
        ChannelV2.Act memory turnCheckGuest = _mkAct(1, 4, 1, 0, prevA);
        _filePhase2Act(session, turnCheckGuest, GUEST_SESSION_PK);
        prevA = _actDigest(session, turnCheckGuest);

        vm.warp(block.timestamp + 300);
        ChannelV2.Act memory turnCheckHost = _mkAct(1, 5, 1, 0, prevA);
        _filePhase2Act(session, turnCheckHost, HOST_SESSION_PK);
        riverBirth = block.timestamp;
        prevA = _actDigest(session, turnCheckHost);

        vm.warp(block.timestamp + 400);
        ChannelV2.Act memory riverCheckGuest = _mkAct(1, 6, 1, 0, prevA);
        _filePhase2Act(session, riverCheckGuest, GUEST_SESSION_PK);
        prevA = _actDigest(session, riverCheckGuest);

        vm.warp(block.timestamp + 500);
        ChannelV2.Act memory riverCheckHost = _mkAct(1, 7, 1, 0, prevA);
        _filePhase2Act(session, riverCheckHost, HOST_SESSION_PK);
        showdownBirth = block.timestamp;
    }

    // ---- Task 8 (AF-39): bank, termination, duties, chain-link collision ----

    /// test_F10_5_crash_at_showdown_survivable (fixtures-index P4 row). A
    /// frozen preflop all-in shove is pending the guest's call when the
    /// window closes; the call is filed LIVE via phase2Act -- the all-in
    /// runout cascade closes every remaining street in that one call,
    /// birthing showdownBirthAt there. Nothing is posted immediately
    /// ("crash"); both sides post everything well inside birth+grace --
    /// resolve() reaches cards-decide, no burn.
    function test_F10_5_crash_at_showdown_survivable() public {
        bytes32 session = keccak256("F10.5-P4");
        uint8[9] memory cardIndices = [uint8(1), 2, 3, 4, 5, 6, 7, 8, 9];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 1111, 2222);
        (bytes32 prev0,) = _setupMarkedHand1WithMaterial(sm, session);

        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        ChannelV2.Act memory call1 = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _filePhase2Act(session, call1, GUEST_SESSION_PK);
        uint256 showdownBirth = channel.showdownBirthAt(session, 1);
        assertEq(showdownBirth, block.timestamp, "showdownBirthAt stamped at the completing live call's own filedAt");

        // "Crash": time passes with nothing posted, well inside grace.
        vm.warp(showdownBirth + GRACE - 60);
        _postAllHost(session, sm);
        _postAllGuest(session, sm);

        channel.resolve(session); // must NOT revert -- duty met inside grace
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned, "duty met inside grace -- no burn");
        assertFalse(guestBurned);
    }

    /// test_F12_4_postings_are_window_duties (fixtures-index P4 row).
    /// Built against the D15 short-duration instance specifically so
    /// SHORT_BANK != SHORT_GRACE gives a real gap to post inside: the
    /// completing player's own shares are posted AFTER a delay that
    /// exceeds a bank-shaped deadline (SHORT_BANK) but still well inside
    /// the duty's own SHORT_GRACE window -- decision 7's structural
    /// separation means this elapsed time is wholly irrelevant to a
    /// posting duty. The duty is met, no burn.
    function test_F12_4_postings_are_window_duties() public {
        ChannelV2 saved = channel;
        ChannelV2 sd = _deployShortDuration();
        channel = sd;

        bytes32 session = keccak256("F12.4-P4");
        uint8[9] memory cardIndices = [uint8(11), 12, 13, 14, 15, 16, 17, 18, 19];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 3333, 4444);
        (bytes32 prev0,) = _setupMarkedHand1WithMaterial(sm, session);

        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + SHORT_WINDOW);

        ChannelV2.Act memory call1 = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _filePhase2Act(session, call1, GUEST_SESSION_PK);
        uint256 showdownBirth = channel.showdownBirthAt(session, 1);

        // Past a bank-shaped deadline (SHORT_BANK=30s) but still inside
        // this duty's own SHORT_GRACE=45s -- a posting is never gated by
        // the bank clock at all.
        vm.warp(showdownBirth + SHORT_BANK + 5);
        _postAllHost(session, sm);
        _postAllGuest(session, sm);

        channel.resolve(session); // must NOT revert -- duty met, bank irrelevant
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned);
        assertFalse(guestBurned);

        channel = saved;
    }

    /// test_F12_5_one_muck_price (fixtures-index P4 row). A phase-2-
    /// resolved one-sided muck (showdown reached via a live phase2Act
    /// call) and a phase-1-resolved one-sided muck (P3's own
    /// test_F12_2-style construction, reused/re-run here), side by side,
    /// same deposits/max -- assert the burned amount is bondHost
    /// identically in both. P4 adds no second muck price.
    function test_F12_5_one_muck_price() public {
        (uint256 bondHostA, uint256 burnedA) = _f12_5_phase2Muck();
        (uint256 bondHostB, uint256 burnedB) = _f12_5_phase1Muck();

        assertEq(bondHostA, bondHostB, "same deposits/max -> same bond -> same burn amount");
        assertEq(burnedA, burnedB, "one muck price, phase-1 or phase-2 alike");
    }

    /// Split out of test_F12_5_one_muck_price purely for legacy (non-IR)
    /// codegen stack depth -- no behavior change.
    function _f12_5_phase2Muck() internal returns (uint256 bondHostA, uint256 burnedA) {
        bytes32 sessionA = keccak256("F12.5-phase2-P4");
        uint8[9] memory idxA = [uint8(11), 12, 13, 14, 15, 16, 17, 18, 19];
        ShowdownMaterial memory smA = _buildShowdown(idxA, 5551, 6661);
        (bytes32 prev0A,) = _setupMarkedHand1WithMaterial(smA, sessionA);
        uint256 openedAtA = channel.sessionDisputeOpenedAt(sessionA);
        ChannelV2.Act memory shoveA = _mkAct(1, 0, 3, 2000, prev0A);
        _fileOneAct(sessionA, shoveA, HOST_SESSION_PK);
        vm.warp(openedAtA + WINDOW);
        ChannelV2.Act memory callA = _mkAct(1, 1, 2, 0, _actDigest(sessionA, shoveA));
        _filePhase2Act(sessionA, callA, GUEST_SESSION_PK);
        uint256 birthA = channel.showdownBirthAt(sessionA, 1);
        _postAllGuest(sessionA, smA); // guest posts everything, host posts nothing
        vm.warp(birthA + GRACE + 1);
        channel.resolve(sessionA);
        bool hostBurnedA;
        (bondHostA,, hostBurnedA,) = channel.sessionBonds(sessionA);
        assertTrue(hostBurnedA, "host never posted -- one-sided muck, host burns");
        burnedA = channel.burned(sessionA);
        assertEq(burnedA, bondHostA);
    }

    /// Split out of test_F12_5_one_muck_price purely for legacy (non-IR)
    /// codegen stack depth -- no behavior change.
    function _f12_5_phase1Muck() internal returns (uint256 bondHostB, uint256 burnedB) {
        bytes32 sessionB = keccak256("F12.5-phase1-P4");
        uint8[9] memory idxB = [uint8(21), 22, 23, 24, 25, 26, 27, 28, 29];
        ShowdownMaterial memory smB = _buildShowdown(idxB, 7771, 8881);
        uint256 completingFiledAtB = _setupCompleteHandWithMaterial(sessionB, smB);
        _postAllGuest(sessionB, smB);
        vm.warp(completingFiledAtB + WINDOW + GRACE + 1);
        channel.resolve(sessionB);
        bool hostBurnedB;
        (bondHostB,, hostBurnedB,) = channel.sessionBonds(sessionB);
        assertTrue(hostBurnedB);
        burnedB = channel.burned(sessionB);
        assertEq(burnedB, bondHostB);
    }

    /// test_F13_7_banks_sequential (fixtures-index P4 row). Host's bank
    /// empties first (structural bank-fold, host never acts preflop);
    /// assert guest's own `_bankSpent` at that moment is strictly less
    /// than `bank` -- the both-banks-empty state is structurally
    /// unreachable because only one clock is ever running at a time (the
    /// turn check plus readyTime's sole-obstacle design together enforce
    /// this).
    function test_F13_7_banks_sequential() public {
        ChannelV2 saved = channel;
        Phase2Harness h = new Phase2Harness(WINDOW, BANK, GRACE);
        channel = h;

        bytes32 session = keccak256("F13.7-P4");
        _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + WINDOW;

        vm.warp(H0 + BANK + 1);
        uint256 guestSpentAtFold = h.bankSpentExternal(session, 1, false);
        assertLt(guestSpentAtFold, BANK, "the non-obstacle seat's own bank was never touched -- only one clock ever runs");

        channel.resolve(session); // must NOT revert -- settles via the fold row
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned, "bank-fold is a fold -- never a burn");
        assertFalse(guestBurned);

        channel = saved;
    }

    /// test_S_absentee_ceiling (verified-sound pin, fixtures-index P4
    /// row). Host (present) raises preflop to 100; guest (to-act,
    /// absentee) never responds and structurally bank-folds. Assert the
    /// pot at resolution equals exactly what guest legitimately put in
    /// (the BB, 10 chips) -- host's own uncalled excess (the raise beyond
    /// guest's BB) returns to host, never growing the pot further against
    /// a bank-folding opponent.
    function test_S_absentee_ceiling() public {
        bytes32 session = keccak256("S.absentee_ceiling-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        ChannelV2.Act memory raise = _mkAct(1, 0, 3, 100, prev0); // host raises to 100
        _filePhase2Act(session, raise, HOST_SESSION_PK);

        vm.warp(block.timestamp + BANK + 1); // guest (to-act) never responds
        channel.resolve(session); // must NOT revert -- settles via the fold row
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));

        (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned);
        assertFalse(guestBurned, "bank-fold is a fold, never misconduct");

        // investedHost=100 (5 sb + 95 raise), investedGuest=10 (bb only);
        // excess=90 returns to host uncalled; contested=20-... worked:
        // excess=|100-10|=90 -> host; contested=(100+10)-90=20 -> host
        // (winner) -> hostChips=90+20=110; stackHost=2000-100=1900;
        // hostStackWei=(1900+110)=2010 chips. guestChips=0;
        // stackGuest=2000-10=1990; guestStackWei=1990 chips. Host's NET
        // gain is +10 chips -- exactly guest's own BB, never the 100-chip
        // raise size.
        uint256 weiPerChip = 0.2 ether / FILLER_STARTING_CHIPS;
        assertEq(channel.credits(hostWallet), 2010 * weiPerChip + bondHost);
        assertEq(channel.credits(guestWallet), 1990 * weiPerChip + bondGuest);
    }

    /// test_S_desert_then_return (verified-sound pin, fixtures-index P4
    /// row). Guest promptly bets the flop live and promptly posts their
    /// own required flop shares (a duty they owed, met in full) -- then,
    /// at a LATER to-act moment (the turn), guest genuinely deserts and
    /// bank-folds. Assert the bond returns in full: the fold itself never
    /// calls `_burnBond`, regardless of the earlier, separately-owed and
    /// already-met posting duty.
    function test_S_desert_then_return() public {
        bytes32 session = keccak256("S.desert_then_return-P4");
        uint8[9] memory cardIndices = [uint8(31), 32, 33, 34, 35, 36, 37, 38, 39];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 9991, 8882);
        (bytes32 prev0,) = _setupMarkedHand1WithMaterial(sm, session);

        ChannelV2.Act memory a0 = _mkAct(1, 0, 2, 0, prev0); // host calls
        _fileOneAct(session, a0, HOST_SESSION_PK);
        ChannelV2.Act memory a1 = _mkAct(1, 1, 1, 0, _actDigest(session, a0)); // guest checks -- closes preflop
        _fileOneAct(session, a1, GUEST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        _desertThenReturnLivePlay(session, sm, _actDigest(session, a1));

        channel.resolve(session); // must NOT revert -- settles via the fold row
        _desertThenReturnAssertions(session);
    }

    /// Split out of test_S_desert_then_return purely for legacy (non-IR)
    /// codegen stack depth -- no behavior change.
    function _desertThenReturnLivePlay(bytes32 session, ShowdownMaterial memory sm, bytes32 prevAfterFrozen) internal {
        ChannelV2.Act memory flopBet = _mkAct(1, 2, 3, 100, prevAfterFrozen); // guest bets the flop -- prompt, not a desertion
        _filePhase2Act(session, flopBet, GUEST_SESSION_PK);
        bytes32 prevA = _actDigest(session, flopBet);

        // Guest promptly posts their own owed flop shares -- a duty met,
        // wholly independent of the bank clock (decision 7): this posting
        // is the counterparty-posting for HOST's own clock, never guest's.
        _postGuest(session, sm, 4);
        _postGuest(session, sm, 5);
        _postGuest(session, sm, 6);
        assertTrue(channel.sharePosted(session, 1, 5, guestWallet));
        assertTrue(channel.sharePosted(session, 1, 6, guestWallet));
        assertTrue(channel.sharePosted(session, 1, 7, guestWallet));

        // Host posts their own flop shares too -- the counterparty posting
        // that actually lets GUEST's own clock run, once guest is to-act
        // again on the turn.
        _postHost(session, sm, 4);
        _postHost(session, sm, 5);
        _postHost(session, sm, 6);

        ChannelV2.Act memory flopCall = _mkAct(1, 3, 2, 0, prevA); // host calls -- closes the flop, cascades to Turn
        _filePhase2Act(session, flopCall, HOST_SESSION_PK);
        uint256 turnStart = block.timestamp;

        // Host also posts the turn position ahead of guest's decision --
        // completes guest's own counterparty-posting requirement for Turn
        // ([5,6,7,9]), so guest's clock genuinely runs from turnStart.
        _postHost(session, sm, 7);

        // Guest (acts first on the turn too) now genuinely deserts.
        vm.warp(turnStart + BANK + 1);
    }

    /// Split out of test_S_desert_then_return purely for legacy (non-IR)
    /// codegen stack depth -- no behavior change.
    function _desertThenReturnAssertions(bytes32 session) internal {
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));

        (, uint256 bondGuest, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(guestBurned, "the fold itself never calls _burnBond -- folding is never misconduct");
        assertFalse(hostBurned);
        assertEq(channel.burned(session), 0);
        assertTrue(bondGuest > 0, "guest's bond returns in full");
    }

    /// test_S_blind_action (verified-sound pin, fixtures-index P4 row). A
    /// to-act player (guest, first to act on the flop) calls phase2Act
    /// with a legal action while the required counterparty (host) board
    /// posting is not on file at all -- assert the call succeeds. Legality
    /// never depends on a card.
    function test_S_blind_action() public {
        bytes32 session = keccak256("S.blind_action-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory a0 = _mkAct(1, 0, 2, 0, prev0);
        _fileOneAct(session, a0, HOST_SESSION_PK);
        ChannelV2.Act memory a1 = _mkAct(1, 1, 1, 0, _actDigest(session, a0));
        _fileOneAct(session, a1, GUEST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        assertFalse(channel.sharePosted(session, 1, 5, hostWallet), "no required counterparty posting on file at all");
        assertFalse(channel.sharePosted(session, 1, 6, hostWallet));
        assertFalse(channel.sharePosted(session, 1, 7, hostWallet));

        ChannelV2.Act memory flopCheck = _mkAct(1, 2, 1, 0, _actDigest(session, a1));
        _filePhase2Act(session, flopCheck, GUEST_SESSION_PK); // must NOT revert -- acting blind is always legal
    }

    /// test_phase2Act_secondCallSameSeq_revertsBadChainLink (task 1 step
    /// 1's no-equivocation-collision claim, tested behaviorally). A second
    /// phase2Act call still targeting an already-accepted seq reverts --
    /// there is no dual-slot storage for it to land in.
    function test_phase2Act_secondCallSameSeq_revertsBadChainLink() public {
        bytes32 session = keccak256("phase2Act.collision-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        ChannelV2.Act memory first = _mkAct(1, 0, 2, 0, prev0); // host calls -- advances the turn to guest
        _filePhase2Act(session, first, HOST_SESSION_PK);

        // Guest IS genuinely to-act now (the turn check alone would pass),
        // but still targets seq 0 -- already accepted, no slot left to
        // collide with -- so this is the chain-link check's own rejection,
        // not a turn-order one.
        ChannelV2.Act memory second = _mkAct(1, 0, 1, 0, prev0);
        bytes memory sig = _sigRaw(GUEST_SESSION_PK, _actDigest(session, second));
        vm.expectRevert("bad chain link");
        channel.phase2Act(session, second, sig);
    }

    /// test_phase2Act_handoffBaseline_endToEnd (integration companion to
    /// test_handoffBaseline_notH0, driven through the real entry point).
    /// Three real, alternating phase2Act calls with real elapsed
    /// vm.warp-advanced time between each; a fourth call landing exactly
    /// at the boundary computed from T2 (the third action's own filedAt,
    /// not H0) succeeds -- a hard-coded `baseline = H0` bug would already
    /// have bank-folded guest well before this boundary (H0 is far earlier
    /// than T2), so this discriminates the correct handoff wiring.
    function test_phase2Act_handoffBaseline_endToEnd() public {
        bytes32 session = keccak256("phase2Act.handoffE2E-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + WINDOW;

        (uint256 t0, uint256 t1, uint256 t2, bytes32 prevN2) = _handoffE2EThreeActions(session, prev0, H0);

        // Guest is now to-act, facing host's reraise. Guest's baseline is
        // T2 (host's own last action's filedAt) per decision 8's handoff
        // rule, not H0. Guest's only prior spend is a single gap: t1 - t0
        // (baseline at guest's own first node was T0).
        uint256 guestSpentSoFar = t1 - t0;
        uint256 remaining = BANK - guestSpentSoFar;

        vm.warp(t2 + remaining); // exactly the T2-derived boundary
        ChannelV2.Act memory n3 = _mkAct(1, 3, 2, 0, prevN2); // guest calls
        _filePhase2Act(session, n3, GUEST_SESSION_PK); // must NOT revert -- a H0-baseline bug would already have folded here
    }

    /// Split out of test_phase2Act_handoffBaseline_endToEnd purely for
    /// legacy (non-IR) codegen stack depth -- no behavior change.
    function _handoffE2EThreeActions(bytes32 session, bytes32 prev0, uint256 H0)
        internal
        returns (uint256 t0, uint256 t1, uint256 t2, bytes32 prevN2)
    {
        t0 = H0 + 1000;
        vm.warp(t0);
        ChannelV2.Act memory n0 = _mkAct(1, 0, 3, 100, prev0); // host bets to 100
        _filePhase2Act(session, n0, HOST_SESSION_PK);

        t1 = t0 + 2000;
        vm.warp(t1);
        ChannelV2.Act memory n1 = _mkAct(1, 1, 3, 300, _actDigest(session, n0)); // guest raises to 300
        _filePhase2Act(session, n1, GUEST_SESSION_PK);

        t2 = t1 + 1500;
        vm.warp(t2);
        ChannelV2.Act memory n2 = _mkAct(1, 2, 3, 700, _actDigest(session, n1)); // host reraises to 700
        _filePhase2Act(session, n2, HOST_SESSION_PK);
        prevN2 = _actDigest(session, n2);
    }

    // ---- Task 9 (AF-39): remaining legality/accounting fixtures ----

    /// test_F11_2_no_cancel_escape (fixtures-index P4 row). No cancel-
    /// shaped entry point exists anywhere in the contract (confirmed by
    /// `grep -n "external" contracts/src/ChannelV2.sol` at dispatch time --
    /// no function named cancel/void/abort/withdraw-dispute exists; the
    /// only externally callable surfaces that ever mutate a marked hand's
    /// outcome are `phase2Act`'s four-action alphabet, `resolve()`'s own
    /// bank-fold discovery, and `postShares`). Behaviorally: waiting with
    /// neither a phase2Act call nor the bank emptying leaves the hand
    /// genuinely pending forever (Phase2InProgress, never settled around);
    /// the facing player's only route past the decision is exactly the
    /// same fold/call/bet the wire offered.
    function test_F11_2_no_cancel_escape() public {
        bytes32 session = keccak256("F11.2-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);

        ChannelV2.Act memory raise = _mkAct(1, 0, 3, 100, prev0); // host raises -- guest faces it mid-hand
        _fileOneAct(session, raise, HOST_SESSION_PK);

        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);

        ChannelV2.Act memory foldAct = _mkAct(1, 1, 0, 0, _actDigest(session, raise));
        _filePhase2Act(session, foldAct, GUEST_SESSION_PK); // the wire's own fold option, live -- no cancellation exists
        channel.resolve(session); // must NOT revert now
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
    }

    /// test_S_continuation_accounting (verified-sound pin, fixtures-index
    /// P4 row). A phase-2 bet at exactly `hi` (the receipt-baseline-
    /// derived maxRaiseTo, 2000 chips = FILLER_STARTING_CHIPS) is legal;
    /// one chip above `hi` reverts "illegal action" -- the receipt
    /// baseline caps a phase-2 bet exactly as it caps a phase-1 one. After
    /// resolve() settles (a symmetric muck -- nobody posts), assert P2's
    /// deposits invariant still holds exactly.
    function test_S_continuation_accounting() public {
        bytes32 session = keccak256("S.continuation_accounting-P4");
        bytes32 prev0 = _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        vm.warp(openedAt + WINDOW);

        ChannelV2.Act memory tooMuch = _mkAct(1, 0, 3, 2001, prev0); // 1 chip above hi
        bytes memory sigTooMuch = _sigRaw(HOST_SESSION_PK, _actDigest(session, tooMuch));
        vm.expectRevert("illegal action");
        channel.phase2Act(session, tooMuch, sigTooMuch);

        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0); // exactly hi -- legal
        _filePhase2Act(session, shove, HOST_SESSION_PK);
        ChannelV2.Act memory call1 = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _filePhase2Act(session, call1, GUEST_SESSION_PK); // all-in call, runs the cascade to COMPLETE

        uint256 showdownBirth = channel.showdownBirthAt(session, 1);
        vm.warp(showdownBirth + GRACE + 1); // nobody posts -- symmetric muck
        channel.resolve(session);
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));

        _assertContinuationDepositsInvariant(session);
    }

    /// Split out of test_S_continuation_accounting purely for legacy
    /// (non-IR) codegen stack depth -- no behavior change.
    function _assertContinuationDepositsInvariant(bytes32 session) internal {
        (uint256 depositedHost, uint256 depositedGuest) = channel.sessionDeposits(session);
        (uint256 bondHost, uint256 bondGuest,,) = channel.sessionBonds(session);
        uint256 left = depositedHost + depositedGuest + bondHost + bondGuest;
        uint256 right = channel.paidOut(session) + channel.burned(session);
        assertEq(left, right, "P2's deposits invariant holds through a phase-2-derived resolution");
    }

    /// D15 short-duration timing (task 9 step 4). The completing action
    /// lands ONE SECOND before the (short) window closes -- the scaled
    /// analog of the fourteenth check's 23:55-style worked case: the
    /// resulting duty is born there, due birth+grace, strictly past the
    /// window's own close, at THIS instance's own short-duration scale.
    function test_shortDuration_birthAnchoredBoundary() public {
        ChannelV2 saved = channel;
        ChannelV2 sd = _deployShortDuration();
        channel = sd;

        bytes32 session = keccak256("shortDuration-birth-P4");
        uint8[9] memory cardIndices = [uint8(2), 3, 4, 5, 6, 7, 8, 9, 10];
        ShowdownMaterial memory sm = _buildShowdown(cardIndices, 12321, 45654);
        (bytes32 prev0,) = _setupMarkedHand1WithMaterial(sm, session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);

        vm.warp(openedAt + SHORT_WINDOW - 1);
        ChannelV2.Act memory shove = _mkAct(1, 0, 3, 2000, prev0);
        _fileOneAct(session, shove, HOST_SESSION_PK);
        ChannelV2.Act memory call1 = _mkAct(1, 1, 2, 0, _actDigest(session, shove));
        _fileOneAct(session, call1, GUEST_SESSION_PK);
        uint256 completingFiledAt = block.timestamp;
        assertEq(completingFiledAt, openedAt + SHORT_WINDOW - 1);

        uint256 dueAtExpected = completingFiledAt + SHORT_GRACE;
        assertTrue(dueAtExpected > openedAt + SHORT_WINDOW, "birth-anchored deadline sits past the window's own close");

        vm.warp(openedAt + SHORT_WINDOW);
        vm.expectRevert("window open");
        channel.resolve(session); // window just closed, but the duty isn't due yet -- must not muck early

        vm.warp(dueAtExpected);
        channel.resolve(session);
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertTrue(hostBurned && guestBurned, "the scaled birth-anchor formula generalizes at this short duration too");

        channel = saved;
    }

    /// D15 short-duration timing (task 9 step 4; P7's own note that a
    /// bank-fold ending needs a real, expired short `bank` duration to be
    /// sweep-exercisable within a human calendar session). Landing exactly
    /// on `H0+SHORT_BANK` is still accepted; one tick later is a real
    /// bank-fold, reached in ~131 simulated seconds at this instance's own
    /// scale rather than ~30 hours at the production one.
    function test_shortDuration_bankFold_reachable() public {
        ChannelV2 saved = channel;
        ChannelV2 sd = _deployShortDuration();
        channel = sd;

        bytes32 session = keccak256("shortDuration-bankfold-P4");
        _setupDisputedMarkedHand1(session);
        uint256 openedAt = channel.sessionDisputeOpenedAt(session);
        uint256 H0 = openedAt + SHORT_WINDOW;

        vm.warp(H0 + SHORT_BANK);
        vm.expectRevert(ChannelV2.Phase2InProgress.selector);
        channel.resolve(session);

        vm.warp(H0 + SHORT_BANK + 1);
        channel.resolve(session);
        (,, ChannelV2.Status status,,) = channel.sessionCore(session);
        assertEq(uint8(status), uint8(ChannelV2.Status.Closed));
        (,, bool hostBurned, bool guestBurned) = channel.sessionBonds(session);
        assertFalse(hostBurned);
        assertFalse(guestBurned);

        channel = saved;
    }
}

/// Test-only harness (decision 8, task 9 step 7): subclasses ChannelV2
/// purely to expose the internal, idempotent _burnBond primitive for
/// direct, repeated calls — not part of src/, never deployed for real use.
contract BurnHarness is ChannelV2 {
    constructor(uint256 _window, uint256 _bank, uint256 _grace) ChannelV2(_window, _bank, _grace) {}

    function exposedBurnBond(bytes32 session, bool isHost) external {
        _burnBond(session, isHost);
    }
}

/// Test-only harness (task 13, AF-34/AF-35): subclasses ChannelV2 purely to
/// expose the internal decodeAt directly for the task-9 functional coverage
/// this dispatch owes (decodeAt lives in ChannelV2, not Evidence.sol, per
/// AF-34) -- not part of src/, never deployed for real use.
contract DecodeHarness is ChannelV2 {
    constructor(uint256 _window, uint256 _bank, uint256 _grace) ChannelV2(_window, _bank, _grace) {}

    function exposedDecodeAt(bytes32 session, uint64 hand, uint8 pos) external view returns (bool ok, uint8 card) {
        return decodeAt(session, hand, pos);
    }
}

/// Test-only harness (P4 task 3 step 4, AF-39): subclasses ChannelV2
/// purely to expose `_phase2Baseline`/`_readyTime`/`_bankSpent` directly
/// for the readyTime/bank-spend adversarial fixtures, and to seed
/// `phase2ActionsAt` with an arbitrary, caller-chosen history via
/// `pushPhase2Cand` (writing straight to storage, bypassing `phase2Act`'s
/// own turn/chain/bank checks -- exactly the "construct an arbitrary
/// phase-2 action history" allowance the phase doc's own task 3 step 4
/// describes) -- not part of src/, never deployed for real use.
///
/// AF-38 reconciliation: the shipped `_readyTime` signature is
/// `(session, hand, forHost, baseline, street)` -- baseline and street are
/// caller-supplied parameters, not re-derived internally from
/// `phase2ActionsAt`/`finalState` (the phase-4 plan doc's own drafted
/// signature, inconsistent between its task 3 and task 5 citations, per
/// AF-38's note). The "H0-or-last-handoff" logic the plan doc describes as
/// part of `_readyTime` itself actually lives in the separate
/// `_phase2Baseline` helper in the shipped code -- this harness exposes
/// both, and the fixtures below test each where it actually lives, not
/// where the doc's superseded draft placed it.
contract Phase2Harness is ChannelV2 {
    constructor(uint256 _window, uint256 _bank, uint256 _grace) ChannelV2(_window, _bank, _grace) {}

    function phase2BaselineExternal(bytes32 session, uint64 hand, uint256 priorCount) external view returns (uint256) {
        return _phase2Baseline(session, hand, priorCount);
    }

    function readyTimeExternal(bytes32 session, uint64 hand, bool forHost, uint256 baseline, BettingReplay.Street street)
        external
        view
        returns (bool started, uint256 readyTime)
    {
        return _readyTime(session, hand, forHost, baseline, street);
    }

    function bankSpentExternal(bytes32 session, uint64 hand, bool forHost) external view returns (uint256) {
        return _bankSpent(session, hand, forHost);
    }

    function pushPhase2Cand(
        bytes32 session,
        uint64 hand,
        address signer,
        uint8 action,
        uint256 amount,
        bytes32 prev,
        bytes32 actionHash,
        uint40 filedAt
    ) external {
        phase2ActionsAt[session][hand].push(
            Phase2Cand({signer: signer, action: action, amount: amount, prev: prev, actionHash: actionHash, filedAt: filedAt})
        );
    }
}
