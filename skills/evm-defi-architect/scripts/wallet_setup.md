# Wallet setup — ask before every QA run or deploy

Never assume. Ask the user which mode, every time a broadcast or role-based QA run is about to happen.

## 1. Encrypted keystore (recommended for testnet/mainnet)
```bash
cast wallet import <name> --interactive   # prompts for private key + password, encrypts to disk
cast wallet list                          # verify
```
Use on scripts: `forge script script/Deploy.s.sol --account <name> --broadcast --rpc-url <rpc>`. Key never sits in plaintext in `.env` or shell history.

## 2. Private key / mnemonic env var (local Anvil only)
```bash
# .env, gitignored
ADMIN_PRIVATE_KEY=0x...
USER1_PRIVATE_KEY=0x...
```
Flag explicitly as unsafe for any network holding real funds — plaintext keys in `.env` are a common leak vector (committed by accident, synced to cloud, logged by tooling).

## 3. Hardware wallet (mainnet fund-controlling deploys)
```bash
forge script script/Deploy.s.sol --ledger --sender <address> --broadcast --rpc-url <rpc>
# or --trezor
```
Signing happens on-device; nothing sensitive touches the host.

## 4. Anvil default accounts (local dev only)
Anvil (no `--fork-url`) starts with 10 deterministic accounts from mnemonic `test test test test test test test test test test test junk`, each funded 10000 ETH. Private keys are publicly known from this mnemonic — local testing only, never for testnet/mainnet real funds.
```bash
anvil   # prints the 10 addresses + private keys on startup
```

## Role-based QA env convention
```bash
WALLET_MODE=keystore|privatekey|ledger|anvil
ADMIN_ACCOUNT=<cast keystore name or address>
USER1_ACCOUNT=...
ATTACKER_ACCOUNT=...
```
Resolve per-role wallets through whichever mode was chosen before running the Foundry/Hardhat QA scenarios or `forge script`/`cast send` deploy commands.
