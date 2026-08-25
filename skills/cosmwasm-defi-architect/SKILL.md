---
name: cosmwasm-defi-architect
description: Full-stack CosmWasm smart contract architect for Cosmos-based chains. Use any time the user wants to design, code, test, audit, or deploy a CosmWasm/DeFi smart contract system — mapping real-world DeFi mechanics (lending, staking, AMMs, vaults, oracles, vesting, DAOs) into contract architecture, writing production Rust CosmWasm code, generating Rust (cw-multitest) + Node (CosmJS) QA suites with role-based wallets, running agency-grade audits (threat modeling, economic review, fix-review cycle), and deploying via CLI. Defaults to ZIGChain, accepts any Cosmos chain via a docs URL or .md file param. Trigger on "cosmwasm", "smart contract", "defi protocol", "audit my contract", "deploy on zigchain/cosmos", "battle test", "qa runner", even without "CosmWasm" named explicitly if it's on-chain financial logic on a Cosmos chain. Say "with a team"/"multiagent" for parallel multi-agent mode instead of the solo pipeline.
---

# CosmWasm DeFi Architect

Pipeline: scope+threat model -> architecture -> code -> QA -> audit -> fix-review -> deploy -> monitoring/IR. Output is always **code + audit report**, tests are always **Rust (cw-multitest) + Node (CosmJS)**, wallets are **asked each time** (mnemonic vs binary keyring).

Read `references/agency-audit-methodology.md` once per engagement — it's the phase-by-phase methodology modeled on real firms (Trail of Bits, OpenZeppelin, Spearbit/Cantina, Certora, Code4rena/Sherlock judging standards), chain-agnostic; every step below maps to a phase in it.

## 0. Resolve target chain (do this first, every run)

**Chain-evidence rule (check this first, especially if `evm-defi-architect` and/or `solana-defi-architect` might also be installed):** overlapping trigger words ("smart contract", "defi protocol", "audit my contract") mean a bare request like that could match any of the three sibling skills in this suite. Before proceeding, look for actual chain evidence: `.rs` with `cosmwasm_std`/`cw-storage-plus` imports, or "CosmWasm"/"ZigChain"/"Cosmos" named explicitly. If evidence points to EVM (`.sol` extension, `pragma solidity`, "Solidity"/an EVM chain named, `forge`/`hardhat`/`cast` mentioned) or Solana (`.rs` with `anchor_lang`/`solana_program` imports, "Anchor"/"Solana"/"PDA"/"CPI" named) instead, defer to that sibling skill rather than running this one on the wrong chain. If there's genuinely no evidence either way, ask which chain before doing anything else — don't guess and don't run all three.

Default chain: **ZIGChain**. Params in `references/zigchain.md` — read it, don't guess.

If user gives `--chain-docs <url>` or `--chain-docs <file.md>`, or says "use chain X docs", switch target:
- URL: web_fetch it (and linked builder/cosmwasm pages) to pull: chain-id (mainnet/testnet), RPC/LCD endpoints, denom, gas price, CosmWasm module version, wallet prefix, any whitelisting/permission rules.
- .md file: read it directly for the same fields.
- **Where to write the snapshot** — don't default to writing inside this skill's own folder: an installed skill (`.skill` upload, `/mnt/skills/user/`, `.claude/skills/`, `.agents/skills/`) is typically **read-only**, and even where it isn't, mutating it silently breaks the dist↔source parity `check_dist_matches_source.sh` checks for. Write the snapshot into the **current project's workspace** instead (e.g. `./chain-notes/<chain-name>-defaults.md`), not into `references/` inside this skill's installed location. Exception: if you can tell you're working *inside this suite's own source repo* (sibling `multi-agent/`, `LICENSE`, `check_dist_matches_source.sh` at the repo root), writing into `references/<chain-name>.md` there is fine — that's how a maintainer adds a new default chain profile. If neither is writable, hold the snapshot in-session.

Always confirm resolved: chain-id, RPC, denom, gas price, cw version, testnet-vs-mainnet before writing code.

## 0.5 Environment check (do this before claiming any tool ran)

Before writing code, and again before any QA/static-analysis/deploy step, check what's actually available in the current execution environment — don't assume `zigchaind`, `cargo`, or network access exist just because the skill tells you to use them:
- `command -v zigchaind`, `command -v cargo`, `command -v cargo-clippy`, `command -v cargo-audit`.
- A quick reachability check on the configured RPC endpoint before any live-network step (the Node QA runner against testnet, `scripts/deploy.sh`).

If a required tool or network access is unavailable (common in a sandboxed chat context with no shell/network, or an agent without code execution): still write the code/tests/scripts — that's still valuable — but **do not claim they were run**. Label every test/scan result explicitly as one of: `RAN` (with the real output attached) or `NOT EXECUTED — <tool> unavailable in this environment; run locally with: <exact command>`. Mirror `scripts/deploy.sh`'s own honest SKIPPED pattern (the smoke-execute/query-verify steps already do this when their env vars aren't set) — the same discipline applies here. This directly matters for the Phase 6.5 validation gate in `references/agency-audit-methodology.md` — a finding claimed as validated by an executed PoC that was never actually run is exactly the "PoC pollution" failure mode that gate exists to prevent; if you can't execute it, downgrade the finding per that gate's own instructions rather than reporting it as confirmed.

## 1. Version check (docs diff)

Before coding, fetch the current CosmWasm module page (and general CosmWasm/cw-std docs) for the target chain, note version. If a previous snapshot exists, diff old vs new API: renamed entry points, deprecated messages, changed gas/whitelisting rules, changed `cosmwasm-std` version. Report material changes to the user before writing code that depends on them.

## 2. Scope & threat model (Phase 0-1 of the audit methodology — do this before architecture)

Write down scope (which contracts, which commit, what's out of scope), assets at risk, and trust assumptions (which roles/multisig/DAO are assumed honest by design). Build a threat model: actors/trust boundaries, money-flow diagram, and a **risk matrix** (impact × likelihood → severity, not impact alone). Rate **key/admin-compromise resilience** explicitly: single key (weakest) < multisig < multisig+timelock/governance-gated < immutable (strongest) — flag anything below multisig+timelock as a finding for any contract holding meaningful value. Full detail in `references/agency-audit-methodology.md` Phases 0-1.

## 3. Architecture pass (map real world -> contract design)

Interview if not already given: protocol type (lending/AMM/vault/staking/vesting/DAO/synthetic/other), actors/roles, asset flows, oracle dependency, admin/upgrade model, fee model. Then produce an architecture doc covering:
- State model (storage layout, `cw-storage-plus` maps/items)
- Message set: `InstantiateMsg`, `ExecuteMsg`, `QueryMsg`, `MigrateMsg`
- Roles & permissions matrix (who can call what) — cross-reference the key-compromise ladder from step 2
- Money flow diagram (in words) — deposits, withdrawals, fees, liquidations
- Edge cases: zero-amount calls, rounding/truncation on division, reentrancy via `reply`/submessages, integer overflow (use `Uint128`/`Decimal` checked ops), price-oracle staleness/manipulation, front-running/sandwiching, insufficient funds, paused/emergency states, admin key compromise, migration data-shape mismatches, denom/IBC edge cases, duplicate/replay execution, unbounded loops over storage (gas griefing/DoS), slippage/minimum-out checks, rounding-in-favor-of-protocol invariants.

Produce an architecture/flow diagram when it clarifies more than prose (Claude: use the Visualizer; other agents: emit a Mermaid diagram inline or as an SVG/image file — see `../../PORTABILITY.md` at the suite root if present, otherwise this parenthetical is the complete guidance).

## 4. Write the contract

Standard CosmWasm layout (`cargo generate --git https://github.com/CosmWasm/cw-template.git`). Use checked arithmetic everywhere (`Uint128::checked_add` etc, never raw `+`/`-` on token amounts). Emit events on every state-changing action. Guard every execute branch with explicit sender checks. No `unwrap()`/`expect()` on user-controlled input — always return `ContractError`.

Follow `references/coding-standards.md` for CosmWasm-specific patterns (checked math, submessage reply safety, migration guards, storage key namespacing).

## 5. QA runner (Rust + Node, role-based) — Phase 4 of the methodology

Always generate **both**:
- `tests/` Rust integration tests using `cw-multitest` — one test module per execute branch, plus adversarial cases (wrong sender, double-spend, reentrancy attempt, overflow input, zero/negative-equivalent amounts, paused-state calls).
- `qa/` Node QA runner using CosmJS — sequential, role-based, runs against a live testnet/local node. See `references/qa-runner.md` for the harness pattern and `scripts/wallet_loader.js` for wallet resolution.

Target the specific properties identified in step 2's risk matrix (solvency, no-value-creation, access-control invariants), not just generic happy-path testing.

Before running the Node runner, **always ask the user** (don't assume): mnemonic-per-role (paste/env var) or binary/system keyring (`zigchaind keys` / OS keyring) — see step 8.

QA runner must cover, sequentially, per role: happy path, permission-denied path, edge/boundary amounts, replay/idempotency, and a final invariant check (contract balance == sum of internal ledger).

## 6. Static analysis (Phase 2 — baseline, not the finish line)

CosmWasm/Rust tooling is thinner than EVM's: run `cargo clippy --all-targets -- -D warnings` and `cargo audit` (dependency CVEs) as a baseline every time. Manually check for the patterns automated Rust tooling won't catch: unchecked arithmetic on `Uint128`/`Decimal`, missing sender checks, submessage `reply` trust issues — these carry into the manual checklist in step 7. Get automated tooling clean/triaged before spending manual-review time on things it would have caught.

## 7. Audit pass (Phases 3, 6, 7 of the methodology)

Run `references/audit-checklist.md` against the final code, informed by the threat model/risk matrix (step 2) and QA results (step 5). Also run the **economic/game-theoretic review** (Phase 6): oracle-manipulation cost vs. value-at-risk, flash-loan-style or same-block manipulation if the chain/ecosystem has composable money markets, governance/admin-key cost-of-attack, centralization risk rated separately per the key-compromise ladder.

Report format (Phase 7): scope & methodology recap, executive summary, then every finding as `[SEVERITY] Title — file/line/branch — scenario — fix`, where severity comes from the impact×likelihood risk matrix (state the likelihood reasoning, not just impact), plus an explicit scope/assumptions section. Include the **coverage traceability matrix** from the end of `references/audit-checklist.md` (mapping checks to chain-agnostic OWASP SC Top 10 2026 categories and real disclosed Oak Security wasmd findings) filled in per row — lets a reader verify completeness against named anchors rather than trust a bare claim. Never mark something safe without showing the check performed.

**Formatting**: for a quick in-chat findings summary, plain markdown is fine. If the user wants a standalone deliverable (a report, a PDF, a Word doc, something to send to a client/investor, "make it look professional"), read `references/report-template.md` — title page, document structure, severity color conventions (Critical=dark red, High=red, Medium=orange, Low=amber, Informational=blue/gray), and concrete `docx` skill usage notes. Don't improvise a report layout when this reference already specifies one.

## 8. Fix review / re-audit cycle (Phase 8 — offer after the team patches findings)

Once findings are patched, offer a re-review pass: does each patch actually close the reported issue, and did it introduce a new one (common under time pressure). Track status per finding: Unresolved / Acknowledged-won't-fix / Partially resolved / Resolved / Resolved-but-introduced-new-issue.

## 9. Wallets — ask every time

Never assume the wallet method. Ask:
1. Mnemonic per role (env vars `ROLE_MNEMONIC`, e.g. `ADMIN_MNEMONIC`, `USER1_MNEMONIC`) — never print mnemonics back, never log them, never write them to a committed file; use `.env` + `.gitignore`.
2. Binary/system keyring (`zigchaind keys add/show`, or OS keyring via CosmJS `DirectSecp256k1HdWallet` from keystore) — reference existing key names instead of raw secrets.

`scripts/wallet_loader.js` implements both paths behind one interface (`getWalletForRole(role)`).

## 10. Deploy + deployment verification

Default: **testnet**. Only deploy to mainnet if user explicitly says so (e.g. `--network mainnet` or "deploy to mainnet") — confirm once before broadcasting. Use `scripts/deploy.sh` (store -> instantiate -> execute smoke test -> query verify) with the resolved chain params from step 0. Whitelisting: ZIGChain restricts `store` to whitelisted addresses (`references/zigchain.md`) — check/remind user before store step.

After deploying: confirm the stored code's checksum/code-id matches the audited build (same commit, same `cosmwasm/workspace-optimizer` version/settings) — deploying a different build than what was reviewed silently invalidates the audit.

## 11. Post-deployment: monitoring & incident response (Phase 10)

For anything holding meaningful value, offer: alert-threshold suggestions derived from step 2's risk matrix (large single-tx withdrawals, oracle deviation, unexpected admin-message execution), and a short incident-response starter doc (who can pause/migrate, decision tree, communication plan) tied to the key-compromise resilience rating from step 2.

## 12. Team mode (multi-agent) — if requested

If the user asks for team/multiagent mode ("with a team", "multiagent", "agent team", "use N agents"), don't run steps 0-11 solo. Check whether `../../multi-agent/` exists relative to this file (true only inside the full suite repo, not for an installed standalone skill) — if it does, follow `../../multi-agent/README.md` and the playbook there. **If it doesn't exist** (the normal case for an installed skill), use `references/team-mode.md` instead — same roles/spawn-pattern/fallback, no dependency on files outside this skill's folder. Either way, say plainly which mode you're actually running.

## Output

Every run produces: scope/threat-model doc (with risk matrix), architecture doc, contract source, Rust test suite, Node QA runner + results, audit report (with economic-review section and explicit scope/assumptions), deploy script/log + deployment-verification note. Save all to the project output directory (Claude: `/mnt/user-data/outputs/<project-name>/`, present with `present_files`; other agents: your equivalent workspace/output path — full detail in `../../PORTABILITY.md` at the suite root if present). Offer the fix-review and monitoring/IR follow-ups explicitly.
