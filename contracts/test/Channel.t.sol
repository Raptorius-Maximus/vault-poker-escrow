// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Channel} from "../src/Channel.sol";

/// Adversarial suite for the V1 escrow. The spec's testing section lists
/// cases in V2 vocabulary (receipts, hand numbers) that don't exist in V1 —
/// each is translated below to its V1 equivalent; the mapping is noted in
/// each test's comment so the intent isn't lost.
contract ChannelTest is Test {
    Channel channel;
    uint256 constant WINDOW = 30 minutes;
    uint256 constant BUYIN = 1 ether;
    uint256 constant BOND = (BUYIN * 1000) / 10000; // matches Channel.BOND_BPS

    uint256 hostPk = 0xA11CE;
    uint256 guestPk = 0xB0B;
    address host;
    address guest;

    function setUp() public {
        channel = new Channel(WINDOW);
        host = vm.addr(hostPk);
        guest = vm.addr(guestPk);
        vm.deal(host, 100 ether);
        vm.deal(guest, 100 ether);
    }

    function _open(bytes32 sessionId) internal {
        vm.prank(host);
        channel.open{value: BUYIN}(sessionId, guest);
    }

    function _openAndJoin(bytes32 sessionId) internal {
        _open(sessionId);
        vm.prank(guest);
        channel.join{value: BUYIN}(sessionId);
    }

    function _sig(uint256 pk, bytes32 sessionId, address winner) internal view returns (bytes memory) {
        bytes32 msgHash = keccak256(abi.encode(address(channel), block.chainid, sessionId, winner));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, ethHash);
        return abi.encodePacked(r, s, v);
    }

    function _status(bytes32 sid) internal view returns (Channel.Status st) {
        (,,,, st,,,) = channel.sessions(sid);
    }

    // ---------------------------------------------------------------- happy path

    function test_openAndJoin_setsActive() public {
        bytes32 sid = keccak256("s1");
        _openAndJoin(sid);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Active));
    }

    function test_closeCooperative_paysFullPotToWinner() public {
        bytes32 sid = keccak256("s2");
        _openAndJoin(sid);
        uint256 before = host.balance;

        bytes memory sigH = _sig(hostPk, sid, host);
        bytes memory sigG = _sig(guestPk, sid, host);
        channel.closeCooperative(sid, host, sigH, sigG);

        assertEq(host.balance, before + BUYIN * 2);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
    }

    function test_sessionZero_behavesLikeAnySession() public {
        // V2's "hand number 0" edge case, translated: bytes32(0) must not be
        // accidentally special-cased as "no session" in our mapping.
        bytes32 sid = bytes32(0);
        _openAndJoin(sid);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Active));
    }

    // ---------------------------------------------------------------- default / dispute path

    function test_uncontestedDefault_claimantTakesPotAndBondBack() public {
        bytes32 sid = keccak256("s3");
        _openAndJoin(sid);

        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        vm.warp(block.timestamp + WINDOW + 1);
        uint256 before = host.balance;
        channel.resolve(sid);

        assertEq(host.balance, before + BUYIN * 2 + BOND);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
    }

    function test_falseClaim_bondMovesToRefuter() public {
        // "the bond moves on a false claim"
        bytes32 sid = keccak256("s4");
        _openAndJoin(sid);

        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        uint256 before = guest.balance;
        vm.prank(guest);
        channel.iAmHere(sid);

        assertEq(guest.balance, before + BOND);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Refuted));
    }

    function test_refutedThenSilence_originalClaimantStillWinsPot() public {
        // "iAmHere() followed by silence still pays the claimant" — the case
        // the spec calls out as easy to leave out and fatal to leave out.
        bytes32 sid = keccak256("s5");
        _openAndJoin(sid);

        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);
        vm.prank(guest);
        channel.iAmHere(sid); // guest proves liveness but then goes quiet

        vm.warp(block.timestamp + WINDOW + 1);
        uint256 before = host.balance;
        channel.resolve(sid);

        // host gets the pot (bond already moved to guest at refutation time)
        assertEq(host.balance, before + BUYIN * 2);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
    }

    function test_refutedThenCooperativeClose_withinW2_settlesNormally() public {
        bytes32 sid = keccak256("s6");
        _openAndJoin(sid);

        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);
        vm.prank(guest);
        channel.iAmHere(sid);

        // guest, now proven alive, actually settles before W2 ends — guest won the match
        uint256 before = guest.balance;
        bytes memory sigH = _sig(hostPk, sid, guest);
        bytes memory sigG = _sig(guestPk, sid, guest);
        channel.closeCooperative(sid, guest, sigH, sigG);

        assertEq(guest.balance, before + BUYIN * 2);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
    }

    function test_iAmHere_onlyCallableByTheOtherParty() public {
        bytes32 sid = keccak256("s7");
        _openAndJoin(sid);
        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        vm.prank(host); // claimant trying to "refute" themselves
        vm.expectRevert("not the claimed-against party");
        channel.iAmHere(sid);
    }

    function test_iAmHere_afterWindowExpired_reverts() public {
        bytes32 sid = keccak256("s8");
        _openAndJoin(sid);
        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        vm.warp(block.timestamp + WINDOW + 1);
        vm.prank(guest);
        vm.expectRevert("window closed");
        channel.iAmHere(sid);
    }

    function test_resolve_beforeW1Expires_reverts() public {
        bytes32 sid = keccak256("s9");
        _openAndJoin(sid);
        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        vm.expectRevert("window open");
        channel.resolve(sid);
    }

    function test_resolve_beforeW2Expires_reverts() public {
        bytes32 sid = keccak256("s10");
        _openAndJoin(sid);
        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);
        vm.prank(guest);
        channel.iAmHere(sid);

        vm.expectRevert("window open");
        channel.resolve(sid);
    }

    function test_bothPartiesSilent_resolveStillPaysClaimantWheneverCalled() public {
        // "both parties offline through the whole window" — resolve() has no
        // deadline of its own; anyone can call it any time after the window,
        // no matter how long the silence lasted.
        bytes32 sid = keccak256("s11");
        _openAndJoin(sid);
        vm.prank(host);
        channel.claimByDefault{value: BOND}(sid);

        vm.warp(block.timestamp + WINDOW * 100); // long silence, not just past the deadline
        uint256 before = host.balance;
        channel.resolve(sid); // called by an unrelated address (this test contract)

        assertEq(host.balance, before + BUYIN * 2 + BOND);
    }

    // ---------------------------------------------------------------- signature / replay safety

    function test_signatureForWrongSession_rejected() public {
        // "a receipt for the wrong session" — a signature produced for one
        // session must not settle a different one.
        bytes32 sidA = keccak256("sidA");
        bytes32 sidB = keccak256("sidB");
        _openAndJoin(sidA);
        _openAndJoin(sidB);

        bytes memory sigH = _sig(hostPk, sidA, host); // signed for A
        bytes memory sigG = _sig(guestPk, sidA, host);

        vm.expectRevert("bad host sig");
        channel.closeCooperative(sidB, host, sigH, sigG); // replayed onto B
    }

    function test_signatureFromWrongContract_rejected() public {
        // "a replayed signature" — a sig bound to a different Channel
        // deployment must not be valid here (the hash includes address(this)).
        Channel other = new Channel(WINDOW);
        bytes32 sid = keccak256("s12");
        _openAndJoin(sid);

        bytes32 wrongHash = keccak256(abi.encode(address(other), block.chainid, sid, host));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", wrongHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPk, ethHash);
        bytes memory sigH = abi.encodePacked(r, s, v);
        bytes memory sigG = _sig(guestPk, sid, host);

        vm.expectRevert("bad host sig");
        channel.closeCooperative(sid, host, sigH, sigG);
    }

    function test_malleableSignature_highS_rejected() public {
        bytes32 sid = keccak256("s13");
        _openAndJoin(sid);

        bytes32 msgHash = keccak256(abi.encode(address(channel), block.chainid, sid, host));
        bytes32 ethHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(hostPk, ethHash);

        // flip to the malleable high-s counterpart of the same valid signature
        uint256 n = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes32 flippedS = bytes32(n - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        bytes memory badSig = abi.encodePacked(r, flippedS, flippedV);
        bytes memory sigG = _sig(guestPk, sid, host);

        vm.expectRevert("bad s");
        channel.closeCooperative(sid, host, badSig, sigG);
    }

    // ---------------------------------------------------------------- double-spend / replay of actions

    function test_closeAttemptedTwice_reverts() public {
        bytes32 sid = keccak256("s14");
        _openAndJoin(sid);
        bytes memory sigH = _sig(hostPk, sid, host);
        bytes memory sigG = _sig(guestPk, sid, host);
        channel.closeCooperative(sid, host, sigH, sigG);

        vm.expectRevert("not closeable");
        channel.closeCooperative(sid, host, sigH, sigG);
    }

    function test_claimByDefault_afterCooperativeClose_reverts() public {
        // "claim after a cooperative close"
        bytes32 sid = keccak256("s15");
        _openAndJoin(sid);
        bytes memory sigH = _sig(hostPk, sid, host);
        bytes memory sigG = _sig(guestPk, sid, host);
        channel.closeCooperative(sid, host, sigH, sigG);

        vm.prank(host);
        vm.expectRevert("not active");
        channel.claimByDefault{value: BOND}(sid);
    }

    function test_reopeningSameSessionId_reverts() public {
        // "two equal hand numbers" translated: a session id is a one-time
        // identifier, same as a hand number must be monotonic in V2.
        bytes32 sid = keccak256("s16");
        _openAndJoin(sid);
        bytes memory sigH = _sig(hostPk, sid, host);
        bytes memory sigG = _sig(guestPk, sid, host);
        channel.closeCooperative(sid, host, sigH, sigG);

        vm.prank(host);
        vm.expectRevert("session exists");
        channel.open{value: BUYIN}(sid, guest);
    }

    // ---------------------------------------------------------------- input validation

    function test_claimByDefault_wrongBondAmount_reverts() public {
        bytes32 sid = keccak256("s17");
        _openAndJoin(sid);
        vm.prank(host);
        vm.expectRevert("wrong bond");
        channel.claimByDefault{value: BOND - 1}(sid);
    }

    function test_claimByDefault_byNonPlayer_reverts() public {
        bytes32 sid = keccak256("s18");
        _openAndJoin(sid);
        address stranger = vm.addr(0xDEAD);
        vm.deal(stranger, 10 ether);
        vm.prank(stranger);
        vm.expectRevert("not a player");
        channel.claimByDefault{value: BOND}(sid);
    }

    function test_join_wrongBuyIn_reverts() public {
        bytes32 sid = keccak256("s19");
        _open(sid);
        vm.prank(guest);
        vm.expectRevert("buyIn mismatch");
        channel.join{value: BUYIN - 1}(sid);
    }

    function test_join_byNonGuest_reverts() public {
        bytes32 sid = keccak256("s20");
        _open(sid);
        address stranger = vm.addr(0xDEAD);
        vm.deal(stranger, 10 ether);
        vm.prank(stranger);
        vm.expectRevert("not invited");
        channel.join{value: BUYIN}(sid);
    }

    // ---------------------------------------------------------------- cancellation (fund-lock safety valve)

    function test_cancelOpen_refundsHostBeforeGuestJoins() public {
        bytes32 sid = keccak256("s21");
        _open(sid);
        uint256 before = host.balance;

        vm.prank(host);
        channel.cancelOpen(sid);

        assertEq(host.balance, before + BUYIN);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
    }

    function test_cancelOpen_notCallableByGuest() public {
        bytes32 sid = keccak256("s22");
        _open(sid);
        vm.prank(guest);
        vm.expectRevert("not host");
        channel.cancelOpen(sid);
    }

    function test_cancelOpen_notCallableAfterJoin() public {
        bytes32 sid = keccak256("s23");
        _openAndJoin(sid);
        vm.prank(host);
        vm.expectRevert("not cancellable");
        channel.cancelOpen(sid);
    }

    // ---------------------------------------------------------------- reentrancy

    function test_reentrancy_cannotDoublePay() public {
        Attacker attacker = new Attacker(channel);
        vm.deal(address(attacker), 10 ether);
        bytes32 sid = keccak256("s24");

        attacker.openAsHost{value: BUYIN}(sid, guest);
        vm.prank(guest);
        channel.join{value: BUYIN}(sid);

        attacker.claim{value: BOND}(sid);
        vm.warp(block.timestamp + WINDOW + 1);

        uint256 before = address(attacker).balance;
        channel.resolve(sid); // triggers attacker's receive(), which tries to re-resolve
        // exactly one payout: pot + bond, no more, and the reentrant attempt failed
        assertEq(address(attacker).balance, before + BUYIN * 2 + BOND);
        assertEq(uint256(_status(sid)), uint256(Channel.Status.Closed));
        assertFalse(attacker.reentrantResolveSucceeded());
    }
}

/// Reenters resolve() from its receive() hook to prove the
/// checks-effects-interactions ordering (status flips to Closed before the
/// payout call) blocks a double payout.
contract Attacker {
    Channel private immutable channel;
    bytes32 private sid;
    bool private reentered;

    constructor(Channel _channel) {
        channel = _channel;
    }

    function openAsHost(bytes32 sessionId, address opponent) external payable {
        sid = sessionId;
        channel.open{value: msg.value}(sessionId, opponent);
    }

    function claim(bytes32 sessionId) external payable {
        channel.claimByDefault{value: msg.value}(sessionId);
    }

    receive() external payable {
        if (!reentered) {
            reentered = true;
            // try/catch so the outer legitimate payout isn't itself reverted
            // by the inner reentrant call's failure — the point being tested
            // is that the inner call fails, not that it takes the outer one
            // down with it.
            try channel.resolve(sid) {
                reentrantResolveSucceeded = true; // would mean a double payout
            } catch {}
        }
    }

    bool public reentrantResolveSucceeded;
}
