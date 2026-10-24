import {
  createPublicClient,
  createWalletClient,
  custom,
  formatEther,
  parseEther,
  keccak256,
  toBytes,
  encodePacked,
  ContractFunctionRevertedError,
} from 'viem';
import { baseSepolia, foundry } from 'viem/chains';
import { CHANNEL_V2_ABI, STATUS_V2 } from './abiV2.js';
import { DEPLOYMENTS_V2 } from './deploymentsV2.js';
import { bondFor } from './bondV2.js';
import * as evidenceStoreV2 from './evidenceStoreV2.js';
import { plan as planAutofile } from './autofileV2.js';

// The V2 (cash-session) Buyin app. Mirrors src/main.js's shape deliberately --
// no framework, one file, module-level state, one render loop keyed on chain
// status, the same withBusy/pendingSeq/explainFailure machinery -- but it
// drives ChannelV2 (a declared-depth handshake, deposits/rebuys, disputes)
// instead of V1's winner-takes-all channel. It never imports or touches any V1
// file (D11/D13); the two apps are textually separate by design (decision 1).

// One entry per chain ChannelV2 has a deployment on. 31337 (local anvil) is
// added alongside Base Sepolia so this phase's own operator-run floor probe can
// run against a local chain; it costs nothing in production, where no V2
// contract is deployed to 31337 outside a dev machine.
const CHAINS = { 84532: baseSepolia, 31337: foundry };

// Below this native balance, warn about gas (spec §8.6). No number is pinned
// upstream; 0.01 is a round, visible default the operator can change here in
// one place (phase-5 open question 3).
const GAS_RESERVE_WEI = parseEther('0.01');

const params = new URLSearchParams(location.search);
const roomId = params.get('session');
const seat = params.get('seat'); // 'host' | 'guest'
const sessionId = roomId ? keccak256(toBytes(roomId)) : null;

const root = document.getElementById('app');
let publicClient = null;
let walletClient = null;
let account = null;
let chainId = null;
let deployment = null;
let pollTimer = null;
let renderGen = 0;
let lastSessionKey = null;

// Immutable deploy parameters, cached after the first successful read (they
// never change for a deployment, so re-reading them every poll is waste).
let durations = null; // { window, bank, grace } as bigint seconds

const isAddress = (s) => /^0x[0-9a-fA-F]{40}$/.test(s);
const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const shortAddr = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

// --- opponent address (host needs it for open()) -- V1's exact precedent ----
const opponentParam = (params.get('opponent') || '').trim();
const prefilledOpponent = isAddress(opponentParam) ? opponentParam : '';
let opponentTouched = false;

// --- session-key address bridge (decision 2) --------------------------------
// The session key's ADDRESS (never its private half -- D2) comes from the poker
// tab via vault:sessionkey-v2 (task 2). Until P6 sends that for real, the
// ?sessionkey= URL param stands in, exactly as ?opponent= stands in for
// vault:opponent -- read once at load, superseded by the first real message,
// never re-asserted after the code has started using it.
const sessionKeyParam = (params.get('sessionkey') || '').trim();
let sessionKeyAddress = isAddress(sessionKeyParam) ? sessionKeyParam : null;
let sessionKeyTouched = false; // latches once a registration begins

// --- open/join form state, kept outside the DOM so a poll re-render never
// wipes what's been typed. Amounts are ETH strings, parsed at submit time.
const formState = {
  opponent: prefilledOpponent,
  maxHost: '',
  maxGuest: '',
  depositNowHost: '',
  depositNowGuest: '',
  rebuy: '',
};

// --- dispute / autofile state ----------------------------------------------
let disputeConfirming = false; // the "open a dispute" confirm gate (task 5 step 1)
let autofileActive = false; // guards against re-entrant autofile runs
let autofileProgress = null; // { n, total } while filing, else null

// --- postMessage handshake with the poker tab (the opener) ------------------
// event.source is set by the browser from the window that actually called
// postMessage -- a third-party tab cannot spoof it. Same guard V1 uses.
window.addEventListener('message', (event) => {
  if (!window.opener || event.source !== window.opener) return;
  const data = event.data;
  if (!data || data.session !== roomId) return;

  // vault:opponent -- the guest's wallet address, for the host's open() (same
  // shape and supersede rule as V1's).
  if (data.type === 'vault:opponent') {
    const addr = typeof data.address === 'string' ? data.address.trim() : '';
    if (!isAddress(addr) || opponentTouched || formState.opponent === addr) return;
    formState.opponent = addr;
    const input = document.getElementById('opponent-input-v2');
    if (input) input.value = addr;
    return;
  }

  // vault:sessionkey-v2 (task 2, TBD-P1-EVIDENCE-SHAPE) -- the session key's
  // ADDRESS from the poker tab. Only the address ever crosses; the private half
  // stays in the poker client (D2, formats §6). Stored only if a registration
  // isn't already using a value (sessionKeyTouched) -- a mid-flow overwrite
  // would be as wrong as overwriting a host's typed opponent address.
  if (data.type === 'vault:sessionkey-v2') {
    const addr = typeof data.sessionKeyAddress === 'string' ? data.sessionKeyAddress.trim() : '';
    if (!isAddress(addr) || sessionKeyTouched) return;
    if (sessionKeyAddress === addr) return;
    sessionKeyAddress = addr;
    render();
    return;
  }

  // vault:evidence-v2 (task 2, TBD-P1-EVIDENCE-SHAPE) -- the evidence bundle to
  // persist to THIS origin's localStorage (spec §6's "both origins"). Written
  // unconditionally; the write is idempotent, exactly vault:progress's own
  // reasoning, so a repeat costs nothing.
  if (data.type === 'vault:evidence-v2') {
    try {
      evidenceStoreV2.save(localStorage, roomId, data);
    } catch {
      /* storage disabled -- recovery via this origin simply won't be available */
    }
    return;
  }

  // vault:derive-key-v2 (P6 task 11, executor half of task 2's round trip) --
  // the poker tab is asking the wallet to sign this session's FIXED key-
  // derivation message so it can derive the AES key that encrypts the session
  // private key at rest. The wallet ADDRESS is here in the tab already; the
  // session private key never crosses (D2). Human-readable string form (the
  // wallet prompt shows legible text), distinct from registration's {raw}
  // digest form. The `nonce` rides for the poker tab's own routing only -- it
  // is NEVER inside the signed text, which must be byte-identical across calls
  // for the determinism probe to mean anything (task 2 step 2). One-shot reply.
  if (data.type === 'vault:derive-key-v2') {
    if (!walletClient || !account) return; // not connected yet -- poker's probe times out and falls back
    const text = `Vault session key — session ${data.session} — do not sign this text on any other site.`;
    walletClient
      .signMessage({ account, message: text })
      .then((signature) => {
        if (window.opener) {
          window.opener.postMessage(
            { type: 'vault:derive-key-result-v2', v: 1, session: roomId, nonce: data.nonce, signature },
            '*',
          );
        }
      })
      .catch(() => {
        /* user rejected / wallet error -- poker's probe times out and falls back to the unencrypted path */
      });
    return;
  }

  // vault:post-marker-v2 (P6 task 11, executor half of task 6's round trip) --
  // the poker tab is asking to record a both-signed hand-start marker on chain
  // (co-filing the receipt it references, via fileMarkerWithReceipt, when one
  // rides along). One attempt, honestly classified, reported back -- the retry
  // lives in poker (design decision 5), never here.
  if (data.type === 'vault:post-marker-v2') {
    void runPostMarker(data);
    return;
  }
});

// Buyin -> poker hello. Mirrors V1's sendHelloToOpener, plus the `liveHand`
// field P6 requires for its deal-gate confirmation and marker-floor recovery
// (AF-10 amendment). Sent every poll tick unconditionally -- one small
// postMessage, not a render -- so the link between the two tabs is
// self-healing rather than a single point of failure (V1's own once-only-hello
// bug, main.js:220-230).
function sendHelloToOpener(session) {
  if (!window.opener) return;
  const known = session && session.status !== 'None' && session.status !== 'AwaitingGuest';
  window.opener.postMessage(
    {
      type: 'vault:hello',
      v: 2,
      session: roomId,
      contractAddress: deployment?.address,
      chainId,
      host: known ? session.host : undefined,
      guest: known ? session.guest : undefined,
      status: session?.status,
      liveHand: session?.liveHand !== undefined ? Number(session.liveHand) : undefined,
    },
    '*',
  );
}

// --- chain / wallet setup --------------------------------------------------
async function connect({ silent = false } = {}) {
  if (!window.ethereum) {
    if (!silent) alert('No wallet found. Install MetaMask (or another browser wallet) first.');
    return;
  }
  walletClient = createWalletClient({ transport: custom(window.ethereum) });
  let addr;
  if (silent) {
    const accounts = await window.ethereum.request({ method: 'eth_accounts' }).catch(() => []);
    addr = accounts?.[0];
    if (!addr) return;
  } else {
    [addr] = await walletClient.requestAddresses();
  }
  account = addr;
  chainId = await walletClient.getChainId();
  deployment = DEPLOYMENTS_V2[chainId] ?? null;
  if (CHAINS[chainId]) walletClient = createWalletClient({ chain: CHAINS[chainId], transport: custom(window.ethereum) });
  publicClient = createPublicClient({ transport: custom(window.ethereum) });
  sendHelloToOpener(null);
  startPolling();
  render();
}

async function switchToDeploymentChain(targetChainId) {
  try {
    await walletClient.switchChain({ id: targetChainId });
  } catch (err) {
    render(`Could not switch networks: ${err.shortMessage || err.message}`);
    return;
  }
  chainId = await walletClient.getChainId();
  deployment = DEPLOYMENTS_V2[chainId] ?? null;
  if (CHAINS[chainId]) walletClient = createWalletClient({ chain: CHAINS[chainId], transport: custom(window.ethereum) });
  render();
}

// --- on-chain reads --------------------------------------------------------
async function readDurations() {
  if (durations) return durations;
  const [w, b, g] = await Promise.all([
    publicClient.readContract({ address: deployment.address, abi: CHANNEL_V2_ABI, functionName: 'window' }),
    publicClient.readContract({ address: deployment.address, abi: CHANNEL_V2_ABI, functionName: 'bank' }),
    publicClient.readContract({ address: deployment.address, abi: CHANNEL_V2_ABI, functionName: 'grace' }),
  ]);
  durations = { window: w, bank: b, grace: g };
  return durations;
}

// Reads ChannelV2's grouped view functions (AF-24 -- there is no single
// sessions() getter) plus the scalar reads task 6/8 need, into one rich object.
async function readSession() {
  if (!publicClient || !deployment || !sessionId) return null;
  const rc = (functionName, args = [sessionId]) =>
    publicClient.readContract({ address: deployment.address, abi: CHANNEL_V2_ABI, functionName, args });
  const [core, bonds, deposits, disputeOpenedAt, keys, liveHand, markedHand, everReceipted, hostFiled, guestFiled, credits, dur, balance] =
    await Promise.all([
      rc('sessionCore'),
      rc('sessionBonds'),
      rc('sessionDeposits'),
      rc('sessionDisputeOpenedAt'),
      rc('sessionKeys'),
      rc('liveHand'),
      rc('markedHand'),
      rc('everReceipted'),
      rc('hostFiledInWindow'),
      rc('guestFiledInWindow'),
      rc('credits', [account]),
      readDurations(),
      publicClient.getBalance({ address: account }),
    ]);
  const [host, guest, status, maxHost, maxGuest] = core;
  const [bondHost, bondGuest, hostBurned, guestBurned] = bonds;
  const [depositedHost, depositedGuest] = deposits;
  const [sessionKeyHost, sessionKeyGuest] = keys;
  return {
    host, guest, status: STATUS_V2[status], statusRaw: status,
    maxHost, maxGuest, bondHost, bondGuest, hostBurned, guestBurned,
    depositedHost, depositedGuest, disputeOpenedAt,
    sessionKeyHost, sessionKeyGuest, liveHand, markedHand, everReceipted,
    hostFiledInWindow: hostFiled, guestFiledInWindow: guestFiled,
    credits, window: dur.window, bank: dur.bank, grace: dur.grace, balance,
  };
}

function sessionKey(session) {
  return JSON.stringify(session, (_, v) => (typeof v === 'bigint' ? v.toString() : v));
}

function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    const session = await readSession().catch(() => null);
    if (!session) return;
    sendHelloToOpener(session);
    const key = sessionKey(session);
    if (key === lastSessionKey) return;
    render();
    // Closed is permanent -- stop polling the chain forever once settled.
    if (session.status === 'Closed' && pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }, 4000);
}

// --- writes: in-flight machinery (mirrors main.js verbatim) -----------------
let pending = null;
let pendingSeq = 0;

function pendingCard() {
  if (!pending) return null;
  const { phase, label, hash } = pending;
  const Label = label ? label[0].toUpperCase() + label.slice(1) : 'It';
  const kids = [
    el('div', { class: 'pending-line' }, [
      el('span', { class: 'spinner' }),
      el('strong', {}, [
        phase === 'wallet' ? 'Waiting for you to approve this in your wallet' : 'Sent — waiting for the network to confirm it',
        el('span', { class: 'dots' }),
      ]),
    ]),
    el('p', { class: 'dim' }, phase === 'wallet'
      ? `Your wallet should have opened a window asking you to confirm ${label}. Nothing has been sent and no money has moved — that only happens when you approve it there. If you can't see the window, check behind this one, or open your wallet from its own icon.`
      : `${Label} is on its way and the network is writing it down. This usually takes a few seconds. Nothing needs doing and nothing is stuck — leave this page open and it'll notice by itself the moment it lands.`),
  ];
  if (phase === 'wallet') {
    kids.push(el('button', { class: 'btn ghost', onclick: cancelPending }, "Nothing happened? Give up on this and try again"));
  }
  if (hash) {
    kids.push(el('div', { class: 'dim hash' }, hash));
    if (deployment?.explorer) {
      kids.push(el('a', { class: 'dim', href: `${deployment.explorer}/tx/${hash}`, target: '_blank', rel: 'noopener noreferrer' }, 'Watch it on the block explorer →'));
    }
  }
  return el('div', { class: 'card pending', role: 'status' }, kids);
}

function showPending() {
  const existing = root.querySelector('.card.pending');
  const next = pendingCard();
  if (existing && next) existing.replaceWith(next);
  else if (existing) existing.remove();
  else if (next) root.insertBefore(next, root.children[1] ?? null);
}

function cancelPending() {
  pendingSeq++;
  pending = null;
  render();
}

// Find a decoded custom-error name (e.g. 'NotYetBuilt', 'Phase2InProgress')
// on a thrown viem error, or null. Solidity custom errors travel as a 4-byte
// selector; viem's ContractFunctionRevertedError decodes it against the ABI
// and exposes the matched name at .data.errorName (viem 2.55.13,
// errors/contract.js). This is the selector match happening inside viem.
function revertErrorName(err) {
  if (err && typeof err.walk === 'function') {
    const e = err.walk((x) => x instanceof ContractFunctionRevertedError);
    if (e) return e.data?.errorName ?? null;
  }
  return null;
}

function explainFailure(err, label) {
  const name = revertErrorName(err);
  // NotYetBuilt is no longer thrown by any live path (P3/P4 shipped), but the
  // branch stays as a defensive decode for any older-build contract instance:
  // conflating "not built yet" with "you did something wrong" is exactly the
  // unreadable-error failure this function exists to prevent (decision 5).
  if (name === 'NotYetBuilt') {
    return "The parts of your evidence that need a marked live hand aren't dispute-ready in this build yet — this is a known gap, not a problem with what you're holding.";
  }
  // The REAL live interim revert from resolve(): a phase-2 continuation is
  // still running, so settlement can't finalise yet.
  if (name === 'Phase2InProgress' || name === 'PendingContinuation') {
    return "The dispute isn't finished being worked out yet — its continuation is still running. Nothing is wrong; this can only settle once that's due.";
  }

  const raw = `${err?.shortMessage || ''} ${err?.message || ''} ${err?.details || ''}`.toLowerCase();
  if (raw.includes('user rejected') || raw.includes('user denied') || raw.includes('rejected the request')) {
    return null;
  }
  if (raw.includes('insufficient funds')) {
    return 'Not enough test ETH in this wallet to cover the amount plus the network fee.';
  }
  if (raw.includes('chain') && raw.includes('match')) {
    return 'Your wallet is on a different network. Switch it to the right one and try again.';
  }
  if (raw.includes('below bond')) {
    return "That doesn't cover the bond this table needs — check the amount and try again.";
  }
  if (raw.includes('past declared max')) {
    return "That would put you past the maximum you declared for this table, and the table won't credit it. Reopen at a bigger table if you need to go deeper.";
  }
  if (raw.includes('not open for deposits')) {
    return "Deposits aren't open right now — check the session status above.";
  }
  if (raw.includes('window open')) {
    return "The evidence window hasn't finished yet — the frozen result can only be settled once it closes. The closing time is shown above.";
  }
  if (raw.includes('internal error') || raw.includes('reverted') || raw.includes('execution reverted')) {
    return `The network wouldn't accept ${label} — almost always because it isn't the right moment for it yet. Nothing was sent and nothing was lost.`;
  }
  return `Couldn't send ${label}: ${err?.shortMessage || err?.message || String(err)}`;
}

// Returns the mined receipt on success, null on failure/abandonment. The
// return lets a two-step flow (fileReceipt then resolve) know the first landed
// before starting the second.
async function withBusy(fn, label = 'this') {
  let failure = null;
  let ok = null;
  const mySeq = ++pendingSeq;
  const mine = () => pendingSeq === mySeq;
  root.querySelectorAll('button').forEach((b) => (b.disabled = true));
  pending = { phase: 'wallet', label, hash: null };
  showPending();
  try {
    const hash = await fn();
    if (!mine()) return null;
    if (hash) {
      pending = { phase: 'sent', label, hash };
      showPending();
      ok = await publicClient.waitForTransactionReceipt({ hash });
      if (!mine()) return null;
    }
  } catch (err) {
    if (mine()) failure = explainFailure(err, label);
  } finally {
    if (mine()) {
      pending = null;
      render(failure);
    }
  }
  return ok;
}

function write(functionName, args, value) {
  return walletClient.writeContract({
    address: deployment.address,
    abi: CHANNEL_V2_ABI,
    functionName,
    args,
    ...(value !== undefined ? { value } : {}),
    account,
  });
}

// --- session-key registration (formats §6, wallet personal_sign) ------------
async function registerSessionKeyAndOpen() {
  sessionKeyTouched = true;
  const opponent = (document.getElementById('opponent-input-v2')?.value || formState.opponent).trim();
  const maxHost = parseEther(formState.maxHost || '0');
  const maxGuest = parseEther(formState.maxGuest || '0');
  const bondHost = bondFor(maxHost, maxGuest);
  const depositNow = parseEther(formState.depositNowHost || '0');
  await withBusy(async () => {
    const walletSig = await signSessionKey(account, sessionKeyAddress);
    return write('open', [sessionId, opponent, maxHost, maxGuest, sessionKeyAddress, walletSig], depositNow + bondHost);
  }, 'setting the table and your bond');
}

async function registerSessionKeyAndJoin(session) {
  sessionKeyTouched = true;
  const bondGuest = session.bondGuest;
  const depositNow = parseEther(formState.depositNowGuest || '0');
  await withBusy(async () => {
    const walletSig = await signSessionKey(account, sessionKeyAddress);
    return write('join', [sessionId, sessionKeyAddress, walletSig], depositNow + bondGuest);
  }, 'joining the table and your bond');
}

// Builds formats §6's registration preimage and gets the wallet's
// personal_sign over the raw digest. encodePacked matches abi.encodePacked
// (string -> raw UTF-8 bytes, no length prefix); signMessage({message:{raw}})
// applies the EIP-191 prefix, which is what the contract's registration
// recovery expects (formats §1/§6).
function sessionKeyDigest(player, sessionKey) {
  return keccak256(
    encodePacked(
      ['uint8', 'string', 'address', 'uint256', 'bytes32', 'address', 'address'],
      [0x04, 'vault/sessionkey/v2', deployment.address, BigInt(chainId), sessionId, player, sessionKey],
    ),
  );
}
function signSessionKey(player, sessionKey) {
  return walletClient.signMessage({ account: player, message: { raw: sessionKeyDigest(player, sessionKey) } });
}

// --- simple writes ---------------------------------------------------------
const cancelOpen = () => withBusy(() => write('cancelOpen', [sessionId]), 'the cancellation, which sends your money back');
const depositMore = (valueWei) => withBusy(() => write('deposit', [sessionId], valueWei), 'your deposit');
const openDispute = () => withBusy(() => write('openDispute', [sessionId]), 'opening the dispute');
const withdraw = () => withBusy(() => write('withdraw', []), 'your withdrawal');
const resolveSession = () => withBusy(() => write('resolve', [sessionId]), 'settling the session');

// The two-transaction cooperative good ending (P2 decision 4): file the
// `final` receipt, then resolve(). One button, both writes back to back.
async function finishMatch(finalR) {
  await withBusy(async () => {
    const h1 = await write('fileReceipt', [receiptTuple(finalR), finalR.sigHost, finalR.sigGuest]);
    await publicClient.waitForTransactionReceipt({ hash: h1 });
    return write('resolve', [sessionId]);
  }, 'finishing the match and paying out');
}

function receiptTuple(r) {
  return {
    hand: BigInt(r.hand), subseq: Number(r.subseq),
    hostStack: BigInt(r.hostStack), guestStack: BigInt(r.guestStack),
    hostDeposit: BigInt(r.hostDeposit), guestDeposit: BigInt(r.guestDeposit),
    isFinal: Boolean(r.final),
  };
}

// --- marker posting (P6 task 11, executor half of task 6) -------------------
// The wire marker names the button numerically (0/1, formats §4) and carries
// startingChips (AF-32); the ABI struct field order is formats §4 exactly. A
// pure inline helper, kept in this file so task 11's exception stays as narrow
// as the finding that authorized it (autofileV2.js's own markerTuple is
// module-private there).
function markerTupleV2(m) {
  return {
    hand: BigInt(m.hand),
    receiptHash: m.receiptHash,
    deckRoot: m.deckRoot,
    hostShareRoot: m.hostShareRoot,
    guestShareRoot: m.guestShareRoot,
    hostCardPk: m.hostCardPk,
    guestCardPk: m.guestCardPk,
    button: Number(m.button),
    sb: BigInt(m.sb),
    bb: BigInt(m.bb),
    startingChips: BigInt(m.startingChips ?? 0),
  };
}

// Classify one marker-post failure honestly, by SHAPE not by guessing
// (design decision 5): a decoded Solidity custom error, or a plain revert
// string, is a genuine on-chain rejection -> 'rejected' (poker does NOT retry
// it). A network-level failure (timeout, connection reset, or the nonce-race
// RESULTS.md measured) -> 'transient-failure' (poker's flat-2s retry targets
// it). Anything unrecognised defaults to 'transient-failure', the safe
// direction: poker retries a bounded number of times rather than treating an
// unknown blip as a permanent rejection. Note (AF-42.2): Phase2InProgress /
// PendingContinuation are `resolve()`'s interim reverts, not fileMarker's, but
// if one ever surfaces here it is still a real decoded contract error -> the
// 'rejected' branch (poker surfaces it, no silent retry loop).
function classifyMarkerError(err) {
  if (revertErrorName(err)) return 'rejected';
  const raw = `${err?.shortMessage || ''} ${err?.message || ''} ${err?.details || ''}`.toLowerCase();
  if (raw.includes('reverted') || raw.includes('execution reverted') || raw.includes('revert')) {
    return 'rejected';
  }
  return 'transient-failure';
}

function reportMarkerResult(hand, outcome, txHash, error) {
  if (!window.opener) return;
  window.opener.postMessage(
    { type: 'vault:marker-result-v2', v: 1, session: roomId, hand, outcome, txHash, error },
    '*',
  );
}

// One attempt, driven through the SAME single-write-at-a-time withBusy/pendingSeq
// machinery the auto-filer uses -- never a second, parallel write queue (task 11
// step 2). The raw error is captured inside the withBusy fn (which otherwise
// swallows it into a rendered notice) so the outcome can be classified; a
// null return with no captured error means the write was cancelled/superseded
// by a newer one, which poker can safely re-request -> transient.
async function runPostMarker(data) {
  if (!deployment || !walletClient || !sessionId) {
    reportMarkerResult(Number(data.hand), 'transient-failure');
    return;
  }
  const m = markerTupleV2(data.marker);
  let caught = null;
  const rcpt = await withBusy(async () => {
    try {
      if (data.receipt) {
        const r = receiptTuple(data.receipt);
        return await write('fileMarkerWithReceipt', [
          sessionId, m, data.marker.sigHost, data.marker.sigGuest,
          r, data.receipt.sigHost, data.receipt.sigGuest,
        ]);
      }
      return await write('fileMarker', [sessionId, m, data.marker.sigHost, data.marker.sigGuest]);
    } catch (err) {
      caught = err; // capture for classification, then rethrow for withBusy's own handling
      throw err;
    }
  }, 'recording the hand on-chain');
  if (rcpt) {
    reportMarkerResult(Number(data.hand), 'confirmed', rcpt.transactionHash);
  } else if (caught) {
    const outcome = classifyMarkerError(caught);
    reportMarkerResult(
      Number(data.hand),
      outcome,
      undefined,
      outcome === 'rejected' ? (caught.shortMessage || caught.message || String(caught)) : undefined,
    );
  } else {
    // superseded/cancelled by a newer write, or a receipt-wait network blip --
    // safe for poker to re-request.
    reportMarkerResult(Number(data.hand), 'transient-failure');
  }
}

// --- duty auto-filing (task 5, spec §5.1 "no expertise required") -----------
// Snapshot of what's already on chain, so plan() skips already-filed artefacts
// and doesn't pop a redundant wallet prompt. Only the receipt-level and
// share-level reads are cheap/available; the rest degrade to "file everything"
// safely (the contract's own idempotence decides).
async function autofileSnapshot(session, bundle) {
  const filedReceiptHands = new Set();
  const receipts = Array.isArray(bundle.receipts) ? bundle.receipts : [];
  await Promise.all(receipts.map(async (r) => {
    try {
      const h = await publicClient.readContract({ address: deployment.address, abi: CHANNEL_V2_ABI, functionName: 'receiptAt', args: [sessionId, BigInt(r.hand)] });
      if (h && h !== '0x0000000000000000000000000000000000000000000000000000000000000000') filedReceiptHands.add(Number(r.hand));
    } catch { /* leave unknown -> plan will (re-)file, a safe no-op */ }
  }));
  return { filedReceiptHands, markedHand: Number(session.markedHand) };
}

// Drives the plan one call at a time (decision 4: never two wallet popups
// racing). Re-plans after each lands, since the on-chain state moved.
async function runAutofile(session) {
  if (autofileActive || session.status !== 'Disputed') return;
  let bundle = null;
  try {
    bundle = evidenceStoreV2.load(localStorage, roomId);
  } catch { return; }
  if (!bundle) return;
  autofileActive = true;
  try {
    let calls = planAutofile(bundle, await autofileSnapshot(session, bundle));
    const total = calls.length;
    if (total === 0) { autofileProgress = null; return; }
    let n = 0;
    while (calls.length > 0) {
      n += 1;
      autofileProgress = { n, total };
      render();
      const call = calls[0];
      const receipt = await withBusy(() => write(call.fn, [sessionId, ...call.args]), 'filing your evidence automatically');
      if (!receipt) break; // a failure (or the user cancelled) -- stop the queue
      const fresh = await readSession().catch(() => session);
      calls = planAutofile(bundle, await autofileSnapshot(fresh, bundle));
    }
  } finally {
    autofileActive = false;
    autofileProgress = null;
  }
}

// --- rendering -------------------------------------------------------------
function el(tag, props = {}, children = []) {
  const node = document.createElement(tag);
  Object.entries(props).forEach(([k, v]) => {
    if (k === 'onclick') node.addEventListener('click', v);
    else if (k === 'class') node.className = v;
    else node.setAttribute(k, v);
  });
  (Array.isArray(children) ? children : [children]).forEach((c) => {
    if (c === null || c === undefined) return;
    node.appendChild(typeof c === 'string' ? document.createTextNode(c) : c);
  });
  return node;
}

function banner() {
  return el('div', { class: 'testnet-banner' }, 'TESTNET — play money only, never mainnet');
}

// The bond, shown next to its consequence BEFORE any deposit (spec §2/§2.1).
// The three sentences render on both the host and guest screens; kept here once
// so the pinned copy lives in exactly one place.
function bondConsequence(bondWei) {
  return [
    el('p', {}, `Your bond is ${formatEther(bondWei)} ETH — 110% of the deeper of half the table or your own declared max. It's held separately and only ever burns; it never goes to your opponent.`),
    el('p', {}, "Play deeper than you declared and the table simply won't credit it — reopen at a bigger table instead."),
    el('p', { class: 'error' }, 'If you desert this session, you lose this.'),
  ];
}

// Gas-reserve warning (task 8 / spec §8.6). Shown from the first chain-
// observable state (status !== 'None') onward, whenever the wallet's native
// balance is under the reserve.
function gasReserveWarning(session) {
  if (!session || session.status === 'None') return null;
  if (session.balance >= GAS_RESERVE_WEI) return null;
  return el('div', { class: 'card' }, [
    el('p', { class: 'dim' }, 'Gas is what lets you defend yourself if this session ever needs a dispute. Keep some test ETH in this wallet the whole time you\'re playing.'),
  ]);
}

// Pull-payment withdraw (D9). Persistent whenever there's a credit balance.
function withdrawCard(session) {
  if (!session || session.credits <= 0n) return null;
  return el('div', { class: 'card' }, [
    el('h2', {}, 'Money to withdraw'),
    el('p', {}, `You have ${formatEther(session.credits)} ETH waiting in the contract — deposits back, bond back, or winnings. Withdraw it to your wallet:`),
    el('button', { class: 'btn primary', onclick: withdraw }, 'Withdraw to my wallet'),
  ]);
}

async function render(errorMsg) {
  await renderScreens(errorMsg);
  if (!pending) return;
  root.querySelectorAll('button').forEach((b) => (b.disabled = true));
  showPending();
}

async function renderScreens(errorMsg) {
  const myGen = ++renderGen;

  const canRead = roomId && seat && account && deployment;
  let session = null;
  let readError = null;
  if (canRead) {
    session = await readSession().catch((err) => { readError = err; return null; });
    if (myGen !== renderGen) return;
  }

  root.innerHTML = '';
  root.appendChild(banner());

  if (!roomId || !seat) {
    root.appendChild(el('div', { class: 'card' }, "Missing ?session= and ?seat= in the URL. Open this from the poker client's Buyin button, not directly."));
    return;
  }

  // Screen 1: connect wallet
  if (!account) {
    root.appendChild(el('div', { class: 'card' }, [
      el('h1', {}, 'Buyin — cash session'),
      el('p', {}, 'This holds your poker buy-in and your bond safely for a cash session, and settles them automatically when the session ends — nobody, including this app, can hold onto the money or decide the result.'),
      el('p', { class: 'dim' }, `You're the ${seat === 'host' ? 'one setting the table' : 'one joining'}.`),
      el('button', { class: 'btn primary', onclick: () => connect() }, 'Connect your wallet to start'),
    ]));
    return;
  }

  // Screen 1b: wrong / no deployment
  if (!deployment) {
    const targets = Object.keys(DEPLOYMENTS_V2);
    root.appendChild(el('div', { class: 'card' }, targets.length ? [
      el('p', {}, 'This runs on a test network only — your wallet needs to switch to it.'),
      el('button', { class: 'btn primary', onclick: () => switchToDeploymentChain(Number(targets[0])) }, 'Switch to the test network'),
    ] : [
      el('p', {}, 'No V2 cash-session contract is configured for this build yet.'),
      el('p', { class: 'dim' }, 'A deployment address gets added when the contract goes live (P7). If you are testing locally, add a 31337 entry to src/deploymentsV2.js and rebuild.'),
    ]));
    return;
  }

  if (!session) {
    root.appendChild(el('div', { class: 'card' }, [
      el('p', { class: 'error' }, readError ? `Couldn't reach the network: ${readError.shortMessage || readError.message}` : "Couldn't read this session from the network."),
      el('p', { class: 'dim' }, 'Nothing is lost — the money and the result live on the chain, not in this page. This keeps retrying by itself every few seconds.'),
      el('button', { class: 'btn ghost', onclick: () => render() }, 'Try again now'),
    ]));
    return;
  }
  lastSessionKey = sessionKey(session);
  sendHelloToOpener(session);

  if (errorMsg) root.appendChild(el('div', { class: 'card error' }, errorMsg));

  const gas = gasReserveWarning(session);
  if (gas) root.appendChild(gas);
  const wc = withdrawCard(session);
  if (wc) root.appendChild(wc);

  root.appendChild(el('div', { class: 'meta' }, [
    el('div', {}, `Connected: ${account}`),
    el('div', {}, `Session: ${roomId} (${sessionId.slice(0, 10)}…) — seat: ${seat}`),
    el('div', {}, `Status: ${session.status}`),
  ]));

  // Route by status.
  if (session.status === 'None') return renderOpen(session);
  if (session.status === 'AwaitingGuest') return renderAwaitingGuest(session);
  if (session.status === 'Active') return renderActive(session);
  if (session.status === 'Disputed') return renderDisputed(session);
  if (session.status === 'Closed') return renderClosed(session);
}

// Screen 2: host sets the table / guest waits (status None)
function renderOpen(session) {
  if (seat !== 'host') {
    root.appendChild(el('div', { class: 'card' }, [
      el('p', {}, 'Waiting for your opponent to set the table up and put their money in.'),
      el('p', { class: 'dim' }, 'Nothing for you to do yet — this page updates itself.'),
    ]));
    return;
  }

  const maxHostWei = safeParse(formState.maxHost);
  const maxGuestWei = safeParse(formState.maxGuest);
  const bothMaxes = maxHostWei !== null && maxGuestWei !== null && maxHostWei > 0n && maxGuestWei > 0n;
  const bondHost = bothMaxes ? bondFor(maxHostWei, maxGuestWei) : null;

  const opponentInput = el('input', { type: 'text', id: 'opponent-input-v2', placeholder: '0x… opponent wallet address', value: formState.opponent });
  opponentInput.addEventListener('input', (e) => { formState.opponent = e.target.value; opponentTouched = true; });

  const maxHostInput = el('input', { type: 'text', placeholder: 'the most you might ever put in (ETH)', value: formState.maxHost });
  const maxGuestInput = el('input', { type: 'text', placeholder: 'the most they might ever put in (ETH)', value: formState.maxGuest });
  const depositInput = el('input', { type: 'text', placeholder: 'put in now (ETH)', value: formState.depositNowHost });
  // Live recompute on every keystroke, so the consequence text is on screen
  // before the Open button is even enabled.
  maxHostInput.addEventListener('input', (e) => { formState.maxHost = e.target.value; render(); });
  maxGuestInput.addEventListener('input', (e) => { formState.maxGuest = e.target.value; render(); });
  depositInput.addEventListener('input', (e) => { formState.depositNowHost = e.target.value; });

  const depositWei = safeParse(formState.depositNowHost);
  const depositOverMax = depositWei !== null && maxHostWei !== null && depositWei > maxHostWei;

  const kids = [
    el('h2', {}, 'Step 1: set the table'),
    el('p', {}, 'Ask your opponent for their wallet address — a text message is fine, it is not a secret. Then declare the table: the most either of you might ever put in.'),
    opponentInput,
    maxHostInput,
    maxGuestInput,
  ];

  if (bondHost !== null) kids.push(...bondConsequence(bondHost));

  kids.push(el('p', {}, 'Put in now (you can top up later, up to your declared max):'));
  kids.push(depositInput);
  if (depositOverMax) kids.push(el('p', { class: 'error' }, "That's more than the max you declared for yourself — the table won't credit it. Lower it, or declare a bigger max."));

  // Session-key gating (decision 2 / task 3 step 3).
  if (!sessionKeyAddress) {
    kids.push(el('p', { class: 'dim' }, 'Waiting for your poker table to tell us your session key…'));
  }
  const ready = bothMaxes && !!sessionKeyAddress && isAddress((opponentInput.value || '').trim()) && !depositOverMax;
  const btn = el('button', { class: 'btn primary', onclick: registerSessionKeyAndOpen }, 'Open the table and post my bond');
  if (!ready) btn.disabled = true;
  kids.push(btn);

  root.appendChild(el('div', { class: 'card' }, kids));
}

// Screen 2b: guest sees the whole table, joins or cancels (status AwaitingGuest)
function renderAwaitingGuest(session) {
  if (seat !== 'guest') {
    root.appendChild(el('div', { class: 'card' }, [
      el('p', {}, 'Waiting for your opponent to put their share in.'),
      el('p', { class: 'dim' }, 'Nothing for you to do yet — this page updates itself.'),
      el('button', { class: 'btn ghost', onclick: cancelOpen }, 'Changed your mind? Cancel and get your money back'),
    ]));
    return;
  }

  const isMe = account?.toLowerCase() === session.guest.toLowerCase();
  const depositInput = el('input', { type: 'text', placeholder: 'put in now (ETH)', value: formState.depositNowGuest });
  depositInput.addEventListener('input', (e) => { formState.depositNowGuest = e.target.value; });
  const depositWei = safeParse(formState.depositNowGuest);
  const depositOverMax = depositWei !== null && depositWei > session.maxGuest;

  const kids = [
    el('h2', {}, 'Step 2: see the table, then join'),
    el('p', {}, `The whole table is set: your opponent can put in up to ${formatEther(session.maxHost)} ETH, you up to ${formatEther(session.maxGuest)} ETH.`),
    ...bondConsequence(session.bondGuest),
  ];

  if (!isMe) {
    kids.push(el('p', { class: 'error' }, `Your opponent set this table up for a different wallet (${session.guest}) than the one you're connected with. Switch to that one, then reload this page.`));
    root.appendChild(el('div', { class: 'card' }, kids));
    return;
  }

  kids.push(el('p', {}, 'Put in now (you can top up later, up to your declared max):'));
  kids.push(depositInput);
  if (depositOverMax) kids.push(el('p', { class: 'error' }, "That's more than your declared max for this table — the table won't credit it."));
  if (!sessionKeyAddress) kids.push(el('p', { class: 'dim' }, 'Waiting for your poker table to tell us your session key…'));

  const ready = !!sessionKeyAddress && !depositOverMax;
  const btn = el('button', { class: 'btn primary', onclick: () => registerSessionKeyAndJoin(session) }, 'Join the table and post my bond');
  if (!ready) btn.disabled = true;
  kids.push(btn);

  root.appendChild(el('div', { class: 'card' }, kids));
}

// Screen 3: active session -- play, rebuy, cooperative finish, open a dispute.
function renderActive(session) {
  const finalR = loadFinalReceipt();
  const kids = [
    el('h2', {}, 'Step 3: play'),
    el('p', {}, finalR
      ? 'The session is over and both sides have signed the final result. One click files it and settles the money — that is the last step.'
      : "You're all set — go play your cash session in the poker app. This page settles the money once the session ends. It's fine to close this tab and come back; reopen Buyin from the poker app and it picks up where it left off."),
  ];
  if (finalR) kids.push(el('button', { class: 'btn primary', onclick: () => finishMatch(finalR) }, 'Finish the match'));
  root.appendChild(el('div', { class: 'card' }, kids));

  root.appendChild(depositCard(session, seat === 'host' ? session.maxHost - session.depositedHost : session.maxGuest - session.depositedGuest));
  root.appendChild(disputeOpenCard());
}

// Screen 4: a dispute is open -- timeline, auto-filing, deposits still allowed,
// and settle-when-due.
function renderDisputed(session) {
  root.appendChild(disputeTimelineCard(session));

  if (autofileProgress) {
    root.appendChild(el('div', { class: 'card', role: 'status' }, [
      el('div', { class: 'pending-line' }, [
        el('span', { class: 'spinner' }),
        el('strong', {}, [`Filing your evidence automatically — ${autofileProgress.n} of ${autofileProgress.total}`, el('span', { class: 'dots' })]),
      ]),
    ]));
  }

  root.appendChild(depositCard(session, seat === 'host' ? session.maxHost - session.depositedHost : session.maxGuest - session.depositedGuest));

  // Kick off the auto-filer after this render (so its own withBusy card and
  // button-disable don't interleave with building the page). Guarded against
  // re-entry; a no-op when the evidence store is empty (the usual case until
  // P6 sends vault:evidence-v2).
  if (!autofileActive) setTimeout(() => runAutofile(session), 0);
}

// Screen 5: closed -- the settlement outcome AF-4 rules on, plus withdraw
// (rendered near the top by withdrawCard).
function renderClosed(session) {
  root.appendChild(el('div', { class: 'card' }, [el('h2', {}, 'Session settled'), settlementOutcome(session)]));
}

// --- dispute / settlement helpers ------------------------------------------
function disputeOpenCard() {
  const kids = [
    el('hr'),
    el('p', { class: 'dim' }, 'Something gone wrong and you need to end this on chain? You can open a dispute.'),
  ];
  if (!disputeConfirming) {
    kids.push(el('button', { class: 'btn ghost', onclick: () => { disputeConfirming = true; render(); } }, 'Open a dispute'));
  } else {
    kids.push(el('p', { class: 'error' }, "This ends the rest of tonight's session early. The hand in progress finishes for real, under time limits — then the table closes for good. Only open this if you mean it."));
    kids.push(el('button', { class: 'btn primary', onclick: () => { disputeConfirming = false; openDispute(); } }, "Yes — open the dispute"));
    kids.push(el('button', { class: 'btn ghost', onclick: () => { disputeConfirming = false; render(); } }, 'Never mind'));
  }
  return el('div', { class: 'card' }, kids);
}

function disputeTimelineCard(session) {
  const kids = [el('h2', {}, 'A dispute is open')];
  const openedAt = session.disputeOpenedAt;
  if (openedAt > 0n) {
    const closeAt = Number(openedAt + session.window) * 1000;
    if (Date.now() < closeAt) {
      kids.push(el('p', {}, `Evidence window closes at ${new Date(closeAt).toLocaleString()}.`));
      kids.push(el('p', { class: 'dim' }, 'While it is open, this page files your evidence for you automatically — you do not have to know which pieces matter.'));
    } else {
      kids.push(el('p', {}, 'The evidence window has closed — the frozen result is being worked out.'));
      // Phase-2 continuation (spec §5.2) is P4 (contract) + P6 (client)
      // territory: P4 shipped the on-chain logic, but the per-duty appointment
      // deadlines are birth-anchored state this UI does not yet read. Honest
      // placeholder rather than a fabricated countdown (TBD-P4-CONTINUATION).
      kids.push(el('p', { class: 'dim' }, 'If a phase-2 continuation is running, a decision may be due from one side. This build does not yet display the per-duty appointment times; the settlement below appears once everything is due.'));
      kids.push(el('button', { class: 'btn ghost', onclick: resolveSession }, 'Settle now (only works once everything is due)'));
    }
  } else {
    kids.push(el('p', {}, 'The dispute is being recorded on chain…'));
  }
  return el('div', { class: 'card' }, kids);
}

// The settlement outcomes AF-4 actually rules on, matched to its own wording.
function settlementOutcome(session) {
  // Zero filings at markedHand == 0 -> never-started semantics, full refund
  // incl. both bonds. everReceipted / markedHand are real public reads.
  if (session.markedHand === 0n && !session.everReceipted) {
    return el('p', {}, 'Nobody filed anything before the window closed, so the table treats this as never having started — your deposit and your bond are both back in full.');
  }

  // One or more filings at markedHand == 0 -> per-duty bond fate. The rule is
  // symmetric in the two players but the copy is not: the connected account is
  // either the one who filed or the one who didn't.
  if (session.markedHand === 0n) {
    const iAmHost = account?.toLowerCase() === session.host.toLowerCase();
    const myFiled = iAmHost ? session.hostFiledInWindow : session.guestFiledInWindow;
    const theirFiled = iAmHost ? session.guestFiledInWindow : session.hostFiledInWindow;
    if (myFiled && !theirFiled) {
      return el('p', {}, "Your deposit and your bond are back — you did what the dispute needed. Your opponent's bond was burned — they didn't file anything for the full 24-hour window.");
    }
    if (!myFiled && theirFiled) {
      return el('p', {}, "Your deposit is back. Your bond was burned — you didn't file anything for the full 24-hour window. Your opponent's bond came back to them because they filed.");
    }
    // Both flags true cannot reach this branch under AF-4 (the per-duty row is
    // reached only when at least one side is absent). If it somehow does, that
    // is a contract-side condition this UI has no business papering over -- so
    // fall through to the generic row rather than guessing.
  }

  // markedHand > 0 -> P3/P4's richer §5.3 rows (TBD-P3-ROWS). A deliberately
  // generic fallback, not a pretend explanation of a row this phase's copy
  // cannot yet distinguish.
  return el('p', {}, 'Settled — see your balance below.');
}

// --- shared small screens --------------------------------------------------
// Deposit / rebuy (task 4). Available whenever status is Active or Disputed.
function depositCard(session, headroomWei) {
  const input = el('input', { type: 'text', placeholder: 'add more (ETH)', value: formState.rebuy });
  input.addEventListener('input', (e) => { formState.rebuy = e.target.value; });
  const amountWei = safeParse(formState.rebuy);
  const over = amountWei !== null && headroomWei !== undefined && amountWei > headroomWei;
  const kids = [
    el('h2', {}, 'Add to your stack'),
    el('p', {}, "This tops up what you might play with — it isn't chips yet. It becomes chips the next time you both sign a receipt naming it. If a hand starts before that happens, this money is still safe; it just waits for the next hand boundary."),
    input,
  ];
  if (headroomWei !== undefined && headroomWei >= 0n) kids.push(el('p', { class: 'dim' }, `You can add up to ${formatEther(headroomWei)} ETH more before hitting your declared max.`));
  if (over) kids.push(el('p', { class: 'error' }, "That's more than your declared max allows — the table won't credit it."));
  const btn = el('button', { class: 'btn primary', onclick: () => { const v = safeParse(formState.rebuy); if (v && v > 0n) depositMore(v); } }, 'Add to my stack');
  if (over || !(amountWei && amountWei > 0n)) btn.disabled = true;
  kids.push(btn);
  return el('div', { class: 'card' }, kids);
}

// --- helpers ---------------------------------------------------------------
function safeParse(ethStr) {
  const s = (ethStr || '').trim();
  if (!s) return null;
  try { return parseEther(s); } catch { return null; }
}

// The both-signed `final` receipt, if the evidence bundle carries one -- the
// data the cooperative good ending files (task 6 step 3). Sourced from
// vault:evidence-v2's receipts array (the entry with final === true).
function loadFinalReceipt() {
  try {
    const bundle = evidenceStoreV2.load(localStorage, roomId);
    if (!bundle || !Array.isArray(bundle.receipts)) return null;
    return bundle.receipts.find((r) => r && r.final && r.sigHost && r.sigGuest) || null;
  } catch {
    return null;
  }
}

// --- boot ------------------------------------------------------------------
render();
connect({ silent: true });

document.addEventListener('visibilitychange', () => {
  if (!document.hidden && account) render();
});
