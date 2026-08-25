#!/usr/bin/env bash
# deploy.sh — store -> instantiate -> smoke execute -> query verify
# Fill in resolved chain params from references/<chain>.md before running.
# Default NETWORK=testnet. Pass NETWORK=mainnet explicitly AND set CONFIRM_MAINNET=yes to target mainnet.
set -euo pipefail

NETWORK="${NETWORK:-testnet}"
BINARY="${BINARY:-zigchaind}"
WALLET_ID="${WALLET_ID:?set WALLET_ID (keyring name)}"
WASM_PATH="${WASM_PATH:?set WASM_PATH (artifacts/<name>.wasm)}"
INIT_MSG="${INIT_MSG:-{}}"
LABEL="${LABEL:?set LABEL}"
POLL_INTERVAL="${POLL_INTERVAL:-2}"
POLL_TIMEOUT="${POLL_TIMEOUT:-60}"
# Optional smoke-test steps — set these to actually exercise the deployed contract.
# If left unset, store+instantiate still run but smoke-execute/query-verify are skipped
# with an explicit warning rather than silently claiming to have run them.
SMOKE_EXECUTE_MSG="${SMOKE_EXECUTE_MSG:-}"
SMOKE_QUERY_MSG="${SMOKE_QUERY_MSG:-}"
# Contract admin defaults to the deployer, matching most quick-iteration workflows — but
# this is a real decision, not a safe default for anything beyond a prototype. For a
# production/mainnet deploy holding real value, set CONTRACT_ADMIN explicitly to a
# multisig/governance address instead of leaving this deployer-owned.
CONTRACT_ADMIN="${CONTRACT_ADMIN:-}"

if [ "$NETWORK" = "mainnet" ]; then
  CHAIN_ID="${CHAIN_ID:?set CHAIN_ID for mainnet — verify against networks repo, do not hardcode}"
  NODE="${NODE:?set NODE (mainnet RPC)}"
  if [ "${CONFIRM_MAINNET:-}" != "yes" ]; then
    echo "REFUSING TO DEPLOY TO MAINNET without CONFIRM_MAINNET=yes set explicitly." >&2
    echo "This is a deliberate hard stop, not just a warning — re-run with CONFIRM_MAINNET=yes" >&2
    echo "only after the user has explicitly confirmed a mainnet deploy was intended." >&2
    exit 1
  fi
  if [ -z "$CONTRACT_ADMIN" ]; then
    echo "WARNING: CONTRACT_ADMIN not set for a mainnet deploy — contract admin will default" >&2
    echo "to the deployer wallet ($WALLET_ID), a single key with full migrate authority over" >&2
    echo "a mainnet contract. Set CONTRACT_ADMIN to a multisig/governance address unless a" >&2
    echo "single-key admin was a deliberate, reviewed decision (see the key-compromise" >&2
    echo "resilience ladder in references/agency-audit-methodology.md)." >&2
  fi
else
  if [ "$BINARY" != "zigchaind" ]; then
    # Chain-agnostic mode: BINARY was overridden away from zigchaind (a different CosmWasm
    # chain's binary), so the ZigChain-specific fallbacks below (zig-test-2, the numia RPC,
    # uzig gas price) would silently target the wrong chain. Require these explicitly instead
    # of guessing — this is the fix for a real reported footgun: overriding BINARY alone used
    # to still deploy against ZigChain's testnet/RPC/gas-denom defaults underneath it.
    CHAIN_ID="${CHAIN_ID:?BINARY=$BINARY is not zigchaind — set CHAIN_ID explicitly, the zig-test-2 default only applies to ZigChain}"
    NODE="${NODE:?BINARY=$BINARY is not zigchaind — set NODE explicitly, the numia RPC default only applies to ZigChain}"
    GAS_PRICE="${GAS_PRICE:?BINARY=$BINARY is not zigchaind — set GAS_PRICE explicitly, the uzig default only applies to ZigChain}"
  else
    CHAIN_ID="${CHAIN_ID:-zig-test-2}"
    NODE="${NODE:-https://public-zigchain-rpc.numia.xyz}"
    GAS_PRICE="${GAS_PRICE:-0.0025uzig}"
  fi
fi

GAS_ADJ="${GAS_ADJ:-1.3}"

# Poll for tx inclusion instead of a fixed sleep — a fixed delay is either too short under
# network congestion (silent failure below) or wastes time when the chain is fast.
wait_for_tx() {
  local txhash="$1"
  local elapsed=0
  while [ "$elapsed" -lt "$POLL_TIMEOUT" ]; do
    if result=$($BINARY q tx "$txhash" --chain-id "$CHAIN_ID" --node "$NODE" -o json 2>/dev/null); then
      echo "$result"
      return 0
    fi
    sleep "$POLL_INTERVAL"
    elapsed=$((elapsed + POLL_INTERVAL))
  done
  echo "ERROR: tx $txhash not found on chain after ${POLL_TIMEOUT}s" >&2
  return 1
}

# Check a tx's result code explicitly — a nonzero code means the tx landed in a block but
# FAILED (e.g. out of gas, contract panic on instantiate) and must not be treated as success
# just because a txhash and a block existed.
assert_tx_success() {
  local tx_json="$1"
  local label="$2"
  local code
  code=$(echo "$tx_json" | jq -r '.code // 0')
  if [ "$code" != "0" ]; then
    local raw_log
    raw_log=$(echo "$tx_json" | jq -r '.raw_log // "no raw_log"')
    echo "ERROR: $label failed on-chain (code=$code): $raw_log" >&2
    exit 1
  fi
}

echo "== store =="
STORE_TX=$($BINARY tx wasm store "$WASM_PATH" --from "$WALLET_ID" \
  --gas auto --gas-adjustment "$GAS_ADJ" --gas-prices "$GAS_PRICE" \
  --chain-id "$CHAIN_ID" --node "$NODE" --yes -o json | jq -r '.txhash')
[ -n "$STORE_TX" ] && [ "$STORE_TX" != "null" ] || { echo "ERROR: store tx did not return a txhash" >&2; exit 1; }
STORE_RESULT=$(wait_for_tx "$STORE_TX")
assert_tx_success "$STORE_RESULT" "store"
CODE_ID=$(echo "$STORE_RESULT" | jq -r '.events[] | select(.type=="store_code") | .attributes[] | select(.key=="code_id") | .value')
[ -n "$CODE_ID" ] && [ "$CODE_ID" != "null" ] || { echo "ERROR: could not extract code_id from store tx" >&2; exit 1; }
echo "code_id=$CODE_ID tx=$STORE_TX"

echo "== instantiate =="
WALLET_ADDRESS=$($BINARY keys show "$WALLET_ID" -a)
ADMIN_ARG="${CONTRACT_ADMIN:-$WALLET_ADDRESS}"
INST_TX=$($BINARY tx wasm instantiate "$CODE_ID" "$INIT_MSG" --label "$LABEL" \
  --from "$WALLET_ID" --admin "$ADMIN_ARG" \
  --gas auto --gas-adjustment "$GAS_ADJ" --gas-prices "$GAS_PRICE" \
  --chain-id "$CHAIN_ID" --node "$NODE" --yes -o json | jq -r '.txhash')
[ -n "$INST_TX" ] && [ "$INST_TX" != "null" ] || { echo "ERROR: instantiate tx did not return a txhash" >&2; exit 1; }
INST_RESULT=$(wait_for_tx "$INST_TX")
assert_tx_success "$INST_RESULT" "instantiate"
CONTRACT_ADDRESS=$(echo "$INST_RESULT" | jq -r '.events[] | select(.type=="instantiate") | .attributes[] | select(.key=="_contract_address") | .value' | head -n1)
[ -n "$CONTRACT_ADDRESS" ] && [ "$CONTRACT_ADDRESS" != "null" ] || { echo "ERROR: could not extract contract_address from instantiate tx" >&2; exit 1; }
echo "contract_address=$CONTRACT_ADDRESS tx=$INST_TX admin=$ADMIN_ARG"

if [ -n "$SMOKE_EXECUTE_MSG" ]; then
  echo "== smoke execute =="
  EXEC_TX=$($BINARY tx wasm execute "$CONTRACT_ADDRESS" "$SMOKE_EXECUTE_MSG" --from "$WALLET_ID" \
    --gas auto --gas-adjustment "$GAS_ADJ" --gas-prices "$GAS_PRICE" \
    --chain-id "$CHAIN_ID" --node "$NODE" --yes -o json | jq -r '.txhash')
  EXEC_RESULT=$(wait_for_tx "$EXEC_TX")
  assert_tx_success "$EXEC_RESULT" "smoke execute"
  echo "smoke execute OK, tx=$EXEC_TX"
else
  echo "== smoke execute SKIPPED (SMOKE_EXECUTE_MSG not set) =="
fi

if [ -n "$SMOKE_QUERY_MSG" ]; then
  echo "== query verify =="
  QUERY_RESULT=$($BINARY q wasm contract-state smart "$CONTRACT_ADDRESS" "$SMOKE_QUERY_MSG" \
    --chain-id "$CHAIN_ID" --node "$NODE" -o json)
  echo "query result: $QUERY_RESULT"
else
  echo "== query verify SKIPPED (SMOKE_QUERY_MSG not set) =="
fi

echo "== done =="
echo "CODE_ID=$CODE_ID"
echo "CONTRACT_ADDRESS=$CONTRACT_ADDRESS"
echo "ADMIN=$ADMIN_ARG"
