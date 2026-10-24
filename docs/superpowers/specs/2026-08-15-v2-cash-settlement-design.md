> **SUPERSEDED 2026-08-16** by
> [the consolidated spec](2026-08-16-v2-cash-settlement-consolidated.md).
> **Do not build from this file.** Most of what follows was killed by cold
> checks — D1's three-number state, D2's per-action co-signing, A1's liveness
> path and A2's award formula among them. It is kept because the parking doc
> references its D-numbers throughout, not because it describes the design.

# V2 — cash game settled by final stacks: design

**Status:** NOT READY — two cold checks returned RETURN TO DESIGN. Pass 7
required, scoped to one question (see Pass 6 status). The first check returned RETURN TO DESIGN; its verdict is recorded in
full in the [parking doc](../parking/v2-cash-game-settlement.md) and every
finding is answered above. **Read Pass 6 before Passes 1-5** — it supersedes
parts of them.
**Parking doc:** [../parking/v2-cash-game-settlement.md](../parking/v2-cash-game-settlement.md)
**Repos:** `vault` (contract + local UI), `poker` (the table client)

A cash game whose buy-ins are escrowed on chain and paid out according to
what each player has left, rather than V1's winner-takes-all. Mid-match
rebuys allowed. Abandoning the table forfeits the pot to whoever stayed.

Passes: 1 settlement model · 2 disputes and timing · 3 session keys ·
4 rebuys · 5 scope and migration.

---

## Pass 1 — settlement model

### D1. The co-signed state carries three numbers, and the pot is one of them

**Locked 2026-08-15.**

State is `(nonce, hostAmount, guestAmount, pot)`, signed by both players.
Invariant, enforced by the contract on settlement:

    hostAmount + guestAmount + pot == total deposited

Carrying the pot as its own signed number is what makes the operator's rule
enforceable. The parking doc concluded the opposite — that awarding the
unfinished hand's pot to whoever stayed would need the contract to trust a
number only the beneficiary could supply. That was reasoning from V1's shape:
with a two-number state the pot is indeed unattested, but a three-number state
has both players' signatures over the pot itself, so it is not a one-sided
claim at all. **Amends the parking doc's "cannot work as stated" section.**

Settlement on abandonment: whoever stayed receives `theirAmount + pot`;
whoever left receives `theirAmount`. Sums to the total by the invariant.

### D2. Co-sign on every action, not per hand or per betting round

**Locked 2026-08-15.** Operator's call, against a recommendation of
per-betting-round.

Every bet, call, check, raise and fold produces a new state that both sides
sign. Roughly ten exchanges a hand rather than four.

Rejected alternatives:

- **Per hand.** Simplest, and it guts the feature: the pot is zero at every
  hand boundary, so the pot-to-whoever-stayed rule would essentially never
  fire and an abandoner would always get their money back.
- **Per betting round.** Four natural boundaries per hand, fewer states to
  reason about. Rejected because of the all-in case: shove, opponent vanishes
  before calling, round never closes, and the shover's money returns as though
  nothing happened. The operator wants abandonment to cost the abandoner.

The signatures ride on messages that already exist — the two tables already
exchange every action over the relay — so the added traffic is a field, not a
round trip.

### D3. The one-message signing lag is load-bearing, and falls correctly

**Locked 2026-08-15.**

Mutual signature on a state is necessarily one message behind: after A acts,
B holds A's signature and can complete the state locally, but A does not hold
B's signature on it until B replies. So the two sides are never symmetric —
whoever acted last is one state behind.

This is not a defect to engineer around. It resolves the abandonment cases
exactly as intended, in both directions:

- **B bets, then vanishes.** A holds the completed state including B's bet.
  A submits it and collects the pot. B's committed money is lost to them —
  correct, they abandoned after committing it.
- **A bets, then B vanishes.** A holds only the state from before their own
  bet. A submits that; A's money returns to A's stack. Also correct — the
  survivor should not be out of pocket for a hand nobody finished.

Design consequence: **never "fix" the asymmetry by having both sides withhold
until fully mutual.** That would break D1's rule in the first case.

### D4. State amounts are denominated in wei, not chips

**Locked 2026-08-15.** Mechanism, not an operator decision — recorded for
arc-plan.

The contract pays wei and should never learn what a chip is. The table
converts at a wei-per-chip rate fixed when the channel opens, so no rounding
enters the contract and no conversion table has to be stored on chain.

Follows: the opening buy-in must divide exactly into the starting chip count,
and every rebuy must be a whole number of chips at that same fixed rate.
Enforced at deposit time. Deferred to Pass 4 for the rebuy half.

### D5. Either player may stop; it takes effect at the end of the current hand

**Locked 2026-08-15.**

A cash game has no natural end, so with money escrowed something has to
release it. Either player announces they are leaving; the current hand plays
out; the escrow settles on the resulting stacks.

Rejected alternatives:

- **Stop immediately.** Makes leaving a *move*: bet, watch it go badly, quit
  before the hand resolves. That is folding without paying for it.
- **Both must agree.** A losing player can refuse to release the other's money
  and hold it hostage until they keep playing. Worse than the problem it
  solves.

The chosen rule is the only one under which stopping cannot be used as a
tactic in either direction — you cannot dodge a bet by leaving, and you
cannot be trapped at the table.

**Quitting and abandoning are deliberately different.** Announce and you keep
your stack, settled normally. Close the tab and the pot goes to whoever
stayed (D1). The gap between the two is what gives abandonment its cost, and
is intentional.

**Hit-and-run is allowed.** Winning one large pot and immediately cashing out
is permitted. It is a matter of manners, not safety, and a minimum-hands rule
would be a technical answer to a social problem. Revisit only on request.

---

## Pass 1 status: complete

Five decisions locked (D1-D5). No sub-questions left open; remaining unknowns
are carried below.

---

## Pass 2 — disputes and timing

### D6. A superseded submission forfeits its whole stake to the disputer

**Locked 2026-08-15, in principle. Threshold unresolved — see D6a.**

Every state ever signed stays valid-looking forever: it really was co-signed,
nothing about it is forged. So a player holding the whole history can submit
an early flattering one and, if nobody objects, collect on it. Concretely: the
true state is *them 20, you 380*; they submit the state from when you were
200 each and walk off with 180 of your money.

Superseding alone is a weak deterrent, because attempting it is free — worst
case the cheat collects what they were owed anyway. So a submission that is
superseded during the window forfeits the submitter's entire share to the
disputer. Cheating becomes worth attempting only against someone certain never
to return.

### D6a. The penalty needs a forgiveness threshold, or it punishes honesty

**Open. Must be settled before the contract is written.**

D3 makes the two sides legitimately hold *different* newest states — whoever
acted last is one behind, and cannot submit the newer state because they lack
the opponent's signature on it. A naive "any supersession is punished" rule
therefore penalises a player for the protocol's own lag.

Nor does "they signed the newer state, so they knew" work: under D3 the lagging
player *did* sign state N+1 — they just never received the counter-signature,
so submitting N was the only honest thing available to them.

Shape of the fix: forgive a gap the mechanism itself can produce, penalise
anything beyond it. The protocol's honest lag is believed to be exactly one
state, making the rule "gap of 1 supersedes without penalty, gap of 2+ is
punished" — but that bound is a hypothesis about the real message flow, not a
verified fact, and getting it wrong either punishes honest players or opens a
free one-state cheat. **arc-plan must derive the true bound from the actual
action/acknowledgement sequence before this is implemented.**

### D7. Challenge window: 24 hours

**Locked 2026-08-15.**

Only runs when someone settles alone. Cooperative settlement pays out
immediately and can also short-circuit an open window at any point, so the
full day elapses only when a player genuinely never returns.

24 hours covers a dead laptop and a night's sleep. An hour was rejected as too
short for anyone not sitting back down the same evening; a week locks an
honest survivor's winnings up for no additional protection.

### D8. Objections are signed by the session key, and fire on open

**Locked 2026-08-15.**

Reopening either app reads the chain, notices a submitted state older than the
one held locally, and objects — with no wallet prompt, because the session key
(Pass 3) signs it rather than the wallet.

Safe rather than merely convenient: an objection can only present a state both
players already signed, so it cannot invent anything. The session key is
restricted to raising an objection with a *higher-numbered* state — never
starting a settlement, never changing a payout address. A compromised session
key can therefore only push the outcome toward the truth.

Nothing can be fully background: sending a transaction needs a page running.
"Open the app" is the whole user action, and it needs no expertise and no
button.

### D9. The bare address is a recovery page; states are stored under both origins

**Locked 2026-08-15.**

Signed states are stored per origin, not per link — so a returning player
needs no invite link, no room key, nothing they were sent. Landing on the
address is sufficient.

Buyin's no-session screen currently says "Missing ?session= — open this from
the poker client's Buyin button", which is exactly the wrong thing to tell
someone whose browser just died. It becomes a recovery page: enumerate every
session this browser holds state for, check each against the chain, act on
what needs acting on.

States are written under **both** the poker origin and the Buyin origin. They
are separate storage areas, so a player covered in both is covered wherever
they land — they never have to know which app was which. The copies are
identical signed data; if they ever disagree, the higher nonce wins.

The address is shown during normal play (rules panel, Buyin) so it is seen
before it is needed rather than hunted for afterwards.

### D10. Signed states never leave the player's own browser

**Locked 2026-08-15.**

No server copy, no sync service, nothing to trust or breach. The accepted cost:
clearing browser data during an open dispute window destroys that player's
ability to defend themselves, and nothing local can recover it.

Rejected because every version of "store it somewhere else" reintroduces a
trusted party, which is the thing this project exists to avoid. The failure
requires someone to wipe their data inside a 24-hour window; the cure would
weaken the guarantee permanently.

---

## Pass 2 status: complete except D6a

D6-D10 locked. **D6a is a blocking open question** — it must be resolved
before contract work starts, and it is a verification task, not an operator
decision.

---

## Pass 3 — session keys

### D11. Two keys in one tab, with opposite persistence rules

**Locked 2026-08-15.** Stated explicitly because it is the most confusing part
of the design and the rules look contradictory until the reasons are side by
side.

- **The card key** decrypts hole cards. Memory only, **dies with the tab**, by
  design — that is what guarantees nobody, the operator included, can reopen
  a played hand.
- **The session key** signs game states so there is no wallet prompt per
  action. **Must survive the tab closing**, or a crashed browser can never
  object to a stale state and every protection in Pass 2 is theatre.

Neither rule may be "harmonised" with the other. They protect different things
and point in opposite directions on purpose.

### D12. The session key persists, and is deleted on settlement

**Locked 2026-08-15.**

Exposure while a channel is live is real and worth naming: a stolen session
key combined with a *colluding opponent* can manufacture a state where the
victim holds nothing, correctly signed by both. Not a small risk — the whole
stack.

Bounded by: per match, never reused; scoped to one origin's storage; deleted
the moment the channel settles, after which it is worthless. Accepted because
the alternative loses the recovery path that Pass 2 is built on, and the
likely failure (browser died) beats the exotic one (profile theft plus a
colluding opponent).

### D13. The stored session key is encrypted with a wallet-derived key

**Locked 2026-08-15.**

Encryption only helps if the decryption key lives somewhere the thief cannot
reach. Two candidates qualified; one intuitive option does not.

- **Rejected as theatre:** encrypting the key and storing the secret beside it
  in the same browser. Anyone who can read one can read the other.
- **Chosen:** derive the encryption key from a wallet signature over a fixed
  message. Copied browser storage yields ciphertext alone — the thief also
  needs the wallet. Costs one wallet tap on reopen.

### D14. Wallet determinism is tested at runtime, once per wallet

**Locked 2026-08-15.**

D13 rests on the wallet producing an identical signature for the same message
every time. MetaMask does; this is not guaranteed across wallets.

Sign twice at first use and compare. Definitive for that wallet and version,
where a compatibility list goes stale on the next wallet release and says
nothing about wallets nobody has tried. The verdict is cached per wallet
address: two taps the first time a wallet is ever used, one thereafter.

A published known-good list is worth keeping as documentation. It is a hint,
never the gate.

### D15. A non-deterministic wallet persists the key unencrypted, loudly

**Locked 2026-08-15.**

Refusing to persist would trade the *likely* failure (browser died, needs to
object) against the *exotic* one (profile copied and opponent colluding).
Wrong way round, and the same reasoning as D10.

The player is told in plain words which protection they are missing, on
screen, at the time.

### D16. Browser-held non-extractable keys: gated upgrade, tested not assumed

**Locked 2026-08-15 as a phase-1 experiment, not a dependency.**

Browsers can hold a signing key a page may use but never read; the private key
never enters JavaScript, so copying the profile does not yield it. Strictly
stronger than D13.

It needs the chain to verify P-256 signatures. **Verified 2026-08-15:** Base
carries the `p256Verify` precompile at `0x100`, added in the Fjord upgrade
([Base docs](https://docs.base.org/base-chain/specs/upgrades/azul/exec-engine),
[OP Stack spec](https://specs.optimism.io/protocol/precompiles.html)).

Two caveats keep it out of the critical path:

- An open report of that precompile returning empty returndata in a **real
  transaction** while working under `eth_call` on an OP Sepolia testnet
  ([discussion](https://github.com/ethereum-optimism/developers/discussions/791))
  — precisely our situation.
- [EIP-7951](https://eips.ethereum.org/EIPS/eip-7951) supersedes RIP-7212 with
  the same interface "without the vulnerability", so what is deployed today
  carries a known flaw.

Therefore: build on D13, and spend an hour in phase 1 smoke-testing a real
Base Sepolia transaction through the precompile. Adopt on success, drop on
failure, having lost an hour rather than a design.

---

## Pass 3 status: complete

D11-D16 locked. D16 carries a bounded experiment into phase 1.

### D17. Encrypted off-device backup, designed in and gated on neutral hosting

**Locked 2026-08-15 as conditional. Not buildable until Pass 5 settles hosting.**

The session key is already encrypted to the wallet (D13), so a server can hold
the sealed blob without becoming a trusted party for confidentiality — it
stores something it cannot open. This directly answers three costs accepted
earlier: D10's cleared-data loss, D9's same-browser limit, and the dead
machine.

**The attack it does not survive, and the reason it is conditional.** A backup
server cannot read the blob but does choose *which* blob to return. Handing
back an older one leaves the victim restoring a stale state, objecting with
it, and losing — undetectably, because the very situation being recovered from
is "my local copy is gone". That requires the server and the opponent to
cooperate.

Which is fatal in the current configuration: **the server is one player's own
machine.** For a guest, the backup service would be run by the person they are
playing against — not a hypothetical conflict but the default setup.

So the backup lives somewhere neither player controls, or it does not exist.
Same question as "a guest on another network cannot reach the recovery page",
and settled in Pass 5 alongside it. Additive and contract-neutral, so it can
land after the first release.

---

## Pass 3 addendum status

D17 added. Watchtower (a service that objects *for* you, so the 24-hour window
stops mattering) parked as a future arc — it needs neutral hosting *and* a
delegated dispute-only key, and is a build in its own right.

---

## Pass 4 — rebuys

### D18. Top up any time between hands; never mid-hand

**Locked 2026-08-15.**

Real cash-game behaviour, and heads-up it matters more than it sounds: if only
a busted player could rebuy, the winner's stack grows while the loser refills
to the starting amount forever, and the game is permanently lopsided. Topping
up lets the short stack match, which is what keeps the play deep.

Every top-up is an on-chain transaction, so the table stops while it confirms
— heads-up there is no sitting out. Accepted because the interruption is
self-inflicted and visible to both, so it polices itself socially, whereas
the stack imbalance is structural with no way to opt out.

**Never mid-hand**, without exception. Standard poker, and here it would also
let a player shove, watch it go badly, and top up to survive.

### D19. A stuck rebuy resumes the table after 30 seconds

**Locked 2026-08-15.**

An approved transaction can simply not land — underpriced gas, a dropped
wallet, a network hiccup. Waiting indefinitely turns one stuck transaction
into a dead session, which is the unbounded-wait failure this project spent a
whole session removing elsewhere.

Visible countdown, 30 seconds, then play resumes on the stacks already held. A
Base transaction normally lands in well under ten, so 30 seconds means
something is actually wrong rather than merely slow.

**Late money never becomes chips.** It sits unassigned in the escrow and is
refunded at settlement. So a late rebuy costs the top-up, never the money —
and it cannot materialise mid-hand, which would violate D18.

### D20. Chips can be added but never removed; stacks are capped

**Locked 2026-08-15.** Standard poker, recorded rather than asked.

No taking money off the table mid-session ("going south") — it exists to stop
a player banking a win and playing on short. And a maximum stack, because
heads-up anything above the opponent's stack cannot be won or lost: escrowing
past that is money locked up doing nothing.

### D21. The buy-in is 200 big blinds, and the table shows what that is worth

**Locked 2026-08-15.** Operator's call, and the second half was not on my list.

The agreed crypto amount divides into **200 big blinds**. Blinds are fixed in a
cash game (they only climb in a freezeout), so the chip-to-money rate is
constant for the whole session — which is what makes the display below
truthful rather than approximate.

**The table shows the real-money equivalent alongside the chips**, so a player
can always see what their stack is actually worth rather than doing arithmetic
on an abstraction. Chips make the game readable; the equivalent is what keeps
people honest with themselves about what is on the line.

Squares with D4: 200bb at a 2-chip big blind is a 400-chip starting stack, so
the fixed rate is `buyIn / 400` wei per chip, and the buy-in must divide
exactly.

*Note for testnet:* the displayed amount is worthless test ETH. The display is
still right to build — it is the habit that matters — but it is a rehearsal of
the number, not the number.

### D22. Deposits are carried in the state; unaccounted deposits are refunded

**Locked 2026-08-15.** Mechanism, recorded for arc-plan.

Rebuys change the total deposited, so D1's invariant cannot compare against a
single fixed figure — a state signed before a rebuy would sum to the old total
and fail. The state therefore carries each player's deposited amount, and the
contract checks those do not exceed what it actually received.

Settlement pays the state's amounts, then refunds each player any deposit the
state does not account for. A state predating a rebuy simply returns that
rebuy to whoever made it, which is also exactly the D19 late-money behaviour —
one rule, both cases.

---

## Pass 4 status: complete

D18-D22 locked.

---

## Pass 5 — scope, migration and hosting

### D23. V2 runs from stable HTTPS subdomains of `slipgate.me`, not the LAN

**Locked 2026-08-15. Requires the server administrator (the server admin) to provision —
see the letter in `~/letterbox/to-ops/`.**

Hosting turned out to be a constraint rather than a preference. **The browser's
built-in crypto is unavailable outside a secure context** — HTTPS or localhost
— so on today's `http://192.168.1.205:8790` the key derivation and encryption
locked in D13 cannot run at all, and D16's browser-held key is impossible
rather than merely untested. A pure-JS crypto library would rescue D13 alone,
weakly. Where this runs therefore decides whether Pass 3 is real.

Four things resolve together:

- **Secure context**, so D13 works and D16 becomes testable.
- **A stable address reachable from any network**, which is what D9's recovery
  page needs — a guest whose browser died can currently reach nothing.
- **Neutral relative to the players.** This is the precise requirement D17
  named, and it is satisfied here not by "run by nobody" but by "not run by
  your opponent". the server admin holds no stake in any match.
- **An address worth printing** in the rules panel, instead of a LAN IP that
  works only in one flat.

**The trust this does and does not require.** Buyin is entirely static — no
backend, no database; it talks to the chain through the player's wallet — so
hosting it grants the host no read access to anything. The relay is a server,
but it was designed untrusted and forwards bytes it cannot read. The one real
trust assumption arrives with D17: a backup host chooses *which* sealed blob
to return, so the assumption is **"the server admin does not collude with your
opponent."** Reasonable, and worth stating rather than absorbing silently.

Rejected: neutral third-party static hosting (Cloudflare/GitHub Pages). Equally
free and equally secure-context, but it cannot store anything, so D17 would
stay blocked. A real server is strictly more capable here and no less neutral
in the sense that matters.

**Migration note:** changing origin orphans anything in the LAN version's
browser storage. Irrelevant for V2, which starts on the new origin — but V1
sessions must be settled before, not across, the move.

### D24. V1 and V2 run side by side, with a stated plan to fold freezeout in

**Locked 2026-08-15.**

Freezeout keeps using V1's deployed winner-takes-all contract; cash games use
V2. **The duplication is explicitly temporary**, and saying so is the point —
"two contracts forever" is what happens by default when nobody writes down
that it was meant to be temporary.

V2's mechanism can already express V1's: winner-takes-all is a final state of
`(winner: total, loser: 0, pot: 0)`. So the fold-in is a migration, not a
rewrite.

**Fold-in trigger:** V2 has settled real matches across all four of its
endings — cooperative close, abandonment, a successful challenge, and a rebuy
— without an amendment to this spec. At that point freezeout moves to V2 and
V1 is retired with a `Replaces:` declaration.

Rejected: replacing V1 now. It is the only part of this system proven against
real transactions, and V2 touches money in more ways while having met no
users. Keeping the working thing alive costs some duplication and buys the
ability to be wrong in public without taking freezeout down too.

---

## Pass 5 status: complete

D23-D24 locked. Design complete pending the cold intent check.

---

## Pass 6 — remediation (2026-08-15)

Triggered by the cold intent check's RETURN TO DESIGN. These amendments
supersede parts of D1-D24; the originals are left standing above so the record
of what was wrong, and why, survives.

**Root cause, stated once.** These five passes never opened
`vault-handover.md`, which `CLAUDE.md` names as the project's source of truth
and which contains a V2 section answering most of what was designed from
scratch here. Every amendment below is either recovering something that file
already said, or repairing damage from not having read it.

### A1 — amends D1. No unilateral abandonment claim; liveness is tested, not asserted

D1 paid "whoever stayed" with no means for the chain to learn who that was,
collapsing to "whoever submits first" and handing the bettor every pot they
lost at showdown.

`vault-handover.md` states the governing principle: *"The chain cannot see who
lost their internet. So do not try to prove a disconnect. Test for liveness
instead, which is the same question asked in a form the chain can answer."*

V1's deployed path is reinstated unchanged:

1. Claimant calls `claimByDefault()`, **posting a bond of 10% of the buy-in**
   (`BOND_BPS = 1000`, already in `Channel.sol`). Window W1 opens.
2. Opponent silent through W1 → claimant takes the pot, bond returned.
3. Opponent calls `iAmHere()` inside W1 → the claim was false, **the bond goes
   to the opponent**, and W2 opens in which the opponent must produce a
   cooperative close. Produce nothing by the end of W2 and the original claim
   resolves in the claimant's favour after all.

Step 3's second half is load-bearing and easy to omit: without it, a player
who is alive but simply refuses to sign a loss refutes forever and nobody is
ever paid. **Proving you are alive obliges you to settle.**

**The operator's rule survives.** Whoever did not close the browser still ends
up with the pot. It is no longer instant, and that is exactly what stops it
being a theft: a false claim now costs a bond and a wait.

### A2 — amends D1, D2, D3; dissolves D6a. Two artefacts, not one state

Replaces the single co-signed `(nonce, host, guest, pot)` tuple with the
construction already specified in `vault-handover.md`:

- **Receipt** — *mutually* co-signed, one per hand boundary:
  `(session, hand, stacks{host,guest}, deposits{host,guest})`. `hand` is the
  dispute nonce; highest wins. **No pot field** — at a hand boundary the pot
  is zero by definition, which is why receipts are clean.
- **Signed action** — *unilaterally* signed, one per action:
  `(session, hand, seq, committed)`. Each player signs only their own
  committed amount for the live hand.

A mid-hand forfeit publishes **the latest receipt plus the opponent's own
latest signed action**. Award: claimant receives `theirReceiptStack +
opponentCommitted`; opponent receives `theirReceiptStack - opponentCommitted`.
Sums to the total.

Three properties, quoted from the source spec: you cannot overstate the pot
(only what they signed), you cannot understate it (that only hurts you), and
they lose exactly what they put in, not a chip more.

**D6a is deleted, not deferred.** It existed only because a mutually-signed
state needs a counter-signature that arrives one message late. A forfeit claim
now presents the *opponent's own* signature, which the claimant already holds,
so there is nothing to wait for and no lag to forgive. The blocking question
was self-inflicted by a design that did not need to exist.

D3's asymmetry analysis is now irrelevant to settlement. Retained above as
reasoning, not as an active constraint.

### A3 — amends D6. The penalty attaches to receipts, which have no lag

Publishing a receipt beaten by a higher-numbered one forfeits the publisher's
entire deposit. Unchanged in severity, and now sound: receipts are mutually
co-signed at hand boundaries where both sides hold the same newest one, so
there is no honest gap to punish and no forgiveness threshold to derive.

Also resolves finding E: with the penalty scoped to receipts rather than to
any submission, and objections restricted to presenting a higher receipt, D8's
claim that a compromised session key "can only push toward the truth" holds
again. **D12's bound is restored to "a stolen key *plus* a colluding
opponent".**

### A4 — repairs a regression. Domain separation is mandatory

D1 signed `(nonce, host, guest, pot)`. The parking doc had specified
`(contract, chainid, session, nonce, …)`, and `Channel.sol:105` already binds
`address(this)`, `block.chainid` and `sessionId`. Dropping them lets a state
signed in one match replay into another match, deployment or chain.

**Both receipts and signed actions bind contract address, chain id and session
id into the hash.** Not optional, not an arc-plan detail.

### A5 — restores a dropped requirement. Three clocks, named

The parking doc asked for a five-minute reconnect window "as now". No decision
carried it. It is restored, and all three timers are named here because
conflating them is how this gets built wrong:

| Clock | Length | Decides |
|---|---|---|
| Table reconnect grace | 5 min (staked) / 1 min (play money) | whether the *table* declares a forfeit. Off-chain, already built (`graceFor`) |
| W1 — liveness window | **30 minutes** | whether an on-chain forfeit claim stands |
| W2 — settle-or-lose | 30 minutes | how long a player who proved liveness has to settle |

**D7's 24 hours is superseded.** It was set before the liveness test existed,
when the window was the only defence. With a bond making false claims costly
and `iAmHere()` a single click, 30 minutes suffices for anyone at their
machine — and matches V1, so there is one behaviour to understand rather than
two. Per-session configurable, as `Channel.sol` already allows.

### A6 — resolves finding H. Supersession has no pot ambiguity

Receipts carry no pot (A2), so a settlement by superseding receipt pays the
stacks in that receipt and nothing else. The question of who collects a
disputed pot does not arise. Deposits unaccounted for by the winning receipt
are refunded per D22.

### A7 — amends D10 and D17. The contradiction is named and resolved

D10 ("states never leave the browser") and D17 (an off-device backup) cannot
both stand. **D17 amends D10**, and D10 is to be read as superseded once
backup ships. A builder reading in order previously built no backup.

D17's mechanism was also unspecified: D13 encrypts *the session key*, while
the thing needing backup is *the receipts and signed actions*, which no
decision encrypts. **Backing up game artefacts requires its own sealing scheme
plus freshness protection against the rollback attack D17 itself identifies.**
Still gated on hosting; now honestly scoped.

### A8 — amends D16. The "strictly stronger" claim was wrong

A non-extractable WebCrypto key is a software key in IndexedDB, not
hardware-bound, and **has no user-presence gate** — a thief running a copied
profile signs freely. D13 forces that same thief to also hold the wallet.
Against D13's own threat model, D16 may be **weaker**, not stronger. It
remains a bounded phase-1 experiment, now for the right reason: it removes
key *extraction*, not key *use*.

The Fjord/Azul citation mismatch stands as noted; confirm the precompile
against Base's own upgrade history during the phase-1 test.

---

## Pass 6 status: INSUFFICIENT — second cold check returned RETURN TO DESIGN

A1-A8 closed the bookkeeping findings and did not close the founding one.
**A1 and A2 were written against different premises**: A2 assumes the chain
already knows someone left, A1 introduces a test for whether they left, and
nothing joins them. The showdown robbery survives both readings of A1 step 3.

Do not build against this spec. See the second verdict in the
[parking doc](../parking/v2-cash-game-settlement.md).

**Pass 7 must answer exactly one question before anything else: what does the
chain do when liveness is proven mid-hand?** N1, N2, N9 and the table-grace
linkage all collapse out of that one answer.

---

## Carry-forwards

| Item | Track |
|---|---|
| Reachability: a guest on another network cannot reach a LAN-hosted recovery page | Pass 5 (hosting) |
| How the wallet authorises the session key to the contract (off-chain attestation presented at settlement, vs on-chain registration) | arc-plan |
| D16 — smoke-test the P-256 precompile in a real Base Sepolia transaction | phase 1, bounded to ~1h |
| Whether crypto cash games expose the existing 100bb depth option or force 200 | arc-plan |
| Where the maximum stack cap is set (D20) | arc-plan |
| D17's backup storage — unblocked by D23 in principle, still to be provisioned | arc-plan, after hosting lands |
| Watchtower service | separate future arc (parked) |
