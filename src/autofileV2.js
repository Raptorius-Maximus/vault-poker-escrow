// Pure planner (task 5): evidence bundle + a small on-chain snapshot -> the
// ordered list of dispute-filing calls still owed. No DOM, no network: the
// caller (mainV2.js) reads the chain and the store, hands both in, and drives
// the returned Call[] through withBusy one at a time. node -e-probable.
//
// spec §5.1's promise -- "no expertise required" -- is this function: the
// player clicks nothing per-duty, the plan is derived for them.
//
// Degradation rule (phase doc task 5 step 3): where the snapshot cannot tell
// whether a given artefact is already filed, plan() falls back to "file
// everything the bundle has and let the contract's own idempotence decide" --
// safe, because filing something already on file reverts as a no-op, never a
// double-spend. Since the SHIPPED contract DOES expose receiptAt / markedHand /
// sharePosted, the wiring passes a real snapshot and plan() skips what is
// already filed, cutting needless wallet popups; with an empty snapshot it
// still degrades correctly to file-everything.
//
// Call shape: { fn: string, args: any[] } -- args are shaped for the caller to
// spread into the corresponding CHANNEL_V2_ABI function (the caller supplies
// `session` as the first real argument; plan() returns only the artefact
// payloads, which is all it can know about).

// onChainState fields (all optional -- absent = "unknown", degrade to file):
//   filedReceiptHands: Set<number>  hands whose receipt is already on chain
//   markedHand:        number       ChannelV2.markedHand(session)
//   markerFiled:       boolean      whether the latest marker is already filed
//   actionsFiled:      boolean      whether the action-chain tip is already filed
//   postedSharePositions: Set<number> share positions already posted
export function plan(bundle, onChainState = {}) {
  const calls = [];
  if (!bundle) return calls;

  const filedReceiptHands = onChainState.filedReceiptHands || null;

  // 1. Receipts, in (hand, subseq) order -- (0,0) first, then the rest.
  const receipts = Array.isArray(bundle.receipts) ? [...bundle.receipts] : [];
  receipts.sort((a, b) => (Number(a.hand) - Number(b.hand)) || (Number(a.subseq) - Number(b.subseq)));
  for (const r of receipts) {
    if (filedReceiptHands && filedReceiptHands.has(Number(r.hand))) continue;
    calls.push({ fn: 'fileReceipt', args: [receiptTuple(r), r.sigHost, r.sigGuest] });
  }

  // 2. Marker (latest only) -- via fileMarkerWithReceipt when a same-hand
  //    receipt rides with it, otherwise fileMarker. Skipped if already filed.
  const m = bundle.marker;
  if (m && !onChainState.markerFiled) {
    calls.push({ fn: 'fileMarker', args: [markerTuple(m), m.sigHost, m.sigGuest] });
  }

  // 3. Actions (the chain the bundle carries) -- skipped if the tip is filed.
  const actions = Array.isArray(bundle.actions) ? bundle.actions : [];
  if (actions.length > 0 && !onChainState.actionsFiled) {
    calls.push({
      fn: 'fileActions',
      args: [actions.map(actTuple), actions.map((a) => a.sig)],
    });
  }

  // 4. Shares -- skip positions already posted; file the remainder.
  const shares = Array.isArray(bundle.shares) ? bundle.shares : [];
  if (shares.length > 0) {
    const posted = onChainState.postedSharePositions || null;
    const owed = posted ? shares.filter((s) => !posted.has(Number(s.pos))) : shares;
    if (owed.length > 0) {
      calls.push({ fn: 'postShares', args: [owed.map(sharePostTuple)] });
    }
  }

  return calls;
}

// --- tuple builders: bundle hex-strings -> the ABI's positional structs ---
// The wire bundle names the receipt's terminal byte `final` (spec/formats
// prose); the ABI struct names it `isFinal` (Solidity reserved word). Mapped
// here so the rest of the code never has to remember the rename.
function receiptTuple(r) {
  return {
    hand: BigInt(r.hand),
    subseq: Number(r.subseq),
    hostStack: BigInt(r.hostStack),
    guestStack: BigInt(r.guestStack),
    hostDeposit: BigInt(r.hostDeposit),
    guestDeposit: BigInt(r.guestDeposit),
    isFinal: Boolean(r.final),
  };
}

function markerTuple(m) {
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
    // AF-32: the both-signed chip<->wei anchor. P6's evidence bundle must
    // carry it; default to 0n only so a pre-AF-32 bundle does not crash the
    // planner (the contract would reject a 0 anchor, which is the correct
    // visible failure).
    startingChips: BigInt(m.startingChips ?? 0),
  };
}

function actTuple(a) {
  return {
    hand: BigInt(a.hand),
    seq: BigInt(a.seq),
    action: Number(a.action),
    amount: BigInt(a.amount),
    prev: a.prev,
  };
}

function sharePostTuple(s) {
  return {
    pos: Number(s.pos),
    shareEnc: s.shareEnc,
    c: BigInt(s.c),
    s: BigInt(s.s),
    shareProof: s.shareProof,
    c1Enc: s.c1Enc,
    c2Enc: s.c2Enc,
    deckProof: s.deckProof,
  };
}
