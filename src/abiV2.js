import { parseAbi } from 'viem';

// Mirrors contracts/src/ChannelV2.sol exactly. Keep in sync by hand -- there
// is no build step that ties the two together (separate toolchains, separate
// languages), so a signature change on one side needs a matching edit here.
// This is the same hand-mirror convention src/abi.js documents for V1.
//
// RECONCILED against contracts/out/ChannelV2.sol/ChannelV2.json (compiled,
// 2026-08-18) -- P2/P3/P4 have all SHIPPED, so this is no longer a guess
// against a pinned prose surface. Notable reconciliations vs. the phase-5
// drafting-time assumptions (TBD-P2-GETTER-ABI resolved per AF-24/AF-38):
//   * There is NO `sessions(bytes32)` public struct getter. The 21-field
//     Session struct exceeds legacy getter stack limits, so the struct is
//     internal and the read surface is the grouped view fns below
//     (sessionCore/Keys/Bonds/Deposits/DisputeOpenedAt/HighestFinal). AF-24.
//   * disputeOpenedAt is a Session field, read via sessionDisputeOpenedAt --
//     not a top-level mapping. AF-38.
//   * everReceipted / markedHand / hostFiledInWindow / guestFiledInWindow ARE
//     named public getters -- the phase doc assumed they were not, so task 6's
//     zero-filings and per-duty settlement copy reads them directly rather
//     than degrading.
//   * The Marker struct carries a `startingChips` field (AF-32, the both-signed
//     chip<->wei anchor). The receipt's `final` byte is named `isFinal`
//     (`final` is reserved in Solidity).
//   * NotYetBuilt() is NEVER thrown by any live path any more (P3/P4 shipped).
//     It is kept in this ABI so viem can still decode it if some older-build
//     contract instance ever reverts it -- a defensive branch, not the
//     expected interim state the phase doc's design decision 5 described.
//     Phase2InProgress() is the real live interim revert from resolve() while
//     a phase-2 continuation is still running.
export const CHANNEL_V2_ABI = parseAbi([
  // --- struct definitions (field order EXACTLY formats §3/§4/§5) ---
  'struct Receipt { uint64 hand; uint32 subseq; uint256 hostStack; uint256 guestStack; uint256 hostDeposit; uint256 guestDeposit; bool isFinal; }',
  'struct Marker { uint64 hand; bytes32 receiptHash; bytes32 deckRoot; bytes32 hostShareRoot; bytes32 guestShareRoot; bytes32 hostCardPk; bytes32 guestCardPk; uint8 button; uint256 sb; uint256 bb; uint256 startingChips; }',
  'struct Act { uint64 hand; uint64 seq; uint8 action; uint256 amount; bytes32 prev; }',
  'struct SharePost { uint8 pos; bytes32 shareEnc; uint256 c; uint256 s; bytes32[] shareProof; bytes32 c1Enc; bytes32 c2Enc; bytes32[] deckProof; }',

  // --- money-frame writes (Session interface, formats §9) ---
  'function open(bytes32 session, address opponent, uint256 maxHost, uint256 maxGuest, address sessionKey, bytes walletSig) external payable',
  'function join(bytes32 session, address sessionKey, bytes walletSig) external payable',
  'function cancelOpen(bytes32 session) external',
  'function deposit(bytes32 session) external payable',

  // --- dispute-filing writes (formats §9) ---
  'function openDispute(bytes32 session) external',
  'function fileReceipt(bytes32 session, Receipt r, bytes sigHost, bytes sigGuest) external',
  'function fileMarker(bytes32 session, Marker m, bytes sigHost, bytes sigGuest) external',
  'function fileMarkerWithReceipt(bytes32 session, Marker m, bytes sigHostM, bytes sigGuestM, Receipt r, bytes sigHostR, bytes sigGuestR) external',
  'function fileActions(bytes32 session, Act[] acts, bytes[] sigs) external',
  'function postShares(bytes32 session, SharePost[] posts) external',
  'function phase2Act(bytes32 session, Act a, bytes sig) external',
  'function resolve(bytes32 session) external',
  'function withdraw() external',

  // --- grouped read surface (AF-24; TBD-P2-GETTER-ABI resolved) ---
  'function sessionCore(bytes32 session) external view returns (address host, address guest, uint8 status, uint256 maxHost, uint256 maxGuest)',
  'function sessionKeys(bytes32 session) external view returns (address sessionKeyHost, address sessionKeyGuest)',
  'function sessionBonds(bytes32 session) external view returns (uint256 bondHost, uint256 bondGuest, bool hostBurned, bool guestBurned)',
  'function sessionDeposits(bytes32 session) external view returns (uint256 depositedHost, uint256 depositedGuest)',
  'function sessionDisputeOpenedAt(bytes32 session) external view returns (uint256)',
  'function sessionHighestFinal(bytes32 session) external view returns (uint64 hand, uint32 subseq, bytes32 hash, uint256 hostStack, uint256 guestStack, uint256 hostDeposit, uint256 guestDeposit)',

  // --- scalar / mapping reads ---
  'function credits(address) external view returns (uint256)',
  'function window() external view returns (uint256)',
  'function bank() external view returns (uint256)',
  'function grace() external view returns (uint256)',
  'function liveHand(bytes32 session) external view returns (uint64)',
  'function markedHand(bytes32) external view returns (uint64)',
  'function everReceipted(bytes32) external view returns (bool)',
  'function hostFiledInWindow(bytes32) external view returns (bool)',
  'function guestFiledInWindow(bytes32) external view returns (bool)',
  'function receiptAt(bytes32, uint64) external view returns (bytes32)',
  'function sharePosted(bytes32, uint64, uint8, address) external view returns (bool)',

  // --- custom errors (so viem can decode them on a revert) ---
  'error NotYetBuilt()',
  'error PendingContinuation()',
  'error Phase2InProgress()',
]);

// Status enum order, exactly as declared in ChannelV2.sol (enum Status {
// None, AwaitingGuest, Active, Disputed, Closed }) -- the grouped getter
// sessionCore() returns it as a raw uint8. Order-sensitive; reconciled
// against the compiled ABI + source 2026-08-18.
export const STATUS_V2 = ['None', 'AwaitingGuest', 'Active', 'Disputed', 'Closed'];
