// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Ristretto} from "./Ristretto.sol";

/// Evidence.sol — position-bound Merkle leaves (artifact-formats.md §7), a
/// generic sorted-pair Merkle verifier (reused from
/// prototypes/dispute-gas/src/Bench.sol's `merkleVerify`, tree-walk
/// arithmetic unchanged), the 52-card ristretto point table (decision 6),
/// and the ElGamal combine-and-match decode helper.
///
/// AF-14 (binding, Phase 1): sorted-pair Merkle nodes are commutative, so
/// proof-of-membership alone never proves *position* — position is proven
/// only by appearing inside the leaf preimage. `shareLeaf`/`deckLeaf` below
/// bind `pos` into the leaf for exactly this reason; `merkleVerify` itself
/// takes no index argument and must never be given one to lean on for
/// correctness — see EvidenceTest's M2 fixture (task 1 step 6), which
/// mechanically proves a position-bound leaf and the prototype's unbound
/// `keccak(shareEnc)` leaf produce different roots from the same
/// `(pos, shareEnc)` inputs.
///
/// See phase-3-disputes-evidence.md task 1.
library Evidence {
    // ------------------------------------------------------- §7: leaves

    bytes1 private constant SHARE_TAG = 0x05;
    bytes1 private constant DECK_TAG = 0x06;

    /// shareLeaf(p) = keccak256(0x05 ‖ "vault/shareleaf/v1" ‖ uint8(p) ‖ shareEnc)
    function shareLeaf(uint8 pos, bytes32 shareEnc) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(SHARE_TAG, "vault/shareleaf/v1", pos, shareEnc));
    }

    /// deckLeaf(p) = keccak256(0x06 ‖ "vault/deckleaf/v1" ‖ uint8(p) ‖ c1Enc ‖ c2Enc)
    function deckLeaf(uint8 pos, bytes32 c1Enc, bytes32 c2Enc) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(DECK_TAG, "vault/deckleaf/v1", pos, c1Enc, c2Enc));
    }

    // ------------------------------------------- generic Merkle verify

    /// Sorted-pair keccak Merkle proof — identical arithmetic to
    /// Bench.sol's `merkleVerify` (leaf-shape-agnostic; the position
    /// binding lives entirely in the leaf-hash functions above, never here
    /// — AF-14). `calldata` per this task's own step 3, so `postShares`
    /// (task 4) can pass a `SharePost[] calldata` element's proof array
    /// straight through with no copy.
    function merkleVerify(bytes32 leaf, bytes32[] calldata proof, bytes32 root)
        internal
        pure
        returns (bool)
    {
        bytes32 h = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 p = proof[i];
            h = h <= p ? keccak256(abi.encodePacked(h, p)) : keccak256(abi.encodePacked(p, h));
        }
        return h == root;
    }

    // ------------------------------------------- 52-card point table

    /// Card i's ristretto255 encoding, i.e. `BASE.multiply(i+1)`
    /// (poker/src/core/cards.ts:19), computed once off-chain by a
    /// deterministic, noble-validated script (task 1 step 4 — throwaway,
    /// not a second vector generator; see that step's own note) and pasted
    /// here as constants. Not computed on-chain: the measured
    /// scalar-mul-and-encode cost (~524k gas, prototype README) would make
    /// 52 on-chain lookups per position prohibitively expensive.
    function cardPoint(uint8 i) internal pure returns (bytes32) {
        require(i < 52, "bad card index");
        return CARD_POINTS()[i];
    }

    /// The 52 constants themselves. A `pure` function returning a fixed
    /// array, per task 1 step 4's explicit either-is-fine allowance —
    /// Solidity constant state variables do not support fixed-size array
    /// types, so this is the compiling form.
    function CARD_POINTS() internal pure returns (bytes32[52] memory t) {
        t[0] = 0xe2f2ae0a6abc4e71a884a961c500515f58e30b6aa582dd8db6a65945e08d2d76; // card 0
        t[1] = 0x6a493210f7499cd17fecb510ae0cea23a110e8d5b901f8acadd3095c73a3b919; // card 1
        t[2] = 0x94741f5d5d52755ece4f23f044ee27d5d1ea1e2bd196b462166b16152a9d0259; // card 2
        t[3] = 0xda80862773358b466ffadfe0b3293ab3d9fd53c5ea6c955358f568322daf6a57; // card 3
        t[4] = 0xe882b131016b52c1d3337080187cf768423efccbb517bb495ab812c4160ff44e; // card 4
        t[5] = 0xf64746d3c92b13050ed8d80236a7f0007c3b3f962f5ba793d19a601ebb1df403; // card 5
        t[6] = 0x44f53520926ec81fbd5a387845beb7df85a96a24ece18738bdcfa6a7822a176d; // card 6
        t[7] = 0x903293d8f2287ebe10e2374dc1a53e0bc887e592699f02d077d5263cdd55601c; // card 7
        t[8] = 0x02622ace8f7303a31cafc63f8fc48fdc16e1c8c8d234b2f0d6685282a9076031; // card 8
        t[9] = 0x20706fd788b2720a1ed2a5dad4952b01f413bcf0e7564de8cdc816689e2db95f; // card 9
        t[10] = 0xbce83f8ba5dd2fa572864c24ba1810f9522bc6004afe95877ac73241cafdab42; // card 10
        t[11] = 0xe4549ee16b9aa03099ca208c67adafcafa4c3f3e4e5303de6026e3ca8ff84460; // card 11
        t[12] = 0xaa52e000df2e16f55fb1032fc33bc42742dad6bd5a8fc0be0167436c5948501f; // card 12
        t[13] = 0x46376b80f409b29dc2b5f6f0c52591990896e5716f41477cd30085ab7f10301e; // card 13
        t[14] = 0xe0c418f7c8d9c4cdd7395b93ea124f3ad99021bb681dfc3302a9d99a2e53e64e; // card 14
        t[15] = 0xc862fced1314e81e9b77d02b847689096b4e7ded39b009b9c996982e4ecac66e; // card 15
        t[16] = 0x682802b3c90112e0f4e7d985e423cd2b16c5bfa63d9c967c52bb6cb7fea7ea7e; // card 16
        t[17] = 0x82e5de819f5d2e9b6ed6a3338ea3a7f6201361b65e13d6832433c419caf01a1b; // card 17
        t[18] = 0x4cf1b9deda93eb9fd515fcc99262aed1368b48f24a27afd2984da8fe7bb2341f; // card 18
        t[19] = 0xee016fbbdde54077fda69fecb546e0a93b1f4f03b1cfecf6fc5bde920f61e961; // card 19
        t[20] = 0xe6fcd7341e95afc3ecd9cd47892bf783a6be7b69d700a7f576addc10eb7a122b; // card 20
        t[21] = 0xd886641e16a1165d70fa89413c4129d56b15d5f44d2dd2b09823cd723487656a; // card 21
        t[22] = 0xc0287ab3502a0f5c5853ebaa191d8b01c42cdc8c124c3cc76030ee08ddab8559; // card 22
        t[23] = 0x8ebe6bc929231656883cfc384290b52438c716f5912535841e92f68154b9384f; // card 23
        t[24] = 0xaa284c17ccc8e5f37a1ce135d28797e08867fe1b932fbf4f790c0bec5cfd4540; // card 24
        t[25] = 0x6cc0a929860a630dee3030be2f2ea4d5fbe3f1511cc0c1bc94c451fd61f36d7c; // card 25
        t[26] = 0x8875a1f137b08640ce57a6c8829cd2a1d8102ad853b60cec13fc901a14a7f07b; // card 26
        t[27] = 0x6ce1753d32f37974829e1d2c6de6cce3f3717fe0440b0247afb6596975518f16; // card 27
        t[28] = 0x2809be5a1c388c4c0070a5c66ace507feade48828590314674cb0a6fd971e903; // card 28
        t[29] = 0x461d2598d7da2e1f67bf3aab17d19d23804bcefeda3d8815b815798a8d49712c; // card 29
        t[30] = 0x18733c1f1ad791067184a90770029a4d74699b9f5d098d50f88aa9d8bbf8e872; // card 30
        t[31] = 0xd827a0808288a3c1ce91192c0770c3ad7372a50ac601dff8323a5bdda104322f; // card 31
        t[32] = 0x6cb925752437368710235314963a2d23751898b536cab9b98a32bab56afeae45; // card 32
        t[33] = 0xa2a0c7d2940748baa58d9b65f7df99876acbabf456357973be10482b6928782a; // card 33
        t[34] = 0xae831391aa3a7a390a9be05e863f21e5a50033b847096cf7565a461050e1d91e; // card 34
        t[35] = 0x6ab79d1d77b9f25e3c0ec90b6fc49cbb576b76c375f1e3c6848ace9b9d3bf86a; // card 35
        t[36] = 0xe490d31f3ac3633033bff8495d510ecd8197db499962d68483a134ade350923b; // card 36
        t[37] = 0xd242ad58e47f3978b6de6ed8f32de5dc221616ee375096b206ee26253c356426; // card 37
        t[38] = 0x5e7e8089547c1f6f76a52a8e9d445e1497a3d02001abcd4725162ebc28804b5e; // card 38
        t[39] = 0x3a2db4d28a5680e89f596032626556b14a2829021c2b4b92d1d1517a2a61f530; // card 39
        t[40] = 0x1a07eebff79eaafd93a88e8667eb43ea3cfa0d426ab2382d9f44a36f4472d119; // card 40
        t[41] = 0xe00af9c74d9edb8ebcc160ceec97d531cbd6e2956f9e9162b8e9eda260e82e43; // card 41
        t[42] = 0xa483ff09887d5fd24cbd44052007100293c6e6f2e787f166119d3bbf0afc4d42; // card 42
        t[43] = 0x2abbaf9343c09de9b63395414e298b3e30c1507b6be4a9e83e270e4fd1e6c435; // card 43
        t[44] = 0x18de438e0e414e7583f48aee690b4e1756ef8a94ccd9f31dbc466a9e1cfca214; // card 44
        t[45] = 0x7cb4f08fecd2f98daaf29f897892e79a511ae5649f213bcd8dde1515a4d87d36; // card 45
        t[46] = 0x1c5daa6ca114445b077686038aae31c31f2e146a7145a2f3f92b47c131a11031; // card 46
        t[47] = 0xce4f565fcbf261658b2a3368f97cf33c0f089e853fe7dfdba55573ef7d14f265; // card 47
        t[48] = 0xcec1426a33965eb2a7d82b281964ad39f06d6fba7d8e57f8da4fcfefd946d855; // card 48
        t[49] = 0x9e504f9b10c40230ec4e1570dcf295d5da01aa0daeced57316b160c80bc57e0c; // card 49
        t[50] = 0xa45af5c5eeb3db9687fe9edae95387f91ff5a90c442159204c3f97514dddad7c; // card 50
        t[51] = 0x30eb54ee0d290e0fd9f8a6c6cbc84e3a516645fe1be77429987375498aee8641; // card 51
    }

    // --------------------------------------------- ElGamal combine/decode

    /// combine(c2, hostShare, guestShare) = c2 - hostShare - guestShare
    /// (poker/src/core/elgamal.ts:76-79's `combineShares`). `decode`
    /// itself (the 52-entry linear scan against the combined point) is
    /// task 9's — this task builds only the table and this arithmetic,
    /// per task 1 step 5.
    function combine(Ristretto.Pt memory c2, Ristretto.Pt memory hostShare, Ristretto.Pt memory guestShare)
        internal
        pure
        returns (Ristretto.Pt memory)
    {
        Ristretto.Pt memory acc = Ristretto.add(c2, Ristretto.neg(hostShare));
        return Ristretto.add(acc, Ristretto.neg(guestShare));
    }
}
