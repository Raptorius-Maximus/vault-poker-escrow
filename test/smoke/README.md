# Stage-1 smoke harness

`npm run smoke` — or `npm run smoke -- --head` to watch it click.

Automates runbook Stage 1: local `anvil`, deploy `ChannelV2`, point the app at
it, build, serve, and drive the real UI from two seats with two wallets. Takes
about a minute; the manual version is fourteen numbered steps clicked twice.

## What it does not replace

- **Stage 2, the real deploy.** A hard stop needing Loke's explicit GO, per the
  repo's own rule. Nothing here touches a real network.
- **Stage 3, the two-human live sweep.** Its value is that two people settled a
  real session. A bot run is an integration test, not that sentence — do not
  let a green smoke stand in for it in a grant document.

This exists to make that evening short, by finding the cheap bugs first.

## How the wallet works

There is no MetaMask. `src/mainV2.js` talks to `window.ethereum`, which is only
an EIP-1193 object, so the page gets a shim whose `request()` forwards to Node
over a Playwright binding. Signing happens in Node with viem and the anvil keys;
the page holds no key material. Automating the real extension is the alternative
and costs a day in onboarding flows and popups, none of which tests Vault.

## Browsers on NixOS

`npx playwright install` downloads a Chromium that expects an FHS filesystem and
cannot run here. The browsers come from `pkgs.playwright-driver.browsers` via
`PLAYWRIGHT_BROWSERS_PATH`, set in the machine's Home Manager config. The npm
`playwright` version must match the nixpkgs driver (**1.59.1**) — Playwright
checks the browser revision and fails with a confusing missing-executable error
on a mismatch.

## Why anvil runs with --disable-code-size-limit

Because ChannelV2 does not fit under EIP-170 and will not deploy without it.
That is a real blocker for Stage 2, not a quirk of the harness — see the
**Blocking** row in `HANDOVER.md` for the measurements.
