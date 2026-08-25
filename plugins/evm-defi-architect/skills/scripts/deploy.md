# Deploy commands — forge script / cast

## Local (Anvil)
```bash
anvil &
forge script script/Deploy.s.sol --rpc-url http://127.0.0.1:8545 --broadcast \
  --private-key <one of anvil's printed keys>   # local only, see scripts/wallet_setup.md
```

## Testnet (default: Sepolia, or resolved custom-chain testnet)
```bash
forge script script/Deploy.s.sol \
  --rpc-url "$SEPOLIA_RPC_URL" \
  --account <keystore-name> \
  --broadcast \
  --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```

## Mainnet — only on explicit user request, confirm once before running
```bash
forge script script/Deploy.s.sol \
  --rpc-url "$MAINNET_RPC_URL" \
  --ledger --sender "$LEDGER_ADDRESS" \
  --broadcast \
  --verify --etherscan-api-key "$ETHERSCAN_API_KEY"
```

## Post-deploy smoke test
```bash
cast call <contract_address> "owner()(address)" --rpc-url "$RPC_URL"
cast send <contract_address> "someWriteFn(uint256)" 100 --account <keystore-name> --rpc-url "$RPC_URL"
```

## Custom EVM chain
Replace `--rpc-url`, `--etherscan-api-key`/`--verifier`+`--verifier-url` (many chains use a non-Etherscan verifier, e.g. Blockscout — pass `--verifier blockscout --verifier-url <url>`), and chain ID assumptions with the values resolved in step 0 of `SKILL.md` from that chain's own docs.
