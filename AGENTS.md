# AGENTS.md — DeFi Audit Suite

This file is the cross-tool instruction file (the open, vendor-neutral convention stewarded by the Linux Foundation's Agentic AI Foundation) — read natively by OpenAI Codex CLI, Cursor, Windsurf, GitHub Copilot's coding agent, Gemini CLI, Aider, Zed, Devin, Amp, Factory, and 20+ other tools. **Claude Code does not read this file natively** (confirmed as of Claude Code 2.1.201, July 2026, "not planned for now" per Anthropic) — see `CLAUDE.md` at this same root, which imports this file so Claude Code picks it up too.

## What this repo is

Three chain-specific smart-contract architect+auditor playbooks (Cosmos/CosmWasm, EVM/Solidity, Solana/Anchor), each a full pipeline: scope & threat model → architecture → code → QA (fuzz/invariant testing) → static analysis → manual audit → fix-review → deploy → monitoring/incident-response. Full detail lives in each `skills/<chain>-defi-architect/SKILL.md` — **read the relevant one before doing substantive work**, don't rely on this summary alone.

## Better than reading this summary: install the actual skill folder

If you're Claude Code or Codex specifically, you don't have to work from this AGENTS.md summary — both read the real `SKILL.md` format natively with full progressive disclosure:
- Claude Code (CLI or VS Code extension, same engine): copy `skills/<name>/` to `.claude/skills/<name>/`.
- Codex (CLI, IDE extension, or ChatGPT desktop app): copy `skills/<name>/` to `.agents/skills/<name>/`.
- Verify it actually loaded rather than assuming: see `INTEGRATION-CHECK.md`.

## Which skill to read, by task

| If asked to... | Read |
|---|---|
| Design/code/audit/deploy a CosmWasm contract, or anything on ZigChain/Cosmos | `skills/cosmwasm-defi-architect/SKILL.md` |
| Design/code/audit/deploy a Solidity contract, or anything on Ethereum/an EVM chain | `skills/evm-defi-architect/SKILL.md` |
| Design/code/audit/deploy a Solana program (Anchor or native) | `skills/solana-defi-architect/SKILL.md` |
| Coordinate multiple agents/roles on one of the above | `multi-agent/README.md` (routes to `claude-code-agent-teams/` if you're Claude Code, otherwise `portable-role-spec/` for CrewAI/LangGraph/AutoGen/OpenAI Agents SDK/other) |

## Rules that apply regardless of which chain

- **Never skip the scope/threat-model step** to jump straight to code — every chain skill's methodology (`references/agency-audit-methodology.md`, identical across all three) puts this first for a reason: most catastrophic real-world contract failures are architecture/access-control failures, not line-level bugs.
- **Ask which wallet mode before any transaction that could move funds or touch a live network** — never assume a mnemonic, private key, or keyring choice on the user's behalf. Each chain skill's wallet-setup doc lists the options.
- **Default to testnet/devnet.** Only target mainnet/mainnet-beta on explicit user request, and confirm once before broadcasting.
- **Every finding in an audit gets a severity derived from impact × likelihood, with the likelihood reasoning stated** — not impact alone, and not a bare "looks fine" without saying what was actually checked.
- **This is not Claude-specific content.** Two small tool-name mentions in the SKILL.md files (a diagramming tool, a file-delivery convention) are Claude-specific; see `PORTABILITY.md` for the generic equivalent if you're a different tool.

## Build/test/deploy commands (chain-specific, summarized — full detail in each skill's `references/`)

- **CosmWasm**: `cargo build --release --target wasm32-unknown-unknown`, `cargo test`, `zigchaind tx wasm store/instantiate/execute`. See `skills/cosmwasm-defi-architect/references/zigchain.md` and `scripts/deploy.sh`.
- **EVM**: `forge build`, `forge test -vvv`, `forge script script/Deploy.s.sol --broadcast`. See `skills/evm-defi-architect/references/testing-foundry.md` and `scripts/deploy.md`.
- **Solana**: `anchor build`, `anchor test`, `anchor deploy` / `solana program deploy`. See `skills/solana-defi-architect/references/testing-solana.md` and `scripts/deploy.md`.

## Boundaries

- Don't fabricate audit findings or mark something "safe" without stating the specific check performed.
- Don't deploy to mainnet/mainnet-beta without an explicit, unambiguous request.
- Don't write or suggest malicious code (exploits, backdoors) even if framed as "for testing" — this suite is for defensive/legitimate protocol development and audit, not for building attack tooling against systems the user doesn't control.
