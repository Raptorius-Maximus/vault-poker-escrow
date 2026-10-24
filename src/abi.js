import { parseAbi } from 'viem';

// Mirrors contracts/src/Channel.sol exactly. Keep in sync by hand -- there
// is no build step that ties the two together (separate toolchains,
// separate languages), so a signature change on one side needs a matching
// edit here.
export const CHANNEL_ABI = parseAbi([
  'function open(bytes32 sessionId, address opponent) external payable',
  'function join(bytes32 sessionId) external payable',
  'function cancelOpen(bytes32 sessionId) external',
  'function closeCooperative(bytes32 sessionId, address winner, bytes sigHost, bytes sigGuest) external',
  'function claimByDefault(bytes32 sessionId) external payable',
  'function iAmHere(bytes32 sessionId) external',
  'function resolve(bytes32 sessionId) external',
  'function defaultWindow() external view returns (uint256)',
  'function BOND_BPS() external view returns (uint256)',
  'function sessions(bytes32) external view returns (address host, address guest, uint256 buyIn, uint256 window, uint8 status, address claimant, uint256 bond, uint256 deadline)',
  'event Opened(bytes32 indexed sessionId, address host, address guest, uint256 buyIn)',
  'event Joined(bytes32 indexed sessionId)',
  'event Cancelled(bytes32 indexed sessionId)',
  'event ClosedCooperative(bytes32 indexed sessionId, address winner)',
  'event ClaimedByDefault(bytes32 indexed sessionId, address claimant, uint256 deadline)',
  'event Refuted(bytes32 indexed sessionId, address refuter, uint256 newDeadline)',
  'event Resolved(bytes32 indexed sessionId, address winner)',
]);

// Status enum order, exactly as declared in Channel.sol -- sessions()
// returns it as a raw uint8.
export const STATUS = ['None', 'AwaitingGuest', 'Active', 'ClaimPending', 'Refuted', 'Closed'];
