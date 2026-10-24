// One live entry per chain ChannelV2 has actually been deployed to, mirroring
// src/deployments.js's shape exactly. EMPTY for now, on purpose:
//
//   D11/D13 -- no address until P7 deploys. Deployment is P7-only work; this
//   phase (P5) builds every screen against the compiled ABI shape without a
//   live address of its own.
//
// For this phase's own operator-run floor probe, the operator adds a throwaway
// local `31337` entry BY HAND against a local anvil deploy, e.g.:
//
//   export const DEPLOYMENTS_V2 = {
//     31337: { address: '0x…', name: 'Local anvil', explorer: null },
//   };
//
// That local entry is never committed as a real deployment record -- P7 is the
// one that adds the real `84532` Base Sepolia entry here to go live.
export const DEPLOYMENTS_V2 = {};
