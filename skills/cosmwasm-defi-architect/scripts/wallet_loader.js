// wallet_loader.js — role-based wallet resolution for the QA runner.
// Ask the user which mode BEFORE running: mnemonic-per-role or binary/system keyring.
// Set WALLET_MODE=mnemonic|keyring and CHAIN_PREFIX (e.g. "zig") before invoking.
//
// IMPORTANT ARCHITECTURE NOTE: these two modes are NOT symmetric, and this file does not
// pretend otherwise. Mnemonic mode returns a real in-process CosmJS OfflineSigner — the QA
// runner (qa-runner.md) can call SigningCosmWasmClient.connectWithSigner(...) with it directly.
// Keyring mode CANNOT do this: a system/binary keyring (zigchaind's own keyring-backend)
// deliberately keeps the private key material inside its own process and does not export it
// to arbitrary callers — that's the security property of using a keyring in the first place.
// So for keyring-mode roles, the QA runner must shell out to `zigchaind tx ...` for every
// transaction instead of building an in-process signer. Use `execKeyringTx()` below for that,
// not `getWalletForRole()`, which only supports mnemonic mode.

import { DirectSecp256k1HdWallet } from "@cosmjs/proto-signing";
import { execFileSync } from "node:child_process";

const PREFIX = process.env.CHAIN_PREFIX || "zig";
const MODE = process.env.WALLET_MODE; // "mnemonic" | "keyring"
const BINARY = process.env.CHAIN_BINARY || "zigchaind";

// Role names are used as CLI arguments and as keyring key names — allowlist strictly to
// prevent argument-injection-style abuse even though execFileSync (below) does not invoke a
// shell and so is not vulnerable to classic shell-metacharacter injection the way the
// previous execSync(`... ${keyName} ...`) template-string version was.
const ROLE_NAME_RE = /^[a-zA-Z0-9_-]{1,64}$/;

function assertValidRoleName(role) {
  if (!ROLE_NAME_RE.test(role)) {
    throw new Error(
      `Invalid role name "${role}" — must match ${ROLE_NAME_RE} (alphanumeric, underscore, hyphen only).`
    );
  }
}

/**
 * Mnemonic mode ONLY. Returns a real in-process CosmJS OfflineSigner.
 * For keyring mode, use execKeyringTx() instead — see the architecture note above.
 * @param {string} role e.g. "admin", "user1", "attacker"
 * @returns {Promise<import("@cosmjs/proto-signing").OfflineSigner>}
 */
export async function getWalletForRole(role) {
  assertValidRoleName(role);

  if (!MODE) {
    throw new Error(
      "WALLET_MODE not set. Ask the user: mnemonic-per-role or binary/system keyring, then set WALLET_MODE."
    );
  }

  if (MODE === "mnemonic") {
    const envKey = `${role.toUpperCase()}_MNEMONIC`;
    const mnemonic = process.env[envKey];
    if (!mnemonic) {
      throw new Error(`Missing ${envKey} in environment (.env, not committed).`);
    }
    return DirectSecp256k1HdWallet.fromMnemonic(mnemonic, { prefix: PREFIX });
  }

  if (MODE === "keyring") {
    throw new Error(
      `WALLET_MODE=keyring cannot produce an in-process OfflineSigner for role "${role}" — ` +
        `a system keyring does not export private key material (that is the point of using one). ` +
        `Use execKeyringTx(role, txArgs) for keyring-mode roles instead of getWalletForRole(); ` +
        `it shells out to ${BINARY} tx directly, matching how scripts/deploy.sh already works.`
    );
  }

  throw new Error(`Unknown WALLET_MODE: ${MODE}`);
}

/**
 * Keyring mode ONLY. Confirms a keyring entry exists for `role`, then executes a transaction
 * via the chain binary directly (no in-process signer — see architecture note above).
 * Uses execFileSync with an argument array (never a template-string shell command), so role
 * names and message content cannot break out of their argument position even if they contained
 * shell metacharacters.
 *
 * @param {string} role keyring key name, e.g. "admin"
 * @param {string[]} txArgs full args after the binary, e.g.
 *   ["tx", "wasm", "execute", contractAddress, msgJson, "--from", role, "--chain-id", chainId,
 *    "--node", node, "--gas", "auto", "--gas-adjustment", "1.3", "--yes", "-o", "json"]
 * @returns {object} parsed JSON tx response
 */
export function execKeyringTx(role, txArgs) {
  assertValidRoleName(role);
  if (!Array.isArray(txArgs) || txArgs.length === 0) {
    throw new Error("execKeyringTx: txArgs must be a non-empty array of CLI arguments.");
  }

  // Confirm the keyring entry exists before attempting a transaction with it.
  try {
    execFileSync(BINARY, ["keys", "show", role, "--output", "json"], { stdio: "pipe" });
  } catch {
    throw new Error(`No keyring entry named "${role}". Create with: ${BINARY} keys add ${role}`);
  }

  const out = execFileSync(BINARY, txArgs, { stdio: "pipe" }).toString();
  let parsed;
  try {
    parsed = JSON.parse(out);
  } catch {
    throw new Error(`${BINARY} did not return valid JSON — raw output: ${out.slice(0, 500)}`);
  }
  if (parsed.code && parsed.code !== 0) {
    throw new Error(`Transaction failed (code ${parsed.code}): ${parsed.raw_log || "no raw_log"}`);
  }
  return parsed;
}
