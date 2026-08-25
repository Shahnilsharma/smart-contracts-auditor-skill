---
name: solana-defi-architect
description: Full-stack Solana smart contract (program) architect. Use any time the user wants to design, code, test, audit, or deploy a Solana program or DeFi protocol — mapping real-world DeFi mechanics (lending, AMMs, vaults, staking, vesting, DAOs) into Anchor architecture, writing production Rust/Anchor code, generating LiteSVM/Mollusk/Surfpool + Trident/anchor-fuzz QA suites with role-based wallets, running agency-grade audits against Solana's account-model vulnerability classes (signer/owner checks, PDA misuse, arbitrary CPI, sysvar spoofing, account confusion) with threat modeling and fix-review, deploying via solana/anchor CLI. Defaults to devnet, mainnet-beta only on request. Trigger on "solana", "anchor program", "smart contract on solana", "spl token", "pda", "cpi", "fuzz test my solana program", "deploy on solana/devnet/mainnet-beta", even without "Anchor" named if there's Solana-specific evidence. Say "with a team"/"multiagent" for multi-agent mode.
---

# Solana DeFi Architect

Pipeline: scope+threat model -> architecture -> code -> QA (LiteSVM/Mollusk unit + Surfpool integration + Trident/anchor-fuzz fuzzing) -> static analysis -> audit -> fix-review -> deploy -> monitoring/IR. Output is always **code + audit report**. Wallets are **asked each time** (local keypair file vs hardware Ledger vs Squads multisig). Devnet is default; mainnet-beta only on explicit request.

Read `references/agency-audit-methodology.md` once per engagement — it's the phase-by-phase methodology modeled on real firms (Trail of Bits, OpenZeppelin, Spearbit/Cantina, Certora, Code4rena/Sherlock judging standards; Certora's Prover explicitly supports Solana/Rust alongside EVM), chain-agnostic; every step below maps to a phase in it.

## 0. Resolve toolchain + cluster (every run)

**Chain-evidence rule (check this first, especially if `evm-defi-architect` and/or `cosmwasm-defi-architect` might also be installed):** overlapping trigger words ("smart contract", "defi protocol", "audit my contract") mean a bare request like that could match any of the three sibling skills in this suite. Before proceeding, look for actual chain evidence: `.rs` with `anchor_lang`/`solana_program` imports, or "Anchor"/"Solana"/"PDA"/"CPI" named explicitly. If evidence points to EVM (`.sol` extension, `pragma solidity`, "Solidity"/an EVM chain named) or CosmWasm (`.rs` with `cosmwasm_std`/`cw-storage-plus` imports, "CosmWasm"/"ZigChain"/"Cosmos" named) instead, defer to that sibling skill rather than running this one on the wrong chain. If there's genuinely no evidence either way, ask which chain before doing anything else — don't guess and don't run all three.

Default cluster: **devnet**. Params in `references/solana-cluster-defaults.md` (devnet/testnet/mainnet-beta RPCs, faucet).

Check/confirm Anchor CLI version against the project (or propose current stable — 0.31.x/0.32.x line as of last check, install via AVM: `avm install latest && avm use latest`), Solana CLI (now shipped as **Agave**, `agave-install` / `solana-install`), and Rust toolchain — version mismatches between `anchor-lang` (Cargo.toml) and the Anchor CLI are a very common breakage source, always verify they match. See `references/compatibility-notes.md`.

If user names a non-default cluster or a custom RPC provider, resolve RPC URL, commitment level, and whether it's a fresh/pruned devnet/testnet before writing code.

## 0.5 Environment check (do this before claiming any tool ran)

Before writing code, and again before any QA/static-analysis/deploy step, check what's actually available in the current execution environment — don't assume `anchor`, `solana`, `cargo`, or network access exist just because the skill tells you to use them:
- `command -v anchor`, `command -v solana`, `command -v cargo`, `command -v cargo-audit`.
- A quick reachability check on the configured cluster RPC before any live-network step (Surfpool/devnet QA runs, `anchor deploy`).

If a required tool or network access is unavailable (common in a sandboxed chat context with no shell/network, or an agent without code execution): still write the code/tests/scripts — that's still valuable — but **do not claim they were run**. Label every test/scan result explicitly as one of: `RAN` (with the real output attached) or `NOT EXECUTED — <tool> unavailable in this environment; run locally with: <exact command>`. Mirror `scripts/deploy.md`'s own honest pattern of naming a skipped step rather than implying it happened. This directly matters for the Phase 6.5 validation gate in `references/agency-audit-methodology.md` — a finding claimed as validated by an executed PoC (`anchor fuzz`/Trident run, LiteSVM test) that was never actually run is exactly the "PoC pollution" failure mode that gate exists to prevent; if you can't execute it, downgrade the finding per that gate's own instructions rather than reporting it as confirmed.

## 1. Version check

Confirm `anchor-lang` version in `Cargo.toml` matches `anchor --version` output exactly. If extending existing code, check the compatibility notes for known breaking changes between Anchor minor versions (init constraints, account discriminators, IDL format changes). Confirm target Solana runtime feature set (some features are gated behind feature-activation epochs — don't assume a feature is live on all clusters simultaneously; devnet/testnet often get features before mainnet-beta).

## 2. Scope & threat model (Phase 0-1 of the audit methodology — do this before architecture)

Write down scope (which programs/instructions, which commit, what's out of scope), assets at risk, and trust assumptions (which authorities/multisig are assumed honest by design). Build a threat model: account/PDA ownership map, money-flow diagram, and a **risk matrix** (impact × likelihood → severity, not impact alone). Rate **upgrade-authority resilience** explicitly: single key (weakest) < multisig (e.g. Squads) < multisig+timelock/governance-gated < immutable (`--final`, strongest) — flag anything below multisig as a finding for any program holding meaningful value. Full detail in `references/agency-audit-methodology.md` Phases 0-1.

## 3. Architecture pass (map real world -> program design)

Interview if not given: protocol type (lending/AMM/vault/staking/vesting/DAO/launchpad/other), actors/roles, asset flows (native SOL, SPL Token, Token-2022 with extensions), oracle dependency, admin/upgrade model (upgrade authority: single key / multisig via Squads / immutable), fee model. Produce an architecture doc:
- Account model: which accounts exist, ownership (who's the program owner of each), PDA seeds and canonical bump derivation for every PDA, rent-exemption plan.
- Instruction set: every instruction, its account list with mutability/signer requirements, and what it validates.
- Roles & permissions matrix — which signer can call which instruction, how authority is checked — cross-reference the upgrade-authority ladder from step 2.
- Money flow — deposits/withdrawals/fees/liquidations, and which accounts hold lamports/tokens at each step.
- Edge cases specific to Solana's account model: missing signer checks, missing owner checks, PDA seed collisions/sharing across authority domains, using a user-supplied bump instead of the canonical one, account type confusion ("cosplay"), arbitrary CPI (invoking an untrusted, user-supplied program ID), sysvar spoofing, reinitialization attacks, account closing done unsafely, integer overflow (Rust release builds don't panic on overflow by default), rent-exemption edge cases, compute-unit budget exhaustion, CPI depth limits (max depth 4).

Produce the account/PDA relationship diagram and instruction flow when it clarifies more than prose (Claude: use the Visualizer; other agents: emit a Mermaid diagram inline or as an SVG/image file — see `../../PORTABILITY.md` at the suite root if present, otherwise this parenthetical is the complete guidance).

## 4. Write the program

Default to **Anchor** unless the user asks for native Rust or Pinocchio. Rules — see `references/coding-standards-anchor.md`:
- Every instruction validates signer, owner, and PDA-seeds via Anchor account constraints rather than manual checks wherever possible.
- Store and reuse the canonical bump; never accept a bump as unchecked instruction input.
- All value arithmetic uses checked math — never raw operators on token/lamport amounts.
- CPI targets validated against a known program ID — never invoke a user-supplied, unchecked program ID.
- Account closing uses Anchor's `close = destination` constraint.

## 5. QA — testing pyramid (always run all three tiers that apply) — Phase 4 of the methodology

See `references/testing-solana.md` for full patterns:
- **LiteSVM** — fast in-process unit tests for individual instruction logic.
- **Mollusk** — isolated single-instruction checks (compute budget, sysvars, feature-set control).
- **Surfpool** — integration tests against realistic cluster state when CPI-ing into real deployed programs.
- **Fuzzing** — `anchor fuzz` (fast default) and **Trident** (release/audit-grade, IDL-driven, flow-based multi-instruction sequences) targeting the specific properties from step 2's risk matrix (balance conservation, no-value-creation), not just generic random search.

Role-based sequential runner: connect each role's keypair, run happy path -> permission-denied attempt -> boundary amount -> replay/reinitialization attempt -> account-state verify, sequentially. Log every transaction signature and compute units consumed.

## 6. Static analysis (Phase 2 — baseline, not the finish line)

- Manual scan for the 6 critical Solana-specific classes (missing signer check, missing owner check, PDA validation gaps, arbitrary CPI, sysvar spoofing, account-type confusion) — `references/audit-checklist.md` encodes these as greppable patterns.
- `cargo audit` for known-vulnerable dependency crates.
- **Fast first-pass option**: if the user has access to a commercial Rust/Solana-specific detector engine (e.g. RustScan/CredShields — an AI-powered scanner purpose-built for Rust/Solana contracts, sibling product to SolidityScan) or its equivalent is connected as a tool, run it first as a cheap, fast triage pass before the deeper manual/formal-verification passes below — same layered pattern as the EVM skill's static-analysis reference. Don't treat a clean commercial-scanner result as sufficient on its own — it doesn't replace the manual checklist or the threat-model-driven review.
- Older third-party scanners (Soteria, Sec3 X-ray) exist but tooling maintenance status varies — verify current availability before depending on one; prefer a currently-maintained option (per the point above) if available.
- **Formal verification**: Certora Prover supports Solana/Rust as of its current published scope — recommend for high-value protocols with a small number of core invariants (solvency, conservation), same as the EVM skill's Phase 5. See `references/agency-audit-methodology.md`.

## 7. Audit pass (Phases 3, 6, 7 of the methodology)

Run `references/audit-checklist.md` against the final code, informed by the threat model/risk matrix (step 2), fuzzing results, and static-analysis findings. Also run the **economic/game-theoretic review** (Phase 6): oracle-manipulation cost vs. value-at-risk, same-transaction/flash-style manipulation, upgrade-authority cost-of-attack, centralization risk rated separately per the upgrade-authority ladder.

Report format (Phase 7): scope & methodology recap, executive summary, then every finding as `[SEVERITY] Title — file:line/instruction — scenario — fix`, where severity comes from the impact×likelihood risk matrix, plus an explicit scope/assumptions section. Include the **coverage traceability matrix** from the end of `references/audit-checklist.md` (mapping checks to all 11 canonical Sealevel Attacks categories) filled in per row — lets a reader verify completeness against the canonical baseline rather than trust a bare claim. Never mark something safe without stating what was actually checked.

**Formatting**: for a quick in-chat findings summary, plain markdown is fine. If the user wants a standalone deliverable (a report, a PDF, a Word doc, something to send to a client/investor, "make it look professional"), read `references/report-template.md` — title page, document structure, severity color conventions (Critical=dark red, High=red, Medium=orange, Low=amber, Informational=blue/gray), and concrete `docx` skill usage notes. Don't improvise a report layout when this reference already specifies one.

## 8. Fix review / re-audit cycle (Phase 8 — offer after the team patches findings)

Once findings are patched, offer a re-review pass: does each patch actually close the reported issue, and did it introduce a new one. Track status per finding: Unresolved / Acknowledged-won't-fix / Partially resolved / Resolved / Resolved-but-introduced-new-issue.

## 9. Wallets — ask every time

Never assume. Ask:
1. **Local keypair file** — fine for devnet/local; flag as unsafe for mainnet-beta if it holds real value.
2. **Hardware wallet (Ledger)** for mainnet-beta fund-controlling deploys/upgrade-authority operations.
3. **Squads multisig** for program upgrade authority and treasury control on anything past a solo-dev prototype.
`scripts/wallet_setup.md` covers all three; ask which before generating role keypairs or running any devnet/mainnet transaction.

## 10. Deploy + deployment verification

Default: **devnet**. Only deploy to **mainnet-beta** on explicit request — confirm once, and confirm upgrade-authority plan (single key vs multisig) before doing so, per step 2's ladder. Use `anchor deploy` / `solana program deploy` — see `scripts/deploy.md`.

After deploying: confirm the on-chain program's deployed hash matches a `--verifiable`/reproducible build of the audited source (same commit, same Anchor/Rust toolchain versions) — deploying a different build than what was reviewed silently invalidates the audit.

## 11. Post-deployment: monitoring & incident response (Phase 10)

For anything holding meaningful value, offer: alert-threshold suggestions derived from step 2's risk matrix (large single-tx withdrawals, oracle deviation, unexpected admin-instruction calls), and a short incident-response starter doc (who can pause/what's the decision tree, communication plan) tied to the upgrade-authority resilience rating from step 2.

## 12. Team mode (multi-agent) — if requested

If the user asks for team/multiagent mode ("with a team", "multiagent", "agent team", "use N agents"), don't run steps 0-11 solo. Check whether `../../multi-agent/` exists relative to this file (true only inside the full suite repo, not for an installed standalone skill) — if it does, follow `../../multi-agent/README.md` and the playbook there. **If it doesn't exist** (the normal case for an installed skill), use `references/team-mode.md` instead — same roles/spawn-pattern/fallback, no dependency on files outside this skill's folder. Either way, say plainly which mode you're actually running.

## Output

Every run produces: scope/threat-model doc (with risk matrix and account/PDA diagram), architecture doc, Anchor program source, LiteSVM/Mollusk unit tests, Surfpool integration test, Trident/anchor-fuzz fuzz harness + results, audit report (with economic-review section and explicit scope/assumptions), deploy script/log + deployment-verification note. Save to the project output directory (Claude: `/mnt/user-data/outputs/<project-name>/`, present with `present_files`; other agents: your equivalent workspace/output path — full detail in `../../PORTABILITY.md` at the suite root if present). Offer the fix-review and monitoring/IR follow-ups explicitly.
