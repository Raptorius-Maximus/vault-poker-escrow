// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {BettingReplay} from "../src/BettingReplay.sol";

/// Phase 3 task 5's own test file — isolated tests of the ported betting
/// engine against `betting.ts`'s own semantics (task 5, task 8). No
/// `ChannelV2` deployment anywhere in this file: `BettingReplay` is a pure
/// library, testable with hand-built inputs alone (Files touched, task 5).
///
/// Every numeric fixture below was cross-checked against the actual
/// `betting.ts` (not reimplemented from memory) via:
///
///   node --experimental-strip-types -e "import('.../betting.ts').then(...)"
///
/// run against `/home/dev/projects/poker/src/core/betting.ts` directly —
/// the differential check the phase doc's task 5 verification probe
/// describes for (f) and recommends generally ("the strongest verification
/// available short of a shared vector file"). The exact transcripts are
/// cited inline above each fixture that used one.
contract BettingReplayTest is Test {
    // ---------------------------------------------------------------- helpers

    function _cand(uint64 seq, bool isHost, BettingReplay.ActionKind action, uint256 amount, uint256 filedAt)
        internal
        pure
        returns (BettingReplay.Cand memory)
    {
        return BettingReplay.Cand({seq: seq, signerIsHost: isHost, action: action, amount: amount, filedAt: filedAt});
    }

    // ================================================================== (a)
    // A folded chain returns FOLD with the correct folder.

    function test_fold_terminal() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](1);
        // Preflop, host is button, acts first: host folds immediately.
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Fold, 0, 111);

        (
            BettingReplay.TermKind kind,
            bool folderIsHost,
            BettingReplay.State memory st,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        ) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.FOLD));
        assertTrue(folderIsHost);
        assertTrue(st.hasFolded);
        assertTrue(st.foldedIsHost);
        assertEq(lastAcceptedSeq, 0);
        // decision 3: completingFiledAt stays 0 for FOLD — a fold owes no
        // share duties at all — even though the accepted candidate's own
        // filedAt (111) was nonzero.
        assertEq(completingFiledAt, 0);
    }

    // Sanity: startHand is called with `(buttonIsHost, sb, bb, stackHost,
    // stackGuest)` positionally different from `replay`'s own
    // `(buttonIsHost, sb, bb, stackHost, stackGuest, ordered)` — both
    // orderings agree, exercised implicitly by every test in this file
    // that reads `st.committedHost`/`st.committedGuest` post-blind.
    function test_startHand_postsMinOfBlindAndStack() public pure {
        // Button (host) stack is short of the small blind: posts what it
        // has, never more (decision 3's first cited fact, betting.ts:48-49).
        BettingReplay.State memory st = BettingReplay.startHand(true, 0, 100, 5, 10);
        assertEq(st.committedHost, 0);
        assertEq(st.stackHost, 0);
        assertEq(st.committedGuest, 10);
        assertEq(st.stackGuest, 90);
        assertTrue(st.toActIsHost); // button acts first preflop
    }

    // ================================================================== (b)
    // A chain reaching river-close with both sides having acted returns
    // COMPLETE. Also *is* the "preflop -> flop chain, consecutive same seat
    // across the boundary" AF-2 probe: seq 1 (guest checks, closing
    // preflop) and seq 2 (guest checks again, first to act on the flop)
    // are the SAME signer at consecutive seqs — a seq%2 parity validator
    // would reject this honest chain (artifact-formats §5's own warning,
    // AF-2). `replay` derives the actor purely from the replayed state,
    // never from seq parity, so both are accepted.
    //
    // Node differential (buttonIsHost='me'=host, stacks 100/100, sb=1,
    // bb=2): call, check, [nextStreet->flop], check, check,
    // [nextStreet->turn], check, check, [nextStreet->river], check, check,
    // nextStreet(river) === null. Confirmed via the harness cited in this
    // file's header comment.
    function test_completeChain_preflopToFlopSameSeatBoundary() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](8);
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Call, 0, 10); // host: call the bb
        ordered[1] = _cand(1, false, BettingReplay.ActionKind.Check, 0, 20); // guest: check, closes preflop
        ordered[2] = _cand(2, false, BettingReplay.ActionKind.Check, 0, 30); // guest AGAIN: first to act, flop
        ordered[3] = _cand(3, true, BettingReplay.ActionKind.Check, 0, 40); // host: closes flop
        ordered[4] = _cand(4, false, BettingReplay.ActionKind.Check, 0, 50);
        ordered[5] = _cand(5, true, BettingReplay.ActionKind.Check, 0, 60); // closes turn
        ordered[6] = _cand(6, false, BettingReplay.ActionKind.Check, 0, 70);
        ordered[7] = _cand(7, true, BettingReplay.ActionKind.Check, 0, 999); // closes river -> COMPLETE

        (
            BettingReplay.TermKind kind,
            ,
            BettingReplay.State memory st,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        ) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.COMPLETE));
        assertEq(uint256(st.street), uint256(BettingReplay.Street.River));
        assertEq(lastAcceptedSeq, 7);
        assertEq(completingFiledAt, 999);
        assertFalse(st.hasFolded);
        // Both sides committed 2 preflop (1 blind + 1 call-top-up), 0 on
        // every later street (all checks) -- matches the node trace's
        // committed = {me:2, them:2} snapshot at preflop close.
        assertEq(st.investedHost, 2);
        assertEq(st.investedGuest, 2);
    }

    // ================================================================== (c)
    // An all-in on the flop with no further filed actions cascades
    // `closeAndAdvance` straight to COMPLETE, consuming zero additional
    // candidates (mirrors betting.ts:195's auto-close).
    //
    // Node differential (stacks 20/20, sb=1, bb=2, button=host): call,
    // check [->flop, stacks 18/18], guest bets 999 (clamps to all-in 18),
    // host calls -> stacks {0,0}, closed=true; nextStreet->turn
    // (closed=true, auto), ->river (closed=true, auto), nextStreet(river)
    // === null. Confirmed via the harness cited in this file's header.
    function test_allInCascade_completeWithoutFurtherActions() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](4);
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Call, 0, 1);
        ordered[1] = _cand(1, false, BettingReplay.ActionKind.Check, 0, 2);
        ordered[2] = _cand(2, false, BettingReplay.ActionKind.Bet, 18, 3); // guest shoves the flop
        ordered[3] = _cand(3, true, BettingReplay.ActionKind.Call, 0, 4); // host calls all-in

        (
            BettingReplay.TermKind kind,
            ,
            BettingReplay.State memory st,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        ) = BettingReplay.replay(true, 1, 2, 20, 20, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.COMPLETE));
        assertEq(uint256(st.street), uint256(BettingReplay.Street.River));
        assertEq(lastAcceptedSeq, 3); // no seq 4/5/6/7 candidate needed
        assertEq(completingFiledAt, 4); // filedAt of the last accepted candidate (seq 3)
        assertEq(st.stackHost, 0);
        assertEq(st.stackGuest, 0);
        assertEq(st.investedHost, 20);
        assertEq(st.investedGuest, 20);
    }

    // ================================================================== (d)
    // A chain missing its next seq's candidate returns NONE.

    function test_pending_missingNextSeqCandidate() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](1);
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Call, 0, 1);
        // seq 1 (guest's check) never filed.

        (BettingReplay.TermKind kind,,, uint256 lastAcceptedSeq,) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.NONE));
        assertEq(lastAcceptedSeq, 0);
    }

    function test_pending_noCandidatesAtAll() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](0);
        (BettingReplay.TermKind kind,,, uint256 lastAcceptedSeq,) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.NONE));
        // Sentinel for "nothing was ever accepted" -- distinct from
        // "accepted seq 0 and stopped".
        assertEq(lastAcceptedSeq, type(uint256).max);
    }

    // ================================================================== (e)
    // A bet whose signed amount sits exactly at `lo` and exactly at `hi`
    // both succeed (decision 3's range-check boundary); `lo-1`/`hi+1` both
    // fail, and a failing bet leaves state untouched.

    function _flopStateGuestToAct() internal pure returns (BettingReplay.State memory st) {
        st = BettingReplay.startHand(true, 100, 100, 1, 2);
        bool ok;
        (st, ok) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Call, 0);
        assertTrue(ok);
        (st, ok) = BettingReplay.applyAction(st, false, BettingReplay.ActionKind.Check, 0);
        assertTrue(ok);
        bool stillLive;
        (st, stillLive) = BettingReplay.closeAndAdvance(st, true);
        assertTrue(stillLive);
        assertEq(uint256(st.street), uint256(BettingReplay.Street.Flop));
        assertFalse(st.toActIsHost); // non-button acts first postflop
    }

    function test_clampBoundary_loAndHiSucceed() public pure {
        BettingReplay.State memory base = _flopStateGuestToAct();
        uint256 lo = BettingReplay.minRaiseTo(base, false);
        uint256 hi = BettingReplay.maxRaiseTo(base, false);
        assertEq(lo, 2);
        assertEq(hi, 98);

        BettingReplay.State memory st1 = _flopStateGuestToAct();
        bool ok1;
        (st1, ok1) = BettingReplay.applyAction(st1, false, BettingReplay.ActionKind.Bet, lo);
        assertTrue(ok1);
        assertEq(st1.committedGuest, lo);

        BettingReplay.State memory st2 = _flopStateGuestToAct();
        bool ok2;
        (st2, ok2) = BettingReplay.applyAction(st2, false, BettingReplay.ActionKind.Bet, hi);
        assertTrue(ok2);
        assertEq(st2.committedGuest, hi);
    }

    function test_clampBoundary_belowLoAndAboveHiFail() public pure {
        BettingReplay.State memory base = _flopStateGuestToAct();
        uint256 lo = BettingReplay.minRaiseTo(base, false);
        uint256 hi = BettingReplay.maxRaiseTo(base, false);

        BettingReplay.State memory st1 = _flopStateGuestToAct();
        bool ok1;
        BettingReplay.State memory unchanged1 = st1;
        (st1, ok1) = BettingReplay.applyAction(st1, false, BettingReplay.ActionKind.Bet, lo - 1);
        assertFalse(ok1);
        assertEq(st1.committedGuest, unchanged1.committedGuest);
        assertEq(st1.stackGuest, unchanged1.stackGuest);

        BettingReplay.State memory st2 = _flopStateGuestToAct();
        bool ok2;
        (st2, ok2) = BettingReplay.applyAction(st2, false, BettingReplay.ActionKind.Bet, hi + 1);
        assertFalse(ok2);
        assertEq(st2.committedGuest, 0);
        assertEq(st2.stackGuest, 98); // 100 - 2 (bb posted preflop), unchanged by the rejected bet
    }

    // Distinguishes "capped by the OPPONENT's effective stack" (tested
    // above, hi = opponent's committed+stack) from "capped by the actor's
    // OWN stack" (maxRaiseTo's other operand, betting.ts:93-97).
    function test_betEqualsOwnStack_cappedByOwnEffectiveStack() public pure {
        BettingReplay.State memory st = BettingReplay.startHand(true, 100, 100, 1, 2);
        // Hand-set a state where host's own stack (5) is the binding
        // constraint, not guest's (100).
        st.committedHost = 0;
        st.stackHost = 5;
        st.committedGuest = 0;
        st.stackGuest = 100;
        st.toActIsHost = true;
        st.lastRaiseSize = 2;
        st.bigBlind = 2;

        uint256 hi = BettingReplay.maxRaiseTo(st, true);
        assertEq(hi, 5); // own committed(0) + stack(5), not guest's 100

        bool ok;
        (st, ok) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Bet, 5);
        assertTrue(ok);
        assertEq(st.stackHost, 0);
        assertEq(st.committedHost, 5);
    }

    // ================================================================== (f)
    // Short all-in does not reopen betting: `raiseSize >= lastRaiseSize`
    // gates whether `actedSinceAggression` resets to {seat} alone or
    // merely gains `seat`, and whether `lastRaiseSize` updates at all.
    //
    // Node differential, run against the actual betting.ts (transcript
    // cited in full in this task's completion notes):
    //   startHand({me:100,them:12},'me',1,2)              -> committed {me:1,them:2}, stacks {me:99,them:10}
    //   applyAction(st,'me','bet',10)                      -> committed {me:10,them:2}, lastRaiseSize=8, acted=['me']
    //   legalActions(st,'them') === ['fold','call','bet']; minRaiseTo(them)=12=maxRaiseTo(them)
    //   applyAction(st,'them','bet',999) clamps to 12       -> committed {me:10,them:12}, stacks {me:90,them:0},
    //                                                          acted=['me','them'] (GAINED, not reset), lastRaiseSize STAYS 8
    //   applyAction(st,'me','call')                         -> closed=true, acted=['me','them']
    function test_shortAllIn_doesNotReopen_actedSetGainsNotResets() public pure {
        BettingReplay.State memory st = BettingReplay.startHand(true, 100, 12, 1, 2);
        assertEq(st.committedHost, 1);
        assertEq(st.committedGuest, 2);
        assertEq(st.stackGuest, 10);

        bool ok;
        (st, ok) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Bet, 10);
        assertTrue(ok);
        assertEq(st.committedHost, 10);
        assertEq(st.lastRaiseSize, 8);
        assertTrue(st.actedSinceAggressionHost);
        assertFalse(st.actedSinceAggressionGuest);

        uint256 lo = BettingReplay.minRaiseTo(st, false);
        uint256 hi = BettingReplay.maxRaiseTo(st, false);
        assertEq(lo, 12); // the min-raise floor (18) is clamped DOWN to hi
        assertEq(hi, 12); // guest's own effective stack: lo == hi (all-in below min-raise)

        (st, ok) = BettingReplay.applyAction(st, false, BettingReplay.ActionKind.Bet, hi); // guest's only legal bet amount
        assertTrue(ok);
        assertEq(st.committedGuest, 12);
        assertEq(st.stackGuest, 0);

        // The short all-in (raiseSize = 12 - 10 = 2 < lastRaiseSize = 8)
        // must NOT reopen: lastRaiseSize stays 8, host's flag is GAINED
        // into (not reset out of, still true).
        assertEq(st.lastRaiseSize, 8);
        assertTrue(st.actedSinceAggressionHost);
        assertTrue(st.actedSinceAggressionGuest);

        (st, ok) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Call, 0);
        assertTrue(ok);
        assertTrue(st.closed);
    }

    // Contrast: a real (>=lastRaiseSize) raise DOES reset the acted set to
    // {seat} alone and DOES update lastRaiseSize -- the branch the short
    // all-in above deliberately does not take.
    function test_realRaise_reopens_actedSetResets() public pure {
        BettingReplay.State memory st = BettingReplay.startHand(true, 100, 100, 1, 2);
        bool ok;
        (st, ok) = BettingReplay.applyAction(st, true, BettingReplay.ActionKind.Bet, 10); // host raises to 10
        assertTrue(ok);
        assertTrue(st.actedSinceAggressionHost);

        // Guest re-raises to 30 (raiseSize = 30 - 10 = 20 >= lastRaiseSize 8): reopens.
        (st, ok) = BettingReplay.applyAction(st, false, BettingReplay.ActionKind.Bet, 30);
        assertTrue(ok);
        assertEq(st.lastRaiseSize, 20);
        assertTrue(st.actedSinceAggressionGuest);
        // Host's flag was WIPED (reset to {guest} alone), unlike the short
        // all-in case above.
        assertFalse(st.actedSinceAggressionHost);
    }

    // ================================================================== (g)
    // M1: an out-of-turn candidate (validly "signed" but by the wrong
    // seat for the replayed state) is treated exactly as "no candidate at
    // this seq" -- never accepted, never equivocation.

    function test_outOfTurn_candidateAtSeqZero_rejected() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](1);
        // Host is button and must act first preflop; only a guest-signed
        // candidate is on file at seq 0.
        ordered[0] = _cand(0, false, BettingReplay.ActionKind.Check, 0, 1);

        (BettingReplay.TermKind kind,,, uint256 lastAcceptedSeq,) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.NONE));
        assertEq(lastAcceptedSeq, type(uint256).max);
    }

    function test_outOfTurn_candidateMidChain_stopsAtPriorSeq() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](2);
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Call, 0, 1); // host: legit
        // seq 1 should be guest's check; instead only a HOST-signed
        // candidate (wrong signer) is on file at seq 1.
        ordered[1] = _cand(1, true, BettingReplay.ActionKind.Check, 0, 2);

        (BettingReplay.TermKind kind,,, uint256 lastAcceptedSeq,) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.NONE));
        assertEq(lastAcceptedSeq, 0); // k-1, per M1's own probe wording
    }

    // Also: a candidate that IS from the right signer but is not a legal
    // continuation (e.g. a bet amount out of [lo,hi]) is likewise treated
    // as "no candidate here" -- not a revert.
    function test_illegalAmount_midChain_stopsAtPriorSeq() public pure {
        BettingReplay.Cand[] memory ordered = new BettingReplay.Cand[](2);
        ordered[0] = _cand(0, true, BettingReplay.ActionKind.Call, 0, 1);
        // Guest's real range on the flop-equivalent preflop-close spot is
        // whatever minRaiseTo/maxRaiseTo compute; deliberately bet far
        // above any possible hi.
        ordered[1] = _cand(1, false, BettingReplay.ActionKind.Bet, type(uint256).max / 2, 2);

        (BettingReplay.TermKind kind,,, uint256 lastAcceptedSeq,) = BettingReplay.replay(true, 1, 2, 100, 100, ordered);

        assertEq(uint256(kind), uint256(BettingReplay.TermKind.NONE));
        assertEq(lastAcceptedSeq, 0);
    }
}
