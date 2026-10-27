# DeFi Audit Suite — Cosmos / EVM / Solana

**Status: structurally validated and statically reviewed; end-to-end chain validation pending.** All 3 skills pass Anthropic's official `quick_validate.py`; internal references and YAML have been checked for consistency; scripts have been syntax-checked. None of this has been run end-to-end against a real deployed contract, a real testnet, or real Claude Code Agent Teams execution — see `VERIFICATION.md` for exactly what was and wasn't checked, and **`LIMITATIONS-AND-COMPARISON.md`** for how this stacks up against real production AI-audit tools (AuditAgent, SolidityScan, RustScan, etc.) and industry benchmark data — read both before treating any output as a substitute for a human audit.

One repo, three chain-specific full-stack smart-contract **architect + auditor** skills, sharing a common agency-grade audit methodology, plus a multi-agent team-mode layer and cross-agent (Codex/Cursor/etc.) support. Each skill takes a protocol from "design this" through "audit and deploy it," not just a code reviewer bolted onto an existing contract.

---

## What's in this repo

```
defi-audit-suite/
├── README.md                      # this file
├── .claude-plugin/marketplace.json # Claude Code plugin-marketplace manifest — enables /plugin marketplace add
├── LICENSE                        # MIT
├── SECURITY.md                    # security policy for this repo's own content
├── .gitignore                     # blocks wallet keys/mnemonics/env files/build artifacts
├── AGENTS.md                      # cross-tool instructions — read natively by Codex/Cursor/Windsurf/Copilot/etc.
├── CLAUDE.md                      # 1-line @AGENTS.md import, since Claude Code doesn't read AGENTS.md natively
├── VERIFICATION.md                # official-validator pass, findings, sign-off, external-review fixes
├── LIMITATIONS-AND-COMPARISON.md  # honest comparison vs real AI audit tools + industry data
├── EVAL-METHODOLOGY.md            # eval mental model — 3-layer framework, failure taxonomy, ground-truth scoring
├── evals/score_findings.py        # reference scoring script — precision/recall vs. ground truth per fixture
├── install.sh                     # one-command installer — copies skill(s) to the right place, verifies the copy
├── PORTABILITY.md                 # using the skills outside Claude entirely
├── check_dist_matches_source.sh   # equivalence gate: fails if dist/*.skill drifted from skills/ source
├── INTEGRATION-CHECK.md           # how to confirm an agent actually loaded a skill
├── skills/
│   ├── cosmwasm-defi-architect/   # Cosmos / CosmWasm, default chain: ZIGChain
│   ├── evm-defi-architect/        # Solidity / EVM, default chain: Ethereum
│   └── solana-defi-architect/     # Solana / Anchor, default cluster: devnet
├── dist/                          # pre-packaged, validated .skill files — install these directly
│   ├── cosmwasm-defi-architect.skill
│   ├── evm-defi-architect.skill
│   └── solana-defi-architect.skill
├── plugins/                       # generated — mirrors skills/<name>/ one level deeper, for /plugin install only
│   ├── cosmwasm-defi-architect/   # (Claude Code's plugin loader only scans <source>/skills/, never source root)
│   ├── evm-defi-architect/
│   └── solana-defi-architect/
└── multi-agent/
    ├── claude-code-agent-teams/   # real parallel teammates via Claude Code Agent Teams
    └── portable-role-spec/        # framework-agnostic version (CrewAI/LangGraph/AutoGen/OpenAI SDK/ADK)
```

Each `skills/<chain>-defi-architect/` folder is internally identical in shape: `SKILL.md` (the pipeline), `.claude-plugin/plugin.json` (a per-skill plugin manifest), `references/*.md` (chain defaults, coding standards, testing patterns, static-analysis commands, the audit checklist, the shared `agency-audit-methodology.md`, `team-mode.md` for self-contained team mode, and `report-template.md` for professional report formatting — title page, severity color conventions, `docx` skill usage notes), `scripts/*` (wallet setup, deploy commands), and `evals/` — `evals.json` (6 test cases: build, audit-existing, team-mode, near-miss, wrong-chain-negative, adversarial-pressure), `fixtures/` (small intentionally-flawed contracts used by the audit-existing case), and `ground-truth/` (the exact planted vulnerabilities in each fixture, each with a FAIL_TO_PASS/PASS_TO_PASS test pair, labeled for precision/recall scoring — see `EVAL-METHODOLOGY.md`).

---

## What each skill does (the pipeline)

Same 12-step shape across all three chains — only the tooling underneath differs:

1. **Resolve target chain** — default chain, or any other via a docs URL/`.md` file param
2. **Version check** — confirm toolchain/runtime versions before writing code
3. **Scope & threat model** — assets at risk, trust assumptions, an impact×likelihood risk matrix, and a key/upgrade-authority compromise resilience rating (single key < multisig < multisig+timelock < immutable)
4. **Architecture pass** — state/account model, roles & permissions, money flow, chain-specific edge cases
5. **Write the contract/program** — following the chain's coding-standards reference
6. **QA** — unit + fuzz + invariant testing, role-based (asks which wallet mode first)
7. **Static analysis** — automated tools, triaged findings (true positive / false positive / accepted risk)
8. **Audit pass** — manual checklist + economic/game-theoretic review, severity from impact×likelihood
9. **Fix review / re-audit cycle** — offered after findings are patched, checks patches don't introduce new bugs
10. **Deploy** — testnet/devnet default, mainnet only on explicit request, plus deployment-drift verification
11. **Monitoring & incident response** — alert thresholds and an IR plan tied to the risk matrix
12. **Team mode** — say "with a team"/"multiagent" to route to the multi-agent layer instead of running solo

Full detail (this is the summary): each skill's own `SKILL.md`, and the shared `references/agency-audit-methodology.md` — modeled on public methodology from Trail of Bits, OpenZeppelin, Spearbit/Cantina, Certora, and the Code4rena/Sherlock contest-judging standard.

---

## Attack vectors covered, by chain

Pulled directly from each skill's `references/audit-checklist.md` — not a marketing list, this is what each skill actually checks line-by-line and cites severity for.

### EVM (`evm-defi-architect`) — Solidity / Foundry / Hardhat
Access control · Logic errors / business logic · Reentrancy · Flash loan / price manipulation · Input validation · Oracle manipulation · Timestamp / block manipulation · Governance bypass · Unchecked external calls · Arithmetic rounding & precision · Integer overflow/underflow (version-dependent) · Permit front-running / nonce DoS · Denial of service · Front-running / MEV · Upgrade / proxy safety (storage layout, uninitialized implementations, UUPS authorization, selector clashes) · ERC-4626 share inflation / donation attacks · Signature verification & replay (EIP-712, `ecrecover`, malleability) · EIP-7702 EOA assumptions · Arbitrary external calls & approval abuse · Read-only reentrancy · Chainlink feed edge cases (L2 sequencer, min/max answer) · Solidity footguns (`msg.value` reuse, `encodePacked` collisions, blocklist/USDT tokens) · Admin/role rotation that actually revokes the old key · Emergency pause · Rounding amplified by repetition · Custom-math differential fuzzing · Deployability (EIP-170 size, test vs deploy compiler parity) · Uniswap v4 hooks · Transient storage (EIP-1153) · Cross-chain messaging & bridge verifier config · Off-chain-authorized mints/withdrawals · Collateral/oracle listing timelocks · Governance vote buying

### Cosmos / CosmWasm (`cosmwasm-defi-architect`) — Rust / cw-multitest / CosmJS
Access control · Arithmetic (unchecked `Uint128`/`Decimal` math) · IBC / cross-module query DoS · Migration / restricted code-ID bypass · Reentrancy / submessage `reply` handling · Submessage `ReplyOn` semantics · CW20 `Receive` hook spoofing · Funds handling (denom/amount validation, replay) · Oracle / price manipulation · Timestamp / block manipulation · Governance bypass (cw3/cw4/x/gov) · IBC packet lifecycle (ack/timeout refunds, channel validation, IBC hooks) · Storage key collisions · `sudo` / `instantiate2` entry points · Slippage / front-running · DoS / gas (unbounded iteration, WriteFlat gas blowup) · Upgrade / admin key rotation · Input validation · Admin rotation (incl. wasmd migrate admin) · Chain/VM version advisories (CWA-2025-001/002, CVE-2025-25500) · Off-chain-authorized actions · Custom-math differential fuzzing & rounding under repetition · Governance vote buying · Collateral/oracle listing timelocks · IBC rate limits

### Solana (`solana-defi-architect`) — Anchor / LiteSVM / Mollusk / Trident
Missing signer check · Missing/incorrect owner check · PDA misuse (seed collision, unchecked bump) · Account type confusion ("cosplay") · Account data matching · Duplicate mutable accounts · Arbitrary CPI (unvalidated program IDs) · CPI depth/call-chain limits · Clock/timestamp manipulation · Governance bypass · Sysvar spoofing · Reinitialization attacks · Arithmetic · Rent exemption · Token program correctness (Token-2022 extensions) · Token-2022 mint risk (permanent delegate, freeze authority, transfer hooks) · Oracle / price manipulation (Pyth, Switchboard) · Stale account data after CPI (`reload`) · `remaining_accounts` validation · `init_if_needed` reinitialization · Instruction introspection (Instructions sysvar, Ed25519 precompile) · Slippage / MEV · Compute budget / DoS · Upgrade authority centralization · Admin initialization front-running · Authority rotation · Durable-nonce pre-signed admin transactions · Emergency pause · Cross-chain message verification · Governance vote buying · Collateral/oracle listing timelocks · Custom-math differential fuzzing · Rounding under repetition

Every finding a skill produces is rated by **impact × likelihood**, not impact alone, and comes with an explicit scope/assumptions section stating what was excluded — see `references/agency-audit-methodology.md` in any skill for why.

---

## How to operate everything in this folder

### 1. Install a skill

**Claude Code — genuinely one command, no clone, no script** (this repo is a plugin marketplace):
```
/plugin marketplace add Shahnilsharma/smart-contracts-auditor-skill
/plugin install evm-defi-architect@defi-audit-suite
```
(swap `evm-defi-architect` for `cosmwasm-defi-architect` or `solana-defi-architect`, or run all three). If you're publishing your own fork, see "Publishing this repo" below — set `.claude-plugin/marketplace.json`'s `owner.name` and every `plugin.json`'s `author.name` to your own name first.

**Any other terminal-based tool** (Codex CLI, or Claude Code if you'd rather not use the plugin mechanism): run the installer — it copies files to the right place and verifies the copy.
```bash
./install.sh                          # interactive: pick a target, pick skill(s)
./install.sh --claude-code all         # all 3, this project's Claude Code
./install.sh --claude-code-personal evm    # just EVM, your personal Claude Code (all projects)
./install.sh --codex solana            # just Solana, this project's Codex
./install.sh --to /custom/path evm     # anywhere else
```
Not for **claude.ai** (the browser chat interface) — there's no shell there. For that, and as the fastest option generally if you don't want a terminal at all: take the matching file from `dist/*.skill` and use your Claude surface's "upload/add skill" UI directly — already packaged, and `./check_dist_matches_source.sh` confirms each one matches its `skills/` source — nothing further to do.

For any other AGENTS.md-compatible tool (Cursor, Windsurf, Copilot, Gemini CLI, Aider, etc.): nothing to install — the root `AGENTS.md` already routes them to the right `skills/<chain>-defi-architect/SKILL.md` the moment this repo is in your project.

Each skill installs and works independently — you don't need all three.

#### Getting updates automatically

- **Claude Code plugin installs:** Claude Code turns auto-update off by default for marketplaces from outside Anthropic. Turn it on once with `/plugin` → Marketplaces → `defi-audit-suite` → **Enable auto-update**. Claude Code then updates the marketplace and your installed skills every time it starts. To update by hand instead: `claude plugin marketplace update defi-audit-suite`, then `claude plugin update evm-defi-architect@defi-audit-suite` (same for the other two), then restart.
- **Teams:** commit this to your project's `.claude/settings.json` so everyone who opens and trusts the project gets the suite with auto-update on:
  ```json
  {
    "extraKnownMarketplaces": {
      "defi-audit-suite": {
        "source": { "source": "github", "repo": "Shahnilsharma/smart-contracts-auditor-skill" },
        "autoUpdate": true
      }
    }
  }
  ```
- **`install.sh` copies, `dist/*.skill` uploads (claude.ai), Codex copies:** these never update by themselves — re-run `install.sh`, or upload the new `.skill` file again.
- **Maintainers:** Claude Code detects updates by version number. Bump `version` in `.claude-plugin/marketplace.json` and in every `skills/<name>/.claude-plugin/plugin.json` and `plugins/<name>/.claude-plugin/plugin.json` on each release, then rebuild `dist/` and run `./check_dist_matches_source.sh`. Push changes without a version bump and nobody receives them, auto-update or not.

### 2. Use it — solo mode (default)
Just ask normally: *"audit this Solidity contract," "build a lending protocol on ZigChain," "deploy this Anchor program to devnet."* Each skill's own `SKILL.md` frontmatter description is what triggers it.

### 3. Use it — team mode (multi-agent)
Say "with a team" / "multiagent" / "agent team" alongside the request, e.g. *"use the solana auditing skill with a team."* Routes to `multi-agent/`:
- **Auditing existing code** (the usual case): just say *"audit this with a team"*. The lead scopes the whole system, maps how the contracts call each other, threat-models it, then splits the contracts between 2–4 auditors sized from the contract count and free memory, and merges everything into one report. With fewer than 5 contracts it tells you a team isn't worth it. Works with plain subagents if Agent Teams isn't enabled.
- **Building a new protocol, Claude Code with Agent Teams enabled**: real parallel teammates (architect → contract-engineer → qa-fuzzer + static-analyst in parallel → auditor → fix-reviewer). See `multi-agent/claude-code-agent-teams/team-lead-playbook.md`.
- **Anywhere without Agent Teams** (claude.ai chat, older Claude Code builds): falls back to a clearly-labeled sequential role-emulation, and says so rather than pretending to parallelize.
- **Any other multi-agent framework**: `multi-agent/portable-role-spec/roles.yaml` + `ADAPTING-OTHER-FRAMEWORKS.md` — mapping guide for CrewAI, LangGraph, AutoGen/AG2, OpenAI Agents SDK, Google ADK/A2A.

### 4. Verify the install actually worked
Don't assume — check. `INTEGRATION-CHECK.md` gives a mechanical check per tool (Claude Code's `/skills` and `/context`, Codex's Skills sidebar) plus an agent-agnostic **canary question** per skill (e.g. asking the Solana skill for its max CPI call depth — a correct, specific answer like "4" proves the file was actually read, a vague answer means it wasn't).

### 5. Trust, but verify, the suite itself
`VERIFICATION.md` documents the actual official-validator pass (Anthropic's `quick_validate.py`), the attack-vector cross-check against a named external list, and the multi-agent facts re-verified against current sources (including a real breaking API change in Claude Code Agent Teams that was caught and fixed). Read it before treating any specific audit output as final — and re-run the equivalent fix-review discipline (step 9 above) on your own target contract, the same way this suite applied it to itself.

## Publishing this repo — GitHub, and "should I submit it to a store"

**GitHub, step by step:**
1. Before pushing a fork: set your own name in `.claude-plugin/marketplace.json` (`owner.name`) and in each `skills/<name>/.claude-plugin/plugin.json` (`author.name`) — currently `Shahnil Sharma`. Then copy each edited `plugin.json` into its `plugins/<name>/.claude-plugin/plugin.json` counterpart too (that's what the marketplace actually installs from — see the `plugins/` note above). Run `./check_dist_matches_source.sh` afterward — it validates all of this (including `plugins/` drift) automatically.
2. `git init && git add -A && git commit -m "initial" && git push` to a new GitHub repo (public, if you want others to install it).
3. That's it for the Claude Code plugin-marketplace path above — `/plugin marketplace add <you>/<repo>` works the moment the repo is public on GitHub, no release/tag needed.
4. **Optional, for the fastest possible download of just one skill without cloning**: create a GitHub Release and attach the 3 files from `dist/*.skill` as release assets. Anyone can then download a single `.skill` file directly from the Releases page and upload it via their Claude surface's UI — no `git clone`, no terminal at all.

**Is there a single official store to submit to?** Checked directly rather than assuming: **no**, not as of mid-2026, for either Claude or Codex. The actual official mechanism is the decentralized plugin-marketplace system this repo now implements (`.claude-plugin/marketplace.json` — any GitHub repo can be one, there's no central submission/approval step). Beyond that, there are several **community-run, unofficial** directories that index public skill repos and are worth knowing about for discoverability, but none of them are Anthropic- or OpenAI-run app stores — treat "submit to a store" as "optionally list it in a few community indexes," not a formal publishing process with a review gate. If you want the discoverability, search for the current versions of things like a Claude-skills marketplace directory site or a Codex/Claude plugin directory site and follow their own submission flow (typically: paste your GitHub URL, they crawl and grade it) — these sites change often enough that naming a specific one here would likely go stale; a quick search for "claude code skills marketplace" or "codex skills directory" at the time you're publishing will surface the current ones.
