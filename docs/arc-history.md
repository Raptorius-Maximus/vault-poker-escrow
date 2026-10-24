# Arc history

Shipped arcs, one paragraph each. Ongoing and future work lives in
[HANDOVER.md](../HANDOVER.md) — this is the record of what's actually done.

## V1: winner-takes-all sit-and-go escrow — shipped 2026-08-13

Full loop built and verified end to end: deposit, auto-sign at match end,
cooperative close, funding enforcement, and the liveness-based dispute path
(claim-by-default → refute → resolve) for a stalled opponent. Renamed
user-facing "Vault" → "Buyin". Two real bugs surfaced and got fixed during
Loke's own testing rather than in review: a dead-window silent-failure bug
in the poker repo's match-end signature delivery (fixed with a `.closed`
check plus `sessionStorage` persistence, so a closed-and-reopened Buyin tab
recovers instead of losing the signature forever), and Buyin's own URL
being hardcoded to `127.0.0.1` (worked only when both apps ran on the same
machine, and failed flatly the moment Loke reached it from a phone over the
LAN). With both fixed, Loke ran a full match over the LAN with two browser
seats, two testnet wallets, and a real payout — Buyin correctly reached
`Status: Closed` on both sides. Deployed to Base Sepolia at
`0xF41A685C7e260397Be07cC75008D29A7457481f6`, dispute window 1800s (30
min). Not yet run by two separate people on two separate machines — that's
V2's trigger condition, still open.
