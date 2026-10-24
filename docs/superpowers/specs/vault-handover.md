HANDOVER — Vault: crypto buy-ins for heads-up

Paste this whole file into a new chat. Attach nothing else to start with;
ask for `heads-up-v12.zip` only when you reach Part 3.

This supersedes `PROMPT-vault-addon.md`. That document proposed per-hand
receipts for everything. Loke found a much simpler rule and it changed the
design — throw the old one away.

---

## What to build

Vault: a standalone local app that lets two people put crypto behind a
heads-up poker session and settle it afterwards, with nobody holding the money
and no third party deciding who won.

Two stages, in this order:

- **V1 — sit and go / freezeout.** Winner takes everything. One number to
  agree on. This is small: a contract under 150 lines. Build it, test it, stop.
- **V2 — cash game.** Structurally harder, and the reason is real rather than
  incidental. Do not start it until V1 runs.

Base Sepolia testnet only. Do not write a mainnet path. See "Refuse to
build" at the end.

---

## The rule everything rests on

Loke's poker client already has a forfeit rule, and it is sound for a reason
worth understanding before you touch any of this:

> The deck is fixed by the shuffle **before any card is dealt**, so quitting
> cannot change an outcome, only concede one. Disconnecting is therefore worth
> precisely what folding is worth.

Vault's whole job is to carry that same rule onto a chain without breaking it.
Every design decision below is downstream of that sentence.

The failure mode to design against: if money only settles at safe checkpoints,
then a player losing a big pot can pull the plug and fall back to the last
checkpoint. Unplugging becomes a free option to escape a losing hand — the
exact property the forfeit rule exists to prevent, reintroduced by the
settlement layer.

V1 kills it by making the penalty maximal. In a sit and go, vanishing
costs the entire buy-in. Nobody rips the cable to dodge a 60-chip pot when it
costs 200. The abuse has negative expected value, so it does not happen.

V2 cannot use that trick, because a cash session has no "winner" to award
everything to. That is what makes it harder, and it is why the two are staged.

---

## Why Vault is a separate program

Not tidiness. Three reasons, in order of weight:

1. **Blast radius.** Vault touches a key that spends money. The poker tab
   holds a key that opens cards and is deliberately volatile — it dies with
   the page, which is precisely why nobody, including the relay, can see your
   hole cards. Those two key lifetimes are opposites. They must not share an
   origin.
2. **Memory and startup.** The poker client is a browser tab doing seconds of
   scalar multiplication per hand in a worker. It must not also hold a wallet
   and an RPC client resident for the whole session. Vault runs only while
   someone is depositing or settling.
3. **Audit surface.** The poker client is already unaudited. Putting a second
   unaudited surface inside it means one review has to cover both, and
   covers neither well.

Hard constraint: separate folder, separate `package.json`, separate
process, separate port, separate launcher. The poker client gains one button.
If Vault is not installed, that button does not render and the poker client is
byte-for-byte what it was.

---

## V1 — sit and go

### What the chain needs to know

One thing: who won. Not chip counts, not hand numbers, not cards. The
contract is small because the question is small.

### The contract

```solidity
open(opponent, buyIn)          // both deposit; max loss is bounded by deposit
closeCooperative(winner, sigA, sigB)   // the 99% path, one tx, instant
claimByDefault()               // "he stopped responding" + anti-grief bond
iAmHere()                      // the refutation
resolve()                      // pays out once a window expires
```

### The dispute path, and read this carefully

The chain cannot see who lost their internet — connections do not exist
on a blockchain. So do not try to prove a disconnect. Test for liveness
instead, which is the same question asked in a form the chain can answer:

1. A calls `claimByDefault()`, posting a bond. Window W1 starts (default 30
   minutes).
2. B does nothing → after W1, A takes the pot. A's bond returns.
3. B calls `iAmHere()` inside W1 → A was wrong. A's bond goes to B.
   And a second window W2 starts, in which B must produce a cooperative
   close. If B produces nothing by the end of W2, A's original claim
   resolves in A's favour after all.

Step 3's second half is the part that is easy to leave out and fatal to leave
out. Without it, a player who is alive but simply refuses to sign a loss can
refute forever and nobody is ever paid. Proving you are alive obliges you to
settle. That is the whole trick: `iAmHere()` is a promise, and W2 is the
deadline on it.

Note there is no loop to worry about. B's refutation alone disproves A's claim
— A said B was gone, B demonstrably is not. A does not get a second turn.

### Window length is a liveness parameter, not a security one

Lightning uses days because Bitcoin has ten-minute blocks and a fee market
that can price you out of responding. Neither applies on an L2. W1 only needs
to exceed "how long might an honest opponent plausibly be unable to answer"
— and both players are awake, at a table, mid-session.

Thirty minutes. Long enough to survive the sequencer having a bad afternoon
(Starknet halted and reverted 18 minutes of history in January 2026; assume
Base can too), and no longer. Make it a constructor parameter, not a magic
number, and default it to 30 minutes.

Be honest with the user about the cost: a genuine connection failure — phone
changing cell tower, 4G on a train — loses the buy-in. That is harsh, it is
symmetric, and it is easy to explain. It is the correct trade for V1.

### What the poker client must produce

Exactly one artifact, at the end of a match:

```jsonc
{
  "v": 1,
  "session": "<room id>",
  "result": "host",              // who won the match
  "sigs": { "host": "0x...", "guest": "0x..." }
}
```

Both signatures, or it is not usable. That is the entire interface. Cards,
proofs, transcript, joint key, betting detail — none of it crosses into Vault.
Vault must be able to settle a session whose rules it knows nothing about.

Transport: the poker client writes it to `localStorage` under
`vault:result:<session>`; the button opens
`http://127.0.0.1:8790/?session=<id>&seat=<host|guest>` in a new tab; Vault
reads it back over a `postMessage` handshake with the opener. No shared module,
no import, no build-time dependency either way.

---

## V2 — cash game (do not start until V1 runs)

### Why it is genuinely harder

A sit and go has one winner and one number. A cash session has neither — only
a standing (1340 against 660) that moves after every hand. The chain has to
know that number to pay out, so per-hand receipts are unavoidable here.
That is not incidental complexity; it is what a cash game is.

```jsonc
{
  "v": 1,
  "session": "<room id>",
  "hand": 14,                    // monotonic; this is the dispute nonce
  "stacks": { "host": 1340, "guest": 660 },
  "sigs": { "host": "0x...", "guest": "0x..." }
}
```

Highest hand number wins a dispute. Publishing a receipt that is then beaten
by a higher-numbered one signed by the same party forfeits the publisher's
entire deposit. Not a fine — everything. That is what makes publishing a
stale state have negative expected value, and it is why nobody tries it.

> **SUPERSEDED for V2, 2026-08-16.** The signed-action construction below was
> killed by cold review: the artefacts are symmetric, so both players can file
> the mirror claim and the chain cannot tell which is honest. V2 divides an
> unfinished hand by **burning** the committed money instead — see
> [the consolidated spec](2026-08-16-v2-cash-settlement-consolidated.md) §1.3.
> The dispute-path section above (liveness, `iAmHere`, W1/W2) remains correct
> for V1 and its principle — *do not try to prove a disconnect* — is what V2
> follows.

### Signed actions: this is what closes the mid-hand hole

Receipts checkpoint between hands, so on its own V2 has exactly the escape
hatch described at the top. Fix it by signing each betting action:

```jsonc
{ "session": "...", "hand": 14, "seq": 3, "committed": 500, "sig": "0x..." }
```

To claim a mid-hand forfeit you publish the latest receipt plus the
opponent's own latest signed action. The contract awards you what he had
committed to that pot.

Three properties fall out, and they are why this shape is right:

- You cannot overstate the pot — you can only show something he signed.
- You cannot understate it — that would only hurt you.
- He loses exactly what he had put in. Not a chip more.

Which is the forfeit rule, unchanged, with the chain as witness.

### Deposits in cash

A sit and go's buy-in is also the maximum loss, which suits an escrow exactly.
Cash has rebuys, so the deposit has to be an explicit session ceiling — say
five buy-ins. When it is empty the session is over until a new channel opens.
Make that number visible in the UI before anyone deposits.

---

## Part 3 — the button in the poker client

The complete change to the existing app:

- A `?vault=1` flag or a stored setting. Absent, none of this renders.
- One button in the header, beside the format label.
- It opens the Vault URL in a new tab. That is all it does. No fetch, no
  import, no state, no polling.
- Plus, for V1, the end-of-match result signing described above.

Anything more than this is a design failure. Move it into Vault.

Before writing the signing code, read landmine 13 and the reload-bug section
of `HANDOFF.md`. The lesson there applies directly: be extremely careful
what a failure gets attributed to. A signature mismatch is far more likely to
be version skew than a thief, and reporting it as cheating is exactly the bug
that project already made once.

---

## Layout

```
vault/
  contracts/Channel.sol
  contracts/test/            # adversarial tests, see below
  src/                       # local UI, four screens
  server.mjs                 # serves the UI on 127.0.0.1:8790, nothing else
  play-vault.bat             # same launcher conventions as the poker one
```

Launcher conventions to copy from the poker project: private Node in `.node/`
if missing, nothing installed system-wide, ASCII-only `.ps1` files (PowerShell
5.1 reads them as the system ANSI codepage — one UTF-8 em dash ends a string
early and produces a cascade 50 lines from the real cause).

UI: connect wallet → open channel → in progress → close. Four screens, no more,
plus a permanent visible TESTNET banner.

---

## Testing — what can and cannot be verified

Say plainly which is which in every report. This matters more than usual here,
because the untestable parts are the ones holding money.

**Can be executed in the sandbox:**

- The contract and its full adversarial test suite. Prefer Foundry; if the
  download fails, Hardhat over npm works and the npm registry is reachable.
- Receipt and signature encode/decode, and the poker-side signing.
- The Vault server and UI build.

**Cannot be executed:**

- A real RPC, a real wallet, a real deployment. No browser wallet exists here.
- Anything involving actual gas, actual finality, actual sequencer behaviour.

Test these specifically, not just the happy path: stale publish loses the
deposit; `iAmHere()` followed by silence still pays the claimant; the bond
moves on a false claim; both parties offline through the whole window; a
receipt for the wrong session; a replayed signature; hand number 0; two equal
hand numbers; close attempted twice; claim after a cooperative close.

Loke drives testnet himself: deploy to Base Sepolia, play real hands with fake
money, and deliberately grief himself. That is where the real bugs are, and it
is days of his time rather than yours.

---

## How Loke works

- Short answers. He is technical and reads code.
- Verify by running things, not by reasoning. Several fixes in the poker
  project were wrong the first time and only a real execution caught it.
- Bugs arrive as screenshots. Read them closely — the answer is usually
  visible in them.
- Deliver multi-file work as a single zip.
- He will spot a hole in the design and propose the simpler fix himself. The
  V1 rule in this document is his, not mine. Take that seriously.

### Running on Loke's machine — things to raise before he hits them

This project is being built by an agent with write access to his filesystem,
on a box that will hold a deploy key. That is a normal setup and a safe one,
but it has a handful of sharp edges he has not met yet, because he has not
deployed a contract before.

Do not dump this list on him at the start. It is noise up front and useful
at the moment it applies. Raise each one when the step arrives, in a
sentence, then carry on:

- A fresh key, and only ever a fresh one. The deploy key must be generated
  for this and must never have touched real funds. If it is ever used on
  mainnet afterwards it is burned — a testnet key lives in plaintext on disk
  and in shell history by design.
- `.env` in `.gitignore` before the key exists, not after. Order matters:
  a key committed once is in the history forever, and rewriting history does
  not help if it has been pushed. Check `git status` before the first commit
  and `git remote -v` before the first push.
- Never a seed phrase. A raw testnet private key only. If he offers a seed
  phrase, refuse it and explain why in one line.
- Check the chain ID before every deploy. The single most expensive
  mistake available here is an RPC URL that quietly points at a real network.
  Print the chain ID and the target address and let him confirm — do not infer
  consent from him having said "deploy" earlier.
- Say when a command touches a network. Local tests, a local chain and a
  real deployment look identical in a terminal. Label which one you are about
  to run, every time.
- A deployed contract cannot be patched. Fixes are redeploys to a new
  address, so the UI must read the address from config rather than a constant,
  and old channels stay pointed at the old contract until they close. Say this
  before the first deploy, not after the first bug.
- The deploy key is not the poker session key. Different lifetimes,
  different blast radius. If those two ever end up in the same variable,
  something has gone wrong upstream.
- Faucets rate-limit. Get testnet ETH before it blocks a session, not
  during one.
- Publishing is fine; publishing the wrong file is not. The contract, the
  tests and the UI are all safe to put on GitHub. Verify what is staged before
  he makes anything public.

The general rule: he is technical and reads code, but this is his first
contract. Assume the EVM conventions are unfamiliar, not the programming.
When something is irreversible, say so before it happens rather than
explaining it afterwards.

### Refuse to build

- A mainnet path. Testnet until an independent audit exists. If asked for
  mainnet, say no and say why.
- Anything that holds, transmits or displays a seed phrase or private key.
  Signing goes through the user's own wallet.
- A hosted or shared deployment. Two people, two machines, local only.
- Custody of anyone's funds by any component you write.

One thing that is not a code problem and does not go away by being ignored:
operating real-money poker is licensed activity in both Sweden and Denmark.
Writing the software is not the same as running a table for money, but the
line is real and thinner than it looks once a relay and ETH are involved. That
is a question for a lawyer before it is a question for an auditor.
