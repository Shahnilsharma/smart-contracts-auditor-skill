# Wallet setup — ask before every QA run or deploy

Never assume. Ask the user which mode, every time a devnet/mainnet transaction or role-based QA run is about to happen.

## 1. Local keypair file (devnet / local default)
```bash
solana-keygen new -o keys/admin.json --no-bip39-passphrase   # generate
solana config set --keypair keys/admin.json --url devnet
solana airdrop 2 --url devnet                                 # fund on devnet
```
Fine for devnet/local dev. Flag as unsafe for mainnet-beta if the key isn't otherwise protected (hardware/multisig) and holds real value — plaintext keypair JSON files are a common leak vector.

## 2. Hardware wallet (Ledger) — mainnet-beta fund-controlling operations
```bash
solana-keygen pubkey usb://ledger                 # confirm device address
solana program deploy target/deploy/program.so --keypair usb://ledger --url mainnet-beta
```
Signing happens on-device.

## 3. Squads multisig (or equivalent) — program upgrade authority / treasury
For anything past a solo-dev prototype on mainnet-beta, recommend moving program upgrade authority and any treasury-controlling authority to a multisig (Squads is the common choice in the Solana ecosystem) rather than a single key — single-key upgrade authority on a live, valuable program is itself flagged in the audit checklist. Setting this up is a Squads-specific flow (their app/CLI) — point the user there rather than hand-rolling a multisig scheme.

## Role-based QA env convention
```bash
WALLET_MODE=keypair|ledger|multisig
ADMIN_KEYPAIR=keys/admin.json      # or usb://ledger, or a Squads vault address for read-only checks
USER1_KEYPAIR=keys/user1.json
ATTACKER_KEYPAIR=keys/attacker.json
```
Resolve per-role wallets through whichever mode was chosen before running LiteSVM/Mollusk/Surfpool QA scenarios or any `solana`/`anchor` CLI deploy/upgrade command. Never commit keypair JSON files — gitignore the keys directory.
