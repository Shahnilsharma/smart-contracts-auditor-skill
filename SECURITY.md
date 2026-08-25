# Security policy

## Scope of this document
This covers the security of **this repository's own content** (the skills, scripts, and multi-agent definitions) — not a promise about the security of contracts this suite helps you audit or build. See `LIMITATIONS-AND-COMPARISON.md` for what this suite's audit output does and doesn't guarantee.

## Reporting an issue with this repo
If you find a real defect in this repo — a script with a command-injection or path-traversal risk, a checklist that's factually wrong about a chain's behavior, a wallet-handling instruction that could leak a key, or a multi-agent definition with a broken reference — open an issue or PR describing it concretely (file, line, reproduction). This suite has already had one such external review folded in (see `VERIFICATION.md`, "Round 3") — further review is welcome and expected, this is a young project.

## Known, accepted risk surfaces (by design, documented rather than hidden)
- **Scripts execute shell commands** (`scripts/deploy.sh`, `scripts/wallet_loader.js`'s `execKeyringTx`) against whatever chain binary/RPC endpoint you configure. They use `execFileSync`/argument-array invocation rather than shell-string interpolation specifically to avoid injection via role names or message content, and validate role names against an allowlist — but you are still responsible for reviewing any generated code before running it against a network holding real funds.
- **Wallet material**: this suite never asks for a wallet mode without prompting the user first, and the `.gitignore` at this repo's root blocks common key/mnemonic file patterns — but a `.gitignore` doesn't protect a key already typed into a chat log, a shell history file, or a `.env` that existed before the ignore rule was added. If you're unsure whether a key was ever exposed, rotate it.
- **LLM-generated audit findings are not automatically trustworthy** — see the Phase 6.5 validation gate in `references/agency-audit-methodology.md` and the honest discussion in `LIMITATIONS-AND-COMPARISON.md`. Treat any Critical/High finding without an executed, passing/failing test backing it as unconfirmed.
- **Mainnet deploy scripts require an explicit confirmation flag** (`CONFIRM_MAINNET=yes` for CosmWasm's `deploy.sh`; equivalent explicit-request language for EVM/Solana) rather than deploying to a network holding real value on default behavior.

## What this is not
This repo is a set of instructions for AI agents (Claude, Codex, and others via `AGENTS.md`) — it is not a hosted service, doesn't collect data, and has no attack surface beyond "code you choose to run after reviewing it." There's no bug bounty program; this is an open, unfunded methodology project, not a company.
