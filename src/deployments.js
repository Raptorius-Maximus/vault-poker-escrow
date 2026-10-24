// One live entry per chain Vault has actually been deployed to. A redeploy
// gives a new address (a deployed contract can't be patched) -- update the
// entry here, don't create a second one. See OVERVIEW.md's Deployments table,
// which is the source of truth this should always match.
export const DEPLOYMENTS = {
  84532: {
    // Base Sepolia
    address: '0xF41A685C7e260397Be07cC75008D29A7457481f6',
    name: 'Base Sepolia',
    explorer: 'https://sepolia.basescan.org',
  },
};
