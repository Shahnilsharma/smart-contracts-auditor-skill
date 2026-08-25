# Hardhat 3 testing pattern (viem + node:test — current recommended default)

Hardhat 3 is production-ready; the recommended new-project setup is `npx hardhat --init` -> "TypeScript Hardhat project using Node Test Runner and Viem". Use the legacy Mocha+ethers setup only if the user's existing repo already uses it — don't migrate mid-task without asking.

## Install (if adding to an existing project)
```bash
npm add --save-dev @nomicfoundation/hardhat-viem @nomicfoundation/hardhat-viem-assertions \
  @nomicfoundation/hardhat-node-test-runner @nomicfoundation/hardhat-network-helpers viem
```

## Deploy + interact pattern
```ts
import { network } from "hardhat";
const { viem } = await network.connect(); // or network.connect("sepolia")
const vault = await viem.deployContract("Vault", [initialParam]);
await vault.write.deposit([amount], { account: userAddress });
const balance = await vault.read.balanceOf([userAddress]);
```

## Fixtures — fast, isolated state
```ts
import { loadFixture } from "@nomicfoundation/hardhat-toolbox-viem/network-helpers";
const deploy = async () => ({ vault: await hre.viem.deployContract("Vault", [param]) });
// first call runs the fixture; subsequent calls snapshot-restore instead of re-deploying
const { vault } = await loadFixture(deploy);
```

## Role-based sequential QA runner (mirrors the Foundry handler scenarios, against a live node)
```ts
import { network } from "hardhat";

const ROLES = ["admin", "user1", "user2", "attacker"] as const;

async function run() {
  const { viem } = await network.connect("sepolia"); // or local for CI
  const wallets = await getWalletsForRoles(ROLES); // see scripts/wallet_setup.md — ask user first
  const results = [];
  for (const role of ROLES) {
    results.push(await scenarioFor(role, viem, wallets[role]));
  }
  await finalInvariantCheck(viem, results);
  printReport(results);
}
```
Each `scenarioFor` runs sequentially (not parallel, since later roles may depend on earlier roles' on-chain state): happy path -> permission-denied attempt (must revert) -> boundary amount -> replay/idempotency attempt (must revert/no-op) -> query/read verify. Log every tx hash + gas used — feeds directly into the audit report as QA evidence.

## Time/block manipulation, snapshots, impersonation
`hardhat-network-helpers`: `time.increase()`, `mine()`, `takeSnapshot()`/`restore()`, `impersonateAccount()` — use for vesting/cooldown/auction scenarios and for testing behavior "as" a specific address without its key.

## Assertions
`hardhat-viem-assertions` plugin adds `viem.assertions` helpers for revert-reason and event-emission checks in a viem-typed way (`assertions.revertWithCustomError`, `assertions.emitWithArgs`, etc. — confirm exact method names against current plugin docs, this is a fast-moving area).
