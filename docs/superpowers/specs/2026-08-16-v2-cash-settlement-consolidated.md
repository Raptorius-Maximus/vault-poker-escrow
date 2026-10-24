---
Replaces: docs/superpowers/specs/2026-08-15-v2-cash-settlement-design.md
---

# V2 — cash game settled by stacks: consolidated design

**Status: READY WITH DECLARED DEFERRALS — the sixteenth cold check,
2026-08-17.** Revision 8, consolidated from eight proposals and sixteen
cold checks. The sixteenth checker reconstructed the fifteenth's CRITICAL
one step earlier in time, swept every named target and the newest text,
and reported: *"the design survives everything on in-model grounds … a
true clean at the rule level, and I say so having genuinely tried not to
find it. No route back required. Contract work can start on §11's order as
written."* Its three LOW word-pins — clarifying sentences, no rule
changes — are applied in §1.0 below. The deferrals are exactly §8's
declared costs and §11.2's gated rerun (marker latency at n=3; top-up
letter to ops on record). **Design phase closed. The build follows §11's
order; §11.2(a)'s congestion-tail rerun and §11.4's contract test suite
are the standing verification gates.**

**Supersedes** the Pass 6 spec, which is frozen at a design killed five checks
ago and is kept only because the parking doc references its D-numbers.
**History and reasoning** — every proposal, every rejection, every finding —
live in [the parking doc](../parking/v2-cash-game-settlement.md). This file is
what to build from; that file is why.

A cash game whose buy-ins are escrowed on chain and paid out by final stacks,
with rebuys. The escrow never learns who won a hand it was not asked about —
and when it *is* asked, it answers only from evidence both players signed in
advance.

---

## 0. The two ideas everything follows from

The chain cannot see the cards, the network, or which player walked away. Nine
designs failed by asking it to infer those things.

The tenth failed differently, and its lesson is now load-bearing:

> **A penalty that both parties can jointly rescind is not a penalty.** Any
> rule of the form "both bonds return if and only if both players sign X"
> hands the refuser and the victim a joint surplus — the bonds — to split by
> choosing X's content. The refuser bribes the victim with a slice of the
> money the fiction recovers, the victim accepts any positive slice, and the
> deterrent evaporates. No choice of X fixes this, because the chain cannot
> tell a truthful mutual receipt from an agreed lie: both carry two real
> signatures.

So revision 3 rests on two ideas instead of one:

1. **Each player's outcome must never depend on the counterparty's
   cooperation.** Bond return is earned unilaterally, by doing attestable
   things — filing, posting, revealing — never granted mutually. There is no
   joint surplus anywhere, so there is nothing to bargain over.
2. **The chain protects settled bets, and an interrupted hand finishes under
   its arbitration.** Everything a player has verifiably wagered is settled
   from evidence — signed actions, committed shares — without needing the
   loser's signature on the outcome. And a hand the wire failed to finish is
   not guessed at, refunded, or folded by fiat: it is *played to its end on
   chain*, with poker's own option set, so every hand terminates one of
   poker's own three ways — fold, showdown, or runout. (Revision 3 cancelled
   unfinished hands instead; the eleventh check showed any cancel branch a
   present loser can reach prices folding at zero, and revision 4 removed
   it.) You can never gain money you had not already won, and you can no
   longer un-risk money you have wagered by refusing to finish wagering it.

What makes idea 2 possible is a fact of the existing crypto layer, verified in
source this revision: a player's decryption share for every card is
`decryptionShare(ct, key)` — a pure function of the post-shuffle deck and their
fixed key (`elgamal.ts:71`, built per position by `makeShares`,
`protocol.ts:186`). **The moment the shuffle ends, all 52 of a
player's shares are already determined**, so they can be committed to before a
single card is looked at, and a posted share can be checked against that
commitment and against the deck (`verifyDleq`) by a contract, cheaply. The
"anchorless" objection that killed on-chain reveal verification (§10, old
§8.4) is gone: the hand-start marker *is* the anchor.

---

## 1. Settlement

### 1.0 One good ending; every other ending is decided per player

**Rewritten 2026-08-17 after the tenth cold check.** Revision 2 had one good
ending and made every other ending burn both bonds — which turned bond return
into a mutual-consent event, and finding A walked in through the consent
(tenth check, finding 1).

The good ending is unchanged:

> **Both players sign a receipt marked `final`.** It pays out at the stacks it
> names and **both bonds return** — except a bond already forfeited by
> on-chain proof. Either player may submit it alone; it does not matter
> which.

**Proven burns are irrevocable** (fifteenth check, finding 1). Three burns
rest on proof the chain itself holds — equivocation (two distinct
signatures, one node), the fourth resolution row (an all-checks-passing yet
undecodable deck), and a duty whose deadline passed unmet. A `final` filed
afterwards settles the stacks it names and closes the session, but the
forfeited bond stays forfeited. Three pins from the sixteenth check, each
a sentence the rules already imply: **bond disposition defers to the
misconduct evidence on file at payout execution — the evidence window for
burn proofs survives a final**, so racing a final past the proof suppresses
nothing; **an equivocation pair is admissible only if complete on file
within phase 1** (which is why §6's cleared-storage refusal rule is
load-bearing and must not be relaxed without this pin); and **a burn is
proven the moment the facts establishing it are on chain**, whether or not
any transaction has yet computed it — proof is the filings, never the
computation event. Without this sentence the equivocation burn
was a penalty both players could jointly rescind — the cheat buys the
victim's signature on a final with a one-chip improvement, exactly §0's
law — and pre-emptively un-betting a transmitted losing wager turned
profitable. With it, the rewrite costs 1100 to recover at most `M_i`, and
dies.

Every other ending now runs through the dispute path (§5), where **each bond's
fate is decided by its own owner's conduct alone**:

> **Your bond returns if and only if you performed your dispute duties** —
> file your receipts, file your action chain, post your committed shares
> (§5.2). Whether your opponent cooperates, defects, or vanishes has no
> bearing on whether your bond comes back. Bonds are returned or burned,
> **never** paid across.

**Why this is executable.** Every duty is a unilateral, on-chain, attestable
act: a filing happened or it did not. Nobody asserts anything about the
opponent; nobody's claim is trusted; no timing or liveness is inferred —
"failed to file signed artefacts within a fixed window" is the same primitive
V1's `claimByDefault`/`iAmHere` already ships.

**What this buys.** An ordinary disconnect still costs nothing: the hand
auto-folds off-chain where a fold is reachable, the clients reconnect, play
continues, the session still ends `final`. A crash *during* a showdown is now
survivable too — the crashed player returns any time inside the window, posts
their shares, and the hand completes at its true result (§6's share
persistence; this closes the tenth check's finding 5). Only conduct burns:
failing your own duties while your opponent performs theirs.

### 1.1 Receipts

A **receipt** is signed by both players at a hand boundary:

    (contract, chainid, session, hand, subseq, hostStack, guestStack,
     hostDeposit, guestDeposit, final)

Contract address, chain id and session id are bound into the hash. Without them
a receipt from one match replays into another (finding D); `Channel.sol` already
binds all three today. A **type tag** distinguishes a receipt preimage from
every other signed artefact.

`final` is the flag §1.0 turns on. It is signed, so neither player can add it
to the other's receipt. `final` receipts are **ordered and terminal** (tenth
check, finding 3): a `final` settles only at or above the floor, the highest
`(hand, subseq)` `final` wins if more than one verifies, the contract closes
the session on paying one out, and the client refuses to deal another hand
after signing one. "We changed our minds and kept playing" after signing
`final` is not a supported state — the session is over; open a new one.

`(hand, subseq)` is a **total order**. `subseq` exists because Q8 puts two
receipts at one hand boundary — pre-rebuy and post-rebuy — and equal hand
numbers otherwise cannot supersede each other (N10), which would brick a session
rather than resolve it.

**Receipt `(0,0)` is mandatory and no hand is dealt before it exists.** It
records the opening stacks and the opening deposits and carries both signatures.
Without it there is a free escape on hand 1 (ninth check, finding 4): with no
receipt in existence, a player who loses an all-in on the first hand refuses,
and the winner has nothing to file. Receipt `(0,0)` means the winner always
holds something.

Invariant, checked on settlement:

    hostStack + guestStack == hostDeposit + guestDeposit

and each recorded deposit must not exceed what the contract actually received.

### 1.2 The settlement rule

**Highest `(hand, subseq)` wins,** subject to §4's floor — **overlaid with the
live hand's dispute result where one exists (§5.3).** A receipt for hand N−1
plus an adjudicated outcome for hand N settles at the receipt's stacks moved by
the adjudicated pot. Deposits not accounted for by the settling state are
refunded to whoever made them.

### 1.3 When nobody files: refund the deposits

If the window closes with **no valid filing from either player at all**, every
deposit returns to whoever made it and **both bonds burn**. The session unwinds
completely.

Unchanged from revision 2, and the tenth check re-verified both halves: it is
not reachable by one player (receipt `(0,0)` means whoever is ahead always
holds something worth filing and always strictly prefers filing it — worked at
200/1800, where the unwind costs the behind player 300 more than filing), and
reaching it never pays (gain = `myDep − myStack` ≤ `myDep` < `1.1 × myDep` ≤
bond). Both-silent means both genuinely gone.

**One new pre-play branch (tenth check, finding 6):** if the window closes and
**no marker was ever posted and no receipt `(0,0)` was ever filed**, the session
never started — deposits *and both bonds* return in full. A laptop that dies
between depositing and the `(0,0)` exchange costs gas, not 1100. This is
attestable (absence of any filing for a session that never marked a hand) and
is V2's analogue of V1's `cancelOpen`.

### 1.3a What the bond now covers, and what evidence covers instead

**Rewritten 2026-08-17.** Revision 2 asked the bond's arithmetic to carry the
whole design, and the tenth check showed the arithmetic was sound but the burn
was rescindable — deterrence failed not in magnitude but in enforceability. In
revision 3 the load is split:

**Evidence settles every completed wager.** A refusal at showdown, the attack
every check since the fifth has circled, is now pointless rather than
expensive: the victim files the action chain (proves the pot and that betting
completed) and the shares, and the contract settles the hand at its true
result without the refuser's signature (§5.3). The refuser's options are to
sign the truth or watch the chain conclude it anyway, minus their bond.

**The bond covers the branches evidence cannot reach**, and for those the
tenth-check-verified inequalities still hold, evaluated at the session's
declared maxima (§2):

- *Vanishing entirely* (no duties performed): your bond burns. Recoverable by
  a refuser whose victim is also absent for the whole window is bounded by one
  hand's contribution ≤ `min(stacks)` ≤ `T_max/2` < bond.
- *The full unwind* (§1.3): recoverable is at most your own deposits ≤ `M_i`
  < bond.

**Strictly worse in every reachable case, with no indifference point** — the
same 10% margin, now attached to a burn no bargain can lift, because no mutual
signature anywhere restores a burned bond.

**Declared, not solved:** a refuser still chooses their moment with full
information (§10 keeps commit-and-accept dropped). What they can no longer do
is profit from the choice: completed wagers settle from evidence, and an
interrupted hand plays to completion on chain (§5.3), where their options are
poker's own — fold and lose the pot they were losing, or play on. (Restored
in revision 4: revision 3's version of this claim was falsified by its cancel
branch, which the eleventh check showed refunded any loser willing to dispute
instead of folding. The claim holds now only because that branch is gone.)

### 1.4 Burning, concretely

**On the EVM a burn is the absence of a payout.** `Channel.sol` has no owner, no
sweep, no `selfdestruct`, and computes payouts from `s.buyIn` rather than
`address(this).balance`, so residue is permanently inert. No sink needs building.
(Verified against source by the tenth check.)

Two conditions, both load-bearing:

- **Per-session accounting only. Never read `address(this).balance`** — or one
  session's residue becomes another's payout.
- Track `burned` explicitly and assert, per session:
  `depositsIn + bondsIn == paidOut + burned`.
- **Burns are idempotent per bond** (fifteenth check, finding 3). One
  player can earn several burn sources in one dispute — equivocate at
  dispute-open, then miss a grace — but a bond burns once; `burned` credits
  it once. A burned-bond player can still win the pot (the frozen chain
  decides the pot; the bond is conduct): allowed, coherent, and now stated.

---

## 2. The bond: declared depth, fixed at the door

**Rewritten 2026-08-17 after the tenth cold check (finding 4).** Revision 2
sized the bond on the last mutual receipt, which made one player's rebuy raise
the *other* player's required bond mid-session — a two-party payment obligation
with no enforcement, costlessly vetoed by whoever was ahead. V2's one
distinguishing feature was optional exactly when it mattered.

Revision 3 moves the whole negotiation to the door, where poker already puts
it:

> **At session open, each player declares the most they might ever have on the
> table — their buy-in plus every rebuy they may want, `M_host` and
> `M_guest`.** These are table stakes, agreed like blinds are agreed. Then:
>
>     bond_i = 1.1 × max( (M_host + M_guest) / 2 , M_i )
>
> posted in full before receipt `(0,0)`, **fixed for the whole session**, held
> segregated outside the playing stack, and **burned — never paid to the
> counterparty.**

This is revision 2's formula — the one the tenth check re-derived from scratch
and could not break across eight constructed cases — evaluated at the declared
maxima instead of the live receipt. Live deposits never exceed the declared
maxima (§3 refuses to credit past them), so the posted bond dominates the
required bond at every receipt the session can ever produce: the coverage
proof carries over pointwise, and **no top-up obligation can ever arise
mid-session**. Nothing is asked of the player who is ahead, so there is
nothing for them to veto. Finding 4's griefing lever (an unmatched 10,000
rebuy obligating the opponent) is gone for the same reason: an unmatched
deposit changes nobody's bond, because nobody's bond ever changes.

**With equal declared depths the two terms coincide: your bond is 110% of the
most you are willing to lose.** That is the common case and the only sentence
the UI needs, plus its consequence: *"play deeper than you declared and the
table simply won't credit it — reopen at a bigger table instead."*

**Why each piece** (unchanged in substance from revision 2, re-anchored):

- **Half the declared total** covers the one-absent-victim branch: recoverable
  is bounded by the smaller stack, which can reach half the total whatever the
  chip distribution.
- **Your own declared max** covers the full unwind: it returns your deposits,
  and your deposits never exceed `M_i`.
- **The 110%** removes the indifference point (ninth check, finding 5).
- **Deposits, not deposits-plus-bonds**, in the totals — stated because that
  is the formula an implementer reads first.

Segregation is the point: a penalty payable from chips is unpayable exactly when
the refuser is broke, which is when it is needed (P4). Burning rather than
paying across is what stops *starting* a dispute being profitable — and with
per-player bond fate (§1.0) it cannot even be bargained back.

### 2.1 Earning a lower bond — deferred to the reputation arc

Unchanged from revision 2. A 110% bond is a heavy entry cost, and the intended
relief is **reputation, not a smaller number**: a cheat must grind dozens of
honest matches to earn a cheap bond, then gets one score capped at a single
buy-in, and their identity is spent. Cheating loses on *rate*. V2 ships with
the flat rule; see [the reputation arc](../parking/reputation-and-profiles.md).

**UI obligation:** the bond must be shown with its consequence attached —
*"if you desert this session, you lose this"* — before either player deposits.

## 3. Game rules

- **A timeout is always a fold. Never an auto-check.** Verified at the engine
  level: `applyAction` sets `b.folded`, `afterAction` calls `settleHand`, and no
  branch touches `makeShares`/`acceptShares`, so a fold reaches phase `done` with
  zero decryption shares. An auto-*check* advances the street and then waits on
  the peer's shares, which die with their tab — it deadlocks. The dispute path
  honours the same rule on chain: absence mid-betting scores as a fold, never
  as a free showdown (§5.3).
- **Every action is signed and chained.** Each action's signature covers
  `(contract, chainid, session, hand, seq, action, amount, prevActionHash)`,
  with its own type tag. *(Corrected 2026-08-17, arc AF-2: the earlier
  "alternates signatures" wording was loose — the same seat legitimately
  acts at consecutive seqs across a street boundary, since the button acts
  first preflop and last postflop (`betting.ts:56,196`). What actually
  holds is stronger and is the rule: the replayed betting state machine
  determines the unique legal actor at every node, so no one signs out of
  turn, forges the other's actions, or forks across keys) — and a truncated filing is beaten by the
  counterparty filing the longer chain, which bears the truncator's own later
  signatures. This is the artefact that makes a pot attestable (§5.3). It is
  **not** the commit-and-accept §10 dropped: nothing is acknowledged, nothing
  blocks on the wire or the chain, and play proceeds exactly as today —
  the signatures are evidence, produced anyway, used only in disputes.
- **No hand is dealt while the previous hand's receipt is unsigned.** The ninth
  check's finding 6: §1.3a's per-hand bound holds only if the last mutual receipt
  is the state at the start of the current hand. An honest client would already
  stop; the safety proof depends on it, so it is a rule. (Enforceable by one
  honest client alone — dealing requires both sides' `hello`/`shuffle`;
  re-verified in source by the tenth check.)
- **An un-receipted deposit is not chips — and that is the whole rule.**
  Rewritten for the tenth check's finding 4, which caught revision 2 saying
  both "no hand is dealt while an un-receipted deposit exists" and "a stuck
  rebuy resumes the table after 30 seconds". The second sentence was always
  Q8's real content: money that no mutual receipt names does not exist at the
  table, cannot be lost, cannot be rolled back past, and is refunded at
  settlement as unaccounted (§1.2). The table never blocks on it. A rebuy
  becomes chips at the next hand boundary, in a receipt naming it and the
  resulting stacks — or it never becomes chips at all, and only its sender is
  affected. N3's underflow stays closed.
- **Rebuys: any time between hands, never mid-hand.** Never mid-hand is
  absolute; otherwise a player shoves, sees it go badly, and tops up to
  survive.
- **Rebuys credit only up to the declared depth (§2).** The contract refuses a
  deposit that would push a player's total past their declared `M_i`. Playing
  deeper is a new session at a bigger declared table — a symmetric, voluntary
  renegotiation, not a mid-session obligation on the counterparty.
- **Chips can be added, never removed.**
- **The buy-in is 200 big blinds**, and the table shows the real-money equivalent
  beside the chips. Truthful only because cash-game blinds are fixed, so the rate
  holds all session.
- **Either player may stop, effective at the end of the current hand** — at
  which point both sign the `final` receipt of §1.0, and the session is over:
  the client will not deal past a `final` it signed (§1.1).
- **No per-hand pot cap, and deep all-ins survive.** The declared depth is not
  a pot cap: any pot the declared stakes can produce is playable, and §2's bond
  covers it at those stakes. Nothing shrinks a hand.

---

## 4. The hand-start marker: floor, checkpoint, and anchor

**Rewritten 2026-08-17 after the tenth cold check (findings 1 and 2).**
Revision 2 posted the previous hand's *receipt* as a floor and relied on an
incentive argument — "the party motivated to post is the party the floor
protects" — that failed three separate ways against an offline victim.

The posted artefact is now the **hand-start marker**, signed by both players
before hand N's first card:

    (contract, chainid, session, hand N, hash of receipt N−1,
     deckRoot, hostShareRoot, guestShareRoot,
     hostCardPk, guestCardPk, button, sb, bb)

- `deckRoot` commits the post-shuffle deck both clients just verified.
- Each `shareRoot` is a Merkle root over that player's 52 decryption shares —
  computable the moment the shuffle ends (§0), before anyone has seen a card.
- **Each `cardPk` is that hand's card public key, straight from the `hello`
  exchange** (twelfth check, finding 2). Without it, on-chain DLEQ proves a
  share consistent with *some* key, and a client that pre-commits a
  shareRoot built from a wrong key passes Merkle and DLEQ at every losing
  showdown while the combined decryption decodes to nothing — fault
  unassignable, finding A relocated into the crypto layer. With the pk in
  the marker, the check is anchored, and the **totality lemma** holds:
  for a deck whose plaintexts the honest client verified against the 52
  protocol card points before signing, *Merkle inclusion + DLEQ against the
  marker's pk passing for both shares implies the combined decryption
  decodes to a card.* No undecodable row exists. An honest client signs the
  marker only if both pks match the `hello` it received.
- Button and blinds make the betting state machine reconstructible on chain
  (§5.3) and give the blinds a signed artefact at last (§9.15).

An honest client signs the marker only after the shuffle proofs verify, so
both signatures on a marker attest an agreed deck under agreed keys. The
marker is what §9.15 asked for, the checkpoint §4 used to describe, and the
anchor that resurrects scoped reveal verification (§10) — one artefact,
three jobs.

**A first marker is always admissible during the window** (twelfth check,
finding 6). Hand N is played while marker N's transaction confirms, so a
dispute opened inside that gap would otherwise find the live hand invisible
and refund a fold played within it. Filing the both-signed marker for the
live hand is therefore a §5.2 duty like any other: it carries both
signatures, either player may file it, and it anchors the hand whenever it
lands inside the window. The duplicate-rejection rule applies unchanged.

**The marker is a floor and an anchor. It is never a settlement state.** No
receipt below the marked hand's predecessor can settle, and settlement must
*account for* the highest marked hand: receipt ≥ N, or receipt N−1 overlaid
with hand N's dispute result (§5.3). Filing receipt N−1 alone against a marker
for hand N is not a settlement — it is one side of a dispute, and the window
gives the other side its say. **This closes the tenth check's finding 2**: the
one-filing branch can no longer treat silence as "no better receipt exists",
because the marker says on chain that a later hand began.

**Marker sequencing, pinned (eleventh check, finding 3) — contract rules, not
client conventions:**

- The contract **rejects a second marker for a hand number that already has
  one confirmed.** Both signatures are required to post at all, and an honest
  client signs one marker per hand, so a duplicate needs both players signing
  against themselves; the rule exists so the settled state is single-valued
  anyway.
- A marker for hand N is **accepted only if its embedded receipt hash matches
  a receipt at hand N−1** already seen by the contract or filed alongside it.
  Marker continuity is verified, not assumed.
- **The marked live hand is the highest confirmed marker with no valid
  receipt at or above its hand number.** Single-valued by the two rules
  above.
- Where a rebuy split hand N−1 into `(N−1,0)` and `(N−1,1)`, the overlay
  baseline is **the receipt the marker's embedded hash names** — which is
  the highest subseq, because marker acceptance verifies continuity against
  it and a mid-hand subseq needs both signatures an honest client withholds
  (fifteenth check: the retroactive flip is unreachable; stated as one rule
  so the builder implements one rule).

**Dealing hand N+1 is gated on marker N being confirmed on chain.** A failed
or slow post pauses the table — it never forfeits anything (the compulsion §4
rejected stays rejected; a pause is not a penalty). This is what makes "the
rewind window is one hand" true rather than aspirational: the floor can lag
the live hand by at most the hand in progress, which is exactly the distance
§1.3a's arithmetic bonds and §5's dispute path adjudicates.

**Cost and latency are now structural, and still unmeasured.** One small L2
transaction per hand sits between hands. §11 gates the build on measuring both
the money and the wall-clock wait on Base Sepolia; if the wait is unplayable,
this design needs a different floor cadence and returns to design. Declared in
§8.

---

## 5. Windows and disputes

### 5.1 The window: two phases, both scheduled in advance

**Phase 1 — evidence. 24 hours, fixed length, known in advance, not chosen
by whoever moves first.** Either player announces settlement on chain;
within the window each side files (§5.2). **Nothing is played and — one
exception — nothing resolves during phase 1**: a mutual `final` settles at
any time, because it is the good ending rather than a dispute outcome, and
it never restores a proven burn (§1.0). Otherwise phase 1 exists so that
late-filed evidence enjoys the whole window unconditionally: a crashed player who returns at hour 23 with
the fuller action chain is exactly as protected as one who filed at minute
one. 24 hours covers a night's sleep and a dead laptop. **Each side's app
files automatically on opening**, so no expertise is required and nobody
needs to know a window exists.

**Consolidation, at hour 24 exactly** — phase 1 is the half-open interval
`[open, open + 24h)`: a block whose timestamp equals `open + 24h` is
phase 2 (fourteenth check, finding 5a). The prevailing chain freezes: built
node by node from the actions on file, taking at each node the
earliest-filed valid action (same-block ties: lowest hash — a total order).
Consolidation needs no transaction of its own: the frozen chain is a pure
function of phase-1 filings, computed lazily by the first interaction that
needs it. **Two *distinct* actions — differing in action or amount — from
the same key at the same `(session, hand, seq, prevActionHash)` are
cryptographic proof of equivocation** — one-sided, attributable — and burn
the equivocator's bond; the earliest-filed stands for the replay.
(Identical duplicates are the normal case — both players file overlapping
segments — and are simply deduplicated.) **This burn is proof of misconduct
only because §6 requires write-ahead signing**: a client persists a signed
action *before* transmitting it, and a restored client never re-signs at or
below its persisted tip, so no crash can innocently produce the pair
(fourteenth check, finding 3). If the frozen hand is terminal *and its
posting graces have all matured*, the dispute resolves; otherwise **phase 2
begins.**

**Phase 2 — play (§5.3).** The pending hand is finished from the frozen
state, starting at the hour-24 appointment every participant has known
since the dispute opened. **Stated honestly** (fourteenth check, finding 2):
phase 2 is not "show up once". Its requirement is a live client through the
episode and a human reachable within any six-hour stretch in which the
decision is theirs — because street timing depends on both sides' filing
choices, an opponent can steer *when* within the bounded episode your turn
arrives, though never *whether* you get your six hours, and never for more
than the pot (§8.12). Every deadline is knowable at least six hours before
it can bite (each is born by an on-chain event). Two mitigations are
legal by design: **acting blind is always legal** — no action's legality
depends on a card, so a to-act player need never wait for postings — and a
client may carry **standing instructions** (check-or-fold when the bank
runs low, as online poker sit-outs do). Clients should file with margin
against sequencer delay; a filing and a deadline in the same block counts
as met (finding 5b).

**A `final` receipt short-circuits everything** — at or above the floor,
highest wins, terminal (§1.1). A partner whose laptop dies *after* signing off
costs nobody anything.

### 5.2 Dispute duties

Within the window, each player independently:

1. **Files their receipts** (the client already holds them).
2. **Files the live hand's marker**, if it has not yet confirmed (§4).
3. **Files their action chain for the marked live hand**, if one is in
   progress past its marker.
4. **Posts their decryption shares for every position the hand can need** —
   hole cards at a showdown, board cards for a runout, and any posting that
   new on-chain betting creates — each share checked against the marker's
   `shareRoot` (Merkle) and against the marker's `cardPk` and the deck
   (`verifyDleq` — the scoped reveal verification §10 readmits, measured at
   ~3.0M gas per share, dispute-only).

**Every mechanical posting is a duty, never a bank item, and every duty's
deadline is `max(hour 24, birth + 6 hours)` — where birth is the on-chain
filing time of the action that made the position required** (fourteenth
check, finding 1: a duty keyed to a phase label instead of its own birth
could be sprung in phase 1's last block, unmeetable by construction). The
price of failing a duty is the muck price — your bond burns and the unshown
hand resolves against you. Two consequences, both load-bearing:

- **A hole-share duty is born only by the filing of a betting-completing
  action.** Until the frozen or extended chain completes betting, hole
  shares are not owed, and withholding them is *correct* — posting them
  against a pending hand would let a counterparty who holds their own 52
  shares locally read your cards and then decide with perfect information.
  The birth anchor removes the trap in both directions: the completing
  action is irrevocably on file before the victim's shares are due, so the
  withholder is committed before they could ever peek.
- **A frozen-terminal hand with unexpired posting graces resolves at its
  last grace, never at consolidation.** "Pending" includes pending
  postings, not just pending decisions; the muck row fires only after a
  duty's own deadline has passed. One rule, one price, wherever in the
hand the posting falls due and whether betting completed on the wire or on
the chain (twelfth check, findings 4 and 5: revision 4 had three regimes
1100 apart and an undeclared six-hour deadline on the live hand; now the
only thing a time bank can ever cost is a *decision*, §5.3). A crashed
player has the whole window to return and post — §1.0's promise, true as
written.

**Your bond returns if and only if your duties are met.** All are unilateral
acts. A player with nothing to file in a category owes nothing in it. The
client performs all duties automatically on window-open; the duties exist so
that a *modified* client's defection is attestable, not as a chore for
honest players.

### 5.3 Resolving the marked live hand: it finishes on chain

**Rewritten 2026-08-17 after the eleventh cold check.** Revision 3 sorted the
live hand into complete/incomplete and *cancelled* the incomplete — which
filed a fold (poker's most common ending) under "incomplete" and refunded the
folder, and let any loser dispute instead of folding. There is no cancel
branch any more. Poker has three ways a hand ends — fold, showdown, runout —
and the dispute path ends the hand one of those three ways, no other.

The contract reconstructs hand N's state from **the frozen chain of §5.1's
consolidation** (either player may file any segment during phase 1; a
truncation loses because the fuller chain carries the truncator's own
signatures and enjoys the whole evidence window) plus the marker's button
and blinds.

**If the frozen chain already shows a terminal state**, it settles from
evidence:

| Terminal state | Rule | Outcome |
|---|---|---|
| Chain ends in a signed `fold` | **A fold is a completed decision** (eleventh check, route back 1) | Pot per the chain to the non-folder, overlaid on receipt N−1. **The folder's bond returns** — folding is legal, attestable, complete |
| Betting complete (river closed, or all-in with runout due) — both posted every required share | **Cards decide.** Each posted share passes the triple check below; hole cards and pending board decrypted; hands evaluated | Pot — attested by the chain — moves per the result, overlaid on receipt N−1. Both bonds return |
| Betting complete — one side posted every required share, the other missed any position | **Muck rule.** Refusing to show at showdown is a live-poker muck. "Posted" is per-position: every position the terminal state requires from that player, each passing the triple check | Pot to the complete poster; the incomplete side's bond burns |
| Betting complete — **both** sides missed a required position | **Symmetric muck** (fifteenth check, finding 2: both machines dead after chains auto-filed — "resolves against you" applied to both is contradictory) | Both bonds burn; settle at the receipt baseline |
| All checks pass, yet a combined decryption fails to decode, or the deck itself is malformed (duplicate cards) | **Both signers misbehaved** — the marker carries both signatures over deck, roots and keys, and one honest client's local verification (§4's proviso) makes this state unreachable for it | Both bonds burn; settle at the receipt baseline. Total resolution: no revert path exists (thirteenth check, finding 6) |

**The triple check, in full** (thirteenth check, finding 5 — Merkle against
the share root alone is not enough): a posted share for deck position `p` is
valid iff (1) the share is Merkle-included in that player's `shareRoot` at
leaf index `p`, (2) **the ciphertext it opens is Merkle-included in
`deckRoot` at the same index `p`** — the contract never takes `c1` from the
filer's word — and (3) the DLEQ proof verifies against the marker's `cardPk`
for that player and that ciphertext. With all three, the totality lemma of
§4 holds and no valid posting can fail to decode unless the deck itself was
dishonest — which is the fourth row.

**If the frozen chain shows a pending decision, phase 2 finishes the hand
from the frozen state** (thirteenth check: banks and evidence cannot share a
clock — an evidence filing must enjoy the whole window, a play deadline must
not be movable by a counterparty's filing schedule, and no admissibility
rule on filing times can serve both, so the phases are disjoint by
construction).

- **The frozen chain is the sole starting state.** Phase-1 filings can no
  longer change it; phase-2 actions are on-chain transactions, totally
  ordered by the chain itself, so the replay is a pure function of on-chain
  facts — there are no retroactive intervals anywhere.
- **The turn-player extends the chain** with a signed action filed on chain:
  `fold | check | call | bet` — the client's own four-action alphabet, `bet`
  covering raises (twelfth check, finding 3a). Amounts are **canonical
  post-clamp integers**: the client signs the *effective* amount its engine
  actually applied, and the on-chain validator enforces exact legality
  against the replayed state (§9.18). Non-bet actions sign `amount = 0`,
  and the validator requires it. A phase-2 filing that is out of turn,
  illegal, or mis-amounted reverts.
- **On chain, fold is legal at any to-act node — in either phase.** The
  client's engine offers fold only against a bet; the on-chain machine
  additionally accepts an open-fold as explicit concession, and one inside
  a phase-1-filed segment is valid at consolidation (fifteenth check,
  finding 5b — a concession only ever hurts its signer). Honest
  client-generated wire segments never contain one, so replay of honest
  play is unaffected.
- **Street transitions run out on postings.** A posting that becomes due
  during phase 2 — showdown shares after an on-chain call, the next board
  card after a street closes — is a duty with a **six-hour grace from the
  moment it becomes due** (thirteenth check, finding 3: a duty born at hour
  28 cannot owe hour 24). Missing its grace is the muck price: bond burns,
  hand resolves against the non-poster. Phase-1 duties keep the plain
  24-hour deadline.
- **Each player has a cumulative six-hour time bank for decisions**, metered
  by block timestamps. A player's clock runs exactly while they are to act
  on the frozen-plus-extended chain **and every counterparty-side posting
  their decision depends on is on file. A player's own postings never pause
  their own clock** (thirteenth check, finding 2) — the cards you need to
  see are opened by *your opponent's* shares; yours you hold locally. **An
  empty bank is a fold at the node where it emptied** — §3's
  timeout-is-always-a-fold. Six hours is generous because a human on a
  phone must be able to answer; an honest client answers in seconds, so two
  present players finish a disputed hand in minutes.
- **The bank decides the hand, never the bond.** A bank-fold is the pot
  consequence of poker, nothing more; bond fate rides the duties alone.
  The only thing a crash can cost through the bank is a *decision* — the
  hand you would have folded anyway — and it can only do that at the one
  appointment printed on the dispute.
- **Termination is guaranteed.** Obstacles in phase 2 are sequential, so
  the first bank to empty folds the hand; every grace is finite; the
  episode ends at a fold, a runout, or the last grace expiring. (The
  both-banks-empty branch of revisions 4–5 is deleted as unreachable: a
  second bank can never start consuming at a node the first bank's fold
  already terminated.)

**Why the fiction is dead.** The tenth check's finding 1 worked because the
truth needed the refuser's signature, so the victim's best move was to sign
the refuser's lie. Now the truth of every completed wager is provable by the
victim alone — chain plus shares — and the victim's bond is safe by their own
conduct regardless. A fiction must beat *truth-plus-bond* for the victim, so
the refuser would have to pay more than the pot they are trying to recover.
There is no surplus to split, so there is no bargain.

**Why refusing-to-finish is dead too** (the eleventh check's deeper cut). In
revision 3, a loser facing a decision could dispute *instead of* folding and
be refunded. Now disputing **is** playing on: the same fold that loses the
pot off-chain loses it on-chain, the same call faces the same showdown, and
walking away mid-dispute is the fold the bank scores. There is no fourth
option, so there is nothing to prefer over poker.

**Why the winner cannot abuse the door either.** A showdown winner who
withholds their receipt signature to force a dispute gains nothing: the
dispute awards exactly the pot the chain attests — the same pot the receipt
would have named — minus their own gas. A player who opens a dispute against
a live opponent mid-hand buys only an expensive, slow end to the session with
the hand's true result protected — §3's "either player may stop" exercised
rudely, declared in §8.

### 5.4 Filings, restated

At the dispute's end, the settling state is: **the highest valid `final`,
else the highest valid receipt overlaid with the live hand's §5.3 result,
else §1.3.** Each player's bond resolves per their own duties and graces, in
every branch.

**The dispute's end is deterministic and bounded.** Phase 1 ends at hour 24
exactly. The dispute ends at the frozen hand's termination *and* the
maturity of every born grace — a fold (signed, open, or by bank), a
completed runout, or the last unmet grace expiring. Worst adversarial case:
two full banks (12h) + a six-hour posting grace per street transition (≤ 4)
+ one showdown grace (the fourteenth check's fix adds it) + honest runtime —
**the whole dispute ends inside ~66 hours.** Every deadline is born by an
on-chain event and known at least six hours before it can bite; none is
computable earlier, and the spec no longer claims otherwise (fourteenth
check, finding 2). Phase-1 evidence deadlines are never moved by anything:
a counterparty's filing schedule can never shorten your evidence window.

---

## 6. Keys and storage

- **Two keys, opposite persistence rules, deliberately.** The **card key**
  decrypts hole cards, lives in memory only, and **dies with the tab** — that
  is what guarantees a *finished* hand can never be reopened. The **session
  key** signs receipts and **must survive the tab**, or a crashed browser can
  never defend itself. Neither rule may be harmonised with the other.
- **Amendment, 2026-08-17 (tenth check, finding 5): the live hand's decryption
  shares survive the tab, and only they.** The 52 shares are determined at
  shuffle end and committed in the marker (§4); the client persists them
  encrypted exactly as it persists the session key, and **destroys them the
  moment the hand's receipt is signed**. A player whose laptop dies mid-showdown
  can therefore return any time in the window and post them — the crash and
  the cheat stop being byte-identical, which was finding 5's exact complaint.
  What §6 protects — finished hands stay sealed — is untouched: a share that
  outlives its hand by zero seconds reopens nothing. The cost is a narrow
  window in which one hand's shares exist on disk in ciphertext; declared in
  §8.
- **Signed actions are persisted before they are transmitted — write-ahead,
  no exceptions** (fourteenth check, finding 3). A restored client treats
  its persisted tip as binding, never re-signs at or below it, and **sends
  or files the persisted action itself** (fifteenth check, finding 4a — a
  persisted-but-unsent tip is still that player's move; re-deciding it is
  equivocation). This is what makes §5.1's equivocation burn proof of
  misconduct rather than proof of a crash. The one residual: cleared
  browser storage erases the tip, so §9.1's refuse-to-resume guard extends
  to the action tip — a client that cannot see what it last signed refuses
  to sign actions for that hand at all, and the player rides the dispute
  path instead (§8.4 already declares what clearing storage costs).
- The session key is deleted on settlement, and is per match, never reused.
- **Stored encrypted under a wallet-derived key**, so copied browser storage
  yields ciphertext alone.
- **Wallet determinism is tested at runtime, once per wallet address**, not
  taken from a compatibility list that goes stale on the next wallet release.
- A non-deterministic wallet persists the key **unencrypted with an explicit
  on-screen warning** — losing recovery to guard against profile theft plus a
  colluding opponent is the wrong trade.
- **Receipts persist in `localStorage`, not `sessionStorage`** (Q13 — they are
  in `sessionStorage` today, which dies with the tab, contradicting the whole
  recovery story).
- **The bare address is a recovery page**; receipts are stored under both
  origins so a returning player is covered wherever they land.

---

## 7. Hosting and scope

- Runs at `https://buyin.slipgate.me` and `https://poker.slipgate.me`.
  **HTTPS is a requirement, not a nicety** — Web Crypto is unavailable outside
  a secure context, so §6's encryption cannot run on a plain-http LAN address.
- **Operator override, recorded 2026-08-16:** `vault-handover.md`'s "Refuse to
  build" list says *"A hosted or shared deployment. Two people, two machines,
  local only."* §7 overrides it. The reason is that Web Crypto requires a
  secure context, which a LAN address cannot provide, so §6 cannot run without
  hosting. Raised as N7 in the second cold check and unrecorded until now.
- **The handover's cash-session deposit ceiling** ("say five buy-ins") is
  resolved by §2's declared depth: the ceiling is whatever the two players
  declare at the door, agreed symmetrically, priced into the bonds. No longer
  open.
- **Testnet only.** A mainnet path requires a new conversation before shipping.
- **No server-side storage without a further letter** — which is what gates the
  encrypted off-device backup.
- **V1 and V2 run side by side.** Freezeout keeps V1's contract; the
  duplication is explicitly temporary. Fold-in trigger: V2 has settled real
  matches across all its endings without an amendment to this spec.

---

## 8. Accepted costs — declared, not solved

Each of these is a known flaw kept deliberately. **Ratify them knowingly rather
than discovering them later.**

1. **A dispute is a legal, rude way to end the session early** (§5.3). Either
   player can force the table on chain at any moment; the live hand finishes
   at its true result and the session closes after it. What the disputer
   buys: the counterparty must finish one hand under time banks and pay
   filing gas, and loses the rest of the session they wanted to play.
   (Replaces revision 3's cancelled-hand leak, which the eleventh check
   showed was not marginal but a refund of any non-all-in loss. Nothing is
   refundable now; the residual nuisance is time, gas, and a shortened
   session, and the durable deterrent for serial cord-pullers stays social —
   the reputation arc.)
2. **A bad ending still costs an innocent-but-absent player their bond.** The
   burn is per-conduct now, so an innocent *present* player always keeps
   theirs — but absence is conduct the chain cannot excuse, and a player whose
   machine and backups all fail for a full 24 hours burns 110% of their
   declared max. Reduced from revision 2 (where every bad ending burned both
   bonds unconditionally), not eliminated.
3. **A relay outage that outlasts the window burns the bonds of everyone who
   could not file** — nothing distinguishes it from desertion. Filing goes to
   the chain, not the relay, so this requires losing chain access too; still
   listed because "my RPC died" is a real failure mode (§8.7 applies).
4. **Clearing browser data during an open window destroys that player's
   ability to defend themselves.** No local fix exists; the cure is the backup
   in §7, gated behind an ops letter.
5. **The 24-hour window only protects a player who shows up.** No notification
   path exists; the watchtower is parked. Vanish for longer and you can lose —
   but nobody *gains* by attacking you beyond the pot you were already in
   (§5.3 awards attested pots, never stacks), which is the achievable
   property.
6. **Gas is a precondition for defending yourself.** An empty tank inside the
   window is indistinguishable from silence. Dispute duties add several
   transactions to what revision 2 required; the client should keep a gas
   reserve warning in front of the player from `(0,0)` onward.
7. **The per-hand marker puts a small transaction between every pair of
   hands.** Unmeasured (§11 gates on it). If confirmation latency on Base is
   seconds, it disappears into the inter-hand rhythm; if it is not playable,
   §4's cadence returns to design. The dispute path's gas (DLEQ verification,
   the evaluator) is likewise measured before build, though it prices only
   disputes, not play.
8. **A refuser chooses the moment with full information** (§10 keeps
   commit-and-accept dropped). What the choice can win is now bounded at zero
   for completed wagers (§5.3) and at un-risking for unfinished ones (item 1);
   the information advantage buys timing, not money.
9. **The chain adjudicates a showdown only from both-committed evidence, and
   builds a poker evaluator to do it.** Heads-up NLHE betting reconstruction
   plus a 7-card evaluator in Solidity is real new contract surface —
   dispute-only, anchored, but the largest single piece of §9 and the place a
   contract bug does the most damage. Named here so nobody discovers the scope
   in the build order.
10. **The live hand's shares exist on disk, encrypted, until the hand ends**
    (§6). A narrow, deliberate dent in "dies with the tab", traded for crash
    survivability at showdowns.
11. **Phase 2 demands more availability than the window alone.** Evidence
    needs one appearance inside 24 hours; a *pending-hand* dispute
    additionally needs a live client through the bounded episode and a
    human reachable within any six-hour to-act stretch — and the opponent
    steers *when* inside the episode that stretch falls, up to parking it
    in your night (fourteenth check, finding 2). Ceiling: the pot, never
    the bond, and never past ~66 hours; blind action and standing
    instructions (§5.1) are the mitigations. Declared rather than solved.
12. **A disputed decision buys thinking time no live table would allow.** A
    player facing one hard decision can force the dispute path and take up
    to six banked hours — solver time, a friend's advice — at the price of
    ending the session (twelfth check, finding 7c). The same information
    was always available to a player willing to stall the wire; the bank
    caps it where the wire's stall was unbounded, but it also *licenses* it.
    Declared; the social layer prices it like every other rudeness.

---

## 9. Must be fixed before this can be built

Concrete defects in existing code, each blocking part of the above:

1. **The hand number** is local, never transmitted, and reset to zero on peer
   restart (`useGame.ts`). Must be transmitted, monotone across reloads, and
   bound into the receipt hash. **Blocks §4 entirely.**

   **Fix — recover it, in this order of trust:**

   - **The client's own stored receipts.** Each is signed by both players and
     carries its `(hand, subseq)`, so a reloaded tab reads its own newest
     receipt from `localStorage` (§6) and cannot be lied to about it. Strongest
     source; requires nothing new.
   - **The on-chain marker floor** (§4). Recoverable from any device, already
     required to exist, and — with the deal gate — never more than one hand
     behind the truth.

   *(Amended 2026-08-17, tenth check finding 7: the relay as a third source is
   struck. It was justified by "covers the gap between checkpoints", a gap the
   per-hand marker abolished, and it broke `relay/server.mjs`'s stated
   invariant — "it never parses a game message, and it holds no game state" —
   for nothing.)*

   **A client with no receipts and no fresh floor must refuse to resume.**
   The guard is "not lower than what I have already signed" — a client with
   cleared storage has signed nothing it can see, so it would accept any
   number from its *peer*, who could relabel the session down to the floor.
   Damage is bounded by the floor, but the rule is needed.

2. **`onPeerRestart` implements V1 winner-takes-all** — it sets
   `{ me: total, them: 0 }` and tells the player the whole buy-in is theirs.
   Contradicts every rule here. Must be rewritten for V2. *(Note 2026-08-17:
   the same rule was deliberately **extended** to the grace timeout for V1
   today, poker@d66a68a — correct for V1, whose contract can only pay a
   zeroed stack. V2's receipts remove that constraint, which is why V2
   settles true stacks instead. The V1 sites are rewritten for V2, not
   reconciled with it.)*

3. **`_pay` reverting bricks settlement.** One reverting payee kills the whole
   payout, and V2 has more legs than V1. Move to pull-payment
   (`credits[addr]` + `withdraw()`).
4. **No transaction-capable identity for the session key** (N6). Every filing
   is a transaction needing gas and a sender; `Channel.sol` requires
   `msg.sender == other`. Determines the hash format, so not a planning detail.
5. **There is no decision clock.** `armDeadline()` sets a value nothing acts
   on, and the disconnect grace never fires for a connected-but-silent peer, so
   a stalling player is untimed today. §3's auto-fold needs a trigger.
   **Who owns that clock is unresolved** — a client-side clock desyncs under
   browser throttling and can be gamed by message delay; a relay-authoritative
   clock hands a public Node process directional power over matches. Both were
   examined and neither ratified. *(Resolved for money 2026-08-17: every
   money-deciding clock is now the chain's — the 24-hour window and §5.3's
   six-hour time banks, both block-timestamp facts. The off-chain decision
   clock decides table flow only, so client-vs-relay ownership is a UX
   choice, no longer a settlement one.)*
6. **There is no receipt message in the protocol at all.** `Msg` is
   `hello | shuffle | shares | act | newhand | bye`. The central artefact of
   this design, and the exchange that produces it, does not exist on the wire.
7. **`Game.forfeit()` and the `bye` path are V1 winner-takes-all too**, and are
   the *common* route rather than `onPeerRestart`. All three sites need
   rewriting, not just the one named in §9.2.
8. **The client has no chain awareness.** `vaultFunded` is a boolean from a
   `postMessage`; there are no deposit amounts and no chain reads. §3's
   deposit-crediting rule and §4's deal gate have no implementation surface
   today. **The largest unnamed item in the build.**
9. **The hand number drives the button** (`hand % 2`), so divergence posts the
   wrong blinds and desyncs the engines. §9.1 treats it as a dispute nonce; it
   is also a correctness bug. The marker (§4) carries the button explicitly,
   which caps the blast radius, but the client bug still needs fixing.
10. **`BOND_BPS` is a constant today** and §2's bond is a formula over declared
    depths. Simpler than revision 2's (no recomputation on deposit, ever), but
    the declared-depth handshake at open does not exist.
11. **There is no session key anywhere in the codebase.** Signing today is a
    single wallet `personal_sign` per match (`useGame.ts:843`). All of §6 — the
    per-match keypair, encryption under a wallet-derived key, the runtime
    determinism probe, the unencrypted fallback with its warning, deletion on
    settlement — is greenfield.
12. **`Channel.sol` cannot learn a session public key, and §1.1's receipt has no
    signer binding.** `_recover` checks against `s.host`/`s.guest`, the wallet
    addresses. A session key needs a registered `sessionKey[player]` authorised
    by a wallet signature at open/join, and the preimage must name which key
    signed. **The largest missing surface in the build**, and the same decision
    as §9.4 rather than a separate one.
13. **No per-player deposit ledger and no deposit entry point.** `join()`
    requires `msg.value == s.buyIn`, so unequal deposits are impossible today and
    a rebuy has no function to call. §1.1's `hostDeposit`/`guestDeposit`, §1.2's
    refund of unaccounted deposits, and §1.4's `burned` counter all need storage
    that does not exist.
14. **There are four winner-takes-all sites, not three:** `onPeerRestart`
    (`useGame.ts:1380`), `game.ts:226` (`bye` → `forfeit`), the `graceFor`
    timeout (`useGame.ts:1320`), and **`worker.ts`'s catch-all error handler,
    which calls `game.forfeit()` on any thrown error — including a failed DLEQ —
    and pays the whole pot to the local player.**
15. **Blinds cross no wire** (`betting.ts` posts both locally). Resolved by
    design in §4: the marker carries button and blinds under both signatures.
    The client work is building the marker exchange itself.
16. **Actions are unsigned** (`protocol.ts:70` — `{ t: 'act'; action; amount }`
    carries no signature and no chain hash; verified in source 2026-08-17).
    §3's signed action chain is new wire format and new client work: sign,
    chain, store alongside receipts, file in disputes. **Blocks §5.3
    entirely.**
17. **Shares are produced on demand and discarded** (`makeShares` builds them
    from the live key per request). §4 needs all 52 computed at shuffle end
    for the `shareRoot`; §6 needs the live hand's set persisted encrypted;
    §5.2 needs them postable with Merkle paths. The primitives all exist
    (`decryptionShare`, `proveDleq`); the lifecycle around them is new.
18. **`Game.act()` signs nothing and sends the raw pre-clamp amount**
    (`game.ts:285` applies the action, then sends `m.amount` as given, while
    `applyAction` rounds and clamps — twelfth check, finding 3b). For the
    signed chain the client must sign the **canonical post-clamp integer
    amount its engine actually applied**, or honest play produces chains an
    exact on-chain validator rejects. Same change carries the signature and
    `prevActionHash` of §3 (formerly §9.16's scope, now precise).
19. **The `hello` card public key appears in no signed artefact**
    (`protocol.ts:114`). The marker now carries both pks (§4); the client
    must bind the hello pk into the marker exchange and refuse to sign on
    mismatch.
20. **The dispute machinery has no contract surface at all.** Marker posting
    and the deal-gate read; the duties and graces (receipt/marker/chain/share
    filings); phase-1 chain consolidation (alternating signatures,
    earliest-per-node, hash tiebreak, equivocation burn); **the triple share
    check — share→`shareRoot` at leaf `p`, ciphertext→`deckRoot` at the same
    `p`, DLEQ against the marker's `cardPk`** (thirteenth check, finding 5:
    the ciphertext is never taken from the filer); `verifyDleq` in Solidity
    (prototyped and measured, `prototypes/dispute-gas/`); card decoding with
    the total fourth row for decode failure; a 7-card evaluator (ported and
    measured, same place); phase-2 action acceptance, banks and graces;
    heads-up betting reconstruction from the chain plus the marker's button
    and blinds. **The largest single item in V2**, dispute-only.

---

## 10. Explicitly dropped, so nobody rebuilds them

| Dropped | Why |
|---|---|
| A2's award formula (`receiptStack + opponentCommitted`) | Symmetric artefacts; both sides can file the mirror claim |
| Per-action co-signing, D6a's lag threshold | Existed to *divide an unfinished hand*, which §5.3 refuses to do (unfinished = cancelled). **Unilateral signed actions were readmitted 2026-08-17 for a different job** — attesting completed wagers — with no acknowledgment step, so Two Generals never enters |
| Server-issued timestamps / any liveness inference | Inverted in heads-up — the deserter holds the newest signature. §5's duties are filings against a fixed window, V1's own shipped primitive, not liveness |
| The 15-second shot clock as a *settlement* primitive | Dropped because a wire-racing clock decided money through network behaviour. **Readmitted 2026-08-17 in changed form:** §5.3's six-hour per-player time bank — hours not seconds, block timestamps not message timing, filings not packets. The third scoped readmission of this pass; the twelfth check is asked to treat readmission erosion as a target |
| Encrypted commit-and-accept on actions | Two Generals — there is always a last message nobody accepted |
| ~~On-chain reveal verification~~ | **Readmitted 2026-08-17, scoped.** Dropped as "affordable but anchorless"; the marker (§4) is the anchor — both-signed deck root and share roots fix the inputs an attacker used to be able to supply. Dispute-only, at the already-measured ~10M-gas scale. Full *shuffle* verification and full-hand replay stay dropped |
| Total forfeiture for non-response | Winner-takes-all, which is V1 — the rule V2 exists to replace. Considered again this revision as the dispute award and dropped again: a showdown winner could then withhold their own signature to convert a small pot into the whole match (the tenth check's finding-3 shape, one level up). §5.3 awards attested pots only |
| W2's compulsion (proving you are alive obliges you to settle) | Answered by not asking: evidence settles what refusal used to hold hostage |
| A per-hand commitment cap | §2 sizes the bond to the declared stakes instead; the pot is never shrunk |
| Refunding original buy-ins as the *general* dispute rule | Discards signed, agreed winnings. **Adopted for the no-filing branch only** (§1.3), where its arithmetic is the one that works |
| Settling at the stored checkpoint when nobody files | Ninth check, finding 1 — a multi-hand rollback bonded for one hand |
| A negotiable bond percentage | §2's formula replaces it; a slider from no deterrent to ruinous helped nobody |
| Rebuyer-funded counterparty bond top-ups | Considered 2026-08-17 for finding 4: the rebuyer posts the opponent's increment. Dropped — a bond only deters its *owner*; money the opponent never posted does not change the opponent's refusal arithmetic. §2's declared depth replaces it |
| Making the marker floor constrain *which receipts* can settle, as the fix for finding 1 | The fiction moves to the marked hand instead of dying — any mutual receipt satisfying the invariant is signable, and the victim can be bribed to sign it (§0's law). Evidence, not constraint, is the fix |

---

## 11. Build order

1. **Cold-check this revision — the sixteenth.** Fifteen checks have run;
   fifteen found something, but the fifteenth verified every §11.1 target
   and found its CRITICAL only in a two-sentence composition (§5.1's
   short-circuit × §1.0's bond return), naming revision 8 "a genuine
   READY-WITH-DEFERRALS candidate" once fixed. Targets: the irrevocable-burn
   rule's own compositions (does refusing to sign a final *after* the
   counterparty's burn crystallised change any §1.3a inequality? can a
   player force the counterparty into a proven burn and then extract via
   the now-asymmetric final bargaining?); the symmetric-muck row against
   §1.3's unwind (both reachable when both vanish — which applies when?);
   and one full adversarial sweep of anything not yet composed with the
   finals rule.
2. **Measure on Base Sepolia, before any contract work:** (a) **first live
   numbers 2026-08-17** (`prototypes/marker-latency/RESULTS.md`): a
   full-size marker post (marker + co-filed receipt calldata) is **61,740
   gas**, and send→confirmed ran **0.7–2.9 s** — one Base block. §4's
   collapse branch is not triggered; the deal gate disappears into the
   shuffle. Caveat: n=3 (the deploy key ran dry; ops letter 2026-08-17
   requests a top-up), congestion tail unmeasured — rerun the 20-sample
   loop when funded. (b) **done 2026-08-17, locally** — the dispute path is
   measured and the ristretto255-in-Solidity risk is retired:
   `prototypes/dispute-gas/` (differential-tested against the client's own
   noble library and verbatim evaluator; all suites pass). DLEQ ~3.0M
   gas/share naive with ~1.5M headroom, evaluator ~228k worst-case, actions
   ~5.4k each, Merkle ~3.8k; worst-case dispute ~27M gas per filing ≈
   $0.50–$10 on Base, dispute-only. Only live gas *price* and marker
   *latency* still need the network — gas units are exact EVM facts.
3. Fix §9.1, §9.9 and §9.16 in the poker client — the hand number, the button,
   signed actions. Cheap, and everything else assumes them.
4. `Channel.sol` V2: session-key registration (§9.12), the per-player deposit
   ledger (§9.13), receipts with `final` (ordered, terminal), the marker and
   the deal-gate read, the window, §5.2's duty filings, §5.3's resolution
   table, the bond formula, the burn, pull-payment. **Contract tests before
   any UI**, per the parking doc's risk note — and the §5.3 table is the piece
   that earns an adversarial test suite of its own.
5. Buyin: declared-depth handshake, deposit, settle, dispute filings, recovery
   page.
6. Poker: the marker exchange, receipts at hand boundaries including `(0,0)`
   and `final`, share lifecycle (§9.17), the decision clock, the four forfeit
   sites (§9.14), storage move.
7. Deploy is a **stop-and-ask**, with the chain id printed.

---

## 12. Where the operator's refund-buy-ins idea ended up

Proposed 2026-08-17. **Adopted in part.** Recorded here because the reasoning
matters more than the outcome.

The idea: a dispute unwinds the session, both players get their deposits back,
both bonds burn. Its advantage is that it caps an honest player's worst case at
one buy-in, where settling at stacks can cost someone who was already losing
their chips *and* their bond.

**As the general dispute rule it was not adopted** — it discards winnings that
were properly signed and agreed, and it makes §4's floor irrelevant.

**As the no-filing branch it was adopted (§1.3), and it is the fix for the ninth
check's worst finding.** That branch needed a rule whose maximum recoverable the
bond actually covers. A full unwind recovers at most one player's own deposits;
§2 bonds exactly that. The previous occupant of that slot — settle at the stored
checkpoint — recovered up to a whole session and was bonded for one hand.

It works there and not elsewhere because the branch is only reachable when
*both* players are silent, and receipt `(0,0)` (§1.1) guarantees the player who
is ahead always holds something worth filing. Neither of those is true of the
general case.

**Revision 3 adopted its spirit in one more place:** the cancelled-hand branch
(§5.3) unwinds an unfinished decision the same way this idea unwinds an
unstarted session — refusing to guess who deserved what, returning
contributions to their origin. Same shape, same reason it is safe there:
nothing signed is discarded.
