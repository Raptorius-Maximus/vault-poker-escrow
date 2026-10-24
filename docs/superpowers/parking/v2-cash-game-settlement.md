# V2 — cash game with escrowed buy-ins, settled by final stacks

Parked 2026-08-14, from a design conversation at the end of the session.
Next step is `arc-design`, not code. Supersedes nothing; sits alongside
`../plans/v2-cash-game-rebuys.md`.

## What Loke wants

A cash game where both buy-ins are escrowed, and settlement pays each player
what is left in their stack rather than everything to one winner. Closing the
browser ends the match: the pot on the table goes to whoever stayed, each side
keeps their remaining stack. Five-minute reconnect window as now. Rebuys
allowed mid-match.

## The one part that cannot work as stated

Awarding the unfinished hand's pot to the survivor requires the contract to
learn the pot size from one side only, and that side is the beneficiary. A
one-sided claim about a number is unverifiable — which is exactly why V1 is
winner-takes-all: a binary outcome is the only thing a single party cannot
distort in its own favour.

Closest sound version: settle at the last completed hand, money committed to
the unfinished hand returns to the stacks it came from. Co-signing after each
betting round instead of each hand shrinks the unsettled amount if that is
not punitive enough.

## The shape that does work

Standard payment-channel construction, three pieces:

1. **Co-signed running state.** Both sides sign `(contract, chainid, session,
   nonce, hostAmount, guestAmount)` at every boundary. The contract pays out
   any state carrying both signatures where the amounts sum to total
   deposited. Neither side can invent one; both can produce the latest.
2. **Challenge window.** A disconnected player's opponent submits the newest
   state they hold. Higher nonce supersedes, so posting a stale favourable
   state is defeated by the other side coming back with a newer one. The
   existing countdown is already the right shape for this.
3. **Session keys.** A throwaway browser keypair authorised once by the wallet
   at match start, signing every state update silently. Without this a cash
   game means two wallet popups per hand and nobody will play it. Effectively
   mandatory, and it is what makes the contract change non-trivial.

## Rebuys

Tractable. The contract accumulates per-player deposits; the co-signed state
carries those totals so the sum check still reconciles. Two rules: do not
credit chips until the deposit confirms on-chain, and pause the table while it
does.

## Why this is worth building beyond the feature itself

Co-signed state solves the closed-tab problem that cost most of this session.
Today a closed tab means no result can ever be signed, because the
card-decrypting key share dies with the page. A co-signed state is just data —
stored, it survives, so a reopened tab can still *settle* even though it can
never continue the hand. V2 is strictly safer than V1 on this axis.

## Pass status

- **Pass 1 — settlement model: COMPLETE** (2026-08-15). D1-D5 locked in the
  [design spec](../specs/2026-08-15-v2-cash-settlement-design.md). Note D1
  **amends this doc**: the "cannot work as stated" section below was wrong —
  a three-number co-signed state does make the pot rule enforceable.
- **Pass 2 — disputes and timing: COMPLETE** (D6-D10). D6a left open and blocking.
- **Pass 3 — session keys: COMPLETE** (D11-D16).
- **Pass 4 — rebuys: COMPLETE** (D18-D22).
- **Pass 5 — scope, migration and hosting: COMPLETE** (D23-D24).

**Design complete 2026-08-15.** All 24 decisions in the
[spec](../specs/2026-08-15-v2-cash-settlement-design.md). Next step: arc-plan.
D6a is blocking and must be derived before contract work.

## Decisions to settle in arc-design, before any Solidity

- Settlement granularity: per hand, or per betting round?
- What happens to the unfinished hand — return to stacks, or something else?
- Challenge window length, traded against how long money is locked.
- Does a rebuy pause the table, or run alongside a hand?

## Risk note

V1's worst failure is money stuck until a countdown. V2 adds a failure where a
wrong challenge window lets someone post a stale state and keep the
difference. Real money, new failure modes, contract tests before UI.

---

## Cold intent check — 2026-08-15 — VERDICT: RETURN TO DESIGN

A fresh reader, given only this parking doc and the design spec, walked the
spec against the intent recorded above. It found the design internally
well-argued and its founding decision wrong. Recorded unfiltered.

### Critical

**A. D1 is unenforceable: the contract cannot tell who abandoned.** D1 pays
"whoever stayed" — and nothing in D1-D24 says how the chain learns who that
is. The only signal at settlement is who submitted, so the rule collapses to
"the pot goes to whoever submits first".

The parking doc's objection was that the pot *number* was a one-sided claim.
D1 refuted that correctly — a co-signed pot field is genuinely attested. But
the number was never the whole claim. *"My opponent abandoned"* is also a
one-sided claim, and D1 left it entirely unattested. **D1 fixed the number and
missed the assertion attached to it.**

The exploit is the most common event in poker, not a corner case. River
betting closes when B calls; per D3 the caller is the one a state behind, so A
holds the newest co-signed state with the pot at maximum. Cards reveal, B wins
the hand. A declines to sign the state awarding B the pot, submits the state
they already hold, and takes it. B's only defence under D8 is a *higher*
state, which was never co-signed and cannot be manufactured. D6's penalty
never fires, because A submitted the genuinely newest state. **The bettor can
rob the caller of every pot they lose at showdown.**

This is a regression against work this project already did.
`vault-handover.md` — named in CLAUDE.md as the source of truth, and
containing a V2 section — states the principle outright: *"The chain cannot
see who lost their internet… do not try to prove a disconnect. Test for
liveness instead."* V1's deployed `Channel.sol` implements it via
`claimByDefault()` / `iAmHere()` / bond / W2. **The V2 spec contains no
occurrence of liveness, iAmHere, refute or bond, and never cites
vault-handover.md once. The five passes were run without reading it.**

**C. D2's action list omits the states that move money out of the pot** —
blinds, showdown award, fold award — and `protocol.ts` has no acknowledgement
message, so D2's claim that signatures ride on existing messages is false
exactly at round boundaries.

### High

**B. The operator's five-minute reconnect window was silently dropped.** This
doc, line 12: *"Five-minute reconnect window as now."* The spec never mentions
it. D7's 24 hours is the on-chain challenge window, a different thing. An
explicit requirement lost with no rejection note — and it is half the fix for A.

**D. Domain separation lost between this doc and D1.** Parking doc: sign
`(contract, chainid, session, nonce, …)`. D1: `(nonce, host, guest, pot)`. No
chain id, contract address or session binding anywhere in 24 decisions — so a
state replays across matches, deployments and chains. `Channel.sol:105`
already binds all three. Plainest money-losing bug in the document.

**E. D6 falsifies D8's safety argument.** "A compromised session key can only
push toward the truth" is false once a superseded submission forfeits the
whole stake: steal a key, wait for an honest lagging submission, object, take
their stack. D12's bound ("stolen key *plus* a colluding opponent") is broken
— the key alone now suffices.

**F. D6a is design work mislabelled as verification, and is self-inflicted.**
There is no acknowledgement sequence to derive the lag bound from. And
`vault-handover.md` already carries a construction with no lag asymmetry: a
per-hand mutually co-signed receipt plus the opponent's own unilaterally
signed committed-amount for the live hand — you present *their* signature, so
you never wait for a counter-signature, so D6a does not exist.

**G. D10 and D17 contradict** and D17 never marks itself as amending D10.
D17's mechanism also does not exist: D13 encrypts *the session key*; the thing
needing backup is *the signed states*, which no decision encrypts.

**H. Unspecified: who gets the pot after a successful supersession.** Under a
naive reading the abandoner collects it, inverting D1's purpose.

### Medium

**I.** D7's "cooperative settlement short-circuits the window" requires both
wallets present, which D8 forbids the session key from doing — often exactly
when a window is open. **J.** V1's 10% anti-grief bond has no V2 analogue;
unilateral submission is free. **K.** D16 over-claims: the citation is Base's
Azul page while the text says Fjord, and "strictly stronger than D13" is
wrong — a non-extractable WebCrypto key has no user-presence gate, so a thief
with a copied profile signs freely, where D13 forces them to hold the wallet
too. Against D13's threat model D16 may be *weaker*.

### Verified sound

D23's secure-context claim, the ops letter's existence and its correct
deferral of D17's storage, D21's arithmetic, and D5 / D18 / D19 / D20 / D22 /
D24 as internally coherent. All four questions this doc set for arc-design
were answered.

### Recommended next step

One more design pass scoped to A-D. A and B resolve together by reinstating a
V1-style liveness challenge: submission opens a window, the counterparty
either supersedes with a higher state *or* proves presence, and presence
returns the pot to the stacks it came from rather than awarding it. C and F
may dissolve by revisiting D2 against the hybrid already in
`vault-handover.md`, which would delete D6a rather than derive it. D is a
one-line fix that must be written down.

**Cost of the check:** ~5 minutes, one cold agent. It caught a
money-losing flaw in the founding decision of a 24-decision spec.

---

## Second cold intent check — 2026-08-15 — VERDICT: RETURN TO DESIGN

Pass 6's remediation was checked cold against the first verdict. It closed the
bookkeeping findings (D, F, K, G-as-deferral) and **did not close the founding
one**. Recorded unfiltered.

### The core failure: A1 and A2 were written against different premises

**A2 assumes the chain already knows someone left. A1 introduces a test for
whether they left. Nothing joins them.**

A2's award — claimant gets `receiptStack + opponentCommitted` — is
arithmetically right only when the claimant is the party who did *not*
abandon. The identical artefacts in the attacker's hands pay the attacker.
The chain cannot distinguish, so the rule reduces to *whoever claims first*
once again, and A1's liveness test is the only tie-break. It does not break
the tie. Both readings of A1 step 3 lose money:

- **Literal — only a cooperative close counts.** That needs the claimant's
  signature; the claimant is the attacker and will not sign. W2 expires and
  the false claim stands. **The showdown robbery survives verbatim**, merely
  delayed 30-60 minutes and priced at a 10% bond — less than most river pots.
- **Generous — the refuter may settle unilaterally.** Then an abandoner
  reconnects inside 30 minutes, calls `iAmHere()`, collects the bond, and
  publishes the pre-hand receipt to get their committed money back. That is
  precisely the escape hatch `vault-handover.md` exists to close, now
  profitable rather than merely free.

The previous reader's suggested fix ("presence returns the pot to the stacks")
*is* the generous reading, and is also unsound. This needs a design answer.

**Pass 6 also missed evidence in this repo.** `HANDOVER.md`'s Small followups
already carries this as an open `[decision]`: *"A peer who closes their tab
and returns forfeits the whole match; one who closes and never returns only
loses the current hand's pot… the two paths should probably agree."* Written
during the previous session's wrap and not consulted.

### Other new findings, ranked

- **N2 CRITICAL — A5 deleted the supersession window without replacing it.**
  D7's 24 hours guarded against a *stale receipt*; A5 replaced it with a
  30-minute liveness window and justified the length with a liveness argument.
  Detection of a stale receipt is not a liveness question — the attacker picks
  the moment, and picks 3am. With the watchtower parked and backup unbuilt,
  30 minutes makes D6's "cheating has negative expected value" false, and all
  of Pass 2's safety rests on that sentence.
- **N3 HIGH — `receiptStack - committed` underflows honestly.** No stated
  linkage between `action.hand` and `receipt.hand`; a rebuy between hands
  reaches it with no adversary at all. Solidity 0.8 reverts, so the honest
  survivor is simply stuck. Needs a clamp and a hand-linkage rule.
- **N4 HIGH — no receipt 0**, so the first hand cannot be settled by forfeit.
- **N5 HIGH — V1's bond mechanics are themselves exploitable**, and A1
  reinstated them "unchanged": `iAmHere()` pays the bond out unconditionally,
  so refuting to harvest 10% and then stonewalling is +EV for a mid-hand
  abandoner.
- **N6 HIGH — D8's wallet-free objection cannot be built as written.** An
  objection is a transaction needing gas and a sender; `Channel.sol` requires
  `msg.sender == other`. Either the contract gains a relayable entry point or
  D8's central convenience claim is false. Not an arc-plan detail — it
  determines A4's hash format.
- **N7 MED-HIGH — D23 overrides an explicit "Refuse to build" item.**
  `vault-handover.md`: *"A hosted or shared deployment. Two people, two
  machines, local only."* Hosting may well be right, but it needs a **recorded
  operator override**, not silence. The same file's session deposit ceiling
  for cash is also uncarried.
- **N9 MED — abandonment between hands is now free.** The award is
  `opponentCommitted`; abandon before committing and that is zero. D5's stated
  deterrent is gone at the most common abandonment moment.
- **N8 MED — A3's total forfeiture now falls on the data-loss victim**, who
  publishes an old receipt honestly and is stripped of everything. D10
  accepted "cannot defend themselves", not "loses the lot".
- **N10/N11/N12 LOW** — equal hand numbers do not supersede; D1's dead
  invariant has no replacement stated; no type tag separating the artefact
  hashes.

### Recommended next step

**A Pass 7 scoped to exactly one question: what the chain does when liveness
is proven mid-hand.** N1, N2, N9 and the table-grace linkage all collapse out
of it. Everything else is drafting.

**Cost of the check:** ~7 minutes. It caught a critical flaw in a remediation
that had itself been written to fix a critical flaw.

---

## Operator's proposed answer — 2026-08-15 — the shot clock

Raptor's, at the end of the session that produced two RETURN TO DESIGN
verdicts. It appears to resolve the blocking question. **Not verified — it must
face a cold check before anything is built on it**, because the two designs it
replaces both looked sound to their author too.

### The rule

1. **A 15-second clock on every decision.** Run it out and the client acts for
   you: **check** if nothing is owed, **fold** if something is.
2. **A 2-minute time bank per match**, drawn on when the 15 seconds expire, so
   a dropped connection has room to come back before anything is forced. Once
   the bank is empty the auto-action fires at 15 seconds with no reprieve.
3. **Refusing to sign forfeits the current pot** — the same treatment as
   refusing to act, because it is the same thing.

### Why it resolves what two passes could not

**It deletes the state the chain could not adjudicate.** Every previous design
foundered on "who abandoned mid-hand", which the chain cannot see. With a shot
clock there are no abandoned hands: silence is an action, the hand completes,
and settlement is always a hand boundary with a receipt. Nobody has to prove
who left, because nothing is left hanging.

**It reproduces what real poker sites do, without needing what they have.**
Their disconnect handling works because the server holds your cards and plays
the hand out without you — returning cannot rewind it. This project cannot do
that: the card key dies with the tab, deliberately (D11). The insight is that
**the cards were never the point.** All that was needed was a rule for what a
silent player does, and "fold" needs no cards at all.

**It removes the reward for coming back.** The operator's earlier proposal —
proving presence takes the pot — killed the showdown robbery but inverted into
a new attack: go quiet deliberately, wait for the claim, reappear, take the pot
you were losing. With the clock, the fold has already happened. Returning does
not undo it, exactly as on a real site, so there is nothing to win by leaving.

**And the forfeit-on-refusal compels the right party.** A1's failure was that
its escape hatch required a *cooperative* close, meaning the attacker's own
signature, which they would never give. Here the player who refuses must
produce a receipt co-signed by **their opponent** — and the opponent will sign
the true one instantly. A rule that can be stonewalled becomes one that cannot.

### Open, for the design pass

- **The showdown receipt.** Hand completes, you lose, you go quiet before
  signing. Your opponent holds the previous receipt plus your signed bet, which
  looks identical to going quiet *during* the hand. The forfeit rule probably
  covers it; "probably" is what both cold checks demolished.
- **Who decides the clock expired.** Two clients do not share a clock, and
  network latency means one may believe the 15 seconds elapsed while the other
  does not. Clean while the player is connected — their own client sends the
  auto-action. The hard case is a disconnected player, where the opponent must
  apply the fold unilaterally and both must still converge on reconnection.
- **Whether the time bank belongs in the signed receipt.** It changes no
  settlement amount, but both sides must agree on the balance or they will
  disagree about whether a fold fired.
- Whether the clock also runs on the guest before the first deal.

### What this simplifies if it holds

Deletes the need for A2's award formula, N3's clamping, N4's implicit receipt
zero, and most of N1 — those existed only to divide an unfinished hand.
Receipts at hand boundaries may be the only artefact required.

### Cold check on the shot clock — 2026-08-15 — VERDICT: RETURN TO DESIGN

Two parts of the proposal are right and should survive: a decision clock
**should** exist (there is none today — see F3), and "refusing to sign is
refusing to act" is the correct *principle*. Neither is a settlement
primitive, which is what the proposal tried to make them.

**Attack A — the showdown robbery — survives unchanged, and the parking doc's
argument for why it does not is factually wrong.** The claim was that a
refuser "must produce a receipt co-signed by their opponent". They need
nothing of the sort: the attacker already holds receipt N plus the opponent's
own signed action, which is a complete claim. The honest winner holds the
*identical pair* and can publish the mirror claim. The chain sees two
symmetric submissions and still cannot tell who refused. Finding A verbatim,
with "who abandoned" renamed to "who refused to countersign".

**Attack B — the clock's central mechanism does not fire on the only players
it matters for.** Fold ends a hand and needs no cards. **Check does not** — it
advances the street, and `advanceStreet()` then waits on the peer's decryption
shares, which only their tab can produce and which died with it (D11). So an
auto-checked hand against a disconnected player *deadlocks at the next
street*. "The cards were never the point" is half true: fold needs no cards,
check does, and the proposal needs both. Patch it to always-fold and the hand
terminates in the survivor's engine only — no mutual receipt exists, and the
survivor is back to publishing receipt N + the opponent's signed action, which
is A2 unchanged. **The clock works on connected players, who could have signed
anyway, and fails on disconnected ones, who are the entire problem.**

**F1 CRITICAL — a 15-second adversarial deadline cannot run over this
transport.** No timestamps in `Msg`, nothing signs send-time, so the clock's
start is whatever the opponent's client says. Withhold a raise three seconds
and you have taken 20% of the victim's budget undetectably. Worse, it voids
`protocol.ts`'s own safety argument that a censoring relay is harmless because
censorship is indistinguishable from unplugging: **with a clock, censorship
becomes directional and profitable — the relay can fold whichever player it
chooses, hand after hand.** Per D23 that relay is the server admin's box, whose threat
model goes from "cannot read, can only kill the match" to "can pick who wins
each pot". This is why every previous design's shortest adversarial clock was
30 minutes.

**F2 CRITICAL — browser timer throttling, which this repo documented today.**
Hidden tabs are throttled to roughly once a minute. A backgrounded tab stays
*connected*, so `graceFor` never fires for it — but the shot clock would.
Alt-tab for three minutes and you are auto-folded: a new way to lose money
that did not previously exist. It also desyncs the two engines with no
adversary present, and there is no state-resync path.

**F3 HIGH — there is no betting-phase clock today, and dead UI promising one.**
`armDeadline(45_000)` is armed only on dealing/revealing/showdown and cleared
on entering betting; `Table.tsx` renders a clock during betting where the
deadline is always null. So a live player really can stall forever — which
vindicates the proposal's *motivation* while complicating its framing.

**F4 HIGH — the time bank breaks `graceFor`'s tested invariant.** That function
is pure and keyed only on `vaultOn` precisely so both sides compute an
identical number (`grace.test.ts`). A bank consumed against two different
clocks makes the effective tolerance differ per side, and its own comment
applies: "the shorter one silently wins."

**F5 HIGH — auto-fold-on-disconnect is a new trusted assertion between
adversaries.** It requires a message meaning "I am telling you that you did
something". The recipient cannot verify the sender's clock, so they either
accept it (any client can steal a pot at will) or reject it (engines desync).
The chain-cannot-see-who-left problem moved somewhere strictly worse — at
least the chain is neutral.

**F7-F10** — `graceFor` and the clock make contradictory promises about the
same silence (auto-folded at 2:15, still "entitled to return" until 5:00);
three tiers of abandonment penalty distinguished by signals the chain cannot
see; nothing clocks the gap *between* hands, so N9 survives; the hand number is
a local counter that A2 makes the dispute nonce.

**N1, N2, N3, N9 all still stand.** N1's answer is "the question no longer
arises", which holds only if hands always complete — they do not.

### The direction the reader points Pass 7 at

Stop trying to award the disputed pot to the right party; every version
founders on the chain being unable to identify that party from symmetric
artefacts. Instead: **a hand that produces no mutual receipt settles at the
previous receipt — committed money returns to both stacks — and both players
pay a fixed penalty for the non-completion.** Nobody has to be identified. The
robber gains nothing and pays; the plug-puller escapes the pot and pays. Size
the penalty above the maximum pot and both attacks go negative-EV, which is
the trick V1 already used.

Its cost is real and must be argued rather than hidden: it punishes the honest
victim too, and invites mutual-destruction griefing from a player who is ahead
on overall stack.

---

## Operator's second proposal — 2026-08-15 — clock, stamped signatures, symmetric penalty

Built across the conversation following the shot clock's rejection, largely by
the operator. **Unverified.** Four rules, each aimed at a different failure the
three previous verdicts identified.

### The rules

1. **A timeout is a fold. Never an auto-check.** Fold terminates a hand and
   needs no cards; check advances the street and then waits on the peer's
   decryption shares, which die with their tab. Always-fold is harsher — a free
   check becomes a discarded hand — and it is what makes "hands always
   complete" true rather than aspirational. The time bank absorbs honest blips.
2. **The relay runs the clock over public game state.** Whose turn, pot size,
   stacks, last action, the countdown. Only the hole cards need secrecy;
   everything else is announced aloud at a real table. This gives both clients
   one shared clock, deleting the "whose watch is right" problem, and removes
   the browser-throttling failure (F2) since a client no longer needs its own
   accurate timer.
3. **Signed actions carry a server-issued timestamp.** This is the load-bearing
   one. Every prior design died because the chain could not tell who abandoned
   — an unattestable one-sided assertion. But **only you can produce your own
   signature**, so the newest artefact you have signed is an unforgeable lower
   bound on when you were last alive. An opponent can withhold a later one; you
   simply present it, and later beats earlier. Comparing the two sides' newest
   stamped signatures answers *who stopped first*, which is the same fact as
   "who left" in a form the chain can verify.
4. **Failure to reach an agreed receipt penalises both sides.** Naive
   "penalise whoever did not sign" inverts immediately: hand your opponent a
   false receipt, they correctly refuse, and they wear the penalty. So the
   refusal is not passive — **the disputing player publishes their own signed
   version**. The chain then holds two conflicting half-signed receipts for one
   hand, knows one party is lying without knowing which, penalises both, and
   settles on the last mutually agreed receipt.

   Honest players never reach this state: both engines are deterministic over
   the same cards, so a genuine disagreement means someone is lying. Lying
   costs guaranteed and gains nothing.

### Why this is different from the three rejected designs

They all tried to award the disputed pot to the correct party, and each
foundered on the chain being unable to identify that party from symmetric
artefacts. This separates the question in two:

- **Who vanished** — now *provable*, via stamped signatures (rule 3).
- **Who won a showdown** — *never* provable, because it depends on cards the
  chain has never seen. So it is not adjudicated at all; it is made expensive
  to lie about (rule 4).

The second is a fact about poker, not a flaw to engineer away. Every previous
pass tried to engineer it away.

### Known costs, stated not hidden

- **The relay becomes a time oracle.** Narrow trust — about what time it is,
  never about who won — but it can withhold timestamps to make a present
  player look absent. Visible to the victim, unlike message-delay attacks.
  Weigh against F1: a clock hands the relay covert directional power anyway,
  so making it overt may be a net improvement.
- **The symmetric penalty punishes the honest victim** when their opponent
  lies. Accepted price for a chain that cannot see cards.
- **Flat penalties are griefable by a chip leader** — the same amount hurts a
  short stack far more. May need to scale with stack. Open.
- Always-fold discards hands that could have checked free.

### Cold check on the four-rule proposal — 2026-08-15 — VERDICT: RETURN TO DESIGN

Two parts survive and should carry into pass 8: the stamped-signature
primitive genuinely is an unforgeable *lower bound* on liveness (the
pre-request-and-hoard attack really does fail — hoarded tokens are older,
which is worse for the hoarder), and splitting "who vanished" from "who won a
showdown" is the correct analytical move. Both halves then fail, but keep the
split.

**P1 CRITICAL — the liveness test is inverted in heads-up.** Heads-up, exactly
one player owes an action at any moment. Vanish while owing one and your stamp
is older, so the test names you: correct. **Vanish immediately after acting and
your stamp is the newest on the table, so the test names your honest
opponent.** And the attacker chooses when to leave.

> River. B bets. A calls — A's stamped call is now the newest artefact in the
> match. Both sides owe hole-card shares. A pulls the cable before sending
> theirs.

The chain reads A as most-recently-alive and B as the deserter. A claims,
collects, and has escaped a called river bet *with a chain-verifiable artefact
naming the victim as the abandoner*. Finding A for the fourth time — and the
first time the mechanism built to defeat it is the mechanism that executes it.

**P2 CRITICAL — liveness proves nothing about compliance, and W2 was dropped.**
Either only legal moves are signable, in which case the test freezes for both
sides the instant the game stalls, or a free-standing "still here" artefact
exists, in which case a script requesting one per second wins the test forever
while stonewalling the receipt. That is V1's `iAmHere()` with W2 deleted, and
`vault-handover.md` names the omission as fatal: *"Proving you are alive
obliges you to settle. That is the whole trick."*

**P3 CRITICAL — at a withheld showdown the honest player cannot compute the
true receipt.** Rule 4 asks them to publish their version; `finishShowdown()`
needs the opponent's decryption shares to know who won, and those never
arrived. They have no true receipt to publish — only the pre-hand one or an
invention. The construction has nothing to say about its own motivating case.

**P4 CRITICAL — the symmetric penalty cannot be sized.** All-in for stack `S`
each, pot `2S`. The loser forces mutual destruction: pays `P`, recovers `S`.
That is +EV whenever `P < S`, and `P` is payable only from escrow so `P ≤ S`.
`P = S` destroys both deposits entirely and arms a short stack to burn the
chip leader's whole stack for the price of their remainder. Arithmetically
closed, not a tuning problem — and it kills the previous reader's own
suggestion too.

**P5 HIGH — rules 1 and 4 combine to punish the honest survivor of every
disconnect.** A timeout-fold carries no signature from the absent player, so
no mutual receipt exists, so rule 4's penalty fires on an ordinary blip.

**P6-P13** — the relay gains a money-deciding key on a public Node process
(violating the handover's blast-radius separation); rule 2 manufactures the
honest divergence rule 4 assumes away by requiring a second betting engine;
authoritative relay state has no persistence across a restart; per-action
token fetches make the relay a prerequisite for playing rather than a pipe;
the penalty has no stated destination; an unopposed half-signed receipt has no
stated behaviour.

**Rule 1 verified SOUND at the engine level.** `applyAction` sets `b.folded`,
`afterAction` calls `settleHand`, and no branch touches `makeShares` or
`acceptShares` — a fold reaches phase `done` with zero decryption shares. The
shot-clock verdict's deadlock is genuinely closed. It is inert at the chain
(no signature from the absent player), and it does not reach the showdown
reveal, which is not a decision and so cannot be folded.

**Also confirmed:** `armDeadline()` sets a deadline nothing acts on, and
`graceFor` never fires for a connected-but-silent peer. **A stalling player has
no timeout at all today.** The whole clock subsystem is greenfield.

### Scope for pass 8 — one question

*What obliges a player who is demonstrably alive to settle?*

V1 filled that hole with W2 and every V2 pass has left it open. P1, P2, P3 and
most of rule 4 collapse out of a real answer. **The answer is probably not a
timestamp — liveness has never been the missing fact.** Compulsion is.

---

## Operator's third proposal — 2026-08-15 — burn the disputed pot, then penalise

Operator's, arrived at after the four-rule rejection. **Unverified.** It does
not replace rules 1-3; it replaces rule 4's symmetric-penalty construction,
which P4 called arithmetically closed.

### The rule

**A hand that produces no mutually-signed receipt is settled at the last
agreed receipt, and the money committed to that hand goes to nobody.** Burned.
Neither player recovers their stake. On top of that, both pay a penalty.

### Why this voids P4 rather than working around it

P4's proof was: *"the loser forces the mutual-destruction path: pays P,
**recovers S** at the previous receipt. Net -P versus -S. +EV whenever P < S."*

**That "recovers" only holds if the fallback returns committed money.** Every
construction discussed to that point did. Burning does not:

| | Play honestly | Refuse to sign |
|---|---|---|
| All-in, losing | receives 0 | receives 0 |
| 100 committed to a 200 pot, losing | keeps 900 | keeps 900 |

The refuser recovers nothing, so there is nothing to gain, and P4's inequality
has no left-hand side. **The sizing problem is not solved — it stops
existing**, because the cheat's baseline is already zero gain rather than a
refund.

This also fixes the flaw in every earlier "void the hand" rule: voiding
*refunded* the loser, which was the escape hatch. Burning does not.

### What the penalty is then for

Deterrence only, not correction. Once refusing gains nothing, any penalty is
pure cost — so it does not have to exceed a stack, a pot, or anything else,
and P4's ceiling (the penalty is payable only from escrow, so P ≤ S) stops
binding. It only has to make refusing unattractive rather than merely futile.

### Known residual, stated not hidden

The honest player still loses their share of the burned pot, and a symmetric
penalty costs them too. A spiteful loser can still spoil a win — they simply
cannot profit from it, and now it costs them as well. That is a real price and
should be argued in the open.

### Open, and the reason for the next cold check

1. **How large should the penalty be**, given it now only has to deter rather
   than out-price a refund? Is any positive amount sufficient, or does the
   griefing case set a floor?
2. **Where does the penalty go?** P10 left this unstated. Constraints already
   identified: to the counterparty it cancels out and makes *triggering* a
   dispute profitable; to the host or relay it gives whoever resolves disputes
   a motive to cause them — **never let the party that resolves a dispute
   profit from it**; burned needs a sink the project has no design for and
   which contradicts nothing but has not been specified.

## Operator's fourth proposal — 2026-08-16 — actions require acceptance

**Unverified.** Pairs with the burn above; the two interact and must be judged
together.

### The rule

An action is committed in encrypted form. **The opponent must accept it before
it takes effect**, and on acceptance the legality of the action is checked
against the previous agreed state — that it really is a legal bet, check, call
or fold given the stakes at the last hand boundary.

### The property it buys

**No action can exist that only one player knows about.** Every state
transition carries both signatures by construction rather than by convention.

That closes a specific gap the readers kept finding: unattested committed
money. Today a player who posts a blind and vanishes has signed nothing, so
the amount they committed has no attestation at all (finding C's blinds gap,
and N3's missing `action.hand` linkage). Under acceptance there is always a
mutual record, because the action could not have occurred without it.

### The tension that must be resolved, not glossed

**Auto-fold (rule 1) says silence ENDS the hand. Acceptance says silence
FREEZES it.** A disconnected player triggers both at once, and they pull in
opposite directions.

A possible join — failing to accept within the clock *is* your fold — may
work, but it is exactly the shape of reasoning that four cold checks have
demolished today, so it is recorded as an open question rather than a fix.

Note also that acceptance reintroduces a round trip per action, which D2
claimed did not exist and P9 already flagged as a cost of the timestamp
scheme.

### Cold check on burn + acceptance — 2026-08-16 — VERDICT: RETURN TO DESIGN

Both proposals contain one correct idea and one false claim.

**BURN — partly sound.** Right that a refund is an escape hatch and a burn is
not. Wrong that this makes sizing "stop existing".

- **It delivers indifference, not deterrence.** All-in loser receives 0 either
  way. The doc read that as proof of deterrence; it is proof of indifference,
  and a free action costing the counterparty 2S will be taken by some players.
  In *relative* position, refusing always buys the refuser the whole pot.
- **P4 is relocated, not voided.** The real constraint was never `P ≤ S` but
  `P ≤ what the refuser still holds after the burn` — and refusing while
  holding nothing is the whole attack, so `P = 0` is forced exactly where it
  is needed.
- **Q8 CRITICAL — after a rebuy, refusing is absolutely +EV.** The last agreed
  receipt predates the rebuy for exactly one hand after every rebuy (D18
  pauses the table; the next receipt is at the *end* of the next hand), and
  the attacker chooses when to rebuy. D22/A6 then refunds deposits the receipt
  does not account for — **handing the attacker their entire rebuy back**.
  Worked case: rebuy 400, shove, lose, refuse, receive +400.
- **Q9 — it inverts V1's founding principle.** V1's trick was that inaction
  loses. Under the burn, inaction is a determinate outcome one party may
  prefer, invocable for free. P2 rises to CRITICAL.
- Credit: it downgrades P3 from CRITICAL to HIGH by at least defining an
  outcome for the withheld showdown.

**ACCEPTANCE — broken as a property claim.**

- **Q1 — "no action only one player knows about" is false by construction.**
  There is always a last message and it is never accepted; adding acceptance
  needs an accept-of-the-accept. This is the Two Generals problem. What it
  really buys is smaller but real: the unattested window shrinks from a whole
  hand to one action — and the attacker picks which action, by picking when to
  vanish.
- **Q2 — P1 survives verbatim.** Vanish owing an acceptance and the deserter
  does not hold the newest signature; vanish owing an *action* and they do.
  Half the time the test names the honest player, and the deserter chooses the
  half.
- **Q4 — blinds are not actions.** `betting.ts` `startHand()` posts both
  locally; no message crosses the wire, so there is nothing to accept. The
  proposal's headline example needs a *start-of-hand receipt*, not acceptance.
- **Q5 — the showdown reveal is not an action and cannot be accepted.** It is
  a `shares` message of ristretto decryption shares plus DLEQ proofs, absent
  from `Action`, `applyAction` and `legalActions`. **The missing thing at a
  withheld showdown is data only the opponent can produce, not a signature.**
  P3 is not moot.
- **Q6 — both sides reveal simultaneously**, so a modified client receives the
  honest shares, computes the result, and *then* withholds its own. The
  attacker sees a hand it did not pay for and decides at zero risk.
- **Q3 — encryption and legality-checking cannot both happen in one step.**
  Accept blind and you have signed something unevaluable; reveal first and it
  is not encrypted. Recommendation: drop the encryption, keep the ack.

**The join — "failing to accept IS your fold" — DOES NOT WORK.** It guarantees
a zero-signature artefact on every timeout, which is the only case that
matters (P5 verbatim). And the two halves destroy each other: the only way to
refuse an illegal action is to not accept it, which folds you — **there is no
way to exercise the check without forfeiting the hand.**

### Answers the reader committed to

**Penalty size: a segregated anti-grief bond, 10% of each side's total
deposits, posted at open, topped up on every rebuy, held OUTSIDE the playing
stack, forfeited in full by both sides on a hand with no mutual receipt, never
drawn from chips.** Segregation is the point — only ring-fenced money is
payable in the state where the refuser is broke. 10% matches `BOND_BPS` already
in `Channel.sol`, so one concept and one number. It cannot be scaled to the
pot, because the chain cannot learn the pot from one side.

**Penalty destination: burned — retained by the contract, never paid out.** The
"needs a sink" objection dissolves on inspection: **in the EVM a burn is the
absence of a payout.** `Channel.sol` has no owner, no sweep, no selfdestruct,
and computes payouts from `s.buyIn` rather than `address(this).balance`, so a
residue is permanently inert. Two load-bearing conditions: **per-session
accounting only, never read `address(this).balance`**, or one session's residue
becomes another's payout; and **the bond burns rather than paying the
counterparty**, which is what stops triggering a dispute being profitable —
and which means **V2 diverges from V1, whose `iAmHere()` pays the bond to the
refuter unconditionally (N5). A1's "reinstated unchanged" is wrong.** Assert
`depositsIn + bondsIn == paidOut + burned` per session, with `burned` tracked
explicitly.

**On the spoiler: no payable penalty closes it.** The spoiler's gain is denying
the opponent's pot, which can exceed anything recoverable from a player who is
by construction broke. Record it as an operator-ratified accepted cost, not as
a mechanism yet to be found.

**Fix the rebuy hole with a rule, not a number:** *no deposit becomes chips
until a receipt naming it is mutually signed, and no hand is dealt while an
un-receipted deposit exists.* Then the only unaccounted deposit at settlement
is D19's genuinely-stuck money, which never became chips.

### New direction worth a pass

**Decryption shares are unforgeable, hand-bound compliance.** They can only be
produced by the holder of that key share, are bound to this hand's ciphertexts
by DLEQ against the shuffled deck, and cannot be pre-fetched or scripted —
exactly what P2 said a free-standing "still here" artefact could never be. The
chain cannot verify a DLEQ, and does not need to: have each player sign
`(contract, chainid, session, hand, keccak(sharesBlob))` on reveal. Holding the
opponent's signed reveal is then chain-checkable proof they complied at the
last step, which makes the withheld showdown adjudicable.

Limit, stated so it is not oversold: it closes P3's motivating case and does
**not** decide the pot when both revealed and one then refuses the receipt.
Progress on P3, none on P1 or P2.

### Other new findings

- **Q11 HIGH — the poker client's `onPeerRestart` implements V1 semantics and
  is incompatible with V2.** It sets `{ me: total, them: 0 }` and says "the
  whole buy-in is yours", which is winner-takes-all and contradicts A2
  outright. It also guarantees a no-mutual-receipt hand, so under the burn the
  honest survivor eats the burn *and* the penalty for something they did not
  cause.
- **Q12 MED-HIGH — `_pay` reverts brick settlement.** One reverting payee kills
  the whole payout. V2 has more legs than V1. Move to pull-payment before V2.
- **Q13 MED — signatures live in `sessionStorage`**, which dies with the tab.
  D11 requires the opposite for V2 artefacts.

### The standing question, unchanged since pass 2

*What obliges a player who is demonstrably alive to settle?* The burn answers
it **perversely** — a determinate default is not a compulsion, and for a losing
all-in player the default is the preferred item at zero cost. Acceptance does
not reach it at all; compulsion lives at the receipt and acceptance governs
only actions within a hand.

The answer remains W2's shape, **which `Channel.sol:133-170` already
implements** and which every V2 pass has dropped.

## Q8 closed — 2026-08-16 — rebuys are mutually receipted before they become chips

**A rebuy is an on-chain deposit via the wallet, exactly as the opening buy-in
is, and it becomes chips only once both players have signed a receipt naming
it and the resulting stacks. No hand is dealt while an un-receipted deposit
exists.**

Proposed by the operator and independently the same rule the fifth cold check
recommended — arrived at from opposite directions, which is the strongest
signal this design has produced.

**Why it is sound rather than novel:** the opening buy-in already works this
way. Real money enters through the wallet and both parties are accounted for
on chain before a card is dealt. A rebuy on the same path is consistency, not
a new mechanism.

**Why it closes Q8:** the attack existed because a rebuy was real money while
the last agreed receipt still predated it, so refusing to settle rolled back
to before the rebuy and D22 refunded it. If chips do not exist until a receipt
naming them is mutually signed, that window never opens — settle at any
moment and the rebuy is already inside the last agreed state. N3's underflow
half goes with it: no receipt can name a commitment larger than the stack it
records.

**Cost:** one signature exchange per rebuy, during a pause the table already
takes (D18/D19) while the deposit confirms. If the opponent declines to
acknowledge a rebuy it simply does not happen — the money is refunded under
D19's late-money rule and no chips appear. Griefable (they can keep you short)
but not exploitable.

**Does not touch** the standing question, P1, P2, P3, P5, N1 or N2.

## Operator's fifth proposal — 2026-08-16 — forfeit-on-refusal, checkpoints, one window

**Unverified.** Four parts. Together they aim at the standing question and at
the 3am problem, and they use **no timestamps, no clock authority, and no
inference about who left** — only "did you do the thing".

### 1. Refuse to sign and you lose everything

If a player does not respond within the window, **their entire buy-in goes to
the other player**, without their signature.

This is V1's trick restored. It works because it does not ask the chain to
identify a liar — only to answer a question it can actually answer: *did a
signed receipt appear within the window, yes or no?*

The arithmetic forces compliance at every stack size. Lost 500 of 1000: sign
and keep 500, refuse and lose 1000 plus deposits. **Signing beats refusing
however badly you lost**, which is what "compulsion" means and what every
previous V2 pass lacked.

It also sidesteps **P1 entirely.** The inverted-liveness problem existed
because the chain was asked to *infer* who left from timestamps. Nothing here
infers anything.

### 2. Challenging requires proving your own reveal

Closes P3. A player who withholds decryption shares leaves their opponent
unable to compute the hand's result, and therefore unable to produce the true
receipt — so under part 1 the honest player would forfeit for something they
could not do.

Fix: **a challenge is only valid if the challenger presents their own signed
reveal for that hand.** Withhold, and you cannot challenge. Challenge, and you
have just handed over what the other player needed to settle. Either way the
attack dies.

Uses the fifth reader's observation that decryption shares are unforgeable,
hand-bound and impossible to pre-fetch or script.

### 3. Checkpoints every 10 hands

**Both players post the current receipt on chain every 10 hands.** Operator's
number.

This is what actually kills the 3am problem, by changing what "old" means: once
receipt 40 is on chain, receipt 4 can never win, because the chain already
knows better. The worst a rewind can achieve is nine hands rather than a whole
session — and it costs the attacker their bond to try.

Cost is gas every ten hands; on Base fractions of a penny, free on testnet.
**Refusing to sign a checkpoint is refusing to turn the key** (part 1), so a
cheat cannot quietly opt out of the mechanism that protects the other player.

### 4. One window, 24 hours, serving both purposes

Deliberately a single number rather than two. Either player announces
settlement on chain, which opens a fixed 24-hour window — **the same length
every time, known in advance, not chosen by whoever moves first.** Within it,
each side either counter-signs or files its own version; highest receipt wins;
failing to do either is the refusal in part 1. Each side's app files
automatically on opening, so no expertise is required.

The fairness is that **the attacker no longer picks a damaging moment** — the
chain already holds a recent checkpoint, so timing buys at most nine hands —
and **the victim no longer has to be lucky**, since the worst case is capped
regardless of when the move comes or how asleep they are. The 24 hours becomes
a courtesy rather than the only thing standing between a player and losing
everything.

### Known cost, stated plainly

Part 1 is total forfeiture and it lands on anyone who cannot respond, not only
those who will not. A permanently dead device forfeits everything. Consistent
with V1 (whose countdown also takes the whole buy-in) and with the operator's
stated intent that closing the browser should forfeit the match — but note the
checkpoints protect against *rewinding*, not against *forfeiting*. Those are
two different protections and only one of them is bounded.

### Cold check on the fifth proposal — 2026-08-16 — VERDICT: RETURN TO DESIGN

**R1 CRITICAL — the forfeit does not fire on the attack it targets.** The
arithmetic in the proposal is correct and prices the wrong choice. The
refuser's alternative to signing is not silence; it is **filing the previous
receipt**, which part 4 explicitly permits.

> A shoves stack S. B calls. Showdown, B wins. Receipt N is never mutually
> signed because A stops. B files receipt N−1 — the highest *mutual* receipt B
> holds, and the only artefact B can produce, since B cannot compute hand N's
> result (P3). A files receipt N−1 too. **Both responded. No forfeit.**
> Settlement A=S, B=S. A escaped a lost all-in at zero cost, and the chain
> never learns hand N happened.

Part 1 compels a **response**, not a **settlement**, and the two diverge
exactly where the design is needed: between hands both sides hold the same
receipt and compulsion is unnecessary; mid-hand neither side can produce one
and compulsion is absent. Finding A, sixth appearance.

**R4 HIGH — the parked write-up misrepresented the operator's own intent.** It
justified total forfeiture as "consistent with the operator's stated intent
that closing the browser should forfeit the match". This doc's opening intent
says the opposite: *"the pot on the table goes to whoever stayed, **each side
keeps their remaining stack**"*, restated in D5. **Total forfeiture is
winner-takes-all — V1's rule, the rule V2 exists to replace.** Author error in
the parking entry, not the operator's proposal.

**R5 HIGH — the announcement carries no bond.** A free transaction whose payoff
is the opponent's entire deposit. `Channel.sol:124` requires 10%; the fifth
check ratified a segregated 10%. Silent regression against both.

**R6 HIGH — both-silent is unsatisfiable.** Each owes the other their entire
buy-in out of a pot of 2S. Funds stuck permanently, where V1's `resolve()`
always pays somebody.

**Part 2 — BROKEN three independent ways.** (a) The chain cannot verify a
ristretto DLEQ and holds neither deck nor joint key, so a "signed reveal" is
the hash of whatever the challenger chooses — **the gate opens on 32 random
bytes**. (b) `makeShares()` is a pure local function of the deck and key, so
withholding on the wire does not prevent producing the artefact later —
"withhold and you cannot challenge" is false at source level. (c) **A fold
produces zero decryption shares**, and the chain cannot distinguish a fold
hand from a showdown hand, so a reveal cannot be required at all without
making every fold hand unfileable. Plus R11: the victim cannot *consume* a
published reveal, because combining it needs their own key share and the deck,
which died with the tab per D11.

**Part 3 — the one real contribution, wrongly specified.** Giving the chain
independent knowledge of a hand number is the first mechanism in this document
that hands the contract a fact neither player supplied at dispute time. Keep
it. But: the bound is denominated in hands while the damage is denominated in
money (nine heads-up hands is several whole stacks); "both must post" turns an
underpriced transaction into total forfeiture, on a chain D19 exists because
transactions sometimes do not land; "refusing to checkpoint is refusal"
recreates finding A one level up; and **`handRef` resets to 0 on a legitimate
reload while never being transmitted — an on-chain monotone floor plus one
reload makes the session permanently unsettleable.**

**Part 4 — sound in length, incomplete as a mechanism.** 24 hours is correctly
argued and A5's 30 minutes was a regression. But W2's compulsion does not
transfer: it works in V1 because it demands an artefact always producible and
unambiguous — a close naming one of two winners. **A deadline only compels if
the thing demanded can be produced**, and V2's window demands a receipt for a
hand neither side may be able to compute. Six proposals have imported W2's
compulsion without importing that precondition.

**P1 CLOSED BY DELETION** — genuine credit, the first proposal to remove the
mechanism rather than patch it. **N2 substantially closed** for the rewind
half. **N8 worsened to CRITICAL** — silence is now total loss, so a dead
device, a cleared profile or an empty gas tank costs the entire deposit.

### The smallest change that would move this closest

**Cap the chips either player may commit in a single hand** — as a starting
number, 25bb against D21's 200bb buy-in.

Every one of the six proposals has failed at the same point: **the disputed
quantity is unbounded**, so no penalty payable from escrow can ever exceed it,
and P4's arithmetic closes every door. Capping the pot is the only move that
makes the deterrent larger than the prize, and it is one number rather than
new cryptography, a new oracle or a new trusted party. With a 25bb cap and a
segregated 10% bond (20bb, outside the stack, burned rather than paid across),
refusing costs 20bb to gain at most 25bb — **the first arithmetic in this
document where the numbers can be made to work.**

Then keep, unchanged in spirit: **part 3 reformulated** — any player may post a
mutually-signed receipt permissionlessly, the contract records the highest hand
number ever posted, nothing below it can settle, and **no forfeit for not
posting**; fix the hand number first (transmit it, make it monotone across
reloads, bind it into the receipt hash per A4). And **part 4's 24 hours** with
D7's cooperative short-circuit. **Drop parts 1 and 2.**

**The cost is real and is the operator's call, not a reader's: no deep
all-ins.** That is a genuine change to the poker.

**And the honest alternative if the cap is rejected:** a chain cannot
adjudicate an unfinished heads-up showdown at all, and V2 should be scoped to
settle only at mutually-signed hand boundaries — with the pull-the-plug escape
hatch declared as an accepted, unbounded cost that the operator ratifies
knowingly rather than discovers later.

## R6 closed — 2026-08-16 — both silent means the session is void

**If neither player responds within the window, the session is void and each
deposit returns to the account it came from.** Operator's.

Well-defined where the previous rule was unsatisfiable (each owing the other
the whole pot out of 2S), and unreachable as an attack: a player who is
*winning* always prefers to file, so one side cannot engineer both-silent
alone. It occurs only when neither party cares, and a refund is the right
answer then.

Note it does refund a losing player — but only in a state their opponent has
to co-operate in reaching, by also walking away from money they are owed.

## Operator's sixth proposal — 2026-08-16 — commit to the reveal before opening it

**Unverified, and parked mid-analysis.** Aimed at Q6: today both sides call
`makeShares` in the same local transition, so a modified client can receive
the honest reveal, compute the result, and only then decide whether to send
its own. Withholding is currently free *and* fully informed.

**The rule:** the final reveal is committed in encrypted form and the opponent
accepts before anything is opened — so nobody can see the outcome first and
then choose to withhold.

**The promising shape:** bundle the commitment into the closing *action*. A
river call then carries a signed commitment to that player's reveal, and
"called, never opened" becomes a **provable** default rather than an inference.
That is the attestable fact every proposal tonight has lacked, and the chain
can check it with keccak alone — no DLEQ needed to verify that an opening
matches its commitment.

**The counter, seen immediately and not yet answered:** commit to the hash of
*garbage*, then open with that garbage. The hash matches, so the chain records
compliance, and the opponent still cannot compute anything — because
distinguishing real ristretto shares from noise requires the DLEQ verification
the EVM cannot do. **The commitment proves you opened something, not that you
opened the truth**, and that gap is where six versions have died.

Possible direction if this is picked up: commit to something the chain *can*
check, which is a cryptographic question (verifiable escrow of the own-hole
decryption share) that the fifth check already listed as unscoped.

## Operator's seventh proposal — 2026-08-16 — the opening must be LEGAL, or you lose everything

Refines the sixth proposal and answers its counter directly.

**The rule:** the last action and the last card reveal are committed encrypted
and accepted before opening. On opening, the content must be **legal** —
checked against the stacks in the last mutually-signed receipt. Open something
illegal, or open noise, and you forfeit everything.

**Why this kills the garbage attack.** The sixth proposal's commitment proved
only that you opened *something*. Requiring the opening to pass a rules check
makes garbage the worst available move rather than a free one.

**The action half is straightforwardly implementable.** Legality of a bet,
call, check or fold is arithmetic over numbers the receipt already carries: is
it this player's turn, is the amount within their stack, does a raise meet the
minimum. The EVM does addition and comparison. **This half is done.**

**The reveal half turns on one factual question, not a design impasse.**
Verifying that decryption shares are genuine needs DLEQ verification over
ristretto255, which has no EVM precompile — the reason five readers have called
it impossible. But *impossible* has been shorthand for *too expensive*, and the
cost only lands in a dispute:

- The happy path never touches the chain at all.
- A dispute should be approximately never.
- The disputing party can be made to pay the gas.

So a verification costing orders of magnitude more than an ordinary transaction
may be perfectly acceptable. **The open question is therefore concrete and
answerable: what does one ristretto255 DLEQ verification cost in gas on Base,
and is that tolerable as a rare, attributable, dispute-only cost?**

This is the "verifiable escrow of the own-hole decryption share" the fifth
check listed as unscoped — reachable, if the number comes back small enough.

**If the number is acceptable, this closes the last hole:** the cheat's final
move (open noise, satisfy the hash, leave the opponent unable to compute)
becomes total forfeiture. Combined with Q8, R6, the checkpoint floor and the
24-hour window, there would be no remaining branch where refusing beats
settling.

**Verify before building on it.** The gas figure is a fact to be measured, and
this design has been wrong six times on things that felt certain.

## The number — 2026-08-16 — on-chain reveal verification is affordable

The seventh proposal turned the last hole into a measurable question. Measured.

**Work required.** `verifyDleq` (`poker/src/core/proofs.ts`) performs **four
scalar multiplications** — `BASE*s`, `pub*c`, `base2*s`, `point2*c` — plus two
subtractions and a SHA-512.

**Cost per operation.** A Solidity ed25519 scalar multiplication runs to about
**1.25M gas** ([reference](https://tech-en.netlify.app/articles/en522202/index.html);
see also [javgh/ed25519-solidity](https://github.com/javgh/ed25519-solidity),
and [EIP-665](https://eips.ethereum.org/EIPS/eip-665) which proposed a 2000-gas
precompile precisely because the EVM is a poor fit for this).

- One DLEQ verification: ~**5M gas**
- A showdown reveal, two hole cards: ~**10M gas**

**Cost on Base.** Base runs around **0.005 gwei**, up to ~0.1 gwei when busy
([Base docs](https://docs.base.org/base-chain/network-information/network-fees),
[analysis](https://openliquid.io/blog/base-chain-gas-fees-explained/)):

| Conditions | One full dispute verification |
|---|---|
| Normal (0.005 gwei) | **~$0.10** |
| Busy (0.1 gwei) | **~$2** |

**Conclusion: affordable.** Five cold checks called on-chain reveal
verification impossible; "impossible" meant "too expensive to do every hand",
which was never what this needs. It runs only in a dispute, disputes should be
approximately never, and the cost is chargeable to whoever loses one — payable
straight out of the forfeited bond.

**The real cost is build time, not gas.** No ristretto255 implementation
exists in Solidity. ed25519 is a starting point; ristretto's encoding sits on
top and needs writing and testing carefully — contract work where a subtle bug
loses money silently.

**Confirm before relying on it:** that ~10M gas fits one Base transaction
(their block limit is generous; current figure unchecked), and that 1.25M
holds for *our* implementation rather than the one measured. Both are cheap to
verify on Base Sepolia, where gas is free.

**What it unlocks.** The cheat's last move — open noise, satisfy the hash,
leave the opponent unable to compute — becomes catchable and punishable. With
Q8, R6, the checkpoint floor, the 24-hour window and the legality check, no
branch is currently known where refusing beats settling. That is the first
time in seven proposals that has been true.

### Final cold check on the assembled design — 2026-08-16 — VERDICT: RETURN TO DESIGN

**The surviving branch: commit, accept, never open.** The design punishes
**opening something illegal** and **opening noise**. It does not punish **not
opening** — and not opening is strictly better for the cheat than opening
noise. Nothing on chain demands an opening.

> River. A shoves 1000 into B's 1000. B calls, legally, opened and verified.
> Both commit reveals; both accept. B opens. A computes the board, sees they
> lost, **and does not open.** Both file receipt N−1 inside the window — which
> R1 established counts as responding — so no refusal-forfeit. The 10M-gas
> check never runs, because there is nothing to verify. **A = 1000, B = 1000.**
> A escaped a lost all-in for at most the bond.

**And R1 verbatim as a second branch:** even if A opens honestly, the chain
learns *the shares are genuine* and still not *who won*. A refuses the receipt,
files N−1, settles there. **The reveal check produces information, not a
settlement** — the fifth check said exactly this and it was never answered.

**Root, stated once: the design punishes a bad artefact and cannot compel a
missing one.** The standing question from pass 2 is still the whole problem.

**A structural problem with the record itself.** There is no written statement
anywhere of **what the contract pays for a hand with no mutual receipt.** A2's
formula was killed; the burn was proposed and never ratified. The single
load-bearing number in the settlement is absent, and every branch analysis is
conditional on a rule nobody has written.

### On the gas measurement: count correct, conclusion over-claimed

The four scalar multiplications are confirmed and the fee arithmetic holds to
an order of magnitude. **Five readers calling it impossible were wrong, and
establishing that was worth the effort.** But the stated caveats were the wrong
two:

- **The contract has no anchor for the inputs.** `verifyDleq` takes the peer's
  key share and the deck ciphertext's `c1` — neither is on chain, both supplied
  by whoever files. An attacker supplies a `c1'` of their choosing and produces
  a perfectly valid DLEQ for it. **The gate opens on chosen inputs.** Closing
  it needs a per-hand mutually signed commitment to `(pkHost, pkGuest, deck)`,
  which does not exist — and must be per *hand*, since `worker.ts` builds a new
  `Game` (new keys, new deck) every hand.
- **It prices the wrong verification.** 10M gas buys "A's two hole cards are
  genuine". For the chain to *adjudicate* it needs 9 cards × 2 shares = **18
  DLEQs ≈ 90M gas**, plus the decode table, plus a 7-card evaluator in
  Solidity. That does not fit a transaction.
- Also uncounted: SHA-512 twice, with no precompile, and the contract must
  reproduce `digest`'s framing byte for byte or every proof fails.

### Composition problems

- **"The action legality half is done" is wrong.** `legalActions` needs
  `toAct`, per-street `committed`, `lastRaiseSize`, `actedSinceAggression`,
  `bigBlind` and `folded`; a hand-boundary receipt carries stacks only. The
  chain would need the whole ordered action list, the blinds and the button —
  and blinds cross no wire at all. Same size of build as the reveal half.
- **Auto-fold plus the bond burn fines honest users.** Timeout-is-a-fold
  guarantees a hand with no signature from the absent player, and the bond
  burns on any hand with no mutual receipt. **Every routine disconnect burns
  10% of both deposits.** A train tunnel, a laptop lid. Not a corner case.
- **Checkpoints need a total order on receipts.** Q8 puts two receipts at one
  hand number and N10 (equal numbers do not supersede) is open — a contract
  that rejects the tie bricks the session. Needs `(hand, subseq)`.
- **The checkpoint stands on a counter that cannot bear it.** `handRef` is
  local, never transmitted, and reset to 0 on peer restart. An on-chain
  monotone floor plus one legitimate reload makes the session permanently
  unsettleable.
- **The written record now describes a dead design.** The spec is frozen at
  Pass 6, and `vault-handover.md` — the declared source of truth — still
  documents A2's award formula at lines 187-204. **A builder reading in the
  prescribed order builds the design that was killed five checks ago.**

### The alternative, and it is ready

> Scope V2 to settle **only at mutually signed hand boundaries**. Drop reveal
> verification entirely. Keep **Q8**, the **checkpoint floor**, the **fixed
> 24-hour window**, **R6**, and the **segregated burned bond** — all five are
> ratified and compose. **Declare the mid-hand pull-the-plug escape as an
> accepted, unbounded cost the operator ratifies knowingly.**
>
> "That design is coherent, buildable, and ready. It does not close finding A.
> It declares it, which is the one thing seven passes have never done."

The harder path — making the window **demand** the opening rather than merely
check it — is W2 in the only form V2 can carry, because the demanded artefact
is always producible by whoever committed to it. But it drags in the deck
commitment and the still-unwritten "what settles when nothing is signed" rule.
**Three things, not one.**

## Correction — 2026-08-16 — the last hole is spite, not theft

Operator's observation, and it corrects a framing this document has carried
all night, including in several of my own summaries.

**The residual hole has repeatedly been described as "the cheat escapes a lost
hand". Under the burn rule, they do not.** Committed money is destroyed, not
returned. Stack 1000, commits 300, loses:

| | Refuser ends with | Honest player ends with |
|---|---|---|
| Played out honestly | 700 | 1300 |
| Refused, pot burned | 700 | 700 |

**The refuser gains nothing.** Their 300 is gone in both columns. They have not
stolen; they have denied.

The confusion came from conflating two different fallbacks. **Settle-at-last-
receipt refunds** the committed money, which genuinely is an escape.
**Burning** does not. Only the first deserved the word "escape", and this
document repeatedly applied it to both.

**So the residual is: a losing player can destroy the winner's pot on the way
out, and the segregated bond makes it cost them 10% to do so.** Refusing is
therefore *strictly worse* for the refuser than playing on — no branch remains
where refusing pays.

**What is still genuinely unfair, and should be declared rather than solved:**
the victim is out their winnings, and the forfeited bond burns rather than
compensating them — because paying it across would make *starting* a dispute
profitable, which is worse.

This materially shrinks the outstanding gap. It does not close finding A on
its own terms, and the seventh check's other findings — no written rule for
what settles a receipt-less hand, the disconnect fining honest players 10%,
the untransmitted hand counter, the specs documenting a dead design — all
stand.

## Operator's eighth proposal — 2026-08-16 — the bond size is the players' choice

**Both players agree a bond percentage before the match, anywhere from 0% to
100% of the buy-in, scaling with rebuys as Q8 already requires.**

### Why this is the right shape rather than a dodge

The bond size trades two things that pull opposite ways, and the tension is
genuine: **a high bond deters spite and punishes bad luck; a low bond forgives
bad luck and tolerates spite.** Auto-fold guarantees an unsigned hand whenever
a connection drops, so at 100% a train tunnel costs a whole buy-in, while at
10% spite is cheap.

There is no correct number, because the answer is not a fact about poker — it
is a fact about who is playing and how good their connection is. Two friends
on fibre want something different from two strangers with real money. Several
passes of this design were spent looking for a value that does not exist.

### Why it is safe

The bond is symmetric — both post the same percentage — and it **burns rather
than paying across**, so no proposable number advantages its proposer. The only
recourse against a number you dislike is to decline the match, which is
sufficient. A player who knows their own connection is unreliable has both the
information and the means to choose accordingly.

**0% is a legitimate choice**, meaning "we trust each other". Informed consent
between two people who have agreed it beats a designer's guess imposed on
everyone.

### What it obliges the UI to do

The number is meaningless as a percentage. It must be shown with its
consequence attached, in plain words — *"if a hand ends without both of you
signing, including someone's connection dropping, you each lose this much"* —
and shown before either player deposits. Chosen blind, people will pick 100
because it sounds safe and then lose a buy-in in a tunnel.

### Interaction with the pot cap

**Probably removes the need for one.** The cap existed because a fine had to
out-price a *profit*; under the burn there is no profit, only spite, which has
no prize to out-price. So the cap is unnecessary at any bond level, and deep
all-ins survive — which was the painful cost the sixth check identified.

Needs verifying rather than assuming: the reasoning is one step, and one-step
reasoning has been wrong repeatedly here.

### Cold check on the CONSOLIDATED spec — 2026-08-16 — VERDICT: RETURN TO DESIGN

The shape is right, the declarations are honest, and §10 resurrects nothing
that was killed. It fails on one thing, and it is the thing everything stands
on.

**§1.3 CANNOT BE EXECUTED BY THE CONTRACT, and the reason is circular.**

Inventory what the contract can see at settlement: the last mutual receipt,
its own deposit ledger, the bonds. **§1.1's own invariant is
`hostStack + guestStack == hostDeposit + guestDeposit` — the receipt allocates
100% of the money to the two stacks.** There is no residue corresponding to the
unfinished hand, because commitments to hand N+1 are chips moving between
stacks *after* the last receipt, attested nowhere on chain.

And **§10 deliberately deleted every artefact that could attest them** — A2's
`opponentCommitted`, per-action co-signing, unilateral signed actions —
justifying the deletion with *"§1.3 divides it by burning"*. **The spec removes
the only inputs to the calculation it then requires.**

So the only implementable behaviour is: pay `hostStack` to host, `guestStack`
to guest, burn the bonds. **That is line 2 of §1.3's own table — the refund
branch it names as the escape hatch six proposals died on.**

Closed replies: a start-of-hand artefact attests only the blinds (2bb of an
arbitrary pot); letting a filer *declare* the commitments gives two conflicting
one-sided numbers, which is finding A on a new quantity; and `settle()` returns
uncalled excess to the overpayer, a third figure the contract cannot see.

**The arithmetic, buy-in D=1000, bond fraction b. Left = as buildable.**

| | Honest | Refuse (buildable) | Gain |
|---|---|---|---|
| Commits 300, loses | 700 | 1000 − 1000b | **+300 − 1000b** |
| All-in 1000, loses | 0 | 1000 − 1000b | **+1000 − 1000b** |
| Rebought, shoves, loses | 0 | 1000 − 1000b | **+1000 − 1000b** |
| Bond 0%, any row | — | full refund | **strictly positive** |

**Refusing is profitable at every bond below 30% for an ordinary pot and below
100% for an all-in.** P4's inequality, untouched.

Even granting the intended rule, the guarantee is **indifference, not
deterrence** — and at b=0 it is exact indifference, so §8.1's "costs them the
agreed bond" is false at a setting §2 offers as normal.

**Q8 is a smaller fix than the spec treats it as:** it closes the refund of an
unaccounted *deposit*, not of the *stack* that deposit became — the same money
by another name.

**Other profitable branches, independent of the above:** §1.4's void refunds a
loser whose opponent cannot file (dead device, cleared data) — §8.3 declares
"cannot defend themselves", not "the opponent is paid for it"; a filing below
the floor has no fallback, because §4 may store only the ordinal; and
**nothing causes checkpoints to exist** — permissionless, unfunded, unassigned,
so the nine-hand bound is a property of somebody having paid recently, not of
the design.

**Composition:** §3's no-pot-cap is the decider. The deterrent must exceed the
escapable amount, the escapable amount is the pot, the pot is unbounded —
therefore only a 100% bond deters, and 100% means a train tunnel costs a whole
buy-in. **§2's slider runs from no deterrent to ruinous with nothing in
between.** §3 flagged its own reasoning as suspect; verified wrong.

**§8.2 is routine, not exceptional** — auto-fold guarantees an unsigned hand on
every mid-hand disconnect, and the client currently pays the pot to the
survivor on that path (`graceFor` → `forfeit()` → `settle(b,'me')`), so the two
clients and the chain hold three different views of the money.

**§9 verified true but incomplete.** Missing: **there is no receipt message in
the protocol at all** — the central artefact of the design is absent from `Msg`
and from the defect list; `Game.forfeit()` and the `bye` path are V1
winner-takes-all too, and are the *common* route rather than `onPeerRestart`;
the client has no chain awareness whatsoever, so §3's deposit rules have no
implementation surface; and the hand number drives the button, so divergence is
a correctness bug, not only a dispute-nonce one.

**§9.1's trust argument is sound against the relay and silent about the peer:**
a client with cleared storage has signed nothing, so it accepts any number ≥
the floor from its peer. Bounded by the floor, so contained. Missing sentence:
**a client with no receipts and no fresh floor must refuse to resume.**

### The smallest change to READY — three edits

1. **§1.3 becomes what the contract can do:** an unsigned hand settles at the
   last mutual receipt with stacks refunded, **and both bonds burn.** Delete
   the commitment-burn and the claim that no configuration rewards refusal.
2. **§3 reinstates a per-hand commitment cap `K`** — 25bb against a 200bb
   buy-in as a starting number.
3. **§2's range becomes `bond ≥ K`**, free choice surviving above that floor.

Then refusing gains at most `K` and costs at least `K`. Never profitable, one
line of arithmetic, and no dependence on a quantity nobody can attest.

**The price is deep all-ins, and it is the operator's call.** But §3's argument
for keeping them rested entirely on §1.3, and §1.3 does not hold.

The larger alternative — attest commitments with a mutually signed state at
every betting action — keeps deep all-ins, but Two Generals still leaves one
unattested increment, so it *still* needs `bond ≥ max single raise`. Strictly
more work for the same guarantee.

---

## Ninth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, spec + parking doc + `Channel.sol` + `game.ts` / `worker.ts` /
`protocol.ts` / `useGame.ts` / `relay/server.mjs`. ~25 min, 18 tool calls,
read-only. First check to verify claims against a compiler-free source read
rather than the spec's own word.

**The headline is split.** §1.3a's arithmetic is **verified sound** — the
reader worked equal deposits, 1000/100 unequal, a rebuy between hands, a rebuy
at the `(N,1)` subseq, a full all-in, far ahead, far behind, and
busted-then-rebought, and **could not construct a single-hand case where
refusing pays.** The chain holds: loss in a hand ≤ `min(H,G)`; `H+G = T_receipt`;
deposits only increase so `T_current ≥ T_receipt`; therefore
`loss ≤ T_receipt/2 ≤ T_current/2 = bond`. Indifference at `H=G` with a full
all-in is the exact boundary and §1.3a admits it. **Bounding the prize instead
of shrinking the pot is a better answer than the eighth check's pot cap.**

**What broke is what this session added.** §5's "settle at the stored
checkpoint when nobody files" — added to close the eighth check's frozen-funds
case — is a *multi-hand* rollback, and §1.3a's bound only reaches one hand.

### Findings

1. **CRITICAL — §5's checkpoint default is a free, unbonded nine-hand rewind.**
   Finding A's ninth appearance, through the door opened to fix frozen funds.
   Both in 1000, `T=2000`, bonds 1000. Checkpoint at hand 10: host 1800 / guest
   200. Hands 11–19 all properly receipted down to host 0 / guest 2000. Guest
   goes offline > 24h (§8.7: no notification path). Host announces, files
   nothing, window closes → settles at the checkpoint. Host **+800** against an
   honest −1000: **gain +1800**. Every hand had a receipt, so §1.3's burn never
   fires. Burning anyway still leaves +800 — the rewind is bounded by the
   checkpoint stack (→ `T`), the bond by `T/2`, so any checkpoint where the
   attacker held over half the chips is profitable. **With a rebuy it is a total
   escape:** checkpoint at 1000/1000, host rebuys 1000, loses all 2000, guest
   offline → settle at the checkpoint *and* §1.2 refunds the unaccounted rebuy
   **to the host**. Net zero on a 2000-chip loss. Requiring the announcer to
   file changes nothing (§4 makes filing the checkpoint itself legal); a
   modified client just stops posting checkpoints once one favours it.
   **§8.5 and §1.3a cannot both be true. §8.5 is right.**

2. **CRITICAL — the contract cannot observe the event §1.3 keys the burn on.**
   The rewrite fixed the *quantity* and left the *event* unattestable. Filed
   receipts, the checkpoint, the deposit ledger and the bonds cannot
   distinguish "hand 21 was played and never signed" from "we ended cleanly at
   receipt 20". Hand numbers report the last hand *signed*, never one
   attempted. Declaring it is a one-sided claim. The only observable proxy is
   "settled through the window", and both settings break: burn on that path and
   a dead laptop after a complete receipt chain costs each player a full
   buy-in; don't burn and finding 1 is free. §11.3 sends a builder to implement
   a burn with no defined trigger.

3. **HIGH — §2's bond level is a two-party obligation with no enforcement, and
   the opening sequence under-bonds the host.** A's deposit creates a payment
   obligation on B. Host opens with 1000 (`T=1000`, half = 500); guest joins
   with 1000 (`T=2000`, both owe 1000); the host must return with a second
   transaction for 500. If nothing gates play on that top-up: hand 1, host
   shoves, loses, refuses — honest −1000, refuse −500, **gain +500**, and the
   guest burns 1000 against the host's 500. §1.3a silently assumes `bond = T/2`
   holds *for both, at the moment of refusal*. Also: sizing on **money in the
   contract** rather than **money in the last receipt** is a griefing lever —
   an unmatched 10,000 rebuy on a 100/100 game makes B owe 5,100. And "half the
   total escrowed" read literally includes the bonds: `B=(D+2B)/2` → `D=0`.
   **Fix: half the total named in the last mutual receipt, with the top-up a
   precondition of signing the receipt that credits the deposit** — a step that
   already needs both signatures, so the coordination has a home.

4. **HIGH — §1.4 never says whether bonds burn, there is no receipt 0, and
   §1.4's own unreachability argument fails on hand 1.** N4 is still open and
   still not in §9. Hand 1, no receipt exists, no checkpoint exists. Host shoves,
   loses, refuses. The guest **has nothing to file** → zero filings → §1.4 void
   → deposits return. If bonds return the host escapes a lost all-in for free;
   if they burn, indifferent. The spec does not choose. And §1.4's "a player who
   is winning always prefers to file" **is false here** — the winner has nothing
   to file, so the loser reaches the void branch unilaterally. **Fix: a mutually
   signed receipt (0,0) recording opening stacks is a precondition of dealing
   hand 1.**

5. **HIGH — the indifference point is engineerable and fully informed.** §3
   permits rebuys between hands and chips only go up, so a player who is behind
   rebuys to *exactly* equalise stacks — landing precisely on the boundary where
   refusal is free — then shoves. Host 500 / guest 1500, host rebuys 1000 →
   1500/1500, `T=3000`, bonds 1500. Host shoves, loses: plays it out −2000,
   refuses −2000. **Costs the host exactly nothing to move the guest by 3000 —
   the whole escrow.** §8.1's "it costs them the agreed bond" is false at the
   maximum-damage point. And Q6 is live in source: `advanceStreet` sends board
   shares street by street and `makeShares` at showdown, so the refuser picks
   the case *after seeing the cards* — §1.3a's "indifferent at the worst case"
   reads as exposure to a distribution, and there is none.

6. **MED-HIGH — §1.3a rests on an invariant the spec never states.**
   `recoverable ≤ min(H,G)` needs the last receipt to be the state at the start
   of the *current* hand. §3 gates on un-receipted deposits and is silent on the
   more important one. Host 900 / guest 100, bond 500; four hands pass unsigned
   while the host loses everything; refuse → settle at 900, **gain +400**. An
   honest client would stop, but the proof depends on it and there is no receipt
   exchange (§9.6) to build it into. **State it: no hand is dealt while the
   previous hand's receipt is unsigned.**

7. **MEDIUM — §8 is stale against the new §2 and understates the routine cost
   10×.** §8.2 still says "a player who knows their connection is unreliable can
   choose a low bond" — §2 no longer offers a choice, and §2.1 says so outright.
   §9.10 likewise sends a builder to implement a negotiation §2 deleted. What
   survives is the magnitude: **one laptop lid costs each player a full buy-in
   to nobody**, re-armed by every rebuy. That is the operator's call to ratify,
   but it cannot be ratified from a ledger describing the old slider.

8. **MEDIUM — missing implementation surfaces not in §9.** *(a)* **No session
   key exists anywhere in the codebase** — signing today is one wallet
   `personal_sign` per match (`useGame.ts:843`); all of §6 is greenfield.
   *(b)* **`Channel.sol` cannot learn a session public key and §1.1's receipt has
   no signer binding** — `_recover` checks `s.host`/`s.guest`. Needs a registered
   `sessionKey[player]` authorised at open/join and a preimage naming the signer.
   **Largest missing surface in the build.** *(c)* **No per-player deposit ledger
   and no deposit entry point** — `join()` requires `msg.value == s.buyIn`, so
   unequal deposits are impossible and a rebuy has no function to call.
   *(d)* §9.1's relay hand-number recovery **contradicts the relay's stated
   design** ("it never parses a game message, and it holds no game state").
   *(e)* **§9.7 undercounts winner-takes-all to three; there are four** —
   `onPeerRestart`, `game.ts:226` (`bye`→`forfeit`), the `graceFor` timeout, and
   **`worker.ts`'s catch-all error handler, which calls `game.forfeit()` on any
   thrown error including a failed DLEQ** and pays the whole pot locally.

### Verified sound — stated explicitly because eight checks running found none

- §1.3a's single-hand arithmetic, across nine constructed cases.
- Q8, within its scope (nothing relative to a stale checkpoint — finding 1).
- §1.5's burn mechanics: no owner, no sweep, no `selfdestruct`, payouts from
  `s.buyIn` never `address(this).balance`. Residue genuinely inert.
- §1.1's domain separation — `Channel.sol:105` binds `address(this)`,
  `block.chainid`, `sessionId` today, exactly as claimed.
- §3's auto-fold-never-auto-check, at engine level: `afterAction` settles and
  returns without touching `makeShares`, while `advanceStreet` does send them —
  so an auto-*check* would strand the hand on a dead tab. Reasoning and code
  reading both right.
- §9 items 1,2,3,5,6,7,8,9,11 verified true against source; item 4 true in
  substance; item 6 slightly narrow (the transport union is wider than
  `protocol.ts`'s) but no receipt message exists in either.
- §12 contradicts nothing in §1–§11; its table is arithmetically right.
- §10 resurrects nothing that was killed.

### Route back

1. **Decide the checkpoint branch** — floor-only with a declared frozen-funds
   case, or bond the checkpoint-to-now swing, which `T/2` cannot. Not a
   drafting fix. *(Operator's §12 is a live candidate here — see below.)*
2. Give the burn an observable trigger and declare the proxy's cost.
3. Receipt (0,0) mandatory; no hand dealt on an unsigned previous receipt;
   §1.4 states the bond treatment.
4. §2 sizes on the last mutual receipt; top-up gates the receipt that credits
   the deposit.
5. Refresh §8; add session-key registration to §1.1 and §9.

### Note for the next pass — §12 may be the answer to finding 1

Not the reader's conclusion; mine, and unchecked. The no-filing fallback needs
a rule whose maximum recoverable is covered by the bond. A full unwind to
deposits has a maximum recoverable of exactly one deposit — which is exactly
what a `T/2` bond is when deposits are equal. That is §12's arithmetic, and it
may fit the fallback slot better than it fits the main rule. **Test it next
pass; do not adopt it on this paragraph.**

## Tenth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Spec read in full (609 lines). Source read:
`Channel.sol` in full, `game.ts` in full, `worker.ts` in full, `protocol.ts`'s
`Msg` union, `useGame.ts` by targeted reads (`handRef`, `spawnWorker`,
`newhand`, the disconnect/`onPeerRestart` block, `rebuy`, `nextHand`/
`startFresh`), `relay/server.mjs` by grep, `Channel.t.sol` as a test inventory
only. Parking doc by grep plus the ninth check's section. ~14 tool calls,
read-only. `forge test` was **not** run.

**The headline.** §1.0's one-good-ending rule makes bond return a **mutual
consent event**, and a mutual-destruction penalty that both parties can jointly
rescind is not a penalty. After a mid-hand refusal the two reachable endings are
"settle at the last mutual receipt with both bonds burned" and "sign a `final`
receipt naming those same stacks and get both bonds back." The second
Pareto-dominates the first by 2.2 buy-ins, and the stacks it names are exactly
the state the refuser wanted. So the refuser's bond does not burn — the victim
hands it back, because handing it back is the victim's best move. §1.3a's table
asserts "Refuses → bond burned" on every line; that line is false, and with it
goes §2's entire deterrent, the 110% margin included. **Refusing is a free
option: worst case identical to honest play, best case a complete escape from a
lost all-in.** Finding A's tenth appearance, through the door revision 2 opened
to close its ninth — the chain still cannot see that the hand happened, so §1.0
hands the question to the players, and the signature it requires belongs to the
party who benefits from the hand not having happened.

### Findings

1. **CRITICAL — §1.0 + §1.2 + §1.3a: the bond is refundable by agreement, so
   refusing weakly dominates honest play and the bargaining solution is total
   escape.** Equal deposits 1000 each, `T`=2000, bond = 1.1 × max(1000,1000) =
   **1100** each; 2100 committed per player. Last mutual receipt (9,0): stacks
   1000/1000, deposits 1000/1000. Hand 10: host shoves 1000, guest calls, both
   all-in. Q6 is live in source — shares are simultaneous, so the host receives
   the guest's shares, computes the result, sees it lost, and withholds its own.
   Hand 10 is now permanently unresolvable by anyone (§6's card key, confirmed
   per-hand in `spawnWorker`).

   | Ending | Host | Guest |
   |---|---|---|
   | **A** `final` at 0/2000 (honest) | 0 + 1100 = **1100** (net −1000) | 2000 + 1100 = **3100** (net +1000) |
   | **B** window settlement at (9,0), both bonds burn | 1000 + 0 = **1000** (net −1100) | 1000 + 0 = **1000** (net −1100) |
   | **C** `final` at (9,1) naming 1000/1000 | **2100** (net **0**) | **2100** (net 0) |

   C satisfies every check the contract can make: `1000+1000 == 1000+1000`,
   neither deposit exceeds what was received, and it sits at the floor (9,0),
   which §4 says settles normally. The host refuses A and offers C. The guest's
   choice is C (2100) or B (1000). **The guest signs C.** The host escapes a
   lost 1000 all-in for nothing: **gain +1000, the whole pot at risk.** Under
   symmetric Nash bargaining over the surplus (2200 = both bonds) from
   disagreement point B = (1000,1000), the split *is* C. And the host's floor is
   the honest baseline — it can accept A at any moment — so refusing risks
   nothing at all.

   Two notes. At the *true* stacks this mechanism is benign: with disagreement
   point (S_h, S_g) and equal bonds, an even split of the surplus lands exactly
   on the honest receipt. The design works when the baseline is true. **The whole
   attack is resetting the baseline**, which a refusal does for free. And
   `useGame.ts`'s own comment already identified this incentive one level down —
   *"a free retry for whoever is losing: close the browser, come back level,
   loss undone"* — and rejected it as obviously wrong with a buy-in in escrow.
   §1.0 reintroduces it at the escrow level.

2. **CRITICAL — §5's one-filing branch reads silence as "no better receipt
   exists". §4's floor is the only defence, §4 forbids everything that would
   make it reliable, and §8.6's "theft is closed" is therefore false.** Equal
   1000/1000, bonds 1100, every hand properly receipted. Host peaks at hand 14
   (1600/400) and its checkpoint for (14,0) lands. Hands 15–19: host falls to
   0/2000, all receipted. By §4 the guest is now the motivated poster — but the
   guest's posts never land: testnet gas ran out at hand 15 (§8.7), or the
   guest's client skips posting because §8.8's per-hand cost is unmeasured. §4
   posts asynchronously, requires nobody to verify a post landed, and rejects
   compulsion. Floor stays (14,0). Guest closes the laptop after hand 19 (§8.6:
   no notification path). Host announces and files (14,0) — one filing, at the
   floor, so §5's table settles it. Honest: 0 + 1100 = 1100 (net −1000). Attack:
   1600 + 0 = 1600 (net −500). **Gain +500** — and with bonds burned, so §1.3's
   fix never fires. Generally gain = `checkpointStack − finalStack − bond`; with
   equal deposits the bond is 0.55·T, so **any stale floor at which the filer
   held more than 55% of the chips is profitable to file**, up to +900 on a 2000
   escrow.

   §4's incentive argument fails three ways. (a) It needs the ahead player's
   transaction to *land* every hand, while §4's own reason for rejecting
   compulsion is that transactions sometimes do not land. (b) "posted
   asynchronously so it never blocks play" and "makes the rewind distance zero"
   cannot both be true — the confirmed floor always lags at least one hand and
   nothing requires anyone to notice by how many. (c) The player who is behind
   has an affirmative incentive *not* to post, so the moment the ahead player's
   posting fails for an innocuous reason, nobody posts. The victim is offline by
   construction, so the party the floor protects is precisely the party who
   cannot act. **The ninth check's finding 1 is half-fixed: §1.3 closed the
   no-filing branch and left the one-filing branch open.**

3. **HIGH — `final` receipts are unordered, not floor-checked, and nothing
   retires the escrow when one is signed.** §1.0 and §5 give `final` an
   unconditional short-circuit. Nothing says the highest `final` wins, nothing
   subjects a `final` to §4's floor, and nothing forbids play continuing after
   one exists. §3 manufactures the situation: *"Either player may stop,
   effective at the end of the current hand — at which point both sign the
   `final` receipt."* Both sign `final` at (5,0), stacks 1600/400. They change
   their minds and keep playing — the escrow is still open and the contract has
   not been told. Twenty hands later the true state is 200/1800 with receipt
   (25,0) signed. The host submits the old `final` (5,0): it pays 1600 and
   returns both bonds, bypassing both the window and the floor. Host 1600 + 1100
   = **2700 (net +600)** against an honest 1300 (net −800): **gain +1400, with
   no counter-filing possible.** Even without malice, the payout is undefined
   when two `final` receipts at different `(hand, subseq)` both verify — which
   means the builder invents it.

4. **HIGH — §3's two rebuy rules contradict each other, and a rebuy is vetoable
   by whoever is ahead.** §3 says both *"No hand is dealt while an un-receipted
   deposit exists (Q8)"* and *"A stuck rebuy resumes the table after 30
   seconds."* A stuck rebuy **is** an un-receipted deposit; the rules give
   opposite answers. And the stuck path is the common path. Host 100 / guest
   1900, `T`=2000, bonds 1100 each. Host deposits a 1000 rebuy. Crediting it
   moves `T` to 3000, so §2 raises the **guest's** required bond from 1100 to
   1.1 × 1500 = **1650** — the guest must send 550 of their own money to let a
   short-stacked opponent reload. §2 makes the top-up a precondition of signing,
   so the guest declines: costless, rational, and available exactly when a rebuy
   is wanted. The host's 1000 sits un-credited and is refunded at settlement.
   **V2's one distinguishing feature over V1 is vetoable by the player who is
   ahead**, so §3's "unlimited rebuys" and §7's dropped deposit ceiling are
   nominal, and the cash game degenerates to a freezeout in the situation cash
   games exist for.

5. **HIGH — §1.0's headline benefit does not hold for all-in hands, and Q5/Q6
   already say why. §9 has no item for it.** §1.0: *"The hand auto-folds, the
   clients reconnect… play continues."* §3: *"A timeout is always a fold."* But
   a fold is only reachable while the betting round is open. Once both players
   are all-in, `nextStreet` closes the round, `runOutIfClosed` →
   `advanceStreet`, and the engine sits in `revealing`/`showdown` waiting on the
   peer's shares; `applyAction` is unreachable and there is no fold to fire.
   That is Q5 verbatim: *"the missing thing at a withheld showdown is data only
   the opponent can produce, not a signature."* A reconnect does not save it
   either — the card key is built per hand inside the worker and §6 makes its
   death with the tab a guarantee; `onPeerRestart`'s own comment says *"Their
   key share died with the old page… that hand is gone."* So: both 1000, host
   shoves, guest calls, both all-in for 2000, the guest's lid closes on the
   flop. Nobody cheated. The hand can never be completed, there is no signable
   post-hand state, §3 forbids dealing the next hand, and the only endings are B
   (each net −1100) or C (each net 0). §1.0 says this case costs nothing; it
   costs 1100 each unless the players negotiate the hand away — and negotiating
   it away is finding 1. **A cheater's required behaviour is byte-identical to
   the most common accident, at the moment the most money is on the table.**

6. **MEDIUM — the pre-(0,0) gap is a naked bond exposure with no cancel path,
   undeclared in §8.** §2 makes the bond a precondition of signing (0,0); §1.1
   makes (0,0) a precondition of hand 1. So both players have 1000 + 1100
   committed before a card exists. If the guest's laptop dies between depositing
   and the (0,0) exchange, no receipt exists, nothing can be filed, and §1.3
   fires: deposits return, **both bonds burn — 1100 each for a session with zero
   hands.** V1 has `cancelOpen` (`Channel.sol:84`) for the analogous fund-lock;
   V2 has no analogue once the guest has joined, and §8 does not list this.
   Stated precisely so it is not over-read: the (0,0) *refusal* case is not an
   extraction — disagreement point (1000,1000), surplus 2200, even split =
   (2100,2100), which is the honest opening. The problem here is the accident.

7. **LOW — §9.1 is stale against §4's rewrite.** Its on-chain-floor bullet still
   says the floor *"Bounds the answer to within ten hands"*; §4 was rewritten to
   every hand. Its third source (the relay) is justified by *"covers the gap
   between checkpoints"* — a gap §4 abolished — so the one option the spec itself
   flags as breaking `relay/server.mjs`'s stated invariant (verified at line 8:
   *"it never parses a game message, and it holds no game state"*) is now
   unmotivated and should simply be struck.

### Verified sound — with the cases actually constructed

- **§2's formula, re-derived from scratch and attacked over eight numeric
  cases.** `bond = 1.1 × max(T_r/2, myDep_r)`; branch-one recoverable ≤
  `min(H_r, G_r)` ≤ `T_r/2`; branch-two recoverable = `myDep_r − myStack_r` ≤
  `myDep_r`. Both strictly under the bond with a 10% margin, no indifference
  point. Cases: equal 1000/1000; unequal 1500/500 (bonds 1650/1100); a rebuy
  between hands; the ninth check's equalising rebuy at the `(N,1)` subseq (host
  500→1500 via a 1000 deposit; bonds 2200/1650; refusal costs the host 700 on
  branch one and 200 on branch two); busted-then-rebought (deposits 2000/1000,
  bonds 2200/1650); all-in for everything; and a hand played with an
  **un-credited** rebuy outstanding, where the bond is sized on credited
  deposits of 1000 while 2000 sits in the contract — safe, because un-credited
  money never becomes chips, so recoverable stays at 900 < 1100. **No case was
  found where the arithmetic itself fails. The formula is right; what defeats it
  is finding 1 — the bond never burns.**
- **§1.3's "not reachable by one player".** §1.1's invariant
  `H+G == D_h+D_g` means at most one player can hold a stack below their own
  deposits, so at most one ever prefers the unwind and the other strictly
  prefers filing. Reaching the unwind never pays: gain = `myDep − myStack` ≤
  `myDep` < `1.1 × myDep` ≤ bond. Worked at 200/1800 — the unwind costs the
  behind player 300 more than filing. Sound, and genuinely fixed by receipt
  (0,0).
- **§3's "no hand while the previous receipt is unsigned" is enforceable by one
  honest client.** Dealing requires both sides' `hello`/`shuffle`
  (`game.ts:162–213`), so a modified client cannot accumulate unsigned hands
  alone. The ninth check's finding 6 is properly closed.
- **§3's auto-fold-never-auto-check at engine level, re-verified:**
  `applyAction` sets `b.folded`, `afterAction` → `settleHand` reaches `done`
  with no `makeShares`; `advanceStreet` does send shares. Correct as claimed —
  see finding 5 for the phases where no fold exists at all.
- **§1.4's burn mechanics against source:** no owner, no sweep, no
  `selfdestruct`, payouts from `s.buyIn` (`Channel.sol:109,157`), never
  `address(this).balance`. Residue inert. (The 33 V1 tests cover no residue or
  accounting identity — a test gap, not a design flaw.)
- **§1.1's domain separation:** `Channel.sol:105` binds `address(this)`,
  `block.chainid`, `sessionId`, exactly as claimed.
- **§9 items 1, 2, 9, 14 re-verified in source:** `handRef` reset to 0 at
  `useGame.ts:1381`; `newhand` carries only `level` (`useGame.ts:1557`) and
  `protocol.ts:71` declares no field at all; `game.ts:119`'s `hand % 2` drives
  the button; four winner-takes-all sites confirmed, including `worker.ts`'s
  catch-all `game.forfeit((err as Error).message)`.
- **§10 resurrects nothing killed.** All 1599 lines of this parking doc grepped
  for renegotiation, hold-up, hostage and bargaining: **finding 1's mechanism
  has never been considered in any of nine prior checks.** It is new with
  revision 2, not inherited.

**Not examined — gaps, not passes.** §6 beyond the card-key lifetime used in
finding 5 (the wallet-determinism probe and the encrypted-storage design are
unreviewed). §7 hosting, §11 build order and §2.1 reputation were read but not
attacked. Gas and cost figures untouched, per the brief. `Channel.t.sol`
inventoried only; no test was run.

### Route back

1. **Break the tie between bond return and mutual consent** (finding 1). The one
   attestable primitive already on the table is §9.15's start-of-hand artefact —
   the spec says it needs one for blinds and then never uses it. Have both
   players sign *"hand N is starting, from receipt N−1"* and post **that** as
   the checkpoint. The chain can then see that hand N happened. Bond return
   becomes automatic and unilateral: bonds return when settlement lands at or
   above the highest posted start-of-hand marker, and burn when it lands below.
   A refusal can no longer be bargained away, and the 110% margin starts doing
   the work §1.3a claims for it. Declare honestly that a bounded hold-up of one
   bond in each direction still exists *around the true result* — that residue
   is unavoidable and should be an §8 item, not a silence.
2. **Gate dealing hand N+1 on the confirmed checkpoint for hand N** (finding 2).
   Not §4's rejected compulsion: a failed transaction pauses the table, it never
   forfeits. It is the only thing that makes "rewind distance zero" true rather
   than aspirational.
3. **Make `final` terminal and ordered** (finding 3): strictly above the floor,
   highest `final` wins, and the client refuses to deal after signing one.
4. **Resolve §3's rebuy contradiction and state what happens when the opponent
   declines the bond top-up** (finding 4) — including in §7's open ceiling
   question and in the UI.
5. **Add a §9 item for "a hand with no signable outcome"** — the all-in /
   withheld-shares case — and narrow §1.0's disconnect claim to exclude it
   (finding 5).
6. **Add a pre-(0,0) branch keyed on "no checkpoint ever posted"** that returns
   both bonds (finding 6), or declare the exposure in §8 if it is kept.
7. **Refresh §9.1 against §4's per-hand rewrite and strike the relay source**
   (finding 7).

**Findings 1 and 2 are not drafting fixes. Contract work must not start on
§§1–5 as written.**

## Design pass on finding 1 — 2026-08-17 — revision 3 written

Run in-session under explicit operator delegation ("figure out how to finish
these loose ends, be creative"), after the tenth check. Decisions below are
therefore **agent calls awaiting operator ratification** — each is reversible
until the arc's build starts, and the operator vetoes any of them by saying so.

### The law the tenth check exposed, stated once

**A penalty both parties can jointly rescind is not a penalty.** Any design
where both bonds return iff both players sign X gives refuser and victim a
joint surplus (the bonds) to divide by choosing X. The refuser bribes with a
slice of whatever the fiction recovers; the victim accepts any positive slice.
Tested against every variant tried this pass — no choice of X survives it,
because two true signatures on a lie verify exactly like two true signatures
on the truth. This generalises finding A: the chain can't identify *who*
defected, and it also can't stop *both* from agreeing to erase that anyone did.

### Dead ends walked so nobody walks them again

1. **The route back's own fix fails as stated.** The tenth check proposed
   bond-return-iff-settlement-lands-at-or-above the start-of-hand marker. The
   fiction just moves to the marked hand: a mutual receipt for hand N at
   invented stacks satisfies the floor, the invariant, and the signature
   check. Constraint on receipts ≠ fix; recorded as a §10 drop.
2. **Per-player bond fate alone fails too.** With the victim's bond safe
   unilaterally, the victim starts indifferent to fictions — but the
   *refuser's* bond is still hostage, and the refuser buys the victim's
   matching filing with a slice of the recovered pot. Bargaining survives
   as long as any recoverable pot exists to bribe from. The pot itself has
   to become unrecoverable-by-agreement, which needs adjudication.
3. **Whole-match dispute awards fail in the mirror direction.** Award the
   proven showdown winner the whole match and a winner *withholds their own
   receipt signature* to convert a 400-chip pot into everything. Award must
   equal the attested pot, exactly. (Also why the V1 whole-match client rule,
   correct for V1, is not V2's on-chain rule — V1's contract can only pay a
   zeroed stack; V2's receipts remove that constraint.)
4. **Rebuyer-funded counterparty bond top-ups fail.** A bond deters only its
   owner; the opponent's arithmetic is unchanged by money they never posted.
5. **Mid-betting adjudication fails in every variant tried.** Fold-by-rule
   against a present turn-player lets the opponent manufacture disputes to
   force folds; opener-pays-penalty rules get weaponised by vanishing at a
   shove and contesting at the last minute. Who stalled mid-betting is
   unattestable — finding A in its purest form — so revision 3 refuses to
   adjudicate it at all: both-present unfinished hands cancel, contributions
   return, declared as §8.1's leak. The chain protects settled bets and
   completed showdowns; it cancels unfinished decisions.

### What made the fix possible

Verified in source this pass: a decryption share is `decryptionShare(ct, key)`
(protocol.ts:186) — a pure function of the post-shuffle deck and the fixed
key, so **all 52 shares are determined the moment the shuffle ends** and can
be Merkle-committed in a both-signed hand-start marker before a card is seen.
Every share already travels with a DLEQ proof off-chain; `verifyDleq` is the
same check the contract runs in disputes. The "anchorless" objection that
dropped on-chain reveal verification is gone — the marker is the anchor. The
~10M-gas dispute-only measurement from the eighth pass becomes load-bearing.
Actions are unsigned today (protocol.ts:70); the signed action chain is new
client work (§9.16). evaluator.ts exists as the port reference for the
Solidity evaluator (§9.18).

### Agent calls needing operator ratification

1. **Live-hand share persistence** — the current hand's shares survive the tab
   (encrypted, destroyed at hand end), narrowing §6's dies-with-the-tab rule
   for the live hand only. Needed so a crash at showdown is defensible.
2. **Declared depth** — table stakes agreed at open; bonds fixed there; rebuys
   credit only up to the declared max. Resolves §7's open ceiling question in
   the same stroke. (Not the settled no-pot-cap rule: any pot the declared
   stakes produce is playable.)
3. **The cancelled-hand leak accepted as §8.1** — unfinished decisions can be
   un-risked by either side at the cost of the session. Priced, symmetric,
   cannot touch settled money; the durable deterrent is the reputation arc.
4. **Scoped readmissions of two §10 drops** (reveal verification; unilateral
   signed actions) — each with a dated entry and the new evidence named.
5. **V2's on-chain abandonment outcome is pot-plus-bond, not whole-match** —
   deliberately different from the V1 client rule ratified earlier today
   (poker@d66a68a), for the reason in dead-end 3.

### State

Revision 3 committed (vault@31075f2). Eleventh cold check dispatched the same
sitting; its verdict lands below as the next dated entry. Both Base Sepolia
measurements (§11.2) remain unrun and gate the build regardless of the
verdict.

## Eleventh cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Revision 3 read in full; `Channel.sol`,
`protocol.ts`, `game.ts`, `betting.ts`, `elgamal.ts`, `evaluator.ts`,
`worker.ts` in full; this doc's tenth-check and design-pass sections in full.
~9 tool calls, read-only. `forge test` not run.

**Headline.** §5.3's resolution table has no branch for the single most common
way a poker hand ends — **a fold.** Every hand that ends in a signed `fold`
action is, by the table's own categories, "betting incomplete", so a losing
player who folds and then withholds the receipt lands in the cancelled-hand
branch: contributions return, both bonds return. **The fold is un-done and the
loser recovers the chips they folded.** Finding A in fresh clothes — the good
ending needs the loser's signature, and when withheld, the fallback refunds
the loser instead of settling the completed wager from evidence. Falsifies
revision 3's thesis for the majority of hands, falsifies §8.1, falsifies
§1.3a's "strictly worse in every reachable case". Against an honest opponent
it is a money pump.

### Findings

1. **CRITICAL — §5.3 rows 3/4 conflate "fold" (a finished decision) with
   "abandoned" (an unfinished one); a completed fold falls into the cancel
   branch, refunding the loser.** Worked case: both deposit 1000, receipt
   (0,0) at 1000/1000, bonds 1100. Hand 1: host raises 300, guest re-raises
   900, host folds. Honest: host −300. Attack: host refuses the receipt and
   files duties (tail of the chain = host's own signed fold); guest must file
   too or lose their bond; both filed → "betting incomplete" → cancel → host
   recovers the 300. Host net 0, **+300 vs honest, at no bond cost.** The
   winner is trapped: filing cancels their win; not filing loses the win and
   their bond. Pump form: sign receipts on won hands, cancel every non-all-in
   lost hand — a called 600 value-bet costs the caller nothing. V2 degenerates
   to all-in-or-fold-for-free. Neither alternative reading survives: classify
   folds "complete" and row 2 burns the folder's bond for a legal fold while
   row 1 can award the folder the pot they folded (all 52 shares persist per
   §6). Root cause: betting terminates three ways — showdown, all-in runout,
   **fold** — plus genuine abandonment; the table covers two and files "fold"
   under "abandoned". A fold is attestable from the chain and can be settled
   from evidence; the design just doesn't.

2. **HIGH — §8.1's boundedness is false for the live hand: cancel refunds the
   entire cross-street investment, not the pending decision.** Both 1000;
   preflop 100 each, flop 300 each (streets complete), turn: host bets 500,
   guest raises all-in, host to act drawing dead. Fold = −400; call = −1000;
   **cancel = 0** — including the completed, called preflop and flop bets.
   "Completed streets are out of reach" is wrong; the true property as
   written is "aggression and calling are risk-free until all-in". Bites even
   with no fold anywhere.

3. **MEDIUM (no clean exploit constructed — specify-before-build, not a
   proven break) — marker sequencing is underspecified on-chain.** Nothing
   verifies marker-chain continuity; duplicate markers at hand N, a marker
   N+1 without receipt N, and which (N−1, subseq) the cancel baseline uses
   after a rebuy are all pinned only by honest-client behaviour. The §5.3
   test suite must pin them before a builder invents them.

### Verified sound — attacked and held

- **§2's declared-depth bond at unequal maxima** (1500/500 → bonds 1650/1100):
  the (M_h+M_g)/2 term is exactly what keeps the small-max player covered;
  substitution of maxima for live values holds pointwise since credit is
  refused past M_i. The formula is sound — finding 1 defeats it by reaching a
  branch where **no bond burns at all**, so the arithmetic never runs.
- **The signed action chain** against truncation (longer chain carries the
  truncator's own signatures), forks (a secretly-kept fork always dead-ends
  shorter), tail-is-victim's-action (victim files their own tail), replay
  (session/hand/seq + prevHash binding; cancel closes the session). Longest
  valid chain reduces to the true chain. The chain machinery is correct; the
  table consuming it is not.
- **"Made to fail a duty":** required share positions derive from the longest
  chain = the true state, which the honest player also ran; an adversary
  cannot manufacture a divergent chain requiring different positions.
- **Garbage share roots** strictly hurt their owner in every branch,
  including the garbage-root *winner* case (fails own duty; honest loser
  becomes sole valid poster and takes the pot).
- **Showdown muck and all-in completeness:** a called all-in is uncancellable;
  a beat player there is dominated by posting. The showdown boundary is the
  one place the leak correctly does not reach.
- **§1.4 burn mechanics and §1.1 domain separation** re-confirmed in source.

**Not examined:** §6 beyond the share-lifetime point, §7, §11 gas, §2.1;
`Channel.t.sol` not read.

### Route back (the checker's; the design pass that follows goes further)

1. Add a fold branch to §5.3: chain terminates in a signed fold → pot to the
   non-folder from the chain's invested amounts, overlaid on receipt N−1;
   the folder's bond returns. Reserve cancel for chains whose tail is a
   non-terminal action awaiting a response.
2. Retitle the cancel category "betting abandoned", making fold / showdown /
   all-in-runout the three completed terminations.
3. Correct §8.1 and §1.3a to the true post-fix bound; drop "strictly worse in
   every reachable case" until the fold branch makes it true.
4. Specify marker-sequencing contract rules.

Findings 1 and 2 are not drafting fixes; contract work on §5 must not start
until the fold/abandonment distinction is in the table.

## Ratification + second design pass — 2026-08-17 — revision 4

**Operator ratified all five agent calls from the finding-1 design pass**
("OK i like all your changes implement them"), same sitting. Call 3 (the
cancelled-hand leak accepted as §8.1) is superseded below by something
strictly better before it ever shipped; the other four stand as ratified.

### Why the eleventh check's own route back is not enough

Route-back 1–2 close the *already-folded* case, but leave the cancel branch
for "tail awaiting a response" — and the loser of a hand is almost always the
player facing an unanswered decision. A player who is behind simply *never
folds*: they open a dispute instead, land in cancel, and recover their whole
hand investment. Fold becomes a dominated action in every non-all-in pot.
That is not an escrow leak, it is the death of the game: the checker's own
finding-2 case (fold −400, call −1000, cancel 0) survives its route back
intact. Any cancel branch reachable by a present loser prices folding at
zero. So revision 4 deletes the cancel branch instead of retitling it.

### The fix: the hand finishes on chain

If the wire fails mid-hand, the dispute does not guess, refund, or fold
anyone by fiat — **it lets the hand finish, with the chain as the table.**
The dispute machinery already reconstructs betting state from the signed
action chain (§9.18); the delta is accepting *new* signed actions, not just
replaying old ones:

- The turn-player (per the reconstructed state) files their next action as a
  signed on-chain extension: fold, call, check, bet, raise — poker's own
  option set, validated by the same state machine.
- Street transitions: both post their committed board-card shares
  (Merkle + DLEQ, as in the duties), the runout advances.
- **Each player has a time bank for the disputed hand — six hours,
  block-timestamp accounting, depleting only while the action (or a share
  posting) is theirs.** Bank empty = fold. This is §3's timeout-is-a-fold
  lifted on chain, an online-poker-native mechanism, and the same fixed-
  deadline-filing primitive as the 24-hour window — not liveness inference.
- **The time bank decides the hand only, never the bond.** Bond fate stays
  on the 24-hour window's duties. A crash that misses a bank folds the hand
  it would have folded anyway; only staying gone for the full window burns.

Every termination is now one of poker's own: fold (attested by signature or
bank), showdown/runout (cards decide), or both banks empty (both deserted
mid-hand — contributions return, the one residue, reachable only jointly).

What this kills, checked against the attacks that killed earlier variants:
fold-dodging (disputing IS playing on; your options in-dispute are exactly
fold/call/raise); the free runout (betting continues street by street, no
auto-check-through); manufacture-a-dispute fold-forcing (nobody is folded
while their bank runs and their client answers in seconds); the equity-theft
cancel (gone with the branch). A manufactured dispute now buys only a rude
early end to the session with the live hand protected — §3's "either player
may stop" exercised expensively.

**Third scoped readmission, recorded honestly:** §10 dropped "the shot clock
as a settlement primitive" because a 15-second wire-racing clock decided
money through network behaviour. The six-hour on-chain bank shares nothing
with that but the word "clock": hours not seconds, block timestamps not
message timing, filings not packets. Pattern worth watching — this pass has
now readmitted three dropped ideas (reveal verification, signed actions, a
clock), each scoped and each with changed premises, but the twelfth check
should treat "readmission erosion" as an explicit target.

Also in revision 4, from the checker's route back: the terminal-fold branch
(evidence-settled, folder's bond returns — folding is legal and complete);
marker sequencing pinned (duplicate markers rejected, live hand = highest
confirmed marker without a completing receipt, overlay baseline = highest
filed subseq of receipt N−1); §8.1 rewritten; §1.3a's claim restored only
because the branches that falsified it no longer exist; §9.5's decision-clock
ownership resolved for all money-deciding cases (the chain owns it).

### State

Revision 4 committed same sitting. Twelfth check dispatched; verdict lands
below. Gas prototypes (§11.2) in progress in parallel — ristretto255
identified as the curve, so on-chain DLEQ is real Solidity field-arithmetic
work; the eighth-pass ~10M figure was literature, not measurement, and is
being replaced with a measured number.

## Measurement — 2026-08-17 — dispute-path gas is real numbers now

§11.2(b) executed locally (gas units are exact EVM facts; only live price
and latency still need Base Sepolia). Full method, numbers and the
noble-validated differential chain: `prototypes/dispute-gas/README.md`
(vault@522fc8b). Headlines:

- **One DLEQ share verification: 2,969,269 gas**, naive double-and-add —
  *better* than the eighth pass's ~5M/share literature estimate, with the
  Strauss/Shamir headroom (~1.5M) deliberately unspent.
- **Worst-case dispute** (preflop all-in, 18 shares): ~53M gas split ~27M
  per player's filing ≈ $0.50–$10 each on Base. Typical river showdown:
  ~$0.20–$4 per side. Dispute-only.
- 7-card evaluator 227,814 worst-case; 20-action chain 107,742; Merkle 3,786;
  ristretto decode/encode ~5.7k/5.3k each (MODEXP precompile).
- The ristretto255-in-Solidity risk is retired: the port exists, passes 120
  evaluator vectors + DLEQ vectors (tampered vector correctly rejected)
  against the client's own noble library and verbatim evaluator.

Still open from §11.2: **(a) marker confirmation latency between hands** —
needs the live network and gates §4's deal-gate playability; live gas price.

## Twelfth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Revision 4 in full; `Channel.sol`,
`betting.ts`, `game.ts`, `protocol.ts`, `elgamal.ts`, `evaluator.ts`,
`worker.ts` in full; this doc's last three sections. ~8 tool calls,
read-only. `forge test` not run.

**Headline.** Revision 4 turned the dispute path from a static filing contest
into a *live* state machine — and forgot that the inputs to a live machine
can change after it starts running. Banks tick against "the longest valid
chain filed", but nothing closes chain filing before banks start, and nothing
says what happens when a longer chain arrives after a bank-fold already
resolved the hand. Separately, the readmitted reveal verification is anchored
to a marker that commits deck and share roots but **not the card public
keys**, so on-chain DLEQ has no trusted key input. Both fixable, neither
drafted; and §5.3's machine disagrees with `betting.ts` in three load-bearing
places.

### Findings

1. **CRITICAL — no chain-consolidation rule: banks tick against "longest
   chain filed so far", so a truncated filing plus a 6–24h outage steals a
   completed hand's pot.** Both 1000, bonds 1100, receipt (N−1) 1000/1000,
   blinds 5/10. Hand N runs to a river bet 250, **B calls** (each invested
   420; B holds the winner). B's laptop dies at 1:00am — the crash §1.0
   promises to survive. A opens at 1:05am filing the chain *truncated at A's
   river bet*: all signatures genuine, a strict prefix, fully "valid".
   Reconstructed state: B to act facing 250; B's bank ticks; 7:05am → empty
   bank = fold → A nets +170. B returns at 9:00am — hour 8 of a 24-hour
   window — with the longer chain bearing A's own river-bet signature, plus
   shares: true result B +420. **No rule orders these events.** If the 7:05
   fold is final, A swings 590 on a hand he lost using only genuine
   signatures and a prefix. If resolution instead recomputes at window close
   from the then-longest chain, the theft dies — but bank accounting across
   chain replacement is entirely undefined and "an empty bank is a fold" is
   not the semantics written. The eleventh check verified longest-chain
   reduction for a *static* model; making the machine live gave the
   truncation defence a 6-hour deadline instead of a 24-hour one.

2. **CRITICAL — the marker omits the card-key public keys, so on-chain DLEQ
   is unanchored; a pre-committed wrong-key share root passes every specified
   check and makes the showdown row undecidable.** `verifyDleq(pk, c1, share,
   proof)` needs the player's card public key — exchanged in an unsigned
   `hello`, regenerated per hand, present in no signed artefact and no marker
   field. A modified client computes its shareRoot from a different key x′ at
   every hand start (premeditated, zero information needed). Losing showdown:
   post x′ shares with DLEQ against pk′ = G·x′ — Merkle passes (own root),
   DLEQ passes (proves consistency with *some* key), combined decryption
   yields a non-card point, decode fails. Two posters who each satisfied
   every check, one undecodable card, no table row, fault unassignable —
   finding A relocated into the crypto layer. Any refund fallback rebuilds
   revision 3's cancel pump one layer down. The eleventh check's "garbage
   roots strictly hurt their owner" silently assumed DLEQ was key-anchored.
   Fix is small (marker carries both hello pks; honest client refuses to
   sign on mismatch; DLEQ runs against marker pks; then Merkle+DLEQ passing
   implies decode succeeds) — but revision 4 contains none of it.

3. **HIGH — §5.3's machine and `betting.ts` disagree three ways.**
   (a) Alphabet: spec says five actions; the client has four (`bet` covers
   raises). (b) Amounts: `applyAction` *coerces* (`Math.round`, clamp to
   [min-raise, effective stack]) and `Game.act()` sends **the raw pre-clamp
   amount** — which is what would be signed. A strict on-chain validator
   rejects an honestly-played `bet 200`-clamped-to-120 chain from that action
   onward, reviving truncation via the validator itself. Either the chain
   replicates clamp semantics bit-for-bit (JS `Math.round` on floats — not
   representable) or the client signs canonical post-clamp integers. Neither
   specified. (c) `legalActions` offers fold only when facing a bet; at a
   check node `applyAction` throws on fold — but "an empty bank is a fold"
   must fire at check nodes, and a player wishing to concede there has no
   legal move. The machine §5.3 claims to reuse cannot express the outcome
   §5.3 mandates.

4. **HIGH — the six-hour bank contradicts the design's own 24-hour crash
   story, and the same missed share posting lands in three rules with
   outcomes 1100 apart.** All-in called *on chain* at 11pm; both owe
   turn-card shares; honest player's laptop dies at midnight; 6am bank empty
   → folds an all-in they could not have folded — falsifying "costs you the
   hand you would have folded anyway" verbatim. The identical posting is a
   24h bond-backed §5.2 window duty when betting completed off-chain, and a
   muck (bond burns) at a filed showdown-complete state. Three regimes —
   bank-fold (pot only), window duty (bond), muck (bond) — overlap by when
   betting completed relative to dispute-open; the line is never drawn. An
   opponent watching relay presence opens the dispute the moment you drop
   offline and prices this deliberately: the live hand's true deadline is six
   hours, undeclared.

5. **MEDIUM — muck-burn vs bank-fold price the same refusal-to-show 1100
   apart, and the cheap side is prospectively reachable** by choosing to call
   on-chain rather than off. No money pump (pot lost either way — verified),
   but the muck deterrent is void for every on-chain completion. Pin one
   price.

6. **MEDIUM — the marker-confirmation gap resurrects the fold refund.**
   Hand N is played while marker N confirms; a dispute inside that gap finds
   no confirmed marker, the live hand is invisible, and a signed fold inside
   it is refunded — the eleventh pump scoped to L2 latency. §5.2's duties
   omit marker filing and §4 never admits a *first* marker mid-window. One
   sentence closes it; it is not there.

7. **LOW — builder-biting gaps:** (a) a turn-player mid-continuation needs
   the opponent's shares for their *own* holes to decide; unspecified whether
   a bank ticks while a needed card is unposted (bounded at one blind in the
   constructed case). (b) "Six hours" must say *cumulative*. (c) The dispute
   path sells six hours of solver time for one hard decision at the price of
   the session — declare alongside §8.1. (d) §11.2's marker measurement must
   include the co-filed receipt, and a raise war stretches the continuation
   to ~stack/BB actions.

### Readmission verdicts (named target)

- **Scoped reveal verification: incomplete as scoped** — the marker anchors
  deck and roots but not keys (finding 2). With pks added, sound.
- **Unilateral signed actions: sound.** Evidence-only signing blocks
  nothing; forks die to longest-wins; the remaining exposure is finding 1's
  timing hole — the continuation's fault, not the signatures'.
- **Time bank: partially erodes.** Genuinely answers wire-racing, strictly
  gentler than the 45s grace for true decisions — but quietly re-imposes a
  6h availability requirement on mechanical postings that the window's own
  sizing rationale rejects (finding 4). Sound for decisions, wrong for
  postings.

### Verified sound — attacked and held

- **Desert-then-return** is strictly *more* expensive than revision 3's
  cancel, not cheaper; no §1.3a inequality leans on a fold-burn; muck-burn
  cannot be escaped retroactively (fold unreachable at betting-complete).
- **Fold/muck/open partition is exact on a fixed chain**; instability is
  only across chain replacement (finding 1) and bond fate (finding 5).
- **Continuation accounting:** on-chain bets capped by receipt-baseline
  stacks; overlay preserves the deposits invariant; uncalled excess returns;
  invested is monotone along a chain so longest-chain maximizes it; the
  one-absent-victim bound holds; contested pots always even.
- **Time-bank griefing bounds** hold under the cumulative reading: only the
  sole-obstacle's bank ticks; 12h + runtime total; other filings land at
  window-open, unpushable past 24h.
- **Both-banks-empty residue:** contribution-return is zero-sum between the
  players — no joint surplus, §0's law does not bite.
- **Turn-order reconstruction:** `betting.ts` heads-up order (SB first
  preflop, last postflop; check-raise via `actedSinceAggression`; short
  all-in not reopening) is deterministic replay from chain + marker + receipt
  stacks. Modulo finding 3, every state's turn-player is well-defined.
- **§0's share-determinism claim** confirmed at `elgamal.ts:71` (the spec's
  citation points at `makeShares`; cosmetic).

**Not reached:** `useGame.ts`, `Channel.t.sol`, `cards.ts` decode table,
`proofs.ts`/`group.ts` internals, §6 storage details, §7, §2.1, §11 gas.

### Route back

1. **Consolidation rule:** resolution — every bank-fold included — is
   provisional until window close and recomputed from the longest valid
   chain then on file, banks re-derived against the prevailing chain (a node
   that vanishes under a longer chain never consumed its player's bank).
   Specify in §5.3/§5.4 with the extension arithmetic.
2. **Anchor the keys:** both card pks into the marker tuple; client signs
   only on hello-match; DLEQ against marker pks; state the totality lemma.
3. **Pin the machine to the code:** four-action alphabet; clients sign
   canonical post-clamp integer amounts; define on-chain open-fold and the
   empty bank at a check node.
4. **One regime per posting:** everything derivable at dispute-open is a
   window duty; only postings created by new on-chain betting are bank items
   — and mechanical postings arguably belong to the window always; reconcile
   muck vs bank-fold to one price; declare the live hand's true deadline.
5. **Admit a first marker as a window filing.**

## Third design pass — 2026-08-17 — revision 5

Same delegation, same sitting. Two calls that go one notch past the twelfth
check's route back, both taken deliberately:

1. **Resolution happens exactly once, at window close** — route back 1's
   option (a) at full strength. Revision 4's mistake generalises: *any*
   consequence made final mid-window inherits a deadline shorter than the
   window, and every such deadline is a truncation lever. So nothing is
   final early — bank-folds included — and the replay at close re-derives
   bank consumption against the prevailing chain, with superseded nodes
   having consumed nothing. The subtle spot (named for the thirteenth
   check): the sole-obstacle definition must make that replay a pure
   function of on-chain facts.
2. **All mechanical postings are window duties at the muck price; banks
   govern decisions only** — route back 4's parenthetical, adopted outright.
   This collapses findings 4 and 5 into one rule, restores §1.0's 24-hour
   crash story verbatim, and leaves exactly one thing a bank can cost: a
   decision, i.e. a fold.

Also per route back: card pks into the marker with a totality lemma
(finding 2 — the checker's fix as given); machine pinned to `betting.ts`
(four actions, canonical post-clamp integer amounts signed by the client —
new §9.18 — and on-chain-only open-fold); first marker admissible as a
window filing (finding 6); solver-time declared as §8.11 (finding 7c);
citation fix (elgamal.ts:71).

State: revision 5 committed (vault@54c57b3). Thirteenth check dispatched
same sitting; verdict lands below.

## Thirteenth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Revision 5 in full; `betting.ts`,
`game.ts`, `protocol.ts`, `elgamal.ts`, `cards.ts`, `Channel.sol`,
`prototypes/dispute-gas/README.md` in full; this doc from the eleventh check
to the end. ~6 tool calls, read-only.

**Headline.** Revision 5's centerpiece — nothing final until close, banks
re-derived against the prevailing chain — correctly kills the twelfth check's
truncation theft, and the extension's float does not reopen it. But the
sole-obstacle definition is missing its start condition and its admissibility
condition: the spec never says when a bank interval *begins* relative to the
filing time of the chain prefix itself, nor whether an action filed after its
node's interval would have emptied the actor's bank is admissible. One
adversarial filing schedule admits three defensible readings with three
different pot destinations. Separately, postings-as-duties creates duties
born after their own 24-hour deadline, leaving the extension without a
defined end. The crypto anchor and the replay parity with `betting.ts` — the
other two named soft spots — held under everything thrown at them.

### Findings

1. **CRITICAL — one schedule, three readings, three outcomes.** 1000/1000,
   bonds 1100, blinds 5/10. Wire: preflop A 30 / B call; flop B check, A 60,
   B call; turn B checks (90 each in, pot 180). A's modified client signs
   action 7 (bet 500), never transmits, opens the dispute at hour 0. Both
   file chains through action 6 (tip: A to act); B files every posting at
   open, watches through hour 23 — "A sole obstacle since hour 0, bank dead
   at 6, pot mine" — and sleeps. At 23:55 A files the genuinely-signed
   action 7 (action preimages carry no signing time). Reading (i): filed
   actions always stand → B to-act, B's bank runs 23:55→05:55, sleeping B
   folded, A +90 on a manufactured zero-risk option. Reading (ii): an action
   filed after its node's interval exhausted the actor's bank is void → A
   bank-folded at hour 6, B +90. Reading (iii), the literal text: B was
   to-act-at-tip with all postings on file since hour 0 → B's bank emptied
   at hour 6, B *retroactively* folded by a segment filed at 23:55. Two
   honest implementers ship (i) and (ii) and disagree by a whole pot.

2. **HIGH — "every posting their decision depends on — their own hole cards
   included" does not say *whose* postings gate the clock.** Read as
   both-shares-on-file, a player suppresses their own clock by withholding
   their own share posting (legal until hour 24), then enters the extension
   with a fresh 6-hour bank against a counterparty who watched 24 quiet
   hours: bets 600 at hour 26 into the sleeper, +400. One sentence kills the
   lever — only the counterparty's missing postings pause your bank; your
   own never do — and it is not there.

3. **HIGH — duties born after ~23:50, or during the extension, have no
   coherent deadline; the extension has no defined end; §1.0's crash story
   fails at the margin.** A call at hour 28 creates showdown-share duties no
   client can safely pre-post (posting own-hole shares early shows your
   hand); their stated deadline (hour 24) has already passed; "extension
   ends when the replay terminates" is circular when the replay is waiting
   on the very posting. And an opponent's duty filed at 23:50 can legally
   move a decision into hours 24–30 — availability the "fixed length, known
   in advance" window never asked for. Needs per-duty grace anchored at
   creation, a defined extension end, and either an honest downgrade of
   §5.1's claim or a design that makes it true.

4. **MEDIUM — "longest valid chain" is a partial function: same-seq
   equivocation by the signer builds equal-length forks with the pot in
   opposite directions, and no tiebreak exists.** No profit constructed
   under any fixed tiebreak; a determinism hole, not a pump. Pin a total
   order; optionally price attributable equivocation (two signatures, same
   key, same (session, hand, seq, prevHash) — cryptographic, one-sided).

5. **MEDIUM — the totality lemma needs a third check never enumerated: the
   ciphertext must be Merkle-verified against `deckRoot` at the same
   position index before it feeds `verifyDleq`.** If the contract takes
   `c1` from the filer, a true-key client roots fake ciphertexts at hand
   start and posts passing DLEQ + passing Merkle at a losing showdown while
   combined decryption decodes to nothing — the twelfth jam surviving the
   pk anchor. The lemma is true as mathematics (verified against
   `elgamal.ts`/`cards.ts`; the honest client constructs `initialDeck()`
   locally from the 52 collision-checked points) but only under the triple
   check (share→shareRoot@p, ciphertext→deckRoot@p, DLEQ vs marker pk),
   which §9.20's build list currently lacks.

6. **MEDIUM — both-clients-modified (one human, two seats — in scope) can
   pass every stated check while resolution has no row.** A marker over 52
   encryptions of the same card: both roots match, both DLEQs pass,
   evaluator receives duplicates or decode throws — unhandled revert bricks
   the session's deposits. No extraction exists (per-session accounting
   caps payout at deposits+bonds in; self-play moves money between the same
   pockets minus gas), but "resolution is total" is exactly rev 5's claim.
   Add the row: undecodable-or-malformed under all-passing checks ⇒ both
   bonds burn, settle at receipt baseline — reachable only when both
   signers misbehaved.

7. **LOW — the both-banks-empty branch is dead code under rev 5** (obstacles
   sequential; the first empty bank folds and terminates). Prove unreachable
   and delete, or it is a cancel branch and the eleventh law applies. Also:
   muck row needs per-position semantics; pin the signed `amount` for
   non-bet actions.

### Verified sound — attacked and held

- **Replay parity with `betting.ts`.** The clamp is total and integer-valued
  on integer state; every integer in [lo, hi] is a fixed point, so the
  on-chain validator is a pure integer range check — no `Math.round` ever
  runs on chain. Edges tried: bet == stack; raise vs all-in below min-raise;
  short all-in not reopening; preflop SB-fold uncalled excess; short-blind
  posting via `min(blind, stack)`. Initial state well-defined from receipt
  stacks + marker button/blinds, rebuy subseq baseline included.
- **Open-fold cannot dodge the muck burn.** No to-act node exists at
  betting-complete; truncating your own call loses at close to the longer
  chain bearing it, whereupon the unposted shares are the muck. One price
  survives.
- **Extension float-vs-freeze, core case:** chain floats, everything
  recomputed → the twelfth theft stays dead; the leaks are findings 1–3,
  not the float.
- **The totality lemma as mathematics**, given finding 5's triple check.
- Desert-then-return, §1.3/§1.3a, invested-monotonicity, bond formula:
  premises unchanged. The twelfth's "time-bank griefing bounds hold" is the
  one prior verified-sound entry rev 5 silently invalidated (findings 2–3
  are its two broken premises).

**Not reached:** §6 storage details, §7, §2.1, `useGame.ts`, `Channel.t.sol`,
`proofs.ts`/`group.ts` internals, live marker latency.

### Route back (the checker's; the fourth pass deviates on item 1 — see below)

1. Adopt reading (ii): bank interval starts at the latest on-file time of
   the complete prefix and the needed counterparty postings; an action is
   admissible only if filed before its node's interval exhausted the
   actor's bank.
2. Only the counterparty's missing postings pause a bank.
3. Duty deadline `max(hour 24, creation + G)`; extension ends at the last
   unmet grace or bank; re-derive the bound with dishonest runtime.
4. Pin a chain tiebreak; decide whether equivocation is priced.
5. Enumerate the triple share check; fix §9.20.
6. Add the total-resolution row; delete or prove-unreachable
   both-banks-empty.

**The trend is real:** the architecture and the crypto anchor survived
adversarial contact; every finding lives in one place — the window/bank
timing semantics of §5.3/§5.4.

## Fourth design pass — 2026-08-17 — revision 6: the two-phase dispute

Same delegation, same sitting.

### Deviation from the thirteenth route back, with the case that forces it

Route-back 1's admissibility rule — *"an action is admissible only if filed
before its node's interval exhausted the actor's bank"* — **reinstates the
twelfth check's CRITICAL.** Replay the twelfth's schedule under it: B's
genuine river call, signed and delivered on the wire at 1am, is filed by the
returning B at hour 8. Its node's interval started when A filed the prefix
(hour ~0); B's bank is 6h; hour 8 > 6 → B's own call is void, the bank-fold
stands, and A's truncation steals the pot again. The rule cannot distinguish
the twelfth's victim (late-filing a decision that was *made* on the wire)
from the thirteenth's attacker (late-filing a decision that was *withheld*),
because action preimages carry no signing time and never can (a signed
timestamp is self-attested). Any admissibility rule keyed on filing time
punishes both or neither.

### The fix: split evidence from play — the two-phase dispute

The root cause of findings 1–3 is one machine trying to be two things: an
evidence window (where late filing must be protected for 24 hours) and a
live game (where late action must be bounded by banks). Revision 6 separates
them:

- **Phase 1 — evidence, hours 0–24, fixed and known in advance.** Receipts,
  markers, chains, postings. Nothing is played, nothing resolves, no banks
  exist. Late-filed wire evidence enjoys the full window unconditionally —
  the twelfth's victim is safe with no admissibility judgment at all.
- **Consolidation at hour 24.** The prevailing chain freezes: built node by
  node from filed actions, earliest-filed-per-node winning (same-block ties:
  lower hash). Terminal → resolve; pending → Phase 2.
- **Phase 2 — play, from a frozen state, at a known appointment.** The
  6-hour cumulative banks govern decisions; clocks pause only on missing
  *counterparty-side* postings (your own never pause you); phase-2-born
  duties get a 6-hour grace from creation; the episode ends when the replay
  terminates or every clock and grace is dry.

Why this kills the thirteenth's findings 1–2 rather than relocating them:
the withheld-bet lever worked because filing at 23:55 bought a *private*
appointment — the victim had no way to know when presence would matter. Now
the only appointment is hour 24, printed on the dispute itself from the
moment it opens. The attacker's 23:55 filing lands in evidence and is
simply part of the frozen state a present-or-scheduled counterparty answers
with a full bank at a time they knew a day in advance. The "only if the
victim is absent" option dies because absence at a known single appointment
is the one availability requirement the design has always accepted (V1's
window is exactly that). Bank accounting becomes trivially deterministic:
phase-2 filings are totally ordered on-chain events against a frozen chain —
no retroactive sole-obstacle intervals exist at all.

Bound, stated honestly in §5.4: phase 2 ≤ two banks (12h) + one 6h posting
grace per street transition (≤ 4) + honest runtime → dispute worst case
≈ 60 hours, adversarial, dispute-only, self-inflicted. §5.1's "fixed
length, known in advance" is restored as: the *evidence* deadline is hour
24 always; the *play* appointment is hour 24 always; only play's tail is
variable and bounded.

Also in revision 6, from the route back as given: equivocation priced (two
signed actions, same key, same (session, hand, seq, prevHash) is
cryptographic, one-sided, attributable → equivocator's bond burns);
the triple share check enumerated including ciphertext→deckRoot at the same
leaf index (§9.20 fixed); the total-resolution row (all checks pass yet
decode fails or the deck is malformed ⇒ both bonds burn, settle at receipt
baseline — reachable only when both signers misbehaved, no joint surplus,
checked against §0's law: a self-playing human loses two bonds to gas);
both-banks-empty deleted (unreachable: phase-2 obstacles are sequential and
the first empty bank terminates the hand); muck defined per-position;
non-bet actions sign amount 0.

State: revision 6 committed same sitting. Fourteenth check dispatched;
verdict lands below.

## Fourteenth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Revision 6 in full; `betting.ts`,
`game.ts`, `protocol.ts`, `elgamal.ts`, `cards.ts`, `Channel.sol`,
`prototypes/dispute-gas/README.md` in full; this doc from the twelfth check
on. ~6 tool calls, read-only.

**Headline.** Revision 6 fixed late-filed *decisions* — the frozen tip plus
the hour-24 appointment genuinely kills the thirteenth's withheld-bet lever.
But a withheld action can do a second thing the fix never covers:
**complete betting.** A wire-signed river call filed in the last block of
phase 1 makes the frozen hand *terminal*, so phase 2 never runs — and the
showdown-share duty it creates is a phase-1 duty with a deadline one block
after its birth. The muck row then convicts the diligent victim. The grace
rule that exists precisely for this is keyed on "born during phase 2", and
this duty is born at 23:59 of phase 1. **First revision where the
architecture itself produced no finding — the CRITICAL is a deadline
formula on one duty class.**

### Findings

1. **CRITICAL — a completing action filed in the last phase-1 block springs
   a showdown-share duty with no time to meet it; the muck row takes the pot
   and burns the victim's bond, and the only defence hands the attacker a
   free perfect-information decision.** Finding A, fourteenth appearance:
   which positions are required is decided by the frozen chain, but the
   duty's deadline is decided by phase 1's fixed clock, and the attacker
   controls the gap. Worked: pot 400 through the turn; river, B bets 300;
   A's modified client signs the call, transmits nothing, opens the dispute.
   Honest B files everything except hole shares — correctly, because posting
   them against a pending hand lets A (holding his own 52 shares locally)
   read B's cards and then choose fold-or-call with perfect information. At
   23:59 A files the call plus his own hole shares: terminal at
   consolidation, B's hole-share duty born and expired in the same minute →
   pot 1000 to A on a hand B won, plus B's 1100 bond. Both horns lose for B;
   no equivocation anywhere. Three readings of §5.2(4) are defensible; two
   are thefts.

2. **HIGH — §5.1's "show up once" and §5.4's "every deadline computable at
   consolidation" are false as written.** Per-duty graces let an opponent
   schedule your to-act moment across a ~36-hour tail: stall your own bank
   so flop betting closes at the victim's 11pm, post the turn share at
   grace-minus-epsilon the next night, and the victim's 6h bank runs
   11:30pm–5:30am while they sleep — a winning hand folded at an
   opponent-chosen instant, money bound intact (pot only) but the stated
   availability promise broken. Also unpinned: whether a to-act player may
   act *blind*, before the counterparty's board shares land (action legality
   never depends on the card).

3. **MEDIUM — the equivocation burn punishes a constructible innocent
   case.** Sign, transmit, crash before persisting, restore, legitimately
   re-decide: two distinct signatures at one node, 1100 burned for a crash.
   §6's persistence list omits signed actions; §9.16's "sign, chain, store"
   has no ordering between store and send. Also a secondary extortion lever:
   the peer holds both signatures and chooses whether to file the second.
   Fix is two sentences: write-ahead (persist before transmit); a restored
   client never re-signs at or below its persisted tip; then the burn is
   sound and should say it is conditional on that rule.

4. **LOW — the equivocation definition reads on identical duplicates** filed
   by both sides in overlapping segments. Add "distinct".

5. **LOW — boundary conventions unpinned:** which side of hour 24 the
   boundary block falls; grace-expiry vs filing in the same block;
   consolidation's trigger mechanics; client filing margin against
   sequencer delay.

### Verified sound — attacked and held

Consolidation determinism including out-of-order and interleaved filing
(single-key nodes, earliest-per-node, hash ties — total order; sequencing
games change nothing). Equivocation never profits its owner (un-betting
recovers ≤ M_i < bond). Maximum extraction against a fully absent opponent =
frozen pot + one bond, exactly §8.2 + §8.5's declared price; the pot cannot
grow without the absentee's signature; no stacked per-grace burns. The ~60h
bound arithmetic (cumulative banks cap alternating stalls; graces run in
parallel per transition; finding 1's fix adds one grace → ~66h). Truncation
dead (full-window evidence; the twelfth's hour-8 victim safe with no
admissibility judgment). The thirteenth's withheld-decision lever dead as
claimed. Open-fold cannot dodge the muck under phase-2 graces (board-share
graces extinguished by a fold are harmless; post-showdown muck strictly
dominated). Desert-then-return both directions. §1.3a timing-independent.
Filing spam self-limiting. The fourth row unreachable for one honest client.
Pre-signed phase-2 actions at 24:00:01 spend only the filer's own turn.

**Not reached:** `useGame.ts`, `worker.ts` vs revision 6's forfeit story,
evaluator/proof internals, §6 storage details, live marker latency.

### Route back

1. **Every posting duty's deadline = max(hour 24, birth + 6h)**, birth = the
   on-chain filing time of the action that made the position required; a
   frozen-terminal hand with unexpired posting graces resolves at the last
   grace, not at consolidation ("pending" includes pending postings). The
   late call is then irrevocably on file before the victim's shares appear —
   no peek in either direction. Restate the bound (~66h).
2. **Fix or downgrade the phase-2 timing claims**; decide blind action and
   client standing instructions.
3. **Write-ahead rule for signed actions** + §6 list + conditional
   soundness of the burn.
4. **Pin the words:** "distinct"; the hour-24 side; same-block precedence;
   the consolidation trigger; filing margin.

## Fifth design pass — 2026-08-17 — revision 7

Route back adopted as given, no deviation needed. The unifying rule that
finally holds: **no deadline may ever be older than the on-chain event that
created the obligation.** Phase 1's fixed clock applies only to duties whose
obligations exist at dispute-open; everything an action's filing brings into
existence owes max(hour 24, birth + 6h). Hole-share duties are born only by
a betting-completing action's filing — until then withholding is *correct*
(the peek defence), and after it the completer is irrevocably committed
before the counterparty's shares fall due. Write-ahead signing added to §6,
making the equivocation burn conditional-and-sound; "distinct" added;
boundary conventions pinned (half-open phase 1, same-block filings count,
lazy consolidation, filing margin); §8.11 declares phase 2's true
availability requirement with blind action and standing instructions as
legal mitigations; bound restated ~66h. Revision 7 committed; fifteenth
check dispatched.

## Fifteenth cold check — 2026-08-17 — RETURN TO DESIGN

Fresh reader, no inherited context. Revision 7 in full; `betting.ts`,
`game.ts`, `protocol.ts`, `elgamal.ts`, `cards.ts`, `Channel.sol`,
`prototypes/dispute-gas/README.md`; this doc from the thirteenth check on.
~5 tool calls, read-only.

**Headline.** The birth-deadline formula is sound end to end — the
fourteenth's trap is genuinely closed in both horns. What breaks is a
composition never given a rule: **"a `final` receipt short-circuits
everything" also short-circuits the equivocation burn.** The burn is the
only thing pricing the frozen-chain rewrite that earliest-filed-stands
hands the dispute opener, and §1.0 returns both bonds on any final — a
penalty both parties can jointly rescind, §0's own law walking back in
through §5.1's short-circuit.

### Findings

1. **CRITICAL — a `final` rescinds a proven equivocation burn; un-betting a
   transmitted losing wager becomes profitable.** 1000/1000, bonds 1100.
   River: B bets 300, A calls on the wire (500 each, pot 1000), sees he
   lost. A opens the dispute and in the opening block files a signed *fold*
   at the call's node; B's app files the true chain later. Equivocation: A's
   bond burns, **earliest-filed stands — A's fold.** Frozen: B 1200, A 800;
   A is net −800 vs truth — deterred, so far. Then A offers a final at
   (799, 1201): short-circuits everything, at the floor, **both bonds
   return.** B's choice: refuse → 1200 + own bond (A's burn pays B
   nothing); sign → 1201 + own bond. B signs; A nets +299 vs truth. Scales
   to any transmitted losing wager, approaching bond/1.1 for all-ins. Fix
   is one sentence: **a burn earned by on-chain proof is irrevocable — a
   final settles stacks but never restores a proven-burned bond.**

2. **MEDIUM — no §5.3 row for betting-complete with *both* sides missing a
   required position** (both machines die after chains auto-file at hour 0).
   "Resolves against you" applied to both is contradictory; totality claim
   false. Natural row: symmetric muck — both bonds burn, receipt baseline.

3. **LOW — burn multiplicity unstated:** one player can accrue equivocation
   + a missed grace; `burned` must credit one bond once. The accounting
   invariant held in every combination tried, including
   equivocator-wins-the-pot (coherent, never stated as allowed).

4. **LOW — write-ahead edges:** (a) persist-succeeds-transmit-never — the
   restored client must *send or file* its persisted unsent tip; no fork
   arises, but say it. (b) §8.4's cleared-storage case can innocently mint
   an equivocation pair; §9.1's refuse-to-resume is keyed to receipts/floor,
   not the action tip.

5. **LOW — words:** "nothing resolves during phase 1" vs finals; open-fold
   validity inside phase-1 segments; the hash tiebreak is nonce-grindable
   (no lever found); overlay baseline should be stated as the marker's
   embedded receipt.

### Verified sound — attacked and held

Birth-deadline both horns (fourteenth's case replayed: duty due 29:59,
frozen-terminal resolves at last grace; post-peek retraction impossible —
earliest-filed-stands means the completer's own filing beats any later
equivocation, and post-24h filings cannot enter the frozen chain). Grace
arithmetic (~66h checks out; phase-1-born graces parallel, ≤ hour 30).
Rebuy `(N−1,1)` retro-flip unreachable (marker pins its receipt; mid-hand
subseq needs both signatures). Blind action vs the peek defence (postings
need no human; no decision is ever forced blind; the always-instant client
composes to exactly §8.11's declared steering, pot-bounded). Write-ahead
core (crash-before-persist leaves no pair; crash-after re-sends the same
bytes). Truncation, withheld-decision, withheld-completing-action
(contingent on finding 1's fix), desert-then-return, muck-dodge, §1.3a,
absentee ceiling (a phase-2 raise into a bank-fold returns uncalled — the
pot cannot grow), consolidation determinism. §§5.1–5.4 timing claims honest
as rewritten except finding 5's wording.

**Checker's own note:** everything named in §11.1 held under construction;
the CRITICAL was found only by composing §5.1's short-circuit with §1.0's
bond-return sentence. *"Fix those two rules and revision 8 is a genuine
READY-WITH-DEFERRALS candidate."*

### Route back

1. Proven burns are irrevocable (equivocation, the fourth row, matured duty
   burns): a final settles stacks and closes the session, never restores a
   forfeited bond.
2. Add the both-sides-incomplete row (both bonds burn, receipt baseline).
3. Burns idempotent per bond (§1.4); restored client transmits-or-files its
   persisted tip; pin open-fold validity in phase-1 segments; overlay
   baseline = the marker's embedded receipt; "nothing resolves in phase 1"
   excepts finals.

## Sixth design pass + live measurement — 2026-08-17 — revision 8

Route back adopted as given. The rule that closes finding 1 generalises
§0's law one last step: **rescindability is the enemy wherever it hides,
including inside the good ending** — so anything the chain has *proven*
(equivocation, a bad deck, a matured missed duty) is beyond the reach of
any later mutual signature. A final still ends every honest session
exactly as before; what it can no longer do is launder a conviction.

Also this sitting, operator-approved: **first live Base Sepolia numbers**
(chain 84532). Marker post 61,740 gas; send→confirmed 0.7–2.9 s (n=3 — the
deploy key ran dry; top-up letter to ops sent same day). §4's deal gate
disappears into the shuffle. Both §11.2 gates now have real numbers.

Revision 8 committed; sixteenth check dispatched — told, as the fifteenth
was, that a true clean verdict is the needed information, and given the
finals-rule compositions as named targets.

## Sixteenth cold check — 2026-08-17 — READY WITH DECLARED DEFERRALS

Fresh reader, no inherited context. Revision 8 in full; `betting.ts`,
`game.ts`, `protocol.ts`, `elgamal.ts`, `cards.ts`, `Channel.sol`, both
prototype READMEs/RESULTS; this doc from the fourteenth check on plus
targeted greps. ~6 tool calls, read-only. Source claims spot-checked
(share purity, unsigned actions, domain binding, no-sweep contract).

**Headline (the checker's own words).** "I attacked every named target and
the newest text hard, including a full reconstruction of the fifteenth's
CRITICAL one step earlier in time — bribing the victim to *suppress the
equivocation proof* rather than rescind the burn — and the design survives
everything on in-model grounds. What remains are three LOW word-pins where
the spec's safety currently rests on an argument the text implies but never
states. None changes a rule. … This is a true clean at the rule level, and
I say so having genuinely tried not to find it."

### Findings — all LOW, all pins, each with a constructed case that FAILS under the rules as written

1. **Pin the final-vs-proof race.** The proof-suppression variant (obtain
   the victim's final before they file the equivocation pair) is dead
   twice over in-model — the victim's app auto-files within one ~1s block
   while a final needs a human signature, and two-player collusion over a
   fixed 4200 is zero-sum with an empty profitable intersection — but the
   deterrent's enforceability should not rest on unstated latency and
   bargaining arguments. Sentence: *bond disposition defers to misconduct
   evidence on file at payout execution; the evidence window for burn
   proofs survives a final.*
2. **Pin evidence admissibility to the window** (an equivocation pair must
   complete on file within phase 1), and note §6's blanket
   cleared-storage refusal is **load-bearing** — a builder must not relax
   it without the admissibility pin.
3. **Pin lazy crystallisation:** a burn is proven the moment the facts
   establishing it are on chain, whether or not any transaction has yet
   computed it.

### Verified sound — the full sweep

Post-burn asymmetric bargaining (no §1.3a inequality assumes bond
symmetry; "extortion" is just the dispute running at §8.1's declared
price). Manufacturing the counterparty's burn (equivocation needs two
signatures from the victim's key; §6's refusal rule means the second never
exists; matured duties unforceable — the spring-trap stays closed).
Symmetric muck vs §1.3: boundary single-valued (§1.3 = zero filings, and
steering into it never pays — the tenth's inequality holds pointwise,
worked at 200/1800; dead-man-switch included). Finals full sweep
(mid-phase-2 legal and coherent; below-result finals are mutual-only; the
final-beats-overlay precedence is safe now that no proven burn can be
laundered). Declared-depth bonds × phase-2 betting × the new rows.
Equivocation × bank accounting (no interaction). The n=3 latency caveat
(nothing money-bearing is seconds-scale; a 60s outlier pauses, never
penalises). Pre-signed-final race vs a crashed opponent (impossible).
Collusive steering into symmetric muck / fourth row (strictly
negative-sum).

### Deferrals, matched to declarations

§8.1–§8.12 all named and standing; §11.2(a)'s congestion-tail rerun gated
with the runbook and the ops top-up letter on record; §2.1 deferred to the
reputation arc. **"Contract work can start on §11's order as written."**

**Post-verdict action, same sitting:** the three pins were applied to the
spec verbatim as the checker drafted them — clarifying sentences, no rule
changes, per the checker's own analysis that every constructed attack
already fails without them. The verdict stands.

## Post-READY lineage note — 2026-08-17 — the §1.3 branch under the marker regime

Found during build planning (arc AF-4, two independent re-derivations).
Under revision 8's own rules, §1.3's both-bonds-burn branch is
**unreachable dead code**: zero dispute filings is observationally
identical to never-started (begun-ness is unattestable — exactly this
doc's finding-A discipline applied once more), so zero filings resolves
as never-started (full refund including bonds), and any filing routes
through §5.4's per-duty settlement. No attack opens in either direction;
the ahead player's incentive to file was always the operative protection,
and a full-window absentee's bond loss is §8.2's declared cost. The
sixteenth check's verified-sound entry cited the tenth check's 200/1800
worked case for this branch — stale since the marker rewrite (the state
it describes cannot arise at markedHand==0). The conclusion it decorated
("steering into §1.3 never pays") survives re-derivation; the citation
did not. V2's contract implements the reconciled rule and does not
implement the dead branch.
