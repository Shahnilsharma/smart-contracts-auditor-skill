---
name: evm-defi-architect
description: Full-stack Solidity/EVM smart contract architect. Use any time the user wants to design, code, test, audit, or deploy a Solidity smart contract or DeFi protocol on Ethereum or any EVM chain — mapping real-world DeFi mechanics (lending, AMMs, vaults, staking, vesting, DAOs) into contract architecture, writing production Solidity, generating Foundry (fuzz+invariant) and Hardhat 3 (viem+node:test) QA suites with role-based wallets, running agency-grade audits (threat modeling, Slither/Mythril/Echidna, OWASP checklist, economic review, fix-review) and deploying via forge script/cast. Defaults to Ethereum mainnet/Sepolia, accepts any EVM chain via a docs URL or .md param. Trigger on "solidity", "smart contract", "defi protocol", "audit my contract", "foundry", "hardhat", "deploy on an EVM chain", "fuzz test", "invariant test", even without "solidity" named if there's EVM-specific evidence (`.sol`, forge/hardhat). Say "with a team"/"multiagent" for multi-agent mode.
---

# EVM DeFi Architect

Pipeline: scope+threat model -> architecture -> code -> QA (Foundry fuzz/invariant + Hardhat viem/node:test) -> static analysis -> audit -> fix-review -> deploy -> monitoring/IR. Output is always **code + audit report**. Wallets are **asked each time** (cast encrypted keystore vs private key/mnemonic env vs hardware). Testnet is default; mainnet only on explicit request.

Read `references/agency-audit-methodology.md` once per engagement — it's the phase-by-phase methodology modeled on real firms (Trail of Bits, OpenZeppelin, Spearbit/Cantina, Certora, Code4rena/Sherlock judging standards), and every step below maps to a phase in it.

## 0. Resolve target chain (every run)

**Chain-evidence rule (check this first, especially if `cosmwasm-defi-architect` and/or `solana-defi-architect` might also be installed):** overlapping trigger words ("smart contract", "defi protocol", "audit my contract") mean a bare request like that could match any of the three sibling skills in this suite. Before proceeding, look for actual chain evidence: a `.sol` file extension, Solidity syntax (`pragma solidity`, `contract X {`), an explicit chain name (Ethereum/an EVM L2), or `forge`/`hardhat`/`cast` mentioned. If evidence points to CosmWasm (`.rs` with `cosmwasm_std`/`cw-storage-plus` imports, "CosmWasm"/"ZigChain"/"Cosmos" named) or Solana (`.rs` with `anchor_lang`/`solana_program` imports, "Anchor"/"Solana"/"PDA"/"CPI" named) instead, defer to that sibling skill rather than running this one on the wrong chain. If there's genuinely no evidence either way (a fully generic "audit my contract" with no attachment or chain name), ask which chain before doing anything else — don't guess and don't run all three.

Default: **Ethereum**, mainnet + **Sepolia** testnet. Params in `references/ethereum-chain-defaults.md`.

If user gives `--chain-docs <url>` or `<file.md>`, or names another EVM chain (Base, Arbitrum, Polygon, BSC, Zig-EVM, etc.): web_fetch the docs to pull chain ID, RPC, native gas token, block explorer + verify API, average gas price, any EVM-version quirks (e.g. no Cancun opcodes on some L2s, different `block.basefee` behavior). Always confirm resolved chain-id, RPC, explorer, gas token before writing code.

**Where to write the chain-defaults snapshot** — this matters, don't default to writing inside this skill's own folder: an installed skill (via `.skill` upload, `/mnt/skills/user/`, `.claude/skills/`, `.agents/skills/`) is typically **read-only**, and even where it isn't, mutating an installed skill's files silently breaks the dist↔source parity this suite's `check_dist_matches_source.sh` checks for. Write the snapshot into the **current project's workspace** instead (e.g. `./chain-notes/<chain-name>-defaults.md` in whatever directory you're actually working in) — never into `references/` inside this skill's own installed location. The one exception: if you can tell you're working *inside this suite's own source repo* (this file's directory has sibling `multi-agent/`, `LICENSE`, `check_dist_matches_source.sh` at the repo root — i.e. you're extending the suite itself, not using an installed copy of it), then writing into `references/<chain-name>.md` there is fine and is how a maintainer would add a new default chain profile. If neither location is writable, just hold the snapshot in-session and restate it if needed later.

## 0.5 Environment check (do this before claiming any tool ran)

Before writing code, and again before any QA/static-analysis/deploy step, check what's actually available in the current execution environment — don't assume `forge`/`cast`/`anvil`/`slither`/`myth`/network access exist just because the skill tells you to use them:
- `command -v forge`, `command -v cast`, `command -v anvil`, `command -v slither`, `command -v myth` — check each before the step that needs it.
- A quick reachability check on the configured RPC endpoint before any live-network step (QA runner against testnet, deploy).

If a required tool or network access is unavailable (common in a sandboxed chat context with no shell/network, or an agent without code execution): still write the code/tests/scripts — that's still valuable — but **do not claim they were run**. Label every test/scan result explicitly as one of: `RAN` (with the real output attached) or `NOT EXECUTED — <tool> unavailable in this environment; run locally with: <exact command>`. Mirror `scripts/deploy.md`'s own honest pattern of naming a skipped step rather than implying it happened. This directly matters for the Phase 6.5 validation gate in `references/agency-audit-methodology.md` — a finding claimed as validated by an executed PoC that was never actually run is exactly the "PoC pollution" failure mode that gate exists to prevent; if you can't execute it, downgrade the finding per that gate's own instructions rather than reporting it as confirmed.

## 1. Version check

Confirm target `pragma solidity` version and EVM version (`--evm-version` in foundry.toml/hardhat.config, e.g. cancun/prague), OpenZeppelin Contracts version in use. If reusing/extending existing code, diff against current OZ/Solidity release notes for breaking changes (e.g. custom errors vs require-strings eras, transient storage opcodes, `unchecked` semantics) before writing new code that depends on them.

## 2. Scope & threat model (Phase 0-1 of the audit methodology — do this before architecture)

Before designing/reviewing anything: write down scope (which contracts, which commit, what's explicitly out of scope — e.g. non-standard/weird ERC-20 behavior unless a token is named as supported, USDT always treated as in-scope), assets at risk, and trust assumptions (which roles are assumed honest by design). Then build a short threat model: actors/trust boundaries, money-flow diagram, and a **risk matrix** (impact × likelihood → severity, not impact alone). Rate the protocol's **key-compromise resilience** explicitly: single EOA (weakest) < multisig < multisig+timelock < immutable (strongest) — flag anything below multisig+timelock as a finding for any contract holding meaningful value, not just a suggestion. Full detail in `references/agency-audit-methodology.md` Phases 0-1.

## 3. Architecture pass (map real world -> contract design)

Interview if not given: protocol type (lending/AMM/vault/staking/vesting/DAO/perp/other), actors/roles, asset flows (ERC-20/721/1155, native ETH), oracle dependency, admin/upgrade model (proxy? timelock? multisig?), fee model. Produce an architecture doc:
- State layout (storage slots, packing opportunities)
- Function surface: constructor/initializer, external/public write, view/pure, admin-only
- Roles & permissions matrix (Ownable/AccessControl roles, who can call what) — cross-reference the key-compromise ladder from step 2
- Money flow — deposits, withdrawals, fees, liquidations, flash-loan surface
- Edge cases: reentrancy via external calls/callbacks (ERC-777, ERC-721 `onERC721Received`, ERC-1155 batch callbacks), integer edge values, division rounding direction, oracle staleness/manipulation (spot price vs TWAP), flash-loan-funded governance/price attacks, front-running/MEV/sandwich exposure, signature replay (missing nonce/domain separator/chainId in EIP-712), delegatecall/proxy storage collisions, self-destruct/selfdestruct removal (post-Cancun `SELFDESTRUCT` semantics changed — don't rely on it for fund recovery), unbounded loops over dynamic arrays (gas DoS), ERC-20 non-standard return values (missing bool return, fee-on-transfer, rebasing tokens), zero-address/zero-amount inputs, paused/emergency-state handling.

Produce an architecture/flow diagram when it clarifies more than prose (Claude: use the Visualizer; other agents: emit a Mermaid diagram inline or as an SVG/image file — see `../../PORTABILITY.md` at the suite root if present, otherwise this parenthetical is the complete guidance).

## 4. Write the contract

Foundry project layout (`forge init`). Rules — see `references/coding-standards.md` for full list:
- Custom errors, not require-strings (gas + clarity).
- Checks-effects-interactions; `ReentrancyGuard` on any function with external calls + state writes.
- `SafeERC20` for token transfers (handles non-standard/no-return tokens); never assume `transfer`/`transferFrom` returns `true` or reverts.
- No raw `tx.origin` auth. No `block.timestamp`/`blockhash` as sole randomness source.
- Explicit access control on every privileged function (`Ownable`, `AccessControl`, or custom modifier) — never rely on obscurity.
- Storage-safe upgradeable patterns if proxy-based (`@openzeppelin/contracts-upgradeable`, storage gaps, `_disableInitializers` in constructor).

## 5. QA — Foundry + Hardhat (always both; Phase 4 of the methodology)

**Foundry** (`references/testing-foundry.md`):
- Unit tests per function branch (happy + revert cases, `vm.expectRevert`).
- Fuzz tests (`testFuzz_` prefix, `vm.assume`/`bound()`) for every function taking numeric/address input.
- Invariant tests (`invariant_` prefix + handler contract pattern with ghost variables) targeting the specific properties identified in step 2's risk matrix (solvency, no-value-creation, access-control invariants), not just generic fuzzing — e.g. `totalSupply == sum(balances)`.
- Optional: `--symbolic` (`check*`/`prove*` functions) for arithmetic-heavy logic where a bounded proof adds value — MVP feature, treat PASS as "no counterexample found under current bounds", not a formal proof.
- Run: `forge test -vvv`, `forge coverage`, `forge snapshot` for gas regression tracking.

**Hardhat 3** (`references/testing-hardhat.md`):
- viem-based toolbox + Node.js `node:test` runner (Hardhat 3's current recommended default — not the legacy Mocha/ethers setup unless the user's existing repo already uses it).
- `hardhat-network-helpers` for time/block manipulation, snapshots, impersonation.
- `loadFixture` pattern for fast, isolated test state.
- Role-based sequential scenario runner mirroring the Foundry handler scenarios but against a live local/testnet node — same pattern as a CosmJS QA runner: connect each role's wallet, run happy/permission-denied/boundary/replay cases sequentially, then a final invariant check.

## 6. Static analysis (Phase 2 of the methodology — baseline, not the finish line)

- **Slither** (`slither .` or `slither --foundry-out-directory out .`) — fast, run every time, CI-friendly. Triage every finding (true positive / false positive / accepted risk), don't just paste raw output.
- **Mythril** (`myth analyze <file> --execution-timeout 300`) — deeper symbolic execution, slower; run on core money-handling contracts for a release/audit-grade pass, not every iteration.
- **Echidna** — property-based fuzzing alternative/complement to Foundry invariants, useful for cross-checking invariant coverage on complex state machines.
- **Formal verification** (Certora Prover, Halmos, or Solidity's built-in SMTChecker for a fast first pass) — recommend, don't necessarily execute yourself, for high-value protocols where a small number of core invariants (solvency, conservation) must be provably true. See `references/agency-audit-methodology.md` Phase 5.

See `references/static-analysis.md` for commands and triage guidance. Get automated tooling to a clean/fully-triaged state before spending manual-review time — tools reliably catch a large share of severe, easy-to-exploit bugs; manual review is for what they structurally can't reason about (business logic, economics, cross-contract composition).

## 7. Audit pass (Phases 3, 6, 7 of the methodology)

Run `references/audit-checklist.md` (OWASP Smart Contract Top 10-based + DeFi-specific items) against the final code, informed by the static-analysis findings (step 6), the threat model/risk matrix (step 2), and the QA results (step 5). Also run the **economic/game-theoretic review** (Phase 6): MEV exposure, flash-loan-funded manipulation, cost-of-attack vs. value-at-risk, centralization/collusion risk rated separately per the key-compromise ladder.

Report format (Phase 7): scope & methodology recap, executive summary, then every finding as `[SEVERITY] Title — file:line — scenario — fix`, where severity comes from the impact×likelihood risk matrix (state the likelihood reasoning, not just impact), plus an explicit scope/assumptions section listing what was excluded. Include the **coverage traceability matrix** from the end of `references/audit-checklist.md` (mapping this suite's checks to OWASP Smart Contract Top 10 2026, SC01-SC10) filled in with a checked/not-applicable/finding-filed status per row — this is what lets a reader verify completeness against a named standard rather than trust a bare "we checked everything" claim. Never mark something safe without stating what was actually checked (e.g. "checked: all external token transfers use SafeERC20, no raw .transfer/.call token pattern found").

**Formatting**: for a quick in-chat findings summary, plain markdown is fine. If the user wants a standalone deliverable (a report, a PDF, a Word doc, something to send to a client/investor, "make it look professional"), read `references/report-template.md` — title page, document structure, severity color conventions (Critical=dark red, High=red, Medium=orange, Low=amber, Informational=blue/gray), and concrete `docx` skill usage notes. Don't improvise a report layout when this reference already specifies one.

**Audit-only mode**: if the user only wants an audit of existing code with no build/test/deploy step, don't run steps 3-5 and 9-11 (architecture design, code generation, deploy) — run only steps 2 (scope/threat model), 6 (static analysis), and this step (7), then offer step 8 (fix review) once findings are patched. This is the same rigor as a full pass, scoped down to what was asked. If a separate `solidity-auditor` skill happens to be installed alongside this one, it may be a lighter-weight option for a quick single-file review with less ceremony — mention it as an alternative if installed, but don't depend on it existing.

## 8. Fix review / re-audit cycle (Phase 8 — offer after the team patches findings)

Once the user has patched reported findings, offer (don't wait to be asked) a re-review pass: for each patch, check (a) does it actually close the reported issue, and (b) did the fix introduce a new issue — patches written under time pressure are a disproportionate source of new bugs. Track status per finding: Unresolved / Acknowledged-won't-fix / Partially resolved / Resolved / Resolved-but-introduced-new-issue.

## 9. Wallets — ask every time

Never assume. Ask:
1. **Encrypted keystore via `cast wallet import <name> --interactive`** + `--account <name>` on scripts — Foundry's recommended method for anything beyond local Anvil, key never touches disk unencrypted or shell history.
2. **Private key / mnemonic env var** (`.env`, gitignored) — acceptable for local Anvil only; flag as unsafe for testnet/mainnet real funds.
3. **Hardware wallet** (`--ledger` / `--trezor` flags on `forge script`/`cast send`) for mainnet fund-controlling deploys.
4. **Anvil default accounts** (deterministic `test test test ... junk` mnemonic, 10 pre-funded accounts) — local-only, publicly known, never for real funds.

`scripts/wallet_setup.md` documents all four; ask which before generating role env vars or running any broadcast.

## 10. Deploy + deployment verification (Phase 9)

Default: **Sepolia testnet** (or the target chain's equivalent testnet if a custom chain was resolved in step 0). Mainnet only on explicit request — confirm once before `--broadcast`. Use `forge script script/Deploy.s.sol --rpc-url <rpc> --account <keystore-name> --broadcast --verify` — verification requires the target chain's explorer API key (Etherscan-family `--etherscan-api-key`, or chain-specific verifier via `--verifier`). See `scripts/deploy.md`.

After deploying: verify the deployed bytecode matches the audited source exactly (compiler version, optimizer settings, constructor args all recorded) — "post-audit drift" from deploying a different build than what was reviewed is a real, recurring failure mode. `forge verify-contract`'s bytecode match against the compiled source is the mechanical check for this.

## 11. Post-deployment: monitoring & incident response (Phase 10 — offer as a deliverable, not an afterthought)

For anything holding meaningful value, offer: alert-threshold suggestions derived from step 2's risk matrix (large single-tx withdrawals, oracle deviation beyond X%, unexpected admin-function calls), and a short incident-response starter doc (who can pause/what's the decision tree/communication plan), tied directly to the key-compromise resilience rating from step 2 rather than treated as a separate question.

## 12. Team mode (multi-agent) — if requested

If the user asks for team/multiagent mode ("with a team", "multiagent", "agent team", "use N agents"), don't run steps 0-11 solo. Check whether `../../multi-agent/` exists relative to this file (true only when running inside the full suite repo, not when this skill was installed standalone via `.skill`/`/mnt/skills/user/`/`.claude/skills/`/`.agents/skills/`) — if it does, follow `../../multi-agent/README.md` and `../../multi-agent/claude-code-agent-teams/team-lead-playbook.md`. **If it doesn't exist** (the normal case for an installed skill), use `references/team-mode.md` instead — a self-contained version of the same roles/spawn-pattern/fallback with no dependency on files outside this skill's own folder. Either way, say plainly which mode you're actually running (real Agent Teams vs. sequential emulation) rather than assuming.

## Output

Every run produces: scope/threat-model doc (with risk matrix), architecture doc, contract source, Foundry test suite (unit+fuzz+invariant), Hardhat QA runner + results, Slither/Mythril triage notes, audit report (with economic-review section and explicit scope/assumptions), deploy script/log + deployment-verification note. Save to the project output directory (Claude: `/mnt/user-data/outputs/<project-name>/`, present with `present_files`; other agents: your equivalent workspace/output path — full detail in `../../PORTABILITY.md` at the suite root if present). Offer the fix-review and monitoring/IR follow-ups explicitly rather than assuming the user knows to ask.
