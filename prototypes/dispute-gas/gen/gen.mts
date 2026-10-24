/**
 * Vector + constant generator for the V2 dispute-path gas prototypes.
 *
 * Nothing here is trusted from memory: every curve constant is computed from
 * first principles, and the whole ristretto255 mirror below is validated
 * against @noble/curves (the poker client's own library) before a single
 * vector is emitted. If the mirror and noble disagree, this script throws.
 *
 * Run: node --experimental-strip-types gen/gen.mts > test/Vectors.sol
 */
import { ristretto255 } from '/home/dev/projects/poker/node_modules/@noble/curves/ed25519.js';
import { secp256k1 } from '/home/dev/projects/poker/node_modules/@noble/curves/secp256k1.js';
import { keccak_256 } from '/home/dev/projects/poker/node_modules/@noble/hashes/sha3.js';
import { evaluate } from './evaluator.mts';

// ---------------------------------------------------------------- field

const P = (1n << 255n) - 19n;
const L = (1n << 252n) + 27742317777372353535851937790883648493n;

const mod = (x: bigint, m = P): bigint => ((x % m) + m) % m;
const fmul = (a: bigint, b: bigint) => mod(a * b);
const fadd = (a: bigint, b: bigint) => mod(a + b);
const fsub = (a: bigint, b: bigint) => mod(a - b);
function fpow(x: bigint, e: bigint): bigint {
  let r = 1n, b = mod(x);
  while (e > 0n) { if (e & 1n) r = fmul(r, b); b = fmul(b, b); e >>= 1n; }
  return r;
}
const finv = (x: bigint) => fpow(x, P - 2n);
const isNeg = (x: bigint) => (x & 1n) === 1n;       // RFC 9496: odd = negative
const ctAbs = (x: bigint) => (isNeg(x) ? fsub(0n, x) : x);

// Constants from first principles.
const D = mod(-121665n * finv(121666n));            // ed25519 d
let SQRT_M1 = fpow(2n, (P - 1n) / 4n);              // a root of -1; sign fixed below
if (fmul(SQRT_M1, SQRT_M1) !== P - 1n) throw new Error('sqrt(-1) sanity');

// ---------------------------------------------------------------- points

type Pt = { X: bigint; Y: bigint; Z: bigint; T: bigint };
const IDENT: Pt = { X: 0n, Y: 1n, Z: 1n, T: 0n };

function ptAdd(p: Pt, q: Pt): Pt {                  // a=-1 extended, complete
  const A = fmul(fsub(p.Y, p.X), fsub(q.Y, q.X));
  const B = fmul(fadd(p.Y, p.X), fadd(q.Y, q.X));
  const C = fmul(fmul(p.T, fmul(2n, D)), q.T);
  const Dd = fmul(fmul(p.Z, 2n), q.Z);
  const E = fsub(B, A), F = fsub(Dd, C), G = fadd(Dd, C), H = fadd(B, A);
  return { X: fmul(E, F), Y: fmul(G, H), Z: fmul(F, G), T: fmul(E, H) };
}
function ptDbl(p: Pt): Pt {
  const A = fmul(p.X, p.X), B = fmul(p.Y, p.Y), C = fmul(2n, fmul(p.Z, p.Z));
  const H = fadd(A, B);
  const xy = fadd(p.X, p.Y);
  const E = fsub(H, fmul(xy, xy));
  const G = fsub(A, B), F = fadd(C, G);
  return { X: fmul(E, F), Y: fmul(G, H), Z: fmul(F, G), T: fmul(E, H) };
}
function ptMul(p: Pt, k: bigint): Pt {
  let r = IDENT;
  for (let i = 252n; i >= 0n; i--) {
    r = ptDbl(r);
    if ((k >> i) & 1n) r = ptAdd(r, p);
  }
  return r;
}
const ptNeg = (p: Pt): Pt => ({ X: fsub(0n, p.X), Y: p.Y, Z: p.Z, T: fsub(0n, p.T) });

// Base point: y = 4/5, x recovered; sign fixed by validation below.
const baseY = fmul(4n, finv(5n));
const xx = fmul(fsub(fmul(baseY, baseY), 1n), finv(fadd(fmul(D, fmul(baseY, baseY)), 1n)));
let baseX = fpow(xx, (P + 3n) / 8n);
if (fmul(baseX, baseX) !== mod(xx)) baseX = fmul(baseX, SQRT_M1);
if (fmul(baseX, baseX) !== mod(xx)) throw new Error('base x recovery');
let BASE: Pt = { X: baseX, Y: baseY, Z: 1n, T: fmul(baseX, baseY) };

// ---------------------------------------------------------------- ristretto

function sqrtRatioM1(u: bigint, v: bigint): { wasSquare: boolean; r: bigint } {
  const v3 = fmul(fmul(v, v), v);
  const v7 = fmul(fmul(v3, v3), v);
  let r = fmul(fmul(u, v3), fpow(fmul(u, v7), (P - 5n) / 8n));
  const check = fmul(v, fmul(r, r));
  const correct = check === mod(u);
  const flipped = check === mod(-u);
  const flippedI = check === mod(fmul(mod(-u), SQRT_M1));
  if (flipped || flippedI) r = fmul(r, SQRT_M1);
  return { wasSquare: correct || flipped, r: ctAbs(r) };
}

let INVSQRT_AMD = 0n; // 1/sqrt(a-d), a=-1; computed after sign selection

function decode(sBytes: Uint8Array): Pt | null {
  let s = 0n;
  for (let i = 31; i >= 0; i--) s = (s << 8n) | BigInt(sBytes[i]);  // little-endian
  if (s >= P || isNeg(s)) return null;
  const ss = fmul(s, s);
  const u1 = fsub(1n, ss);
  const u2 = fadd(1n, ss);
  const u2s = fmul(u2, u2);
  const v = fsub(fsub(0n, fmul(D, fmul(u1, u1))), u2s);
  const { wasSquare, r: invsqrt } = sqrtRatioM1(1n, fmul(v, u2s));
  const denX = fmul(invsqrt, u2);
  const denY = fmul(fmul(invsqrt, denX), v);
  const x = ctAbs(fmul(fmul(2n, s), denX));
  const y = fmul(u1, denY);
  const t = fmul(x, y);
  if (!wasSquare || isNeg(t) || y === 0n) return null;
  return { X: x, Y: y, Z: 1n, T: t };
}

function encode(p: Pt): Uint8Array {
  const u1 = fmul(fadd(p.Z, p.Y), fsub(p.Z, p.Y));
  const u2 = fmul(p.X, p.Y);
  const { r: invsqrt } = sqrtRatioM1(1n, fmul(u1, fmul(u2, u2)));
  const den1 = fmul(invsqrt, u1);
  const den2 = fmul(invsqrt, u2);
  const zInv = fmul(fmul(den1, den2), p.T);
  let x = p.X, y = p.Y, denInv = den2;
  if (isNeg(fmul(p.T, zInv))) {
    x = fmul(p.Y, SQRT_M1);
    y = fmul(p.X, SQRT_M1);
    denInv = fmul(den1, INVSQRT_AMD);
  }
  if (isNeg(fmul(x, zInv))) y = fsub(0n, y);
  const s = ctAbs(fmul(denInv, fsub(p.Z, y)));
  const out = new Uint8Array(32);
  let v = s;
  for (let i = 0; i < 32; i++) { out[i] = Number(v & 255n); v >>= 8n; }
  return out;
}

// ------------------------------------------------- validate against noble

const toHex = (b: Uint8Array) => [...b].map((x) => x.toString(16).padStart(2, '0')).join('');
const nobleHex = (pt: any): string => pt.toHex();
const NP = ristretto255.Point;
if (NP.Fn.ORDER !== L) throw new Error('order mismatch vs noble');

function randScalar(): bigint {
  const b = crypto.getRandomValues(new Uint8Array(64));
  let x = 0n;
  for (const v of b) x = (x << 8n) | BigInt(v);
  x %= L;
  return x === 0n ? 1n : x;
}

// Select signs (SQRT_M1 root, INVSQRT_AMD root, BASE.X root) so the mirror
// matches noble exactly; throw if no combination works.
function computeInvsqrtAmd(): bigint[] {
  const aMinusD = mod(-1n - D);
  const inv = finv(aMinusD);
  let r = fpow(inv, (P + 3n) / 8n);
  if (fmul(r, r) !== inv) r = fmul(r, SQRT_M1);
  if (fmul(r, r) !== inv) throw new Error('invsqrt(a-d) not square');
  return [r, fsub(0n, r)];
}
function mirrorMatchesNoble(samples: number): boolean {
  for (let i = 0; i < samples; i++) {
    const k = randScalar();
    if (toHex(encode(ptMul(BASE, k))) !== nobleHex(NP.BASE.multiply(k))) return false;
  }
  return true;
}
let locked = false;
outer: for (const sq of [SQRT_M1, fsub(0n, SQRT_M1)]) {
  SQRT_M1 = sq;
  for (const bx of [BASE.X, fsub(0n, BASE.X)]) {
    BASE = { X: bx, Y: baseY, Z: 1n, T: fmul(bx, baseY) };
    for (const ia of computeInvsqrtAmd()) {
      INVSQRT_AMD = ia;
      if (mirrorMatchesNoble(8)) { locked = true; break outer; }
    }
  }
}
if (!locked) throw new Error('no sign combination matches noble');
if (!mirrorMatchesNoble(200)) throw new Error('mirror diverges from noble at scale');
// decode side: round-trip noble points through the mirror
for (let i = 0; i < 100; i++) {
  const k = randScalar();
  const enc = NP.BASE.multiply(k).toBytes();
  const p = decode(enc);
  if (!p) throw new Error('mirror decode failed on noble point');
  if (toHex(encode(p)) !== toHex(enc)) throw new Error('decode/encode round-trip');
}
// point subtraction consistency (DLEQ needs G*s - pub*c)
{
  const a = randScalar(), b = randScalar();
  const lhs = encode(ptAdd(ptMul(BASE, a), ptNeg(ptMul(BASE, b))));
  const rhs = NP.BASE.multiply(a).subtract(NP.BASE.multiply(b)).toBytes();
  if (toHex(lhs) !== toHex(rhs)) throw new Error('sub mismatch');
}

// ---------------------------------------------------------------- DLEQ

const DOMAIN = new TextEncoder().encode('vault/dleq/keccak-v1');
function keccakChallenge(parts: Uint8Array[]): bigint {
  const payload = new Uint8Array(parts.reduce((n, p) => n + p.length, 0));
  let off = 0;
  for (const p of parts) { payload.set(p, off); off += p.length; }
  const pre1 = new Uint8Array([1, ...DOMAIN, ...payload]);
  const pre2 = new Uint8Array([2, ...DOMAIN, ...payload]);
  let h1 = 0n, h2 = 0n;
  for (const v of keccak_256(pre1)) h1 = (h1 << 8n) | BigInt(v);
  for (const v of keccak_256(pre2)) h2 = (h2 << 8n) | BigInt(v);
  return mod(mod(h1, L) * mod(1n << 256n, L) + mod(h2, L), L);
}

interface DleqVec { pub: string; base2: string; point2: string; c: bigint; s: bigint; ok: boolean }
const dleqVecs: DleqVec[] = [];
for (let i = 0; i < 6; i++) {
  const x = randScalar();                            // secret
  const h = randScalar();
  const pub = ptMul(BASE, x);
  const H = ptMul(BASE, h);
  const point2 = ptMul(H, x);
  const k = randScalar();
  const t1 = ptMul(BASE, k);
  const t2 = ptMul(H, k);
  const [ePub, eH, eP2, eT1, eT2] = [pub, H, point2, t1, t2].map(encode);
  const c = keccakChallenge([ePub, eH, eP2, eT1, eT2]);
  let s = mod(k + c * x, L);
  const ok = i < 5;                                  // vector 5 is tampered
  if (!ok) s = mod(s + 1n, L);
  dleqVecs.push({ pub: toHex(ePub), base2: toHex(eH), point2: toHex(eP2), c, s, ok });
}

// ---------------------------------------------------------------- evaluator

function packScore(score: number[]): bigint {
  let v = BigInt(score[0]);
  for (let i = 1; i <= 5; i++) v = (v << 4n) | BigInt(score[i] ?? 0);
  return v;
}
interface EvalVec { cards: number[]; packed: bigint }
const evalVecs: EvalVec[] = [];
// A few crafted hands first: straight flush, wheel, quads, boat, flush,
// straight (incl. wheel-in-7), trips, two pair, pair, air.
const crafted = [
  [0, 1, 2, 3, 4, 18, 33],       // 2c..6c straight flush
  [12, 0, 1, 2, 3, 30, 44],      // wheel A-5, mixed suits + Ac low
  [5, 18, 31, 44, 7, 8, 9],      // quad 7s
  [5, 18, 31, 6, 19, 10, 24],    // 7s full of 8s
  [0, 2, 4, 6, 9, 14, 27],       // club flush, no straight
  [3, 17, 5, 19, 7, 25, 38],     // 5-9 straight, offsuit
  [11, 24, 37, 2, 16, 8, 22],    // trip kings
  [10, 23, 9, 22, 3, 17, 30],    // queens and jacks
  [12, 25, 4, 18, 7, 21, 9],     // pair of aces
  [12, 24, 9, 21, 6, 16, 1],     // ace high air
];
for (const c of crafted) evalVecs.push({ cards: c, packed: packScore(evaluate(c)) });
// randoms
for (let i = 0; i < 110; i++) {
  const deck = [...Array(52).keys()];
  for (let j = 51; j > 0; j--) {
    const r = Math.floor(Math.random() * (j + 1));
    [deck[j], deck[r]] = [deck[r], deck[j]];
  }
  const cards = deck.slice(0, 7);
  evalVecs.push({ cards, packed: packScore(evaluate(cards)) });
}

// ---------------------------------------------------------------- actions

const ACT_DOMAIN = new TextEncoder().encode('vault/act/v1');
const be = (x: bigint, n: number) => {
  const out = new Uint8Array(n);
  for (let i = n - 1; i >= 0; i--) { out[i] = Number(x & 255n); x >>= 8n; }
  return out;
};
const kHost = 0xa11ce00000000000000000000000000000000000000000000000000000000001n;
const kGuest = 0xb0b0000000000000000000000000000000000000000000000000000000000002n;
function addr(priv: bigint): string {
  const pub = secp256k1.getPublicKey(be(priv, 32), false).slice(1);
  const low = toHex(keccak_256(pub).slice(12));
  const h = toHex(keccak_256(new TextEncoder().encode(low)));   // EIP-55
  return [...low].map((ch, i) => (parseInt(h[i], 16) >= 8 ? ch.toUpperCase() : ch)).join('');
}
const session = keccak_256(new TextEncoder().encode('measure-session'));
interface ActVec { hand: bigint; seq: bigint; action: number; amount: bigint; prev: string; hash: string; v: number; r: string; s: string }
const actVecs: ActVec[] = [];
let prev = new Uint8Array(32);
for (let seq = 0n; seq < 20n; seq++) {
  const action = Number(seq % 4n);                    // arbitrary mix
  const amount = 50n + seq * 10n;
  const preimage = new Uint8Array([3, ...ACT_DOMAIN, ...session, ...be(7n, 8), ...be(seq, 8), action, ...be(amount, 32), ...prev]);
  const hash = keccak_256(preimage);
  const priv = seq % 2n === 0n ? kHost : kGuest;
  const sig = secp256k1.sign(hash, be(priv, 32), { prehash: false, format: 'recovered' });
  actVecs.push({
    hand: 7n, seq, action, amount, prev: toHex(prev), hash: toHex(hash),
    v: 27 + sig[0], r: toHex(sig.slice(1, 33)), s: toHex(sig.slice(33, 65)),
  });
  prev = hash;
}

// ---------------------------------------------------------------- merkle (52 leaves, keccak, sorted pairs)

const shares: Uint8Array[] = [];
{
  const x = randScalar();
  for (let i = 0; i < 52; i++) shares.push(encode(ptMul(BASE, mod(x + BigInt(i) * 7n, L) + 1n)));
}
const leaves = shares.map((s) => keccak_256(s));
function level(nodes: Uint8Array[]): Uint8Array[] {
  const out: Uint8Array[] = [];
  for (let i = 0; i < nodes.length; i += 2) {
    const a = nodes[i], b = nodes[i + 1] ?? nodes[i];
    const [lo, hi] = toHex(a) <= toHex(b) ? [a, b] : [b, a];
    out.push(keccak_256(new Uint8Array([...lo, ...hi])));
  }
  return out;
}
let nodes = leaves.slice();
const tree: Uint8Array[][] = [nodes];
while (nodes.length > 1) { nodes = level(nodes); tree.push(nodes); }
const root = tree[tree.length - 1][0];
function proofFor(idx: number): string[] {
  const proof: string[] = [];
  let i = idx;
  for (let d = 0; d < tree.length - 1; d++) {
    const sib = i ^ 1;
    proof.push(toHex(tree[d][sib] ?? tree[d][i]));
    i >>= 1;
  }
  return proof;
}
const merkleIdx = 17;

// ---------------------------------------------------------------- emit

const hex32 = (h: string) => `hex"${h}"`;
const lines: string[] = [];
lines.push('// SPDX-License-Identifier: MIT');
lines.push('// AUTO-GENERATED by gen/gen.mts — do not edit. Mirror validated against @noble/curves.');
lines.push('pragma solidity ^0.8.24;');
lines.push('');
lines.push('library Vectors {');
lines.push(`    uint256 internal constant D = ${D};`);
lines.push(`    uint256 internal constant SQRT_M1 = ${SQRT_M1};`);
lines.push(`    uint256 internal constant INVSQRT_AMD = ${INVSQRT_AMD};`);
lines.push(`    uint256 internal constant BASE_X = ${BASE.X};`);
lines.push(`    uint256 internal constant BASE_Y = ${BASE.Y};`);
lines.push(`    uint256 internal constant TWO256_MOD_L = ${mod(1n << 256n, L)};`);
lines.push('');
lines.push('    struct Dleq { bytes pub; bytes base2; bytes point2; uint256 c; uint256 s; bool ok; }');
lines.push('    function dleqCount() internal pure returns (uint256) { return ' + dleqVecs.length + '; }');
lines.push('    function dleq(uint256 i) internal pure returns (Dleq memory d) {');
dleqVecs.forEach((v, i) => {
  lines.push(`        if (i == ${i}) return Dleq(${hex32(v.pub)}, ${hex32(v.base2)}, ${hex32(v.point2)}, ${v.c}, ${v.s}, ${v.ok});`);
});
lines.push('        revert("i");');
lines.push('    }');
lines.push('');
lines.push('    function evalCount() internal pure returns (uint256) { return ' + evalVecs.length + '; }');
lines.push('    function evalVec(uint256 i) internal pure returns (uint8[7] memory c, uint256 packed) {');
evalVecs.forEach((v, i) => {
  lines.push(`        if (i == ${i}) return ([uint8(${v.cards.join('), uint8(')})], ${v.packed});`);
});
lines.push('        revert("i");');
lines.push('    }');
lines.push('');
lines.push(`    address internal constant HOST = address(uint160(0x${addr(kHost)}));`);
lines.push(`    address internal constant GUEST = address(uint160(0x${addr(kGuest)}));`);
lines.push(`    bytes32 internal constant SESSION = 0x${toHex(session)};`);
lines.push('    struct Act { uint64 hand; uint64 seq; uint8 action; uint256 amount; bytes32 prev; bytes32 hash; uint8 v; bytes32 r; bytes32 s; }');
lines.push('    function actCount() internal pure returns (uint256) { return ' + actVecs.length + '; }');
lines.push('    function act(uint256 i) internal pure returns (Act memory a) {');
actVecs.forEach((v, i) => {
  lines.push(`        if (i == ${i}) return Act(${v.hand}, ${v.seq}, ${v.action}, ${v.amount}, 0x${v.prev}, 0x${v.hash}, ${v.v}, 0x${v.r}, 0x${v.s});`);
});
lines.push('        revert("i");');
lines.push('    }');
lines.push('');
lines.push(`    bytes32 internal constant MERKLE_ROOT = 0x${toHex(root)};`);
lines.push(`    uint256 internal constant MERKLE_INDEX = ${merkleIdx};`);
lines.push(`    bytes32 internal constant MERKLE_LEAF_SHARE_HASH = 0x${toHex(leaves[merkleIdx])};`);
lines.push('    function merkleProof() internal pure returns (bytes32[] memory p) {');
const prf = proofFor(merkleIdx);
lines.push(`        p = new bytes32[](${prf.length});`);
prf.forEach((h, i) => lines.push(`        p[${i}] = 0x${h};`));
lines.push('    }');
lines.push('}');
console.log(lines.join('\n'));
console.error('OK: mirror validated against noble (200 mul + 100 round-trip); ' +
  `${dleqVecs.length} dleq, ${evalVecs.length} eval, ${actVecs.length} act vectors`);
