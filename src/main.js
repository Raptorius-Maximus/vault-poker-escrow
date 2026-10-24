import {
  createPublicClient,
  createWalletClient,
  custom,
  formatEther,
  parseEther,
  keccak256,
  toBytes,
  toHex,
  encodeAbiParameters,
  parseAbiParameters,
  recoverMessageAddress,
} from 'viem';
import { baseSepolia } from 'viem/chains';
import { CHANNEL_ABI, STATUS } from './abi.js';
import { DEPLOYMENTS } from './deployments.js';

// Maps a chain id to viem's chain definition -- needed by writeContract to
// correctly format a transaction (without it, every write fails with "No
// chain was provided"). One entry per key in DEPLOYMENTS; add here too if a
// new network is ever deployed to.
const CHAINS = { 84532: baseSepolia };

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
let matchResult = null; // { v, session, result, sigs: { host, guest } } once received
let lastMatchResultKey = null; // dedupes a repeated vault:result so it can't force a needless re-render
let renderGen = 0; // guards against an in-flight (slow-RPC) render finishing after a newer one
let lastSessionKey = null; // skip re-render on poll ticks where nothing actually changed on-chain

// Open-channel form state, kept outside the DOM so a re-render (poll tick,
// or any other trigger) never wipes out what's been typed so far -- every
// re-render seeds the inputs from here instead of a hardcoded default.
// buyIn defaults from ?buyin= if the poker client's Lobby set one (still
// freely editable here -- that URL param is a convenience, not a lock).
//
// opponent defaults the same way, from ?opponent=, which the poker client
// fills in once the guest has sent their address over the game connection.
// It replaces the old "have them text it to you and type it back" step --
// the single most error-prone thing in this whole flow, since one wrong
// character escrows the buy-in against a wallet nobody can pay out from.
// Shape-checked before it's trusted enough to pre-fill: an address arriving
// pre-typed reads as "already verified" and invites clicking straight past
// it, so anything that isn't 0x-and-40-hex leaves the field empty instead of
// showing junk with that same air of authority. The host still confirms
// whatever ends up in the box -- this is a convenience, not a lock, exactly
// like buyIn.
const isAddress = (s) => /^0x[0-9a-fA-F]{40}$/.test(s);
const opponentParam = (params.get('opponent') || '').trim();
const prefilledOpponent = isAddress(opponentParam) ? opponentParam : '';
const formState = { opponent: prefilledOpponent, buyIn: params.get('buyin') || '0.01' };

/**
 * Where the address in that field came from, which decides what the screen
 * says about it -- "your opponent sent this, check it" versus "go ask them
 * for it". Not derivable from the value itself: a host who typed it by hand
 * would otherwise be told their own typing arrived from somewhere else.
 */
let opponentFromPoker = Boolean(prefilledOpponent);
/**
 * The host has edited that field themselves. Latches on the first keystroke
 * and never clears, because from then on the value on screen is *their*
 * decision and a late-arriving push must not silently overwrite it -- that
 * would be this page changing where the money goes while they were looking
 * away, which is the one thing it must never do.
 */
let opponentTouched = false;

/**
 * The other player's deposit is broadcast but not yet in a block: `{ hash }`,
 * or null.
 *
 * Nothing on-chain says this -- that's the whole reason it has to be relayed
 * from their tab. It arrives by the same route their wallet address does
 * (their Buyin -> their poker page -> the relay -> our poker page -> here),
 * and it's purely a message on screen: no money, no signature and no decision
 * depends on it, so a wrong or missing one costs a few seconds of not knowing
 * rather than anything real.
 */
let peerSent = null;

/**
 * The status of the last successful chain read, or null before the first one.
 *
 * Exists so peerSent can be cleared by comparing against where the chain
 * actually is, rather than by catching the tick it changed on -- see the poll
 * for why that distinction turned out to matter.
 */
let currentStatus = null;

/**
 * The poker app's own view of the two match-result signatures, or null before
 * it has said anything: `{ matchOver, haveMine, haveTheirs }`.
 *
 * Both are needed to pay out, and this page used to be told only when both
 * had arrived -- so "one signature missing" looked exactly like "still
 * playing". One player got a payout button, the other got "go play your
 * match", and nothing anywhere named the difference. Knowing the halves lets
 * this screen say which one it is.
 */
let pokerProgress = null;

/**
 * Where the poker table for this session lives, remembered across a closed
 * tab: the full link, room key and all.
 *
 * Buyin cannot work this out for itself. The key rides in the URL fragment,
 * which browsers never send to a server and which nothing tells this page --
 * so it can only come from the poker page itself, while that page is still
 * open. Which is exactly when nobody needs it. Hence storing it.
 *
 * That key is what lets someone into the room, so this is a real widening of
 * where it lives: from one tab's address bar to this origin's storage on the
 * same machine. It is already in that browser's history, so the exposure is
 * comparable rather than new -- but it is a deliberate trade, made because
 * the alternative is a funded match nobody can finish.
 */
const POKER_LINK_KEY = `poker:link:${roomId}`;
let pokerUrl = (() => {
  try {
    return localStorage.getItem(POKER_LINK_KEY);
  } catch {
    return null; // storage disabled; the feature simply doesn't exist then
  }
})();

/**
 * Only accept a link pointing at the same machine this page came from.
 *
 * It arrives over postMessage and ends up as something a person is invited to
 * click, so "it parsed as a URL" is not a high enough bar.
 */
function rememberPokerUrl(raw) {
  if (typeof raw !== 'string' || raw === pokerUrl) return;
  let parsed;
  try {
    parsed = new URL(raw);
  } catch {
    return;
  }
  if (parsed.hostname !== location.hostname) return;
  if (parsed.protocol !== 'http:' && parsed.protocol !== 'https:') return;
  pokerUrl = raw;
  try {
    localStorage.setItem(POKER_LINK_KEY, raw);
  } catch {
    /* storage full or disabled -- still works for this page's lifetime */
  }
}

/**
 * The way back to a poker table that has been closed.
 *
 * Only offered when this page is not hearing from one, which is the whole
 * signal that it is gone. Reopening does NOT resume the closed match -- the
 * key share that decrypted those cards died with that tab -- but it does put
 * both players back in the same room to play a fresh match, and that match's
 * result is what settles the escrow already sitting here. Without it, a
 * funded session with a closed tab has no ending but the countdown.
 */
function pokerLinkCard() {
  if (!pokerUrl) return null;
  // Actively hearing from a table: obviously not missing.
  if (pokerProgress) return null;
  /*
   * A live opener means a poker tab is attached and simply hasn't reported in
   * yet -- true for the first few seconds of every session, and on the
   * connect screen before this page has said anything at all. Announcing a
   * missing table then would be wrong far more often than right.
   */
  try {
    if (window.opener && !window.opener.closed) return null;
  } catch {
    /* cross-origin or gone; treat as absent */
  }
  const input = el('input', { type: 'text', readonly: 'readonly', value: pokerUrl });
  input.addEventListener('focus', () => input.select());
  const copy = el('button', { class: 'btn ghost' }, 'Copy link');
  copy.addEventListener('click', async () => {
    try {
      // Only exists on a secure page; over a plain LAN address it does not.
      if (!navigator.clipboard?.writeText) throw new Error('no clipboard');
      await navigator.clipboard.writeText(pokerUrl);
      copy.textContent = 'Copied';
      setTimeout(() => (copy.textContent = 'Copy link'), 1800);
    } catch {
      input.focus();
      input.select();
      copy.textContent = 'Selected — press Ctrl+C';
      setTimeout(() => (copy.textContent = 'Copy link'), 2600);
    }
  });
  return el('div', { class: 'card' }, [
    el('h2', {}, 'Your poker table isn’t open'),
    el('p', {}, "Nothing here can finish without it — the result that pays the winner is worked out at the table, not on this page. This is the link back to it:"),
    input,
    copy,
    el('p', { class: 'dim' }, "Reopening won't restore the hand that was interrupted; that one is gone for good. It does put you both back in the same room, and the next match you finish there settles the money already held here."),
  ]);
}

/** Fired the countdown answer once already this page. See the ClaimPending screen. */
let autoRefuted = false;

// --- postMessage handshake with the poker client (the opener) ------------
//
// event.source is set by the browser itself from which window object's
// postMessage() was actually called -- a third-party tab cannot spoof it.
// That is the real authenticity check; origin varies by deployment (dev,
// LAN, tunnel) so it is not something to hardcode here.
// Used to skip resending an identical hello once it had already gone out
// once. That was the actual bug behind "the vault does not come up
// automatic": once a session reaches Active, its hello content never
// changes again for the rest of the match, so that dedupe meant Buyin sent
// it *exactly once, ever* -- and if the poker tab missed that one message
// for any reason (a startup race, a reload on either side), there was no
// second chance for the rest of the match, silently. Now called every poll
// tick unconditionally instead: it's one small postMessage, not a render,
// so resending it every 4s is not spam -- it's what makes the link between
// the two tabs self-healing instead of a single point of failure.
function sendHelloToOpener(session) {
  if (!window.opener) return;
  // host/guest are only meaningful once both have deposited (session
  // beyond AwaitingGuest); send undefined until then rather than the
  // zero address, so the poker client can tell "not known yet" from
  // "known to be the zero address" (which should never happen, but a
  // signature built from a wrong-but-valid-looking address is a much
  // worse failure than one that visibly never arrives).
  const host = session && session.status !== 'None' && session.status !== 'AwaitingGuest' ? session.host : undefined;
  const guest = session && session.status !== 'None' && session.status !== 'AwaitingGuest' ? session.guest : undefined;
  // status rides along so the poker client can tell "still owed" from
  // "paid out and finished" without reading the chain itself. It's the only
  // way that app can know the payout actually landed rather than merely
  // having been clicked, which is what it gates its own end-of-match screen
  // on. Undefined until the first successful read, which reads there as
  // "don't know yet" -- distinct from any real status.
  window.opener.postMessage(
    {
      type: 'vault:hello',
      session: roomId,
      contractAddress: deployment?.address,
      chainId,
      host,
      guest,
      status: session?.status,
    },
    '*',
  );
}

/**
 * What the payout is waiting on, in words, or null if it isn't waiting.
 *
 * The two signatures are gathered by the poker app and handed here together.
 * When one is missing, that is worth saying out loud: it is the difference
 * between "your opponent hasn't confirmed yet, sit tight" and "your wallet
 * never answered, go poke it", and previously both looked like an ordinary
 * match in progress.
 */
function waitingOnSignatures() {
  if (!pokerProgress || !pokerProgress.matchOver) return null;
  const { haveMine, haveTheirs } = pokerProgress;
  if (haveMine && haveTheirs) {
    // Both exist over there but the combined result hasn't reached this tab
    // yet. A second or two at most, and it self-heals on the next hello.
    return 'The match is over and both of you have confirmed. Getting the payout ready…';
  }
  if (!haveMine) {
    return "The match is over. Your wallet still needs to confirm the result — look for its popup, or open your wallet from its own icon. Nothing can be paid out until both of you have confirmed.";
  }
  return "The match is over and you've confirmed. Waiting on your opponent's confirmation — their app does that by itself, so this usually only takes a moment. Nothing can be paid out until it arrives. If they've gone for good, use the countdown below.";
}

/**
 * Bring the poker tab back to the front.
 *
 * Two attempts, because neither is guaranteed. Browsers deliberately restrict
 * one tab pulling focus to another -- that restriction exists to stop adverts
 * stealing your screen, and it does not make an exception for good intentions.
 * So we ask directly, and we also ask the poker page to do it from its own
 * side, where it can at least change its tab title if focus is refused. A tab
 * you cannot see can still say what it wants.
 */
function goToPokerTable() {
  if (!window.opener || window.opener.closed) return;
  try {
    window.opener.postMessage({ type: 'vault:focus-poker', v: 1, session: roomId }, '*');
  } catch {
    /* nothing more to try */
  }
  try {
    window.opener.focus();
  } catch {
    /* refused; the poker tab's own title change is the fallback */
  }
}

/**
 * Once both buy-ins are in, this tab is done until the match ends -- so leave
 * on your own rather than making someone notice that and go looking for the
 * other tab. Fires once per page: a second unrequested tab switch, later,
 * would be the browser doing something the person did not ask for.
 */
let autoReturnTimer = null;
let autoReturned = false;
function scheduleReturnToPoker() {
  if (autoReturned || autoReturnTimer || !window.opener || window.opener.closed) return;
  autoReturnTimer = setTimeout(() => {
    autoReturnTimer = null;
    autoReturned = true;
    goToPokerTable();
    render();
  }, 5000);
}

const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';
const shortAddr = (a) => `${a.slice(0, 6)}…${a.slice(-4)}`;

/**
 * Is this page showing a seat that the connected wallet does not hold?
 *
 * Both Buyin links look almost identical -- one word differs -- so opening
 * your opponent's instead of your own is an easy mistake, and it has been
 * made. The page then quietly shows you the wrong player's side of the
 * match: their buttons, their next step, none of which will work for your
 * wallet, and no clue anywhere that anything is off.
 *
 * Two checks, because they cover different moments. Once the channel exists,
 * the chain says who holds each seat and that settles it. Before it does,
 * there is nothing on chain to compare against -- but a host link whose
 * `opponent` address is the wallet reading it can only mean one thing.
 */
function seatMismatch(session) {
  if (!account || !seat) return null;

  // The guest-joining screen makes this exact check itself, more precisely.
  if (session && session.status === 'AwaitingGuest' && seat === 'guest') return null;

  const expected = session && session.status !== 'None'
    ? (seat === 'host' ? session.host : session.guest)
    : null;
  if (expected && expected !== ZERO_ADDRESS && expected.toLowerCase() !== account.toLowerCase()) {
    return `This page is showing the ${seat}'s side of the match, but the ${seat} of this match is ${shortAddr(expected)} — and your wallet is ${shortAddr(account)}. You are almost certainly on your opponent's Buyin link. Open Buyin from your own poker tab instead.`;
  }

  if (seat === 'host' && prefilledOpponent && prefilledOpponent.toLowerCase() === account.toLowerCase()) {
    return `This is the host's Buyin link, and your wallet (${shortAddr(account)}) is the opponent named in it. You have opened your opponent's link rather than your own. Open Buyin from your own poker tab instead.`;
  }

  return null;
}

/** Copy for the open-channel screen, in both places it has to stay in sync. */
const OPPONENT_HELP_SENT =
  "Your opponent sent their wallet address through the poker app, so it's already filled in below — give it a quick look against what they told you, set how much you're both putting in, and one click records who you're playing and sends your own money in.";
const OPPONENT_HELP_ASK =
  "Ask your opponent for their wallet address — a text message is fine, it's not a secret. Paste it below with how much you're both putting in. One click both records who you're playing and sends your own money in.";

/**
 * The guest's address, arriving from the poker app after this tab was opened.
 *
 * The URL pre-fill only covers the case where Buyin is opened *after* the
 * guest sends their wallet, and the usual order is the opposite: the host
 * opens the table, this tab comes up with it, and the guest turns up a minute
 * later. Without this, the field stays empty and the only way out is knowing
 * to close the tab and reopen it from the poker app — an invisible ordering
 * rule that produces a screen which simply looks broken.
 *
 * Fills the live input in place rather than re-rendering. A re-render here
 * would be mid-typing for a host filling in the buy-in field next to it, and
 * would take their caret with it; the value would survive (formState is kept
 * outside the DOM for exactly that reason) but the interruption would not be
 * worth it for what is one field changing.
 */
function applyOpponentFromPoker(raw) {
  const addr = typeof raw === 'string' ? raw.trim() : '';
  // Checked here as well as by the sender: this arrives from another window,
  // and it decides which address a real deposit gets escrowed against.
  if (!isAddress(addr)) return;
  if (opponentTouched) return; // the host's own typing wins, always
  if (formState.opponent === addr) return; // repeat of what we already have
  formState.opponent = addr;
  opponentFromPoker = true;
  // Absent when the open-channel screen isn't the one showing (still
  // connecting, or the channel is already open). Nothing to do then --
  // formState is what the next render seeds from.
  const input = document.getElementById('opponent-input');
  if (input) input.value = addr;
  const help = document.getElementById('opponent-help');
  if (help) help.textContent = OPPONENT_HELP_SENT;
}

window.addEventListener('message', (event) => {
  if (!window.opener || event.source !== window.opener) return;
  const data = event.data;
  if (data && data.type === 'vault:opponent' && data.session === roomId) {
    applyOpponentFromPoker(data.address);
    return;
  }
  if (data && data.type === 'vault:peer-sent' && data.session === roomId) {
    const hash = typeof data.hash === 'string' ? data.hash : null;
    const kind = data.kind === 'payout' ? 'payout' : 'deposit';
    if (peerSent && peerSent.hash === hash) return; // already showing this one
    peerSent = { hash, kind };
    if (!peerStillRelevant()) {
      // Already arrived. Happens for real: the relay replays undelivered
      // messages when a connection resumes, so this announcement can turn up
      // long after the thing it announces has confirmed.
      peerSent = null;
      return;
    }
    // Safe to re-render here, unlike the opponent-address push: the only
    // screens this can arrive on are the two "waiting for the other player"
    // ones, and neither has an input to interrupt.
    render();
    return;
  }
  if (data && data.type === 'vault:progress' && data.session === roomId) {
    const next = {
      matchOver: Boolean(data.matchOver),
      haveMine: Boolean(data.haveMine),
      haveTheirs: Boolean(data.haveTheirs),
      connected: Boolean(data.connected),
    };
    rememberPokerUrl(data.pokerUrl);
    // Arrives every few seconds; only redraw when it actually says something
    // different, or this would rebuild the screen forever.
    if (pokerProgress
      && pokerProgress.matchOver === next.matchOver
      && pokerProgress.haveMine === next.haveMine
      && pokerProgress.haveTheirs === next.haveTheirs
      && pokerProgress.connected === next.connected) return;
    pokerProgress = next;
    render();
    return;
  }
  if (data && data.type === 'vault:result' && data.session === roomId) {
    // The poker side is now expected to send this at most once per tab
    // (see its own vaultFinalizedWindowRef comment), but re-rendering on an
    // identical repeat -- from a stale sender, a race, anything -- would
    // tear the whole screen down and back up again and re-query the chain
    // for no reason. Belt and suspenders: only actually act on a change.
    const key = JSON.stringify(data);
    if (key === lastMatchResultKey) return;
    lastMatchResultKey = key;
    matchResult = data;
    render();
  }
});

// --- chain / wallet setup --------------------------------------------------

/**
 * @param silent  Reconnect without prompting, or give up quietly.
 *
 * `eth_accounts` reports the accounts this site is *already* authorised for
 * and never opens a wallet popup; `eth_requestAccounts` is the one that asks.
 * So a returning tab can pick its own connection back up with no interaction
 * at all, and the "Connect your wallet to start" screen is only shown to
 * someone who genuinely has to press something.
 *
 * That screen was appearing on every single trip here -- the poker app opens
 * this tab at deal time and again before the payout -- and each time it was a
 * step that existed only because nothing had asked the wallet whether it was
 * already connected. It reads as information; it was really just a missing
 * question.
 */
async function connect({ silent = false } = {}) {
  if (!window.ethereum) {
    if (!silent) alert('No wallet found. Install MetaMask (or another browser wallet) first.');
    return;
  }
  walletClient = createWalletClient({ transport: custom(window.ethereum) });
  let addr;
  if (silent) {
    const accounts = await window.ethereum
      .request({ method: 'eth_accounts' })
      .catch(() => []);
    addr = accounts?.[0];
    // Not authorised yet (or the wallet is locked). Nothing more can happen
    // without a real click, so fall back to showing the button.
    if (!addr) return;
  } else {
    [addr] = await walletClient.requestAddresses();
  }
  account = addr;
  chainId = await walletClient.getChainId();
  deployment = DEPLOYMENTS[chainId] ?? null;
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
  deployment = DEPLOYMENTS[chainId] ?? null;
  if (CHAINS[chainId]) walletClient = createWalletClient({ chain: CHAINS[chainId], transport: custom(window.ethereum) });
  render();
}

// --- on-chain reads ----------------------------------------------------

async function readSession() {
  if (!publicClient || !deployment || !sessionId) return null;
  const [host, guest, buyIn, window_, status, claimant, bond, deadline] =
    await publicClient.readContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'sessions',
      args: [sessionId],
    });
  return { host, guest, buyIn, window: window_, status: STATUS[status], claimant, bond, deadline };
}

function sessionKey(session) {
  return JSON.stringify(session, (_, v) => (typeof v === 'bigint' ? v.toString() : v));
}

/**
 * Keep saying "Closed" after the chain reads stop.
 *
 * Polling ends at Closed on purpose (see below), but that leaves the tick
 * where the status flipped as the *only* one that would ever carry it -- and
 * the poker client gates its entire end-of-match screen on hearing that, so a
 * single missed message would leave it waiting on a payout that already
 * happened, forever. Exactly the failure mode sendHelloToOpener's own comment
 * describes, in the one place where the message never comes round again.
 *
 * Costs no RPC: the session is Closed, which is permanent, so this re-sends a
 * value that can no longer change.
 */
let closedTimer = null;
function startClosedHeartbeat(session) {
  if (closedTimer) return;
  closedTimer = setInterval(() => sendHelloToOpener(session), 4000);
}

function startPolling() {
  if (pollTimer) return;
  pollTimer = setInterval(async () => {
    // A full render() clears and rebuilds the whole screen -- fine as a
    // response to something real changing, disruptive (wipes out whatever
    // you're mid-typing) if it fires just because a timer ticked. Do a
    // light read first and only re-render if the on-chain state actually
    // moved since the last one we saw.
    const session = await readSession().catch(() => null);
    if (!session) return;
    currentStatus = session.status;
    // Runs every tick, independent of whether the render below fires --
    // see sendHelloToOpener's own comment for why this must not be gated
    // on the session having actually changed.
    sendHelloToOpener(session);
    // Their transfer has arrived (or stopped mattering). See peerStillRelevant.
    let landed = false;
    if (peerSent && !peerStillRelevant()) {
      peerSent = null;
      landed = true;
    }

    const key = sessionKey(session);
    if (key === lastSessionKey && !landed) return;
    render();
    // Closed is permanent -- this exact session can never change again, so
    // a tab left open past that point was polling the chain forever for no
    // reason. One Buyin tab doing that is harmless; several stacking up
    // over a night of testing is real load, and is very likely what tipped
    // the RPC endpoint into rate-limiting earlier tonight. This session is
    // done; a new game gets its own new session (and its own fresh tab,
    // opened by the poker app's Buyin button) rather than this one somehow
    // reopening -- V1's contract has no "reopen" this could call anyway.
    if (session.status === 'Closed' && pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
      startClosedHeartbeat(session);
    }
  }, 4000);
}

// --- writes --------------------------------------------------------------

/**
 * What's currently in flight, or null. `{ phase, label, hash }`.
 *
 * Two phases, and the difference between them is the whole point of showing
 * this at all:
 *
 *   'wallet' — we asked the wallet, nothing has been broadcast, nothing has
 *              moved. The only thing that can advance this is the person
 *              clicking approve in a window that may well be behind this one.
 *   'sent'   — the wallet gave us a transaction hash. The money has left and
 *              the network is confirming it. Nobody can do anything to hurry
 *              this and nothing is wrong; it just takes a few seconds.
 *
 * Yes, a page can know a transfer is sent before it goes through: the hash IS
 * that knowledge, handed back the instant the transaction is broadcast and
 * long before any block contains it. Before this, both phases looked
 * identical from the outside -- a frozen screen with disabled buttons -- so
 * "my wallet is waiting for me" and "the chain is working on it" were
 * indistinguishable, and the natural response to either was to click things
 * or reload, which is the worst available move during a deposit.
 */
let pending = null;

/** Live status for an in-flight transaction. Null when nothing is pending. */
function pendingCard() {
  if (!pending) return null;
  const { phase, label, hash } = pending;
  const Label = label ? label[0].toUpperCase() + label.slice(1) : 'It';

  const kids = [
    el('div', { class: 'pending-line' }, [
      el('span', { class: 'spinner' }),
      el('strong', {}, [
        phase === 'wallet'
          ? 'Waiting for you to approve this in your wallet'
          : 'Sent — waiting for the network to confirm it',
        el('span', { class: 'dots' }),
      ]),
    ]),
    el('p', { class: 'dim' }, phase === 'wallet'
      ? `Your wallet should have opened a window asking you to confirm ${label}. Nothing has been sent and no money has moved — that only happens when you approve it there. If you can't see the window, check behind this one, or open your wallet from its own icon.`
      : `${Label} is on its way and the network is writing it down. This usually takes a few seconds. Nothing needs doing and nothing is stuck — leave this page open and it'll notice by itself the moment it lands.`),
  ];

  /*
   * Only in the wallet phase, and only because a wallet genuinely can fail to
   * answer -- a popup that never opened, two wallet extensions racing for the
   * same page. The request is then waiting on something that will never
   * arrive, and without this the whole screen stays switched off.
   *
   * Deliberately absent once there's a hash: at that point the money really
   * has left, and a button implying otherwise would be a lie.
   */
  if (phase === 'wallet') {
    kids.push(el('button', {
      class: 'btn ghost',
      onclick: cancelPending,
    }, "Nothing happened? Give up on this and try again"));
  }

  // The hash exists only in the 'sent' phase, which is exactly why it's worth
  // showing: it's the receipt proving the transfer really did leave, for
  // anyone who wants to watch it land somewhere other than here.
  if (hash) {
    kids.push(el('div', { class: 'dim hash' }, hash));
    if (deployment?.explorer) {
      kids.push(el('a', {
        class: 'dim',
        href: `${deployment.explorer}/tx/${hash}`,
        target: '_blank',
        rel: 'noopener noreferrer',
      }, 'Watch it on the block explorer →'));
    }
  }

  // role=status so this is announced rather than silently appearing.
  return el('div', { class: 'card pending', role: 'status' }, kids);
}

/** The same live wait, for the transfer coming from the other player. */
/**
 * Is the other side's announced transfer still something we're waiting on?
 *
 * Read straight off the current chain state, which is the whole point. Two
 * earlier versions of this tried to notice the *moment* it arrived -- first
 * off the poll's key-changed branch, then by remembering the status it was
 * announced against -- and both got stranded showing a transfer that had long
 * since landed. The second failed on message replay: the relay re-delivers
 * undelivered messages when a connection resumes, so the announcement can
 * arrive after the deposit already confirmed, and "the status it was
 * announced against" is then the status it will stay at forever.
 *
 * A question about the present has no such failure mode. What we are waiting
 * for is fully determined by seat, status and kind:
 *
 *   deposit, host  -- their money is missing exactly while AwaitingGuest
 *   deposit, guest -- theirs is missing exactly while None
 *   payout         -- outstanding exactly while Active (Closed means paid)
 */
function peerStillRelevant() {
  if (!peerSent) return false;
  if (!currentStatus) return true; // no read yet; don't hide it on a guess
  if (peerSent.kind === 'payout') return currentStatus === 'Active';
  return seat === 'host' ? currentStatus === 'AwaitingGuest' : currentStatus === 'None';
}

function peerPendingCard() {
  if (!peerStillRelevant()) return null;
  const payout = peerSent.kind === 'payout';
  const kids = [
    el('div', { class: 'pending-line' }, [
      el('span', { class: 'spinner' }),
      el('strong', {}, [
        payout
          ? 'Your opponent is paying the winner — waiting for the network'
          : 'Your opponent has sent theirs — waiting for the network to confirm it',
        el('span', { class: 'dots' }),
      ]),
    ]),
    el('p', { class: 'dim' }, "It's left their wallet and the network is writing it down — usually a few seconds. Nothing for you to do; this page moves on by itself the moment it lands."),
  ];
  if (peerSent.hash) {
    kids.push(el('div', { class: 'dim hash' }, peerSent.hash));
    if (deployment?.explorer) {
      kids.push(el('a', {
        class: 'dim',
        href: `${deployment.explorer}/tx/${peerSent.hash}`,
        target: '_blank',
        rel: 'noopener noreferrer',
      }, 'Watch it on the block explorer →'));
    }
  }
  return el('div', { class: 'card peer-pending', role: 'status' }, kids);
}

/**
 * Put the pending card on screen without a full render().
 *
 * render() rebuilds every button in its enabled state, which is precisely
 * wrong in the middle of a transaction -- the buttons were disabled on
 * purpose. So the card is swapped in place instead.
 */
function showPending() {
  const existing = root.querySelector('.card.pending');
  const next = pendingCard();
  if (existing && next) existing.replaceWith(next);
  else if (existing) existing.remove();
  else if (next) root.insertBefore(next, root.children[1] ?? null); // just under the banner
}

/**
 * @param kind  Optional tag carried to the poker client alongside the hash.
 *              Only the payout is tagged, because that is the one write whose
 *              in-flight state the poker app has to show on its own screen --
 *              it hides "new game" until the money has actually moved, and
 *              "a transaction is happening" is not specific enough to gate
 *              that on.
 */
/**
 * Numbers each withBusy call so a stale one can't clean up after a live one.
 *
 * Needed because the wait is now escapable: dismiss a stuck request, start
 * another, and the first one settling later would otherwise clear the second
 * one's card and re-enable its buttons mid-transaction.
 */
let pendingSeq = 0;

/**
 * Give up on a wallet request that never answered.
 *
 * A wallet can simply not come back -- a popup that never opened, a second
 * wallet extension racing for the same page, an approval that went somewhere
 * unseen. The promise then never settles, so the `finally` below never runs.
 * That used to be survivable by accident: a poll re-render put the buttons
 * back. Then re-rendering started restoring the disabled state too -- correct
 * for stopping a double-deposit, but it turned a stall into a dead screen
 * with every control switched off and nothing to click.
 *
 * Only offered before anything is broadcast. Once there's a hash the money
 * has genuinely moved and pretending otherwise would be a lie.
 */
function cancelPending() {
  pendingSeq++; // orphan the in-flight call so its finally can't undo this
  pending = null;
  render();
}

/**
 * Turn a wallet or chain error into something worth reading.
 *
 * These used to go straight into an alert() exactly as received, which
 * produced "An internal error was received." on screen -- seen live, from
 * pressing "Finish the original countdown" before the countdown had
 * finished. That is a correct refusal by the contract and an entirely
 * reasonable thing to have tried, and the message managed to convey neither.
 *
 * Returns null for a rejection, because deciding not to sign is not a
 * failure and does not need reporting back to the person who decided it.
 */
function explainFailure(err, label) {
  const raw = `${err?.shortMessage || ''} ${err?.message || ''} ${err?.details || ''}`.toLowerCase();

  if (raw.includes('user rejected') || raw.includes('user denied') || raw.includes('rejected the request')) {
    return null;
  }
  if (raw.includes('insufficient funds')) {
    return "Not enough test ETH in this wallet to cover the amount plus the network fee.";
  }
  if (raw.includes('chain') && raw.includes('match')) {
    return 'Your wallet is on a different network. Switch it to Base Sepolia and try again.';
  }
  /*
   * Everything the contract refuses arrives as a bare "internal error" with
   * no reason attached, because a revert during gas estimation carries none.
   * Timing is overwhelmingly the cause here -- every action on this page is
   * only legal in one particular state -- so say that rather than the empty
   * literal truth.
   */
  if (raw.includes('internal error') || raw.includes('reverted') || raw.includes('execution reverted')) {
    return `The network wouldn't accept ${label} — almost always because it isn't the right moment for it yet. If you were finishing a countdown, it has to actually run out first; the time is shown above. Nothing was sent and nothing was lost.`;
  }
  return `Couldn't send ${label}: ${err?.shortMessage || err?.message || String(err)}`;
}

async function withBusy(fn, label = 'this', kind = undefined) {
  let failure = null;
  const mySeq = ++pendingSeq;
  const mine = () => pendingSeq === mySeq;
  const btns = root.querySelectorAll('button');
  btns.forEach((b) => (b.disabled = true));
  pending = { phase: 'wallet', label, hash: null };
  showPending();
  try {
    const hash = await fn();
    if (!mine()) return; // abandoned while we waited -- leave the screen alone
    if (hash) {
      pending = { phase: 'sent', label, hash };
      showPending();
      // Tell the other player's screen it's coming. Only this tab can know
      // this yet -- the transaction is broadcast but in no block, so there is
      // nothing on-chain for their side to read. Without this they sit on an
      // unchanged screen for the whole confirmation, which is the same dead
      // air this card was added to fix, just moved to the other person.
      if (window.opener) {
        window.opener.postMessage({ type: 'vault:sent', v: 1, session: roomId, seat, hash, kind }, '*');
      }
      await publicClient.waitForTransactionReceipt({ hash });
      if (!mine()) return;
      /*
       * Say so the instant the receipt lands.
       *
       * This tab knows before anyone else, and everything else finds out by
       * polling -- which is fine here, in the foreground, and much less fine
       * in the *other* player's Buyin tab, sitting in the background behind
       * their poker table. Browsers throttle timers in hidden tabs, down to
       * about once a minute once they have been hidden a while, so the other
       * side's "waiting for the network" spinner could run for minutes after
       * the money had actually arrived, or effectively forever.
       *
       * The poker app relays this to the other player, so neither screen has
       * to wait on a throttled clock to notice something that already
       * happened.
       */
      if (window.opener) {
        window.opener.postMessage(
          { type: 'vault:confirmed', v: 1, session: roomId, seat, hash, kind },
          '*',
        );
      }
    }
  } catch (err) {
    if (mine()) failure = explainFailure(err, label);
  } finally {
    if (mine()) {
      pending = null;
      render(failure);
    }
  }
}

const openChannel = (opponent, buyInEth) =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'open',
      args: [sessionId, opponent],
      value: parseEther(buyInEth),
      account,
    }),
    'your buy-in',
  );

const joinChannel = (buyIn) =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'join',
      args: [sessionId],
      value: buyIn,
      account,
    }),
    'your share of the buy-in',
  );

const cancelOpen = () =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'cancelOpen',
      args: [sessionId],
      account,
    }),
    'the cancellation, which sends your money back',
  );

const claimByDefault = (bondWei) =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'claimByDefault',
      args: [sessionId],
      value: bondWei,
      account,
    }),
    'your claim and its deposit',
  );

const iAmHere = () =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'iAmHere',
      args: [sessionId],
      account,
    }),
    "your answer that you're still here",
  );

const resolveSession = () =>
  withBusy(() =>
    walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'resolve',
      args: [sessionId],
      account,
    }),
    'the finish of the countdown',
  );

const closeCooperative = (winner, s) =>
  withBusy(async () => {
    // Recover locally first -- matches Channel.sol's own _recover formula
    // exactly (keccak256(abi.encode(address(this), chainid, sessionId,
    // winner)), EIP-191-wrapped). If this disagrees with the chain, better
    // to see the actual values here than guess from MetaMask's contentless
    // "likely to fail" warning.
    const hash = keccak256(
      encodeAbiParameters(parseAbiParameters('address, uint256, bytes32, address'), [
        deployment.address,
        BigInt(chainId),
        sessionId,
        winner,
      ]),
    );
    const [recoveredHost, recoveredGuest] = await Promise.all([
      recoverMessageAddress({ message: { raw: hash }, signature: matchResult.sigs.host }).catch((e) => `error: ${e.message}`),
      recoverMessageAddress({ message: { raw: hash }, signature: matchResult.sigs.guest }).catch((e) => `error: ${e.message}`),
    ]);
    console.log('[vault debug] closeCooperative check', {
      hash,
      winner,
      expectedHost: s.host,
      recoveredHost,
      hostMatches: recoveredHost === s.host,
      expectedGuest: s.guest,
      recoveredGuest,
      guestMatches: recoveredGuest === s.guest,
    });
    return walletClient.writeContract({
      address: deployment.address,
      abi: CHANNEL_ABI,
      functionName: 'closeCooperative',
      args: [sessionId, winner, matchResult.sigs.host, matchResult.sigs.guest],
      account,
    });
  }, 'the payout to the winner', 'payout');

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

/**
 * A permanent map of the whole process, in plain words, present on every
 * screen -- written for someone who has never touched crypto before and
 * has no reason to know what a "channel" or a "cooperative close" is.
 * Written to match how Loke described the flow back: post the opponent's
 * wallet, they accept the transfer, the match stats transfer the money.
 * `active` is 1, 2, or 3; steps before it are marked done, the current one
 * highlighted, the rest dimmed.
 */
function stepTracker(active) {
  const steps = [
    'Set up who you’re playing',
    'Both of you put your money in',
    'Play — the winner gets paid automatically',
  ];
  return el(
    'div',
    { class: 'steps' },
    steps.map((label, i) => {
      const n = i + 1;
      const state = n < active ? 'done' : n === active ? 'now' : 'next';
      return el('div', { class: `step ${state}` }, [
        el('span', { class: 'step-num' }, n < active ? '✓' : String(n)),
        el('span', { class: 'step-label' }, label),
      ]);
    }),
  );
}

// Nothing on the poker side checks whether this channel is actually funded
// before letting a match start -- the two apps don't coordinate that. If
// someone starts playing before both deposits land, the "loser" walks away
// with nothing at risk (the winner can't be paid from a channel that was
// never fully funded either). This is the one place Vault can say so.
function fundingWarning() {
  return el(
    'div',
    { class: 'card warning' },
    "⚠ Don't start the poker match yet — the money isn't locked in until step 2 is finished for both of you.",
  );
}

/**
 * Draw the screen, then put back anything an in-flight transaction needs.
 *
 * A poll tick can re-render in the middle of a deposit -- the other player
 * depositing is exactly the sort of change that triggers one, and it happens
 * right when you're most likely to be mid-transaction yourself. Everything
 * that render draws is fresh and clickable, including the button that started
 * the transaction still in flight, and a second click there is a second real
 * deposit. So the disable and the status card are re-applied afterwards
 * rather than being one-shot effects of withBusy.
 */
async function render(errorMsg) {
  await renderScreens(errorMsg);
  if (!pending) return;
  root.querySelectorAll('button').forEach((b) => (b.disabled = true));
  showPending();
}

async function renderScreens(errorMsg) {
  const myGen = ++renderGen;

  /*
   * Read the chain BEFORE touching the DOM.
   *
   * This used to wipe the page first and read second, which meant every exit
   * between those two points left a half-built page on screen: the banner, a
   * card or two, and nothing else. Seen live at the end of a match -- a blank
   * Buyin with one stale card floating in it. A slow or failed read, or a
   * newer render superseding this one mid-await, all produced the same stub,
   * and none of them are unusual events.
   *
   * Everything after the wipe below is synchronous, so the page is now either
   * the old one or a complete new one, and never a fragment of either.
   */
  const canRead = roomId && seat && account && deployment;
  let session = null;
  let readError = null;
  if (canRead) {
    session = await readSession().catch((err) => {
      readError = err;
      return null;
    });
    // Bail before the wipe, not after: a superseded render should leave the
    // screen exactly as it found it.
    if (myGen !== renderGen) return;
  }

  root.innerHTML = '';
  root.appendChild(banner());

  const peerCard = peerPendingCard();
  if (peerCard) root.appendChild(peerCard);

  const mismatch = seatMismatch(session);
  if (mismatch) {
    root.appendChild(el('div', { class: 'card warning' }, `⚠ ${mismatch}`));
  }

  const linkCard = pokerLinkCard();
  if (linkCard) root.appendChild(linkCard);

  if (!roomId || !seat) {
    root.appendChild(
      el('div', { class: 'card' }, [
        el('p', {}, 'Missing ?session= and ?seat= in the URL. Open this from the poker client\'s Buyin button, not directly.'),
        el('p', {}, ['New here? ', el('a', { href: 'guide.html' }, 'Read the step-by-step guide'), ' — wallet setup, free test ETH, and your first match.']),
      ]),
    );
    return;
  }

  // Screen 1: connect wallet
  if (!account) {
    root.appendChild(
      el('div', { class: 'card' }, [
        el('h1', {}, 'Buyin'),
        el('p', {}, 'This holds your poker buy-in safely and pays the winner automatically when the match ends — nobody, including this app, can hold onto the money or decide who won.'),
        el('p', { class: 'dim' }, `You're the ${seat === 'host' ? 'one setting this match up' : 'one joining'}.`),
        // Wrapped, not passed directly: as a handler it would receive the
        // click event as its options object, which is a trap waiting for
        // whoever adds a second option to connect().
        el('button', { class: 'btn primary', onclick: () => connect() }, 'Connect your wallet to start'),
      ]),
    );
    return;
  }

  if (!deployment) {
    root.appendChild(
      el('div', { class: 'card' }, [
        el('p', {}, 'This only runs on a free practice network, not real money — your wallet needs to switch to it.'),
        el('button', {
          class: 'btn primary',
          onclick: () => switchToDeploymentChain(84532),
        }, 'Switch to the practice network'),
      ]),
    );
    return;
  }

  /*
   * No session to draw from. Always say so with something on screen and a way
   * forward -- returning quietly here is what produced the blank page, and a
   * blank page is the one outcome that tells nobody anything.
   */
  if (!session) {
    root.appendChild(el('div', { class: 'card' }, [
      el('p', { class: 'error' }, readError
        ? `Couldn't reach the network: ${readError.shortMessage || readError.message}`
        : "Couldn't read this session from the network."),
      el('p', { class: 'dim' }, 'Nothing is lost — the money and the result live on the chain, not in this page. This keeps retrying by itself every few seconds.'),
      el('button', { class: 'btn ghost', onclick: () => render() }, 'Try again now'),
    ]));
    return;
  }
  currentStatus = session.status;
  lastSessionKey = sessionKey(session);
  sendHelloToOpener(session);
  if (errorMsg) root.appendChild(el('div', { class: 'card error' }, errorMsg));

  const step = session.status === 'None' ? 1 : session.status === 'AwaitingGuest' ? 2 : 3;
  root.appendChild(stepTracker(step));

  root.appendChild(
    el('div', { class: 'meta' }, [
      el('div', {}, `Connected: ${account}`),
      el('div', {}, `Session: ${roomId} (${sessionId.slice(0, 10)}…) — seat: ${seat}`),
      el('div', {}, `Status: ${session.status}`),
      /*
       * A one-line readout of the things that decide whether a payout is
       * possible. Small and unglamorous, and it earns its place: every
       * "it's stuck" report so far has been guesswork from a screenshot,
       * because the screen showed a state without showing what produced it.
       * This makes the next screenshot answer the question by itself.
       *
       * link  -- is the poker tab talking to this one at all
       * mine  -- has my wallet signed the result
       * theirs-- has my opponent's signature reached my poker tab
       */
      el('div', { class: 'dim' }, pokerProgress
        ? `link ✓ · match ${pokerProgress.matchOver ? 'over' : 'running'} · my confirm ${pokerProgress.haveMine ? '✓' : '✗'} · theirs ${pokerProgress.haveTheirs ? '✓' : '✗'}`
        : 'link ✗ — the poker tab has not reached this one yet'),
    ]),
  );

  if (session.status === 'None' || session.status === 'AwaitingGuest') {
    root.appendChild(fundingWarning());
  }

  // Screen 2: open / join
  if (session.status === 'None') {
    if (seat === 'host') {
      // The ids are how a late-arriving address from the poker app updates
      // this screen without a re-render -- see applyOpponentFromPoker.
      const opponentInput = el('input', { type: 'text', id: 'opponent-input', placeholder: '0x… opponent wallet address', value: formState.opponent });
      opponentInput.addEventListener('input', (e) => {
        formState.opponent = e.target.value;
        // From here on this field is the host's to decide, and nothing
        // arriving from the poker app may quietly change it underneath them.
        opponentTouched = true;
        opponentFromPoker = false;
      });
      const buyInInput = el('input', { type: 'text', placeholder: 'buy-in in ETH, e.g. 0.001', value: formState.buyIn });
      buyInInput.addEventListener('input', (e) => (formState.buyIn = e.target.value));
      root.appendChild(
        el('div', { class: 'card' }, [
          el('h2', {}, 'Step 1: Set up the match'),
          el('p', { id: 'opponent-help' }, opponentFromPoker ? OPPONENT_HELP_SENT : OPPONENT_HELP_ASK),
          opponentInput,
          buyInInput,
          el('button', {
            class: 'btn primary',
            onclick: () => openChannel(opponentInput.value.trim(), buyInInput.value.trim()),
          }, 'Send opponent’s info and deposit my share'),
        ]),
      );
    } else {
      root.appendChild(el('div', { class: 'card' }, [
        el('p', {}, 'Waiting for your opponent to set the match up and put their money in.'),
        el('p', { class: 'dim' }, 'Nothing for you to do yet — this page updates itself.'),
      ]));
    }
    return;
  }

  // Screen 2b: guest joins
  if (session.status === 'AwaitingGuest') {
    if (seat === 'guest') {
      const isMe = account?.toLowerCase() === session.guest.toLowerCase();
      root.appendChild(
        el('div', { class: 'card' }, [
          el('h2', {}, 'Step 2: Put your money in'),
          el('p', {}, `Your opponent already sent their share. Now it's your turn — deposit ${formatEther(session.buyIn)} ETH to lock the match in. You'll get it back automatically if you win.`),
          !isMe
            ? el('p', { class: 'error' }, `Your opponent set this up for a different wallet (${session.guest}) than the one you're connected with. Switch to that one, then reload this page.`)
            : el('button', { class: 'btn primary', onclick: () => joinChannel(session.buyIn) }, 'Deposit my share'),
        ]),
      );
    } else {
      root.appendChild(
        el('div', { class: 'card' }, [
          el('p', {}, 'Waiting for your opponent to put their share in.'),
          el('p', { class: 'dim' }, 'Nothing for you to do yet — this page updates itself.'),
          el('button', { class: 'btn ghost', onclick: cancelOpen }, 'Changed your mind? Cancel and get your money back'),
        ]),
      );
    }
    return;
  }

  // Screen 3/4: active — in progress, dispute path, and cooperative close
  const iAmHost = account?.toLowerCase() === session.host.toLowerCase();
  const otherParty = iAmHost ? session.guest : session.host;

  if (session.status === 'Active') {
    root.appendChild(
      el('div', { class: 'card' }, [
        el('h2', {}, 'Step 3: Play'),
        el('p', {}, matchResult
          ? 'The match is over and both sides have confirmed who won. One click sends the whole pot to the winner — that\'s the last step.'
          : waitingOnSignatures()
          ? waitingOnSignatures()
          : 'You\'re all set — go play your match in the poker app now. The instant it ends, this page figures out who won by itself and gets the payout ready. You don\'t need to do anything here until then, and it\'s fine to close this tab and come back later — reopen Buyin from the poker app\'s button and it\'ll pick up right where it left off.'),
        matchResult
          ? el('button', {
              class: 'btn primary',
              onclick: () => closeCooperative(matchResult.result === 'host' ? session.host : session.guest, session),
            }, 'Pay the winner')
          : null,
        el('hr'),
        el('p', { class: 'dim' }, 'Opponent actually gone, not just still playing? You can start a safety countdown instead — after it runs out, you can claim the pot without them:'),
        el('button', {
          class: 'btn ghost',
          onclick: () => claimByDefault((session.buyIn * 1000n) / 10000n),
        }, 'Start the countdown (opponent isn’t responding)'),
      ]),
    );

    /*
     * Both deposits are in, so this tab's job is done until the match ends --
     * and the very next thing to do is somewhere else entirely. Saying "go
     * play in the poker app" and then leaving someone to find that tab
     * themselves is the sort of small gap that reads as being stranded.
     *
     * Only when there's an opener to go back to (this tab was opened by the
     * poker app, which is the normal route) and no payout waiting -- once
     * "Pay the winner" is on screen, that is the thing to click, and a
     * blinking button next to it would be competing for the wrong one.
     */
    if (!matchResult && window.opener && !window.opener.closed) {
      scheduleReturnToPoker();
      root.appendChild(
        el('div', { class: 'card go-play' }, [
          el('p', { class: 'dim' }, 'Both buy-ins are locked in. Nothing else happens here until the match is over.'),
          el('button', {
            class: 'btn primary blink',
            onclick: goToPokerTable,
          }, 'Go to the poker table →'),
          el('p', { class: 'dim' }, autoReturned
            ? "If the poker tab didn't come to the front, switch to it yourself — its tab will say \u25b6 Your table is ready."
            : 'Taking you back there automatically in a moment.'),
        ]),
      );
    }
    return;
  }

  if (session.status === 'ClaimPending') {
    const isClaimant = account?.toLowerCase() === session.claimant.toLowerCase();
    const deadlineDate = new Date(Number(session.deadline) * 1000);

    /*
     * Answer the countdown ourselves when the poker table says we're here.
     *
     * The countdown must exist: someone who genuinely vanishes cannot be
     * allowed to freeze the other player's money forever. But answering it
     * was a step nobody could reasonably be expected to know about -- you
     * reconnect, you're back at the table, everything looks fine, and a clock
     * you cannot see is running down towards handing your buy-in away, in a
     * tab you may well have closed.
     *
     * This does NOT weaken what the countdown proves. iAmHere is an on-chain
     * transaction, so the wallet still has to approve it, and that approval
     * is the human being present. All this removes is having to notice the
     * clock and go find the button.
     *
     * Deferred to a timeout so it runs after this render finishes: iAmHere
     * goes through withBusy, which disables buttons and draws its own card,
     * and doing that halfway through building the page would interleave the
     * two. Once per page, and the button below still does the same job for
     * anything this misses.
     */
    if (!isClaimant && !autoRefuted && pokerProgress && pokerProgress.connected) {
      autoRefuted = true;
      setTimeout(() => iAmHere(), 0);
    }

    root.appendChild(
      el('div', { class: 'card' }, [
        el('p', {}, `${isClaimant ? 'You' : 'Your opponent'} started the "gone quiet" countdown. It ends at ${deadlineDate.toLocaleTimeString()}.`),
        !isClaimant
          ? el('p', { class: 'dim' }, autoRefuted
              ? 'Your poker table is open and connected, so this page is answering for you — approve the request in your wallet and the clock stops. The button below does the same thing if you miss it.'
              : "If your poker table is open and connected, this page answers by itself. Otherwise, stop the clock here:")
          : null,
        !isClaimant
          ? el('button', { class: 'btn primary', onclick: iAmHere }, "I'm actually here — stop the countdown")
          : el('button', { class: 'btn ghost', onclick: resolveSession }, 'Finish the claim (only works after the countdown ends)'),
      ]),
    );
    return;
  }

  if (session.status === 'Refuted') {
    const deadlineDate = new Date(Number(session.deadline) * 1000);
    root.appendChild(
      el('div', { class: 'card' }, [
        el('p', {}, `Your opponent said they're still here, so that countdown was cancelled. This now needs both of you to confirm the result by ${deadlineDate.toLocaleTimeString()}, or the original claim wins by default.`),
        matchResult
          ? el('button', {
              class: 'btn primary',
              onclick: () => closeCooperative(matchResult.result === 'host' ? session.host : session.guest, session),
            }, 'Pay the winner')
          : el('p', { class: 'dim' }, 'Waiting for the match result to come through…'),
        el('button', { class: 'btn ghost', onclick: resolveSession }, 'Finish the original countdown (only works after it ends)'),
      ]),
    );
    return;
  }

  if (session.status === 'Closed') {
    root.appendChild(
      el('div', { class: 'card' }, [
        el('p', {}, 'All done — the money has already been sent to the winner.'),
        el('p', { class: 'dim' }, 'This tab is finished for good (this exact game can\'t be reopened). Starting another game? Click "New game" in the poker app, then Buyin there again — it\'ll open a fresh deposit screen for the new one.'),
      ]),
    );
    return;
  }

  void otherParty; // reserved for a future "who I'm waiting on" display
}

/*
 * Draw once immediately so there is never a blank page, then try to pick up
 * an existing wallet authorisation without prompting. connect() renders again
 * itself if that succeeds, so the connect screen is only ever seen by someone
 * who actually has to press the button.
 */
render();
connect({ silent: true });

/*
 * Coming back to this tab re-reads the chain at once.
 *
 * The poll is a timer, and browsers throttle timers in hidden tabs -- so a
 * tab you return to could otherwise sit showing a minute-old view of the
 * world while you stare at it waiting for it to catch up.
 */
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && account) render();
});
