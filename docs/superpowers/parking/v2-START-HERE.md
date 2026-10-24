# V2 cash settlement — start here

Written 2026-08-17 to hand this arc to a fresh session without replaying the
conversation. **Read this file, then the spec. Do not read the parking doc
front to back** — it is 1500 lines of history and you only need it when you
want to know *why* something was rejected.

## What is being built

A heads-up poker cash game whose buy-ins are escrowed on chain and paid out by
**final stacks**, with mid-match rebuys. Two repos: `~/projects/vault`
(Solidity + Buyin UI) and `~/projects/poker` (the table client). V1 —
winner-takes-all freezeout — **is built and running live** on
`poker.slipgate.me` / `buyin.slipgate.me`. V2 is design-only. No V2 code exists.

## The one idea

The chain can verify exactly one thing: **a receipt carrying both players'
signatures.** It cannot see the cards, the network, or who walked away.

Sixteen cold checks have run. **The sixteenth returned READY WITH DECLARED DEFERRALS; the fifteen before it each found something, and almost every
failure was the same failure** — a rule that quietly asked the chain to identify *who*
abandoned or *who* won. That is a one-sided unattestable claim. The parking doc
calls it **finding A**. It has come back through a side door every single time
someone patched something else. Assume your next idea has it in it.

The tenth found its newest door: when the chain cannot see that a hand happened,
§1.0 hands that question to the *players* — and the signature it then requires
belongs to the party who profits from the hand not having happened. Watch for
finding A appearing as **something the two of them can agree to undo**, not only
as something the chain is asked to judge.

## Where things stand

| | |
|---|---|
| **Build from** | `../specs/2026-08-16-v2-cash-settlement-consolidated.md` (revision 8) |
| **Why, and every rejected idea** | `v2-cash-game-settlement.md` — grep it, don't read it |
| **Status** | **READY WITH DECLARED DEFERRALS** — sixteenth check, 2026-08-17. Design phase closed; three word-pins applied post-verdict |
| **Blocking next step** | Operator go-ahead to plan the build (arc-plan against spec §11's order) |

Revision 1 was checked and returned RETURN TO DESIGN. That ninth check
**verified the bond arithmetic as sound** — nine constructed cases, none where
refusing pays — and broke the design somewhere else instead. Revision 2 rewrote
§§1–5, 8, 9, 10, 12 against that verdict.

## The next three things, in order

1. **Plan the build.** The design is ratified: sixteenth check, READY WITH
   DECLARED DEFERRALS, verdict in the parking doc. Next step per the
   harness: arc-plan against spec §11's build order. Both §11.2
   measurements have live numbers; the congestion-tail rerun (n=3 caveat)
   happens when ops tops up the deploy key (letter sent 2026-08-17).
   gas, cost, and the wall-clock gap it puts between hands (§4's deal-gate
   makes latency structural now, not just cost); (b) the dispute path's gas —
   `verifyDleq` per share, Merkle checks, an evaluator prototype. Either
   number unaffordable → back to design, not a quiet narrowing.

3. Only then, §11's build order.

## Rules that are settled — do not relitigate

Each cost multiple passes. Reopening one without new evidence wastes a session.

- **Settlement is by final stacks, never winner-takes-all.** That is V1, and
  replacing it is the entire point of V2.
- **No liveness inference, ever.** No server timestamps, no "who replied last",
  no lag thresholds. In heads-up the deserter holds the newest signature, so
  every liveness signal is inverted.
- **Bonds burn; they are never paid to the counterparty.** Paying across makes
  *starting* a dispute profitable, and the chain cannot identify a victim.
- **No per-hand pot cap.** The bond is sized to the largest possible pot
  instead. Operator was explicit: no cap on all-ins.
- **No commit-and-accept on actions.** Two Generals — there is always a last
  message nobody acknowledged.
- **The relay holds no game state.** `relay/server.mjs` says so and means it.
- Full list with reasons: spec §10.

## Operator context

Raptor is **new to the terminal and new to code**. Plain language, recommend
rather than present menus, say what a command does before running it. He is
sharp about the design itself — **§1.3's refund-on-no-filing rule is his idea**,
and it is the fix for the ninth check's worst finding. Do not talk down.

He has been burned by me bundling several changes into one commit and by me
over-claiming that a design held when it did not. **One change per commit.
Report what the check actually said, not your reading of it.**

## Hard constraints

- **Testnet (Base Sepolia) only.** No mainnet path, ever, without an explicit
  new instruction. Re-approval trigger, not a code change.
- **No server-side storage without a new letter to ops** (`~/letterbox`). This
  gates the encrypted backup *and* the reputation arc.
- Print the chain ID and stop-and-ask before anything touching a real network.
- Never handle a seed phrase. Secrets go through `secret-drop`, never chat.
- The deploy key and the poker client's session key never share a variable,
  file, or process.
- Do not hardcode `slipgate.me`. Do not add TLS or HTTPS redirects in node.
- `forge test` must actually run before any claim about contract behaviour.

## Related

- [Reputation and profiles](reputation-and-profiles.md) — future arc, the
  intended relief for a 110% bond. Blocked on the same ops letter.
- [Watchtower](v2-watchtower.md) — parked; the answer to §8.6.
