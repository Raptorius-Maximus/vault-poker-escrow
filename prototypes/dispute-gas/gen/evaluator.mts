/** Seven-card hold'em evaluator. Best-of-21; returns comparable arrays. */

import { RANKS, cardRank, cardSuit } from './cards-mini.mts';

export const HIGH_CARD = 0, PAIR = 1, TWO_PAIR = 2, TRIPS = 3, STRAIGHT = 4,
  FLUSH = 5, FULL_HOUSE = 6, QUADS = 7, STRAIGHT_FLUSH = 8;

export const CATEGORY_NAMES = ['high card', 'pair', 'two pair', 'three of a kind',
  'straight', 'flush', 'full house', 'four of a kind', 'straight flush'];

function straightHigh(ranks: Set<number>): number | null {
  for (let high = 12; high >= 4; high--) {
    let ok = true;
    for (let r = high - 4; r <= high; r++) if (!ranks.has(r)) { ok = false; break; }
    if (ok) return high;
  }
  // wheel: ace plays low
  if ([12, 0, 1, 2, 3].every((r) => ranks.has(r))) return 3;
  return null;
}

function scoreFive(hand: number[]): number[] {
  const ranks = hand.map(cardRank).sort((a, b) => b - a);
  const isFlush = new Set(hand.map(cardSuit)).size === 1;
  const straight = straightHigh(new Set(ranks));

  if (isFlush && straight !== null) return [STRAIGHT_FLUSH, straight];

  const counts = new Map<number, number>();
  for (const r of ranks) counts.set(r, (counts.get(r) ?? 0) + 1);
  const ordered = [...counts.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0]);
  const shape = ordered.map(([, c]) => c);
  const kick = ordered.map(([r]) => r);

  if (shape[0] === 4) return [QUADS, ...kick];
  if (shape[0] === 3 && shape[1] === 2) return [FULL_HOUSE, ...kick];
  if (isFlush) return [FLUSH, ...ranks];
  if (straight !== null) return [STRAIGHT, straight];
  if (shape[0] === 3) return [TRIPS, ...kick];
  if (shape[0] === 2 && shape[1] === 2) return [TWO_PAIR, ...kick];
  if (shape[0] === 2) return [PAIR, ...kick];
  return [HIGH_CARD, ...ranks];
}

export function cmpScore(a: number[], b: number[]): number {
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const d = (a[i] ?? -1) - (b[i] ?? -1);
    if (d !== 0) return d < 0 ? -1 : 1;
  }
  return 0;
}

export function evaluate(seven: number[]): number[] {
  let best: number[] | null = null;
  const n = seven.length;
  for (let a = 0; a < n - 4; a++)
    for (let b = a + 1; b < n - 3; b++)
      for (let c = b + 1; c < n - 2; c++)
        for (let d = c + 1; d < n - 1; d++)
          for (let e = d + 1; e < n; e++) {
            const s = scoreFive([seven[a], seven[b], seven[c], seven[d], seven[e]]);
            if (!best || cmpScore(s, best) > 0) best = s;
          }
  return best!;
}

export function describe(score: number[]): string {
  const cat = CATEGORY_NAMES[score[0]];
  switch (score[0]) {
    case STRAIGHT: case STRAIGHT_FLUSH: case FLUSH: case HIGH_CARD:
      return `${cat}, ${RANKS[score[1]]} high`;
    case QUADS: case TRIPS: case PAIR:
      return `${cat}, ${RANKS[score[1]]}s`;
    case FULL_HOUSE:
      return `${cat}, ${RANKS[score[1]]}s full of ${RANKS[score[2]]}s`;
    case TWO_PAIR:
      return `${cat}, ${RANKS[score[1]]}s and ${RANKS[score[2]]}s`;
    default:
      return cat;
  }
}
