// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
// Copied from prototypes/dispute-gas/src/Ristretto.sol, 2026-08-17 — see that file's README for the differential-testing chain that validated it.

/**
 * ristretto255 on the EVM — measurement prototype for the V2 dispute path.
 *
 * Faithful port of the BigInt mirror in gen/gen.mts, which is validated
 * against noble-curves (the poker client's own library) every time the
 * vectors regenerate. Constants below are pasted from the generator's
 * output, never typed from memory.
 *
 * Prototype: written for measured correctness on vectors, not audited for
 * adversarial inputs beyond decode's canonical-encoding checks.
 */
library Ristretto {
    uint256 internal constant P = 2 ** 255 - 19;
    uint256 internal constant L =
        7237005577332262213973186563042994240857116359379907606001950938285454250989; // 2^252 + 27742...
    uint256 internal constant D =
        37095705934669439343138083508754565189542113879843219016388785533085940283555;
    uint256 internal constant SQRT_M1 =
        19681161376707505956807079304988542015446066515923890162744021073123829784752;
    uint256 internal constant INVSQRT_AMD =
        54469307008909316920995813868745141605393597292927456921205312896311721017578;
    uint256 internal constant BASE_X =
        15112221349535400772501151409588531511454012693041857206046113283949847762202;
    uint256 internal constant BASE_Y =
        46316835694926478169428394003475163141307993866256225615783033603165251855960;

    struct Pt {
        uint256 x;
        uint256 y;
        uint256 z;
        uint256 t;
    }

    // ------------------------------------------------------------- field

    function fmul(uint256 a, uint256 b) private pure returns (uint256) {
        return mulmod(a, b, P);
    }

    function fadd(uint256 a, uint256 b) private pure returns (uint256) {
        return addmod(a, b, P);
    }

    function fsub(uint256 a, uint256 b) private pure returns (uint256) {
        return addmod(a, P - mulmod(b, 1, P), P);
    }

    /// modexp precompile; exponent fixed-width 32 bytes.
    function fpow(uint256 base, uint256 e) private view returns (uint256 r) {
        assembly {
            let m := mload(0x40)
            mstore(m, 32)
            mstore(add(m, 0x20), 32)
            mstore(add(m, 0x40), 32)
            mstore(add(m, 0x60), base)
            mstore(add(m, 0x80), e)
            mstore(add(m, 0xa0), P)
            if iszero(staticcall(gas(), 0x05, m, 0xc0, m, 0x20)) { revert(0, 0) }
            r := mload(m)
        }
    }

    function isNeg(uint256 x) private pure returns (bool) {
        return x & 1 == 1;
    }

    function ctAbs(uint256 x) private pure returns (uint256) {
        return isNeg(x) ? P - x : x;
    }

    // ------------------------------------------------------------- points

    function base() internal pure returns (Pt memory) {
        return Pt(BASE_X, BASE_Y, 1, mulmod(BASE_X, BASE_Y, P));
    }

    function ident() internal pure returns (Pt memory) {
        return Pt(0, 1, 1, 0);
    }

    function add(Pt memory p, Pt memory q) internal pure returns (Pt memory o) {
        uint256 a = fmul(fsub(p.y, p.x), fsub(q.y, q.x));
        uint256 b = fmul(fadd(p.y, p.x), fadd(q.y, q.x));
        uint256 c = fmul(fmul(p.t, mulmod(2, D, P)), q.t);
        uint256 d_ = fmul(fmul(p.z, 2), q.z);
        uint256 e = fsub(b, a);
        uint256 f = fsub(d_, c);
        uint256 g = fadd(d_, c);
        uint256 h = fadd(b, a);
        o.x = fmul(e, f);
        o.y = fmul(g, h);
        o.z = fmul(f, g);
        o.t = fmul(e, h);
    }

    function dbl(Pt memory p) internal pure returns (Pt memory o) {
        uint256 a = fmul(p.x, p.x);
        uint256 b = fmul(p.y, p.y);
        uint256 c = fmul(2, fmul(p.z, p.z));
        uint256 h = fadd(a, b);
        uint256 xy = fadd(p.x, p.y);
        uint256 e = fsub(h, fmul(xy, xy));
        uint256 g = fsub(a, b);
        uint256 f = fadd(c, g);
        o.x = fmul(e, f);
        o.y = fmul(g, h);
        o.z = fmul(f, g);
        o.t = fmul(e, h);
    }

    function neg(Pt memory p) internal pure returns (Pt memory) {
        return Pt(P - mulmod(p.x, 1, P), p.y, p.z, P - mulmod(p.t, 1, P));
    }

    function mul(Pt memory p, uint256 k) internal pure returns (Pt memory r) {
        r = ident();
        for (uint256 i = 253; i > 0; i--) {
            r = dbl(r);
            if ((k >> (i - 1)) & 1 == 1) r = add(r, p);
        }
    }

    // ---------------------------------------------------------- ristretto

    function sqrtRatioM1(uint256 u, uint256 v) private view returns (bool wasSquare, uint256 r) {
        uint256 v3 = fmul(fmul(v, v), v);
        uint256 v7 = fmul(fmul(v3, v3), v);
        r = fmul(fmul(u, v3), fpow(fmul(u, v7), (P - 5) / 8));
        uint256 check = fmul(v, fmul(r, r));
        bool correct = check == u % P;
        bool flipped = check == P - (u % P);
        bool flippedI = check == fmul(P - (u % P), SQRT_M1);
        if (flipped || flippedI) r = fmul(r, SQRT_M1);
        r = ctAbs(r);
        wasSquare = correct || flipped;
    }

    /// bytes32 wire encoding (little-endian field element) -> point.
    function decode(bytes32 enc) internal view returns (bool ok, Pt memory p) {
        uint256 s = rev(uint256(enc));
        if (s >= P || isNeg(s)) return (false, p);
        uint256 ss = fmul(s, s);
        uint256 u1 = fsub(1, ss);
        uint256 u2 = fadd(1, ss);
        uint256 u2s = fmul(u2, u2);
        uint256 v = fsub(fsub(0, fmul(D, fmul(u1, u1))), u2s);
        (bool wasSquare, uint256 invsqrt) = sqrtRatioM1(1, fmul(v, u2s));
        uint256 denX = fmul(invsqrt, u2);
        uint256 denY = fmul(fmul(invsqrt, denX), v);
        p.x = ctAbs(fmul(fmul(2, s), denX));
        p.y = fmul(u1, denY);
        p.z = 1;
        p.t = fmul(p.x, p.y);
        if (!wasSquare || isNeg(p.t) || p.y == 0) return (false, p);
        ok = true;
    }

    function encode(Pt memory p) internal view returns (bytes32) {
        uint256 u1 = fmul(fadd(p.z, p.y), fsub(p.z, p.y));
        uint256 u2 = fmul(p.x, p.y);
        (, uint256 invsqrt) = sqrtRatioM1(1, fmul(u1, fmul(u2, u2)));
        uint256 den1 = fmul(invsqrt, u1);
        uint256 den2 = fmul(invsqrt, u2);
        uint256 zInv = fmul(fmul(den1, den2), p.t);
        uint256 x = p.x;
        uint256 y = p.y;
        uint256 denInv = den2;
        if (isNeg(fmul(p.t, zInv))) {
            x = fmul(p.y, SQRT_M1);
            y = fmul(p.x, SQRT_M1);
            denInv = fmul(den1, INVSQRT_AMD);
        }
        if (isNeg(fmul(x, zInv))) y = P - y;
        uint256 s = ctAbs(fmul(denInv, fsub(p.z, y)));
        return bytes32(rev(s));
    }

    /// byte-order reversal: wire is little-endian, uint256 is big-endian.
    function rev(uint256 v) private pure returns (uint256 r) {
        r = ((v & 0x00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF) << 8)
            | ((v & 0xFF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00FF00) >> 8);
        r = ((r & 0x0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF) << 16)
            | ((r & 0xFFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000FFFF0000) >> 16);
        r = ((r & 0x00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF) << 32)
            | ((r & 0xFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000) >> 32);
        r = ((r & 0x0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF) << 64)
            | ((r & 0xFFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000) >> 64);
        r = (r << 128) | (r >> 128);
    }
}
