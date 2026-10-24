import { createWalletClient, custom } from 'viem';
import * as evidenceStoreV2 from './evidenceStoreV2.js';

// The bare-address recovery page (spec §6): no ?session= required. A returning
// player connects their wallet and this page lists every V2 cash session this
// browser has kept evidence for -- "receipts are stored under both origins so a
// returning player is covered wherever they land."
//
// The filter is extracted as a pure, exported function so it can be probed with
// no DOM (task 7's node -e script). Everything DOM/boot-related below is guarded
// so importing this module in Node (for that probe) does not crash.

// matchingSessions(envelopes, account): the envidence envelopes (as
// evidenceStoreV2.listSessions returns them: { session, bundle }) whose bundle
// names this wallet as host or guest. Case-insensitive compare, matching the
// .toLowerCase() convention used throughout the V1 app.
export function matchingSessions(envelopes, account) {
  const me = (account || '').toLowerCase();
  if (!me) return [];
  return envelopes.filter(({ bundle }) => {
    if (!bundle) return false;
    const host = (bundle.host || '').toLowerCase();
    const guest = (bundle.guest || '').toLowerCase();
    return host === me || guest === me;
  });
}

// --- everything below is browser-only ---
if (typeof document !== 'undefined' && typeof window !== 'undefined') {
  bootRecoveryPage();
}

function bootRecoveryPage() {
  const root = document.getElementById('app');
  let walletClient = null;
  let account = null;

  const el = (tag, props = {}, children = []) => {
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
  };

  const banner = () => el('div', { class: 'testnet-banner' }, 'TESTNET — play money only, never mainnet');

  // Always-shown honesty about the limit (task 7 step 3).
  const limitNote = () => el('p', { class: 'dim' },
    "This only finds sessions this browser has kept evidence for. A different browser or a cleared profile won't show anything here — that's exactly why receipts also live on your poker table's side; if this list is empty, check there instead.");

  async function connect() {
    if (!window.ethereum) {
      alert('No wallet found. Install MetaMask (or another browser wallet) first.');
      return;
    }
    walletClient = createWalletClient({ transport: custom(window.ethereum) });
    [account] = await walletClient.requestAddresses();
    render();
  }

  function sessionCard({ session, bundle }) {
    const iAmHost = (bundle.host || '').toLowerCase() === account.toLowerCase();
    const mySeat = iAmHost ? 'host' : 'guest';
    const kids = [
      el('h2', {}, `Room: ${session.slice(0, 10)}…`),
      el('div', { class: 'dim' }, `Your seat: ${mySeat}`),
    ];
    if (bundle.status) kids.push(el('div', { class: 'dim' }, `Last-known status: ${bundle.status}`));
    kids.push(el('a', { class: 'btn primary', href: `v2.html?session=${encodeURIComponent(session)}&seat=${mySeat}` }, 'Open this session'));
    return el('div', { class: 'card' }, kids);
  }

  function render() {
    root.innerHTML = '';
    root.appendChild(banner());

    if (!account) {
      root.appendChild(el('div', { class: 'card' }, [
        el('h1', {}, 'Recover a cash session'),
        el('p', {}, 'Connect the wallet you played with, and this page shows any cash sessions this browser is holding evidence for.'),
        el('button', { class: 'btn primary', onclick: connect }, 'Connect your wallet'),
        limitNote(),
      ]));
      return;
    }

    let envelopes = [];
    try {
      envelopes = evidenceStoreV2.listSessions(localStorage);
    } catch {
      /* storage disabled -- treat as none found */
    }
    const matches = matchingSessions(envelopes, account);

    root.appendChild(el('div', { class: 'meta' }, [el('div', {}, `Connected: ${account}`)]));
    if (matches.length === 0) {
      root.appendChild(el('div', { class: 'card' }, [el('p', {}, 'No cash sessions found for this wallet in this browser.')]));
    } else {
      matches.forEach((m) => root.appendChild(sessionCard(m)));
    }
    root.appendChild(el('div', { class: 'card' }, [limitNote()]));
  }

  render();
}
