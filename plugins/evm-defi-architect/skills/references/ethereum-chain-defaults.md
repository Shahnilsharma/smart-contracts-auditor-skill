# Ethereum — default chain params

## Networks

| Env | Chain ID | Notes |
|---|---|---|
| Mainnet | 1 | real funds — only deploy on explicit request |
| Sepolia | 11155111 | default deploy target; current recommended public testnet (Goerli is deprecated/deactivated) |

Faucets: Sepolia ETH via any current faucet (e.g. Alchemy/Infura/Google Cloud Web3 faucets — check availability, they rotate) or a bridged faucet from an existing testnet balance.

## RPC

No public unauthenticated RPC recommended for real use — get a free-tier endpoint from Alchemy, Infura, or similar, or run your own node/Anvil fork. Don't hardcode a shared public RPC into deploy scripts; use `${RPC_URL}` env var, resolved per-network.

## Block explorer / verification

- Mainnet: Etherscan (`etherscan.io`), API key required for `forge script --verify`.
- Sepolia: Etherscan's unified API now covers testnets under the same API key (single Etherscan V2 API key works across supported chains) — confirm current key/endpoint requirements against Etherscan docs at run time, this has changed over time.
- `forge verify-contract` / `--verify` flag on `forge script` for automated verification post-deploy.

## Gas

- EIP-1559 fee market: `maxFeePerGas` / `maxPriorityFeePerGas`, not legacy `gasPrice`, on mainnet/Sepolia.
- `forge script` estimates gas automatically; for L2s check whether the target chain still uses 1559 or a different model (some don't).

## EVM version

Confirm target EVM hardfork in `foundry.toml` (`evm_version`) / `hardhat.config` — mainnet is on Cancun+ (post-Dencun), some L2s/older testnets lag behind and lack transient storage opcodes (`TLOAD`/`TSTORE`) or blob-related opcodes. Don't assume feature parity on a non-Ethereum-mainnet EVM chain — verify from that chain's own docs (chain ID, EVM version, gas token, explorer) same as the ZigChain-style docs-param flow.

## Custom EVM chain override

If user supplies a different EVM chain (URL or .md): replace chain-id, RPC, native gas token, explorer/verify config, and EVM-version assumptions with the fetched values. Common non-mainnet EVM chains to watch for version/opcode gaps: newer L2s, appchains, and non-Ethereum EVM-compatible chains — always verify rather than assume mainnet-equivalent behavior.
