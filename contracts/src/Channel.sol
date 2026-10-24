// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// Escrows a heads-up sit-and-go buy-in and settles it either cooperatively
/// (both players sign a winner) or via a liveness-based dispute path when one
/// side stops responding. See docs/superpowers/specs/vault-handover.md for
/// the full design rationale — this contract implements V1 only.
///
/// Design decisions not spelled out verbatim in the spec, made here and
/// worth flagging to whoever reads this next:
///  - The anti-grief bond is fixed at BOND_BPS of the buy-in, paid as
///    msg.value on claimByDefault. The spec says "posting a bond" without a
///    number; 10% was chosen as large enough to deter a false claim without
///    being a second buy-in.
///  - cancelOpen() exists so a host is not permanently stuck if the invited
///    opponent never joins. This does not touch the forfeit rule — no game
///    has started, neither side has deposited both stakes, nothing is being
///    conceded. It closes a fund-lock hole, not a scope addition.
contract Channel {
    enum Status {
        None,
        AwaitingGuest,
        Active,
        ClaimPending,
        Refuted,
        Closed
    }

    struct Session {
        address host;
        address guest;
        uint256 buyIn;
        uint256 window;
        Status status;
        address claimant;
        uint256 bond;
        uint256 deadline;
    }

    uint256 public constant BOND_BPS = 1000; // 10% of buyIn
    uint256 private constant SECP256K1N_HALF =
        0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0;

    uint256 public immutable defaultWindow;
    mapping(bytes32 => Session) public sessions;

    event Opened(bytes32 indexed sessionId, address host, address guest, uint256 buyIn);
    event Joined(bytes32 indexed sessionId);
    event Cancelled(bytes32 indexed sessionId);
    event ClosedCooperative(bytes32 indexed sessionId, address winner);
    event ClaimedByDefault(bytes32 indexed sessionId, address claimant, uint256 deadline);
    event Refuted(bytes32 indexed sessionId, address refuter, uint256 newDeadline);
    event Resolved(bytes32 indexed sessionId, address winner);

    constructor(uint256 _defaultWindow) {
        require(_defaultWindow > 0, "window required");
        defaultWindow = _defaultWindow;
    }

    function open(bytes32 sessionId, address opponent) external payable {
        Session storage s = sessions[sessionId];
        require(s.status == Status.None, "session exists");
        require(opponent != address(0) && opponent != msg.sender, "bad opponent");
        require(msg.value > 0, "buyIn required");

        s.host = msg.sender;
        s.guest = opponent;
        s.buyIn = msg.value;
        s.window = defaultWindow;
        s.status = Status.AwaitingGuest;
        emit Opened(sessionId, msg.sender, opponent, msg.value);
    }

    function join(bytes32 sessionId) external payable {
        Session storage s = sessions[sessionId];
        require(s.status == Status.AwaitingGuest, "not awaiting guest");
        require(msg.sender == s.guest, "not invited");
        require(msg.value == s.buyIn, "buyIn mismatch");

        s.status = Status.Active;
        emit Joined(sessionId);
    }

    function cancelOpen(bytes32 sessionId) external {
        Session storage s = sessions[sessionId];
        require(s.status == Status.AwaitingGuest, "not cancellable");
        require(msg.sender == s.host, "not host");

        uint256 refund = s.buyIn;
        s.status = Status.Closed;
        emit Cancelled(sessionId);
        _pay(s.host, refund);
    }

    function closeCooperative(bytes32 sessionId, address winner, bytes calldata sigHost, bytes calldata sigGuest)
        external
    {
        Session storage s = sessions[sessionId];
        require(
            s.status == Status.Active || s.status == Status.ClaimPending || s.status == Status.Refuted,
            "not closeable"
        );
        require(winner == s.host || winner == s.guest, "unknown winner");

        bytes32 msgHash = keccak256(abi.encode(address(this), block.chainid, sessionId, winner));
        require(_recover(msgHash, sigHost) == s.host, "bad host sig");
        require(_recover(msgHash, sigGuest) == s.guest, "bad guest sig");

        uint256 pot = s.buyIn * 2;
        uint256 refundBond = s.bond;
        address refundTo = s.claimant;
        s.status = Status.Closed;
        s.bond = 0;
        emit ClosedCooperative(sessionId, winner);

        _pay(winner, pot);
        if (refundBond > 0) _pay(refundTo, refundBond);
    }

    function claimByDefault(bytes32 sessionId) external payable {
        Session storage s = sessions[sessionId];
        require(s.status == Status.Active, "not active");
        require(msg.sender == s.host || msg.sender == s.guest, "not a player");
        require(msg.value == (s.buyIn * BOND_BPS) / 10000, "wrong bond");

        s.claimant = msg.sender;
        s.bond = msg.value;
        s.deadline = block.timestamp + s.window;
        s.status = Status.ClaimPending;
        emit ClaimedByDefault(sessionId, msg.sender, s.deadline);
    }

    function iAmHere(bytes32 sessionId) external {
        Session storage s = sessions[sessionId];
        require(s.status == Status.ClaimPending, "no claim pending");
        require(block.timestamp < s.deadline, "window closed");
        address other = s.claimant == s.host ? s.guest : s.host;
        require(msg.sender == other, "not the claimed-against party");

        uint256 bond = s.bond;
        s.bond = 0;
        s.status = Status.Refuted;
        s.deadline = block.timestamp + s.window;
        emit Refuted(sessionId, msg.sender, s.deadline);

        _pay(msg.sender, bond);
    }

    function resolve(bytes32 sessionId) external {
        Session storage s = sessions[sessionId];
        address winner;
        uint256 payout;

        if (s.status == Status.ClaimPending) {
            require(block.timestamp >= s.deadline, "window open");
            winner = s.claimant;
            payout = s.buyIn * 2 + s.bond;
            s.bond = 0;
        } else if (s.status == Status.Refuted) {
            require(block.timestamp >= s.deadline, "window open");
            winner = s.claimant;
            payout = s.buyIn * 2;
        } else {
            revert("nothing to resolve");
        }

        s.status = Status.Closed;
        emit Resolved(sessionId, winner);
        _pay(winner, payout);
    }

    function _pay(address to, uint256 amount) private {
        (bool ok,) = to.call{value: amount}("");
        require(ok, "transfer failed");
    }

    function _recover(bytes32 hash, bytes calldata sig) private pure returns (address) {
        require(sig.length == 65, "bad sig length");
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        if (v < 27) v += 27;
        require(v == 27 || v == 28, "bad v");
        require(uint256(s) <= SECP256K1N_HALF, "bad s");

        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
        address signer = ecrecover(ethHash, v, r, s);
        require(signer != address(0), "bad sig");
        return signer;
    }
}
