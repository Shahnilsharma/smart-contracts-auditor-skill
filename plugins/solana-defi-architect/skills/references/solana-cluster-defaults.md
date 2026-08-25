# Solana clusters — default params

## Clusters

| Cluster | Purpose | Public RPC | Notes |
|---|---|---|---|
| **devnet** (default) | app/program development, public, free airdrops | `https://api.devnet.solana.com` | rate-limited single node; use a provider (Helius/QuickNode/Alchemy/Chainstack) for anything beyond quick iteration; state can be reset less often than local but don't treat as permanent |
| testnet | validator/network stress-testing, newer software branch than devnet/mainnet | `https://api.testnet.solana.com` | not the right target for app development — devnet is |
| mainnet-beta | production, real value | `https://api.mainnet-beta.solana.com` | rate-limited shared node, not for production load — use a paid RPC provider; only deploy here on explicit user request |
| local (`solana-test-validator` or `surfpool`'s `surfnet`) | fastest iteration, full control | `http://127.0.0.1:8899` | reset at will, airdrop freely; Surfpool's Surfnet can fetch real mainnet account/program state on demand for realistic CPI testing without redeploying dependencies |

Devnet SOL: airdrop via `solana airdrop 2 --url devnet` or a web faucet (rotates — search current options if the CLI airdrop is rate-limited). Never rely on devnet/testnet token balances having real value or persisting indefinitely.

## RPC provider note

Public endpoints above are shared, rate-limited, and have no SLA — fine for quick checks, not for a QA runner making many sequential calls or any production traffic. Get a free-tier key from a provider (Helius, QuickNode, Alchemy, Chainstack, Triton, etc.) for anything beyond trivial use, and pass it via `--url`/`RPC_URL` env var rather than hardcoding a public endpoint into scripts.

## Program deploys cost rent

Deploying a program allocates an on-chain account sized to the compiled `.so` — you pay rent-exempt-minimum SOL proportional to program size (larger programs = more SOL locked). Budget for this on every cluster, especially before a mainnet-beta deploy; verify current balance with `solana balance` before deploying.

## Custom cluster / non-Solana-Foundation RPC override

If the user gives a private RPC URL, provider docs link, or a fork/appchain, treat it the same way the other chain skills treat a custom chain: fetch/confirm the endpoint, commitment-level defaults, and any feature-set differences from mainnet-beta before writing code that depends on specific runtime behavior.
