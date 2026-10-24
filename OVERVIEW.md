# Overview

**Last reviewed:** 2026-08-13

## What exists right now

V1's escrow contract is written, tested (26 adversarial tests, `forge test`),
and **deployed live on Base Sepolia** — see Deployments below. Vault's own
local UI (connect wallet → open/join → in progress/dispute → close) exists
and the deposit half is verified for real: Loke ran a full open() + join()
through the actual browser UI with two MetaMask accounts standing in for two
players, confirmed independently on-chain (host and guest both deposited,
status Active, real pot locked). That pass also caught three real bugs no
amount of reading the code would have — a poll that wiped in-progress form
input, a race that could duplicate rendered cards under a slow RPC, and a
missing `chain` parameter that failed every write — all fixed and verified
afterward. **Part 3 (the poker client) is now fully implemented**: the
button, the postMessage handshake in both directions, and match-end
auto-signing (each side signs independently the instant a freezeout ends
and exchanges signatures over the existing relay, so a cooperative-close
artifact exists before the dispute path would ever need to run). Verified
by unit tests on the poker side (230 passing, including a cross-check that
the signing hash formula matches Channel.sol's exactly) and by Vault's own
live deposit test — but **not yet run end to end with a real, complete
match** (that needs two browsers actually playing a freezeout to
completion, which is necessarily Loke's step). The full design — for both
V1 and V2 — arrived
pre-written as a handover doc from a prior session and lives at
`docs/superpowers/specs/vault-handover.md`; that document is the source of
truth for every design decision below, this file is the living summary.

## Where it runs

Live at **`https://buyin.slipgate.me`** since 2026-08-15, alongside
`https://poker.slipgate.me`, as reverse proxies onto the two node processes on
their existing ports. Nothing of ours is copied anywhere and there is no CI:
each app serves its own built output, so rebuild plus restart is the whole
deploy.

**HTTPS is a requirement, not a nicety.** Browsers withhold the Web Crypto API
outside a secure context. `http://localhost` is exempt; a LAN address is not —
so the V2 design's wallet-derived encryption cannot run on the old
`http://192.168.1.205:8790` at all. That single fact is why hosting moved.

Two conditions attached to the grant, both standing: **testnet only** (a
mainnet plan requires a new conversation before shipping, not just a code
change), and **no server-side storage without a further letter** — which is
what gates the V2 design's encrypted backup. The domain is a loan, so no
hostname is hardcoded anywhere; moving to another domain should be a DNS
change and nothing else.

## Deployments

| Network | Address | Deployed |
|---|---|---|
| Base Sepolia | [`0xF41A685C7e260397Be07cC75008D29A7457481f6`](https://sepolia.basescan.org/address/0xF41A685C7e260397Be07cC75008D29A7457481f6) | 2026-08-12 |

Deploy key lives at `~/projects/.secrets/vault-deploy.env` (outside the repo,
outside the writable lane `secret-drop` allows for project-local `.env`
files — see that file's own registry). Redeploying gives a new address; the
UI must read the address from config, never hardcode it (spec's own
guidance — a deployed contract can't be patched).

## Code landmarks

| Thing | Where | Note |
|---|---|---|
| Full design spec | `docs/superpowers/specs/vault-handover.md` | V1 + V2 + operational guidance, pre-written, treat as ratified |
| V1 contract | `contracts/src/Channel.sol` | Escrow + dispute-window settlement |
| V1 tests | `contracts/test/Channel.t.sol` | 26 adversarial tests, all passing |
| Deploy script | `contracts/script/Deploy.s.sol` | Refuses to run off Base Sepolia (84532) or local anvil (31337) |
| Vault server | `server.mjs` | Static file server on `0.0.0.0:8790`. Sends `Cache-Control: no-cache` plus an mtime/size ETag, so a repeat visit revalidates into an empty 304 and can never run a stale bundle — it previously sent no cache header at all, which is not "no caching" but "browser decides" |
| Keep-alive | `run.sh` | Supervises the server: restart on exit, backoff on instant failure, `flock` so a second copy refuses rather than fighting for the port, logs to `~/projects/.logs/` (which survives a container rebuild — `~/` does not). Started by `~/dotfiles/start-stack.sh` |
| Vault UI | `src/main.js`, `src/abi.js`, `src/deployments.js` | Connect → open/join → in progress/dispute → close, as one page with state, no framework |
| Vault build | `build.mjs` (`npm run build`) | esbuild bundles `src/main.js` → `public/bundle.js` (gitignored, regenerate after any `src/` change) |

**A known asymmetry in the dispute path, found while designing the signing
flow — mitigated now, not fixed at the contract layer:**
`claimByDefault`/`iAmHere`/`resolve` can't distinguish "the party being
claimed against is the actual loser stalling" from "the party being claimed
against is the actual winner who's just briefly away" — both look identical
on-chain, but the correct outcome is opposite. Two "obvious" fixes (default
to the refuter instead of the claimant, or vice versa) each just move the
exploit to the other player; traced both dead ends before concluding the
contract alone can't resolve this with liveness/bond mechanics only. The
mitigation, now built: the poker client auto-signs the match result the
instant it's decided, so a legitimate cooperative close exists before the
dispute path would ever need to run in the honest case. Residual risk: a
custom/malicious client that refuses to auto-sign could still attempt this.
Bounded to the session's own buy-in, testnet-only for now.

## Design intent

**Why V1 and V2 are staged, not built together:** V1 (sit and go) has one
winner, so vanishing costs the entire buy-in — that penalty alone makes
disconnecting-to-dodge-a-loss a losing move, which is what makes V1 small (a
single contract, no per-hand state). V2 (cash game) has no single winner —
only a stack balance that moves every hand — so it needs per-hand signed
receipts and signed mid-hand actions to close the same hole. That's real
complexity, not padding, which is why V2 does not start until V1 has run for
real.

**Why Vault is a separate program from the poker client, not a feature of
it:** the poker client's session key is deliberately volatile (dies with the
page, so nobody — including the relay — can recover hole cards); Vault's key
spends money and must not share an origin, a process, or a memory lifetime
with that. See the spec's "Why Vault is a separate program" section for the
full reasoning (blast radius, memory/startup, audit surface).

**Rejected alternative:** an earlier document (`PROMPT-vault-addon.md`,
not carried into this repo) proposed per-hand receipts even for the
winner-takes-all case. Loke's simplification — that a sit-and-go's forfeit
penalty is already maximal, so no receipt trail is needed for V1 — is what
made V1 small. Do not reintroduce per-hand receipts into V1.

## Integration boundaries

- **Poker client → Vault:** one button, rendered only behind a `?vault=1`
  flag, opening `<buyin origin>/?session=<id>&seat=<host|guest>` in a new tab.
  The origin is derived from wherever the poker page itself was served —
  `poker.<domain>` becomes `buyin.<domain>` on the same scheme, anything else
  falls back to `<hostname>:8790`. Deliberately a rule rather than a hostname:
  the domain is on loan, and baking it in would make it load-bearing. No shared code, no import, no build-time dependency. Everything
  that crosses after that goes over `postMessage` between the two tabs —
  `localStorage` is per-origin and the two apps run on different origins, so
  it was never actually usable for this despite how the original spec
  phrased it; each side checks `event.source` against the specific window
  reference it holds (the opener, or the window `window.open()` returned),
  which a third-party tab cannot spoof.
- **Vault → chain:** Base Sepolia testnet only, via the user's own wallet for
  signing. Vault never holds a wallet's key material itself.
- **The poker client's own codebase** lives outside this repo (referenced in
  the spec as `heads-up-v12.zip`) and is only needed once work reaches Part 3
  (the button + result-signing change) — not for the V1 contract itself.
- **Funding is now enforced on the poker side, not just warned about.**
  Vault still can't force anything (it has no way to touch the poker
  client's state), but the poker client's own `beginMatch` now refuses to
  deal at all while `vaultOn && !vaultFunded` — a match genuinely cannot
  start until Vault confirms both sides deposited. Vault's pre-Active
  screens still carry a matching warning for anyone looking at Vault
  directly. Choosing "Crypto stakes" is now an explicit tab in the poker
  client's lobby (not just a `?vault=1` link parameter) and rides through
  the invite link automatically, same mechanism as the game format. Money
  was never at risk either way (a channel that isn't Active can't pay
  out) — this closes the "match played through with no real stake on one
  side" gap directly, rather than just warning about it.

- **The postMessage channel is now a running conversation, not a handshake.**
  It started as one hello and one result. What it carries now, and why each
  earns its place: `vault:hello` (Vault → poker: contract, chain, both
  addresses once known, and the on-chain `status`, which is how the poker app
  learns a payout actually landed rather than merely having been clicked);
  `vault:opponent` (poker → Vault: the guest's wallet address, collected at
  the poker table, so the host never types it off a text message);
  `vault:progress` (poker → Vault: whether the match is over, which of the two
  result signatures each side holds, whether the table is live, and the poker
  page's own URL — the room key lives in a URL fragment Vault is never told,
  so only the poker page can supply a way back to a closed table);
  `vault:sent` / `vault:peer-sent` (a transfer is broadcast but unconfirmed —
  knowable only to the sending tab, since no chain state exists for it yet);
  `vault:confirmed` (a receipt landed — announced rather than left to be
  polled, because the *other* player's Vault tab sits in the background where
  browsers throttle timers to roughly once a minute, and their screen would
  otherwise spin for minutes after the money arrived); and `vault:focus-poker`
  (Vault asking the poker tab forward once both buy-ins are in).
- **Anything sent once is a bug waiting to happen.** Every message above is
  re-sent on the hello cycle rather than fired at a chosen moment. The
  failures that forced this were all the same shape: a reloaded tab is the
  same window object with no memory, and a reconnecting peer has its replay
  outbox deliberately cleared — so "delivered once" repeatedly meant "lost,
  silently, with one screen quietly right and the other quietly wrong."
- **Both apps report what they are waiting for.** Vault's status line shows
  link / match / my-confirm / theirs, and names which signature a payout is
  blocked on. This exists because several "it's stuck" reports could only be
  guessed at from screenshots: the screen showed a state without showing what
  produced it.

## Parked with purpose

- **V2 (cash game)** — parked until V1 has been built, tested, and actually
  run on testnet by Loke. Condition to unpark: V1 is live and stable.
- **Mainnet path** — parked indefinitely, pending an independent security
  audit. Not being tracked as near-term work.
- **Poker-client integration (Part 3)** — done (button, handshake,
  auto-signing). Not yet parked-with-purpose so much as awaiting its first
  real end-to-end run: two people, two browsers, a full match, a real
  cooperative close.

## Guiding the user to the buy-in step, post-match

The button (and this app's own UI) were renamed from "Vault" to "Buyin"
user-facing — plainer, describes what it does. Untouched: internal names
(`vaultOn`, `vaultUrl`, this repo's own name), since those aren't
user-facing.

**2026-08-13: modal built, and a real delivery bug found and fixed
underneath it.** The pulsing header button alone wasn't enough (confirmed
live by Loke), so match-end now also opens a blocking modal — "Match's
over — go close out Buyin," with a big "Open Buyin to finish up" button —
the instant `vaultReadyToClose` flips true (poker repo, `useGame.ts` +
`App.tsx`). That's the UX half.

The other half: Loke's last test reported "close and settle didn't come up
at all," which traced to a real bug, not just weak signage.
`vaultMaybeFinalize()` (poker repo) posts the signed result to Buyin's tab
using a window reference captured once, back when Buyin was first opened —
and calling `.postMessage()`/`.focus()` on a *closed* tab is a silent
no-op in every browser: no error, no exception, nothing to notice. Close
the Buyin tab after depositing (the natural thing to do — there's nothing
to look at mid-match) and the result that gets signed at match-end goes
nowhere, forever, with zero indication anything went wrong. Two things
fixed together:
- the finalize call now checks `.closed` and skips a dead window instead
  of pretending to succeed;
- the actual recovery — signed results now persist to `sessionStorage`
  keyed by room id (`saveVaultSigs`/`loadVaultSigs`, pure and unit-tested),
  so reopening Buyin at any point after match-end re-triggers the same
  `vault:hello` handshake that was already wired, and a page reload no
  longer loses a signature that only ever lived in a React ref.

Verified: poker repo's full suite (240 tests, including 4 new ones for the
persistence round-trip) passes, `tsc --noEmit` is clean, `vite build`
succeeds.

**2026-08-13, later the same night: verified end to end, for real.** Loke
ran a full match over the LAN — Buyin, both seats, both wallets, both
signatures, a genuine payout. One more real bug surfaced on the way:
Buyin's own URL (and its postMessage origin check) was hardcoded to
`http://127.0.0.1:8790`, which only ever worked when both apps ran on the
same machine — reached from a phone over the LAN it failed with a flat
"connection refused" the moment Buyin was clicked. Fixed in the poker
repo (`useGame.ts`'s `vaultOrigin()`, now derived from `location.hostname`
at call time instead of a hardcoded constant; see that repo's commit
history). With that fixed, both tabs correctly reached `Status: Closed —
the money has already been sent to the winner`. V1 is done; see
[docs/arc-history.md](docs/arc-history.md).
