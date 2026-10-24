// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * Seven-card hold'em evaluator — port of poker/src/core/evaluator.ts.
 *
 * Best-of-21; returns the score array packed big-endian into six nibbles:
 * category, then up to five kickers, zero-padded — ordering-equivalent to
 * the TS `cmpScore` because lengths agree within a category.
 * Cards 0..51: rank = card % 13, suit = card / 13.
 */
library Evaluator7 {
    uint256 private constant STRAIGHT_FLUSH = 8;
    uint256 private constant QUADS = 7;
    uint256 private constant FULL_HOUSE = 6;
    uint256 private constant FLUSH = 5;
    uint256 private constant STRAIGHT = 4;
    uint256 private constant TRIPS = 3;
    uint256 private constant TWO_PAIR = 2;
    uint256 private constant PAIR = 1;

    function evaluate(uint8[7] memory cards) internal pure returns (uint256 best) {
        for (uint256 a = 0; a < 3; a++) {
            for (uint256 b = a + 1; b < 4; b++) {
                for (uint256 c = b + 1; c < 5; c++) {
                    for (uint256 d = c + 1; d < 6; d++) {
                        for (uint256 e = d + 1; e < 7; e++) {
                            uint256 s = scoreFive(
                                cards[a], cards[b], cards[c], cards[d], cards[e]
                            );
                            if (s > best) best = s;
                        }
                    }
                }
            }
        }
    }

    function scoreFive(uint8 c0, uint8 c1, uint8 c2, uint8 c3, uint8 c4)
        private
        pure
        returns (uint256)
    {
        unchecked {
            uint256[5] memory r =
                [uint256(c0 % 13), c1 % 13, c2 % 13, c3 % 13, c4 % 13];
            // sort desc, 5-element insertion sort
            for (uint256 i = 1; i < 5; i++) {
                uint256 v = r[i];
                uint256 j = i;
                while (j > 0 && r[j - 1] < v) {
                    r[j] = r[j - 1];
                    j--;
                }
                r[j] = v;
            }
            bool isFlush = (c0 / 13 == c1 / 13) && (c1 / 13 == c2 / 13)
                && (c2 / 13 == c3 / 13) && (c3 / 13 == c4 / 13);

            uint256 mask = (1 << r[0]) | (1 << r[1]) | (1 << r[2]) | (1 << r[3]) | (1 << r[4]);
            (bool hasStraight, uint256 straightHigh) = straight(mask);

            if (isFlush && hasStraight) return pack1(STRAIGHT_FLUSH, straightHigh);

            // counts ordered by (count desc, rank desc); ranks are desc-sorted
            // already, so a linear group scan preserves rank order per count.
            uint256[5] memory gRank;
            uint256[5] memory gCount;
            uint256 groups;
            for (uint256 i = 0; i < 5;) {
                uint256 v = r[i];
                uint256 n = 1;
                while (i + n < 5 && r[i + n] == v) n++;
                gRank[groups] = v;
                gCount[groups] = n;
                groups++;
                i += n;
            }
            // insertion sort groups by (count desc, rank desc)
            for (uint256 i = 1; i < groups; i++) {
                uint256 cr = gRank[i];
                uint256 cc = gCount[i];
                uint256 j = i;
                while (j > 0 && (gCount[j - 1] < cc || (gCount[j - 1] == cc && gRank[j - 1] < cr))) {
                    gRank[j] = gRank[j - 1];
                    gCount[j] = gCount[j - 1];
                    j--;
                }
                gRank[j] = cr;
                gCount[j] = cc;
            }

            if (gCount[0] == 4) return pack2(QUADS, gRank[0], gRank[1]);
            if (gCount[0] == 3 && gCount[1] == 2) return pack2(FULL_HOUSE, gRank[0], gRank[1]);
            if (isFlush) return pack5(FLUSH, r);
            if (hasStraight) return pack1(STRAIGHT, straightHigh);
            if (gCount[0] == 3) return pack3(TRIPS, gRank[0], gRank[1], gRank[2]);
            if (gCount[0] == 2 && gCount[1] == 2) {
                return pack3(TWO_PAIR, gRank[0], gRank[1], gRank[2]);
            }
            if (gCount[0] == 2) return pack4(PAIR, gRank[0], gRank[1], gRank[2], gRank[3]);
            return pack5(0, r);
        }
    }

    function straight(uint256 mask) private pure returns (bool, uint256) {
        for (uint256 high = 12; high >= 4; high--) {
            uint256 window = 0x1F << (high - 4);
            if ((mask & window) == window) return (true, high);
        }
        // wheel: A-2-3-4-5
        if ((mask & 0x100F) == 0x100F) return (true, 3);
        return (false, 0);
    }

    // pack: category then kickers, six nibbles total, zero-padded right.
    function pack1(uint256 cat, uint256 k1) private pure returns (uint256) {
        return (((cat << 4) | k1) << 16);
    }

    function pack2(uint256 cat, uint256 k1, uint256 k2) private pure returns (uint256) {
        return (((((cat << 4) | k1) << 4) | k2) << 12);
    }

    function pack3(uint256 cat, uint256 k1, uint256 k2, uint256 k3) private pure returns (uint256) {
        return (((((((cat << 4) | k1) << 4) | k2) << 4) | k3) << 8);
    }

    function pack4(uint256 cat, uint256 k1, uint256 k2, uint256 k3, uint256 k4)
        private
        pure
        returns (uint256)
    {
        return (((((((((cat << 4) | k1) << 4) | k2) << 4) | k3) << 4) | k4) << 4);
    }

    function pack5(uint256 cat, uint256[5] memory r) private pure returns (uint256) {
        return (cat << 20) | (r[0] << 16) | (r[1] << 12) | (r[2] << 8) | (r[3] << 4) | r[4];
    }
}
