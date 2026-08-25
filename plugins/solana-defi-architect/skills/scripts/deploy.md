# Deploy commands — anchor / solana CLI

## Local (solana-test-validator or Surfpool's Surfnet)
```bash
solana-test-validator &   # or: NO_DNA=1 surfpool start
anchor deploy --provider.cluster localnet
```

## Devnet (default)
```bash
solana config set --url devnet --keypair keys/admin.json
solana airdrop 2   # repeat as needed; program deploy costs rent proportional to program size
anchor build
anchor deploy --provider.cluster devnet
# or directly:
solana program deploy target/deploy/<program>.so --url devnet --keypair keys/admin.json
```

## Mainnet-beta — only on explicit user request, confirm once + confirm upgrade-authority plan first
```bash
solana balance --url mainnet-beta --keypair <wallet per scripts/wallet_setup.md>
anchor build --verifiable   # reproducible build, recommended before a real mainnet deploy
solana program deploy target/deploy/<program>.so \
  --url mainnet-beta \
  --keypair usb://ledger \       # or a Squads-managed authority — see scripts/wallet_setup.md
  --program-id target/deploy/<program>-keypair.json
```

## Upgrade authority
```bash
solana program show <program_id> --url <cluster>              # check current authority
solana program set-upgrade-authority <program_id> \
  --new-upgrade-authority <squads_vault_or_new_key> --url <cluster>
```
Recommend multisig (e.g. Squads) upgrade authority before/at first mainnet-beta deploy of anything holding meaningful value — see `scripts/wallet_setup.md`.

## Post-deploy smoke test
```bash
anchor idl init <program_id> -f target/idl/<program>.json --provider.cluster <cluster>
# then run the role-based QA runner (references/testing-solana.md) against the deployed program
```

## Custom / non-default cluster
Replace `--url`, RPC provider, and any feature-set assumptions with values resolved in step 0 of `SKILL.md`.
