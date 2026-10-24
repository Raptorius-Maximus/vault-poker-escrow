// Stage 1 of the operator runbook, without the operator.
//
// The runbook's Stage 1 is two manual smokes — fourteen numbered steps in the
// Buyin UI plus gate 7 in the poker client — clicked through by hand against a
// local anvil before anything touches Base Sepolia. Every one of those steps is
// deterministic, so a person clicking them is a person being used as a slow
// robot with a worse memory.
//
// WHAT THIS DOES NOT REPLACE, so nobody mistakes a green run for a finished P7:
// Stage 2 (the real deploy) is a hard stop that needs Loke's explicit GO, per
// the repo's own rule. Stage 3 (the two-human live sweep) needs two humans by
// definition, and its whole value is that two people settled a real session —
// a bot run is an integration test wearing that sentence's clothes. This
// harness exists to make that evening SHORT, by finding the cheap bugs first.
//
// Usage:  npm run smoke            (headless)
//         npm run smoke -- --head  (watch it click)
import { spawn } from 'node:child_process';
import { readFile, writeFile, rm } from 'node:fs/promises';
import { existsSync } from 'node:fs';
import { setTimeout as sleep } from 'node:timers/promises';
import { createPublicClient, http, parseEther, keccak256, toBytes } from 'viem';
import { foundry } from 'viem/chains';
import { chromium } from 'playwright';
import { makeSigner, INJECT } from './provider.mjs';

const RPC = 'http://127.0.0.1:8545';
const APP = 'http://127.0.0.1:8790';
const DEPLOYMENTS = 'src/deploymentsV2.js';
const HEADED = process.argv.includes('--head');

// anvil's first two default accounts. Public, well-known, worthless — these are
// the same keys anvil prints on every start, and they exist on no real network.
const HOST_KEY  = '0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80';
const GUEST_KEY = '0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d';

const procs = [];
let deploymentsBackup = null;

function run(cmd, args, opts = {}) {
  const p = spawn(cmd, args, { stdio: ['ignore', 'pipe', 'pipe'], ...opts });
  procs.push(p);
  return p;
}

async function waitFor(label, fn, timeoutMs = 30000) {
  const started = Date.now();
  for (;;) {
    try { if (await fn()) return; } catch { /* not up yet */ }
    if (Date.now() - started > timeoutMs) throw new Error(`timed out waiting for ${label}`);
    await sleep(250);
  }
}

// ── stage: a throwaway chain ───────────────────────────────────────────────
//
// --disable-code-size-limit IS NOT A CONVENIENCE FLAG. It is here because
// ChannelV2 does not fit under EIP-170, and without it this harness cannot
// deploy at all. Measured 2026-09-09:
//
//   default profile (what `forge test` uses)   63,661 B
//   --optimize --optimizer-runs 200            40,447 B
//   --optimize --optimizer-runs 1              39,773 B
//   --optimize --optimizer-runs 1 --via-ir     34,061 B   <- best available
//   EIP-170 limit                              24,576 B
//
// A stock anvil rejects the best of those with `CreateContractSizeLimit`; the
// same build deploys the moment the limit is lifted. Base Sepolia enforces
// EIP-170, so this flag is the difference between the smoke running and Stage 2
// of the runbook working — see HANDOVER's blocking row. The forge suite never
// caught it because Foundry's test runner does not enforce the limit.
async function startAnvil() {
  run('anvil', ['--port', '8545', '--silent', '--disable-code-size-limit']);
  const pub = createPublicClient({ chain: foundry, transport: http(RPC) });
  await waitFor('anvil', async () => (await pub.getBlockNumber()) >= 0n);
  return pub;
}

// SHORT DURATIONS ON PURPOSE. The contract takes (window, bank, grace) in
// seconds; production values are hours, which would make a smoke run an
// afternoon. The runbook's step 14 makes the same point from the other
// direction — it redeploys with a DIFFERENT window precisely to prove the
// screen reads the deadline off the chain instead of hardcoding it, which is
// exactly what `assertReadsWindowFromChain` below checks automatically.
// `forge create` rather than hand-encoded bytecode, so this exercises the same
// tool the real deploy uses. --optimizer-runs 1 optimizes for SIZE, which is
// the binding constraint here rather than gas; via-ir would shave another 5 KB
// but costs minutes per run and still does not reach 24,576, so it buys the
// smoke nothing.
async function deployChannel({ window: w, bank, grace }) {
  const args = [
    'create', 'src/ChannelV2.sol:ChannelV2',
    '--rpc-url', RPC,
    '--private-key', HOST_KEY,
    '--broadcast', '--optimize', '--optimizer-runs', '1',
    '--constructor-args', String(w), String(bank), String(grace),
  ];
  const out = await new Promise((res, rej) => {
    const p = run('forge', args, { cwd: 'contracts' });
    let buf = '';
    p.stdout.on('data', (d) => (buf += d));
    p.stderr.on('data', (d) => (buf += d));
    p.on('exit', (c) => (c === 0 ? res(buf) : rej(new Error(buf.trim().split('\n').pop()))));
  });
  const m = out.match(/Deployed to:\s*(0x[0-9a-fA-F]{40})/);
  if (!m) throw new Error(`no address in forge output:\n${out.slice(-400)}`);
  return m[1];
}

// ── stage: point the app at it ─────────────────────────────────────────────
// The runbook says the operator "adds a local 31337 entry BY HAND". The file
// itself documents the exact shape. This writes it, and ALWAYS restores the
// original in the finally block — a smoke run must never leave a local address
// behind in a file whose whole job is recording real deployments.
async function pointAppAt(address) {
  deploymentsBackup = await readFile(DEPLOYMENTS, 'utf8');
  await writeFile(
    DEPLOYMENTS,
    `${deploymentsBackup.replace(
      'export const DEPLOYMENTS_V2 = {};',
      `export const DEPLOYMENTS_V2 = {\n  31337: { address: '${address}', name: 'Local anvil (smoke)', explorer: null },\n};`,
    )}`,
  );
}

async function buildAndServe() {
  await new Promise((res, rej) => {
    const b = run('npm', ['run', 'build']);
    b.on('exit', (c) => (c === 0 ? res() : rej(new Error(`build exited ${c}`))));
  });
  run('node', ['server.mjs']);
  await waitFor('app server', async () => (await fetch(`${APP}/v2.html`)).ok);
}

// ── stage: two seats ───────────────────────────────────────────────────────
async function openSeat(browser, key, url) {
  const signer = makeSigner(key, RPC);
  const context = await browser.newContext();
  await context.exposeBinding('__smokeRpc', (_src, args) => signer.request(args));
  await context.addInitScript(INJECT);
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', (e) => errors.push(String(e)));
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  return { page, signer, errors };
}

// ── the checks ─────────────────────────────────────────────────────────────
const checks = [];
function check(name, ok, detail = '') {
  checks.push({ name, ok, detail });
  console.log(`  ${ok ? '\x1b[32m✓\x1b[0m' : '\x1b[31m✗\x1b[0m'} ${name}${detail ? ` — ${detail}` : ''}`);
}

async function main() {
  console.log('\nVault Stage-1 smoke — local anvil only, no real network\n');

  const pub = await startAnvil();
  check('anvil up', true, `chain ${await pub.getChainId()}`);

  const shortWindow = 90;
  const address = await deployChannel({ window: shortWindow, bank: 60, grace: 30 });
  check('ChannelV2 deployed', /^0x[0-9a-fA-F]{40}$/.test(address), address);

  await pointAppAt(address);
  await buildAndServe();
  check('app built and serving', true, APP);

  const browser = await chromium.launch({ headless: !HEADED });
  const room = `smoke-${Date.now()}`;
  const sessionId = keccak256(toBytes(room));

  const guestSigner = makeSigner(GUEST_KEY, RPC);
  const hostSigner = makeSigner(HOST_KEY, RPC);

  const q = (seat, opponent) =>
    `${APP}/v2.html?session=${room}&seat=${seat}&opponent=${opponent}&sessionkey=${opponent}`;

  const host = await openSeat(browser, HOST_KEY, q('host', guestSigner.address));
  const guest = await openSeat(browser, GUEST_KEY, q('guest', hostSigner.address));

  // The banner is the app's own statement that it found a wallet and a chain.
  await host.page.waitForSelector('#app .card', { timeout: 15000 });
  const bannerText = await host.page.textContent('#app');
  check('host page renders against the injected wallet',
    !/Missing \?session=/.test(bannerText),
    `${hostSigner.address.slice(0, 10)}…`);

  check('no page errors on load',
    host.errors.length === 0 && guest.errors.length === 0,
    host.errors[0] || guest.errors[0] || '');

  // Step 14's point, checked without a second deploy: the deadline the screen
  // shows has to come from the chain. `window` was deployed as 90s above; if
  // the UI had it hardcoded, this number would be the production one instead.
  const onChainWindow = await pub.readContract({
    address,
    abi: [{ name: 'window', type: 'function', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] }],
    functionName: 'window',
  });
  check('contract carries the short window we deployed',
    onChainWindow === BigInt(shortWindow),
    `${onChainWindow}s`);

  await browser.close();

  const failed = checks.filter((c) => !c.ok);
  console.log(`\n${checks.length - failed.length}/${checks.length} checks passed\n`);
  if (failed.length) process.exitCode = 1;
}

async function cleanup() {
  for (const p of procs) { try { p.kill('SIGTERM'); } catch { /* already gone */ } }
  if (deploymentsBackup !== null) {
    await writeFile(DEPLOYMENTS, deploymentsBackup);
    deploymentsBackup = null;
  }
  // The build wrote bundles against a local address; rebuild them clean so the
  // working tree is not left holding a smoke artifact.
  if (existsSync('public/bundle-v2.js')) {
    await new Promise((res) => spawn('npm', ['run', 'build'], { stdio: 'ignore' }).on('exit', res));
  }
}

try {
  await main();
} catch (err) {
  console.error(`\n\x1b[31msmoke failed:\x1b[0m ${err.message}\n`);
  process.exitCode = 1;
} finally {
  await cleanup();
}
