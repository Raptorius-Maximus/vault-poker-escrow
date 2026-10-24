// A window.ethereum that is not MetaMask.
//
// The app talks to `window.ethereum` and nothing else — there is no test-signer
// hook in src/mainV2.js, and that is fine, because window.ethereum is only an
// EIP-1193 object with a `request` method. So the browser gets a shim whose
// request() hands everything to Node, where viem already lives and the anvil
// private keys are in scope.
//
// WHY THE SIGNING HAPPENS IN NODE rather than in the page: putting viem in the
// page would mean bundling it into an init script and keeping a private key in
// browser memory, for no gain. This way the page holds no key material at all
// and the shim is fifteen lines.
//
// Automating the real MetaMask extension is the alternative, and it is a well
// known way to lose a day: extension IDs, an onboarding flow, and a popup to
// click for every signature. None of that tests anything about Vault.
import { createWalletClient, createPublicClient, http } from 'viem';
import { privateKeyToAccount } from 'viem/accounts';
import { foundry } from 'viem/chains';

export function makeSigner(privateKey, rpcUrl) {
  const account = privateKeyToAccount(privateKey);
  const wallet = createWalletClient({ account, chain: foundry, transport: http(rpcUrl) });
  const pub = createPublicClient({ chain: foundry, transport: http(rpcUrl) });

  return {
    address: account.address,
    async request({ method, params = [] }) {
      switch (method) {
        case 'eth_requestAccounts':
        case 'eth_accounts':
          return [account.address];

        case 'eth_chainId':
          return '0x7a69'; // 31337

        // personal_sign arrives as [message, address] — the reverse of
        // eth_sign, and the order MetaMask uses. The message is hex; viem
        // wants { raw } to sign the bytes rather than the string.
        case 'personal_sign':
          return wallet.signMessage({ message: { raw: params[0] } });

        case 'eth_signTypedData_v4':
          return wallet.signTypedData(
            typeof params[1] === 'string' ? JSON.parse(params[1]) : params[1],
          );

        // The page sends a transaction object with hex `value`/`gas`; viem
        // wants BigInt. Anything absent stays absent so viem fills it in.
        case 'eth_sendTransaction': {
          const t = params[0] || {};
          return wallet.sendTransaction({
            to: t.to,
            data: t.data,
            value: t.value === undefined ? undefined : BigInt(t.value),
            gas: t.gas === undefined ? undefined : BigInt(t.gas),
          });
        }

        // Everything else is a plain read: forward it to anvil untouched.
        default:
          return pub.request({ method, params });
      }
    },
  };
}

// Runs inside the page, before any of the app's own code. Deliberately minimal:
// `on`/`removeListener` are no-ops because the app only ever subscribes to
// account and chain changes, and neither happens during a smoke run.
export const INJECT = `
  window.ethereum = {
    isMetaMask: true,
    request: (args) => window.__smokeRpc(args),
    on: () => {},
    removeListener: () => {},
  };
`;
