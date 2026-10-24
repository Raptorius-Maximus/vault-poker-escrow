// Pure reimplementation of P2 decision 1's bond formula (decisions.md D1/D4),
// verbatim, in JS BigInt -- so the UI can show the bond next to its
// consequence BEFORE any transaction (spec §2/§2.1). No DOM, no network:
// independently node -e-probable.
//
// Decision 1, verbatim:
//   ceilDiv(a, b) = (a + b - 1) / b
//   avgCeil       = ceilDiv(M_host + M_guest, 2)
//   base_i        = max(avgCeil, M_i)
//   bond_i        = ceilDiv(11 * base_i, 10)
//
// Worked case pinned by D1 (ETH-scale units elsewhere; the ratios are what
// matter): M_host=1500, M_guest=500 -> bondHost=1650, bondGuest=1100.
//   avgCeil = ceilDiv(2000, 2) = 1000
//   bondHost: base = max(1000, 1500) = 1500 -> ceilDiv(16500,10) = 1650 ✓
//   bondGuest: base = max(1000,  500) = 1000 -> ceilDiv(11000,10) = 1100 ✓

export function ceilDiv(a, b) {
  return (a + b - 1n) / b;
}

export function avgCeil(maxHost, maxGuest) {
  return ceilDiv(maxHost + maxGuest, 2n);
}

// bondFor(mine, other): the bond the caller (who declared `mine`) must post,
// given the opponent's declared max `other`.
export function bondFor(mine, other) {
  const avg = avgCeil(mine, other);
  const base = avg > mine ? avg : mine;
  return ceilDiv(11n * base, 10n);
}
