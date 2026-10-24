# Marker latency on Base Sepolia — first measurement, 2026-08-17

Spec §11.2(a). Live network: **Base Sepolia, chain 84532**, RPC
`https://sepolia.base.org`, operator-approved run from the vault deploy key.
Bench contract `MarkerBench.sol` (this dir) deployed at
`0xcaE60a624E6DFb31f0eB677679879EA6174a913b`
(tx `0x3c7874ea145436413609228a56cc24d8ad1f60c44e001f2516f1867b8e9fe3a2`).

## Numbers

| Send → confirmed | Wall clock |
|---|---|
| contract deploy | 1,229 ms |
| marker post, full size (500B marker + 360B receipt) | 2,884 ms |
| marker post, full size | 697 ms |

- **Gas per full-size marker post: 61,740** (storage slot + event + ~900B
  calldata). Effective price at run time: 0.006 gwei → ~3.7e-7 test ETH per
  post. At mainnet-Base prices (0.005–0.1 gwei): **~$0.001–0.02 per hand.**
- Base blocks are 2s; observed send→confirm 0.7–2.9s, i.e. current-or-next
  block plus RPC round trip.

## Verdict for §4's gate

**The deal gate disappears into the inter-hand rhythm.** The wait it adds
between hands is one confirmation ≈ 1–3 s, comparable to the shuffle itself.
§4's collapse branch ("if the wait is unplayable, cadence returns to
design") is not triggered.

## Full run — 2026-08-17, same day (ops top-up granted)

20 full-size posts, same contract, chain 84532:

    samples (ms): 696 706 709 732 736 737 741 746 747 779
                  805 819 930 948 962 976 1077 1162 1261 2767
    n=20  min=696  median=792  mean=952  p95=1261  max=2767

**§11.2(a) is closed:** the deal gate costs a sub-second wait at median,
~1.3 s at p95, 2.8 s worst observed — inside the shuffle's own rhythm in
every sample. Congestion tail beyond this remains unmeasured but is
block-time-bound on an OP-stack chain.

**Operational finding for P6:** 17 of 20 first-attempt sends failed
transiently — `sepolia.base.org` is load-balanced and nodes lag each other
on nonce state, so rapid sequential sends race. A single retry after 2 s
fixed every one (17/17). Client marker-posting MUST carry retry-on-
transient-failure; the deal gate's pause semantics already tolerate it.
