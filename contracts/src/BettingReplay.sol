// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// BettingReplay — the ported heads-up betting state machine.
///
/// A faithful integer port of `/home/dev/projects/poker/src/core/betting.ts`
/// (223 lines, read in full for this port). See
/// docs/superpowers/plans/2026-08-17-v2-cash-settlement/phase-3-disputes-evidence.md
/// task 5 and decision 3/3a for the design record this file implements.
///
/// Design constraints this file honors (phase-3 decision 3, "standalone
/// library, ported not wrapped"):
///   - Pure/stateless. No storage, no ChannelV2 dependency. Every function
///     is `internal pure`, so this library is testable with hand-built
///     inputs and needs no ChannelV2 deployment (Files touched, task 5).
///   - Chip-space only (decision 3a). No wei figure is ever read or
///     produced by this file; the caller (ChannelV2's future consolidation,
///     task 6 — out of this task's scope) is responsible for the wei<->chip
///     conversion on both sides of every call.
///   - Turn order is derived purely by replaying seq 0..k-1 — never from
///     `seq % 2` (AF-2, artifact-formats §5's explicit warning: the same
///     seat legitimately acts at consecutive seqs across a street
///     boundary — button first preflop, non-button first postflop — so a
///     parity-based validator rejects honest chains).
///   - The clamp reduces to an integer range check (phase brief's
///     "fifteenth check"): a `bet` action's canonical, already-clamped
///     `amount` is legal iff `lo <= amount <= hi`; no clamping computation
///     (no `min`/`max`/`round` folding a client's raw request) is ever
///     performed here — the client already signed the applied integer.
///
/// Interface note, disclosed rather than silently decided (see this task's
/// completion report for the full reasoning): the phase-3 doc's prose
/// signature for `replay(...)` returns `address folder` and lists no
/// host/guest key parameters, which is unconstructible together — an
/// address can't be produced without an address ever entering the
/// function. Since decision 3a and the Files-touched section both commit
/// this library to chip-space purity and zero ChannelV2/address
/// dependency, and P4's own reuse note describes the entry point as
/// taking only "button, sb, bb, baseline stacks, and an ordered action
/// list" (no keys), this file resolves the gap by keeping signer identity
/// as a `bool signerIsHost` on `Cand` (already resolved by the caller from
/// `ecrecover`'d self-authentication at storage time, decision 1) and
/// returning `bool folderIsHost` in place of `address folder`. The future
/// ChannelV2 caller (task 6/7, not this task) translates that bool to a
/// wallet address using its own `host`/`guest` storage, exactly as it
/// already must translate `weiPerChip`-adjacent quantities. This is an
/// interface-completion, not a betting.ts semantic divergence.
library BettingReplay {
    // ------------------------------------------------------------ types

    /// betting.ts:17 `Street[]` order — River is deliberately last so
    /// `Street(uint8(street) + 1)` walks preflop -> flop -> turn -> river,
    /// matching `STREETS.indexOf` / `STREETS[idx + 1]` (betting.ts:188-191).
    enum Street {
        Preflop,
        Flop,
        Turn,
        River
    }

    /// artifact-formats §5's wire encoding: 0x00 fold, 0x01 check,
    /// 0x02 call, 0x03 bet — Solidity's default enum numbering matches
    /// this exactly, so `uint8(action)` round-trips the wire byte.
    enum ActionKind {
        Fold,
        Check,
        Call,
        Bet
    }

    /// The replay's own termination signal (task 5 step 6). `NONE` means
    /// "pending" — a filed action exists for every seq reached so far, but
    /// the street in progress is not yet closed, or the next required
    /// action was never filed. Routing `NONE` to `PendingContinuation` is
    /// ChannelV2's job (task 7), not this library's.
    enum TermKind {
        NONE,
        FOLD,
        COMPLETE
    }

    /// betting.ts:23-37's `BettingState`, ported. `Set<Seat>` becomes two
    /// bools (a fixed two-element universe needs no set structure); `folded:
    /// Seat | null` becomes `hasFolded` + `foldedIsHost` — a tri-state
    /// flattened to two fields rather than a signed/sentinel int, per task
    /// 5 step 1's explicit "implementer's choice."
    struct State {
        Street street;
        uint256 committedHost;
        uint256 committedGuest;
        uint256 investedHost;
        uint256 investedGuest;
        uint256 stackHost;
        uint256 stackGuest;
        bool toActIsHost;
        uint256 lastRaiseSize;
        bool actedSinceAggressionHost;
        bool actedSinceAggressionGuest;
        bool closed;
        bool hasFolded;
        bool foldedIsHost;
        uint256 bigBlind;
    }

    /// A single filed-action candidate, already resolved to chip-space
    /// (formats §5, decision 3a) and to a host/guest signer identity
    /// (decision 1's self-authentication, done by the caller at storage
    /// time — see this file's header note). `filedAt` threads through to
    /// `completingFiledAt` (decision 3's share-duty birth anchor) untouched.
    struct Cand {
        uint64 seq;
        bool signerIsHost;
        ActionKind action;
        uint256 amount;
        uint256 filedAt;
    }

    /// Sentinel for "no action was ever accepted" — distinguishes a chain
    /// that never got off the ground (missing seq 0 entirely) from one
    /// that accepted seq 0 and stopped (`lastAcceptedSeq == 0`).
    uint256 internal constant NO_SEQ = type(uint256).max;

    // ------------------------------------------------------------ small helpers

    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function _committed(State memory st, bool isHost) internal pure returns (uint256) {
        return isHost ? st.committedHost : st.committedGuest;
    }

    function _stack(State memory st, bool isHost) internal pure returns (uint256) {
        return isHost ? st.stackHost : st.stackGuest;
    }

    function _actedSinceAggression(State memory st, bool isHost) internal pure returns (bool) {
        return isHost ? st.actedSinceAggressionHost : st.actedSinceAggressionGuest;
    }

    function _setActedSinceAggression(State memory st, bool isHost, bool val) internal pure {
        if (isHost) {
            st.actedSinceAggressionHost = val;
        } else {
            st.actedSinceAggressionGuest = val;
        }
    }

    /// betting.ts:69-73 `post` — moves chips from stack into committed and
    /// invested for one seat.
    function _post(State memory st, bool isHost, uint256 amount) internal pure {
        if (isHost) {
            st.stackHost -= amount;
            st.committedHost += amount;
            st.investedHost += amount;
        } else {
            st.stackGuest -= amount;
            st.committedGuest += amount;
            st.investedGuest += amount;
        }
    }

    // ------------------------------------------------------------ betting.ts:77-121 ports

    /// betting.ts:77-78.
    function toCall(State memory st, bool isHost) internal pure returns (uint256) {
        uint256 own = _committed(st, isHost);
        uint256 other = _committed(st, !isHost);
        // Invariant: own <= other whenever it is genuinely `isHost`'s turn
        // to act (the last action was the other seat's, which only ever
        // equalizes or raises `other`'s committed figure). Plain
        // subtraction mirrors the JS exactly and doubles as an assertion —
        // it can only revert if that invariant is broken.
        uint256 need = other - own;
        uint256 stack = _stack(st, isHost);
        return _min(need, stack);
    }

    /// betting.ts:80-83.
    function minRaiseTo(State memory st, bool isHost) internal pure returns (uint256) {
        uint256 target = _committed(st, !isHost) + _max(st.lastRaiseSize, st.bigBlind);
        return _min(target, _committed(st, isHost) + _stack(st, isHost));
    }

    /// betting.ts:93-97.
    function maxRaiseTo(State memory st, bool isHost) internal pure returns (uint256) {
        return _min(
            _committed(st, isHost) + _stack(st, isHost), _committed(st, !isHost) + _stack(st, !isHost)
        );
    }

    /// betting.ts:99-109's `legalActions`, collapsed to a membership test
    /// (this library never needs the full list, only "is this action —
    /// possibly with this amount category — legal right now").
    function _legalCategory(State memory st, bool isHost, ActionKind action) internal pure returns (bool) {
        if (st.closed || st.toActIsHost != isHost) return false;
        uint256 need = toCall(st, isHost);
        if (need > 0) {
            if (action == ActionKind.Fold || action == ActionKind.Call) return true;
        } else {
            if (action == ActionKind.Check) return true;
        }
        if (action == ActionKind.Bet) {
            uint256 stack = _stack(st, isHost);
            if (stack > need && maxRaiseTo(st, isHost) > _committed(st, !isHost)) return true;
        }
        return false;
    }

    /// betting.ts:118-121.
    function _canAct(State memory st, bool isHost) internal pure returns (bool) {
        if (_stack(st, isHost) == 0) return false;
        return _committed(st, isHost) < _committed(st, !isHost) || !_actedSinceAggression(st, isHost);
    }

    // ------------------------------------------------------------ betting.ts:41-67 startHand

    /// betting.ts:41-67. Posts `min(blind, stack)` for both blinds
    /// (decision 3's first cited fact — a short stack posts what it has,
    /// never more) and sets `toActIsHost = buttonIsHost` (button acts
    /// first preflop, betting.ts:56).
    function startHand(bool buttonIsHost, uint256 stackHost, uint256 stackGuest, uint256 sb, uint256 bb)
        internal
        pure
        returns (State memory st)
    {
        st.street = Street.Preflop;
        st.stackHost = stackHost;
        st.stackGuest = stackGuest;
        st.toActIsHost = buttonIsHost;
        st.lastRaiseSize = bb;
        st.bigBlind = bb;
        // committed/invested/actedSinceAggression/closed/hasFolded all
        // default-zero/false, matching betting.ts's fresh-state literals.

        uint256 sbPost = _min(sb, buttonIsHost ? stackHost : stackGuest);
        uint256 bbPost = _min(bb, buttonIsHost ? stackGuest : stackHost);
        _post(st, buttonIsHost, sbPost);
        _post(st, !buttonIsHost, bbPost);
    }

    // ------------------------------------------------------------ betting.ts:127-183 applyAction

    /// betting.ts:127-183. Returns `ok = false`, with `st` left untouched,
    /// for any illegal action (wrong actor, wrong action for the current
    /// legal set, or an out-of-range `bet` amount) — task 5 step 4's
    /// explicit contract: the caller treats this exactly like "no
    /// candidate exists for this seq," never a revert.
    function applyAction(State memory st, bool actorIsHost, ActionKind action, uint256 amount)
        internal
        pure
        returns (State memory, bool ok)
    {
        if (st.closed || st.toActIsHost != actorIsHost || !_legalCategory(st, actorIsHost, action)) {
            return (st, false);
        }

        if (action == ActionKind.Fold) {
            st.hasFolded = true;
            st.foldedIsHost = actorIsHost;
            st.closed = true;
            return (st, true);
        }

        if (action == ActionKind.Check) {
            _setActedSinceAggression(st, actorIsHost, true);
        } else if (action == ActionKind.Call) {
            uint256 need = toCall(st, actorIsHost);
            _post(st, actorIsHost, need);
            _setActedSinceAggression(st, actorIsHost, true);
        } else {
            // Bet — decision 3's range-check simplification: the client
            // already signed the post-clamp integer, so legality is
            // exactly `lo <= amount <= hi`, no clamp computed here.
            uint256 hi = maxRaiseTo(st, actorIsHost);
            uint256 mrt = minRaiseTo(st, actorIsHost);
            uint256 lo = _min(mrt, hi);
            if (amount < lo || amount > hi) {
                return (st, false);
            }
            uint256 target = amount;
            uint256 otherCommitted = _committed(st, !actorIsHost);
            uint256 raiseSize = target - otherCommitted;
            uint256 ownCommitted = _committed(st, actorIsHost);
            _post(st, actorIsHost, target - ownCommitted);

            // betting.ts:161-166 — a short all-in does not reopen betting.
            if (raiseSize >= st.lastRaiseSize) {
                st.lastRaiseSize = raiseSize;
                st.actedSinceAggressionHost = actorIsHost;
                st.actedSinceAggressionGuest = !actorIsHost;
            } else {
                _setActedSinceAggression(st, actorIsHost, true);
            }
        }

        st.toActIsHost = !actorIsHost;

        // betting.ts:181 — round closes when neither seat can still be
        // asked to act.
        if (!_canAct(st, true) && !_canAct(st, false)) {
            st.closed = true;
        }

        return (st, true);
    }

    // ------------------------------------------------------------ betting.ts:186-198 nextStreet

    /// betting.ts:186-198, renamed per task 5 step 5 (`nextStreet` proper
    /// is only ever invoked here, after a round-closing `applyAction`, so
    /// folding the two together loses nothing). Called only when `st.closed
    /// == true` from a round-over (never a fold — the replay loop
    /// intercepts folds before this is reached). Returns `stillLive =
    /// false` exactly when `betting.ts`'s `nextStreet` would return `null`
    /// (already at River) — the COMPLETE signal.
    function closeAndAdvance(State memory st, bool buttonIsHost)
        internal
        pure
        returns (State memory, bool stillLive)
    {
        if (st.street == Street.River) {
            return (st, false);
        }
        st.street = Street(uint8(st.street) + 1);
        st.committedHost = 0;
        st.committedGuest = 0;
        st.lastRaiseSize = st.bigBlind;
        st.actedSinceAggressionHost = false;
        st.actedSinceAggressionGuest = false;
        // betting.ts:195 — all-in runout: either stack empty auto-closes
        // the fresh street, cascading straight through to River with no
        // further action filed.
        st.closed = (st.stackHost == 0 || st.stackGuest == 0);
        st.toActIsHost = !buttonIsHost;
        return (st, true);
    }

    // ------------------------------------------------------------ task 5 step 6 — replay

    /// The public entry point (decision 3's "reused by P4, unchanged").
    /// Every `uint256` here is chip-space in and out (decision 3a) — the
    /// caller performs the wei<->chip conversion on both sides.
    ///
    /// `ordered` is the caller-prepared, already in-window-filtered,
    /// seq-ascending view into the filed-action storage (ChannelV2's
    /// future task 6) — grouped by `seq` (each seq may contribute 0, 1, or
    /// 2 entries, one per possible signer, mirroring the two-slot storage
    /// model). Walking `ordered` by seq starting from `startHand`'s
    /// result: at each step, this function requires a candidate whose
    /// `signerIsHost` matches the just-computed `st.toActIsHost` — a
    /// candidate that exists at that seq but from the wrong signer is
    /// skipped/ignored exactly like "no candidate at this seq" (never
    /// accepted, never treated as equivocation — that is a same-key
    /// conflict, a different, storage-time concern per decision 2).
    function replay(
        bool buttonIsHost,
        uint256 sb,
        uint256 bb,
        uint256 stackHost,
        uint256 stackGuest,
        Cand[] memory ordered
    )
        internal
        pure
        returns (
            TermKind kind,
            bool folderIsHost,
            State memory finalState,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        )
    {
        // The walking loop is factored into `_walk` (below) purely to keep
        // this function's own local-variable count under the legacy
        // codegen's stack-slot ceiling — `sb`/`bb`/`stackHost`/`stackGuest`
        // are dead the instant `startHand` returns, but a function
        // parameter occupies a stack slot for its whole function, so
        // keeping the loop out-of-line here (rather than a purely
        // stylistic split) is what makes `forge build` succeed without
        // `--via-ir`. No behavior lives in this wrapper beyond that.
        State memory st = startHand(buttonIsHost, stackHost, stackGuest, sb, bb);
        (kind, folderIsHost, finalState, lastAcceptedSeq, completingFiledAt) = _walk(st, buttonIsHost, ordered);
    }

    /// The actual seq-walking loop (task 5 step 6), factored out of
    /// `replay` for stack-depth reasons only (see `replay`'s own comment).
    function _walk(State memory st, bool buttonIsHost, Cand[] memory ordered)
        internal
        pure
        returns (
            TermKind kind,
            bool folderIsHost,
            State memory finalState,
            uint256 lastAcceptedSeq,
            uint256 completingFiledAt
        )
    {
        kind = TermKind.NONE;
        lastAcceptedSeq = NO_SEQ;

        uint256 idx = 0;
        uint256 nextSeq = 0;

        while (true) {
            bool found;
            Cand memory chosen;
            (idx, found, chosen) = _nextCandidate(ordered, idx, nextSeq, st.toActIsHost);
            if (!found) {
                // Pending: no valid continuation at this seq.
                break;
            }

            bool ok;
            (st, ok) = applyAction(st, st.toActIsHost, chosen.action, chosen.amount);
            if (!ok) {
                // A candidate existed and signed by the right key, but was
                // not a legal continuation (wrong action for the current
                // legal set, or an out-of-range bet amount) — the chain
                // has no valid continuation here either.
                break;
            }
            lastAcceptedSeq = nextSeq;
            nextSeq++;

            if (st.hasFolded) {
                kind = TermKind.FOLD;
                folderIsHost = st.foldedIsHost;
                // completingFiledAt stays 0 for FOLD (decision 3's spec —
                // a fold owes no share duties at all).
                break;
            }

            if (st.closed) {
                bool complete;
                (st, complete) = _cascade(st, buttonIsHost);
                if (complete) {
                    kind = TermKind.COMPLETE;
                    completingFiledAt = chosen.filedAt;
                    break;
                }
                // else: a fresh, un-auto-closed street — continue the
                // outer loop, waiting for `nextSeq`'s candidate.
            }
        }

        finalState = st;
    }

    /// Scans `ordered` starting at `idx` for every entry filed at `seq`
    /// (0, 1, or 2 of them, mirroring the two-slot storage model), keeping
    /// whichever one matches `expectedIsHost`. A wrong-signer entry is
    /// consumed (advances the returned index) but never selected — the
    /// M1 property (a candidate from the wrong signer at a seq is
    /// skipped/ignored, exactly like no candidate at all).
    function _nextCandidate(Cand[] memory ordered, uint256 idx, uint256 seq, bool expectedIsHost)
        internal
        pure
        returns (uint256, bool found, Cand memory chosen)
    {
        while (idx < ordered.length && ordered[idx].seq == seq) {
            if (ordered[idx].signerIsHost == expectedIsHost) {
                chosen = ordered[idx];
                found = true;
            }
            idx++;
        }
        return (idx, found, chosen);
    }

    /// Repeatedly calls `closeAndAdvance` while the (possibly freshly
    /// advanced) street is itself already closed — the all-in-runout
    /// cascade (betting.ts:195, task 5 step 5) that can carry a hand
    /// straight to river with no further action filed. Returns `complete
    /// = true` the moment `closeAndAdvance` reports the river was already
    /// closed (mirrors `nextStreet` returning `null`); `complete = false`
    /// once a freshly advanced street is NOT auto-closed (someone must
    /// still act — the outer loop resumes waiting for a candidate).
    function _cascade(State memory st, bool buttonIsHost) internal pure returns (State memory, bool complete) {
        while (st.closed) {
            bool live;
            (st, live) = closeAndAdvance(st, buttonIsHost);
            if (!live) {
                return (st, true);
            }
        }
        return (st, false);
    }
}
