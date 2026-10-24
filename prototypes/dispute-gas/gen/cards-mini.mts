export const RANKS = "23456789TJQKA";
export function cardRank(i: number): number { return i % 13; }
export function cardSuit(i: number): number { return Math.floor(i / 13); }
