# Portability — using these skills outside Claude

The three skills under `skills/` are plain markdown (`SKILL.md` + `references/*.md` + `scripts/*`) — no proprietary format, no Claude-only syntax in the substance of the instructions. Any AI coding agent that can read files from a working directory and follow written instructions can use them.

## Cross-tool discovery: `AGENTS.md` (checked, current as of July 2026)

This repo ships a root `AGENTS.md` — the open, vendor-neutral instruction-file convention (stewarded by the Linux Foundation's Agentic AI Foundation). Read **natively, on session start, with no setup** by: OpenAI Codex CLI, Cursor, Windsurf, GitHub Copilot's coding agent, Gemini CLI, Aider, Zed, Devin, Amp, Factory, and 20+ other tools. Drop this repo into any of those and it's already working.

**Claude Code is the one notable exception.** Verified across multiple independent, recent sources: as of Claude Code 2.1.201 (July 2026), Claude Code does **not** read `AGENTS.md` natively — it reads `CLAUDE.md`. Anthropic has an open feature request for native support with no committed timeline ("not planned for now" as of May 2026). The standard, Anthropic-documented workaround — which this repo already does for you — is a thin `CLAUDE.md` that imports it: `@AGENTS.md` as the file's content. So this repo ships **both** `AGENTS.md` (for everyone else) and `CLAUDE.md` (a one-line import, for Claude Code) — you don't need to do anything extra.

Don't take a single blog post's word for Claude Code/AGENTS.md compatibility without checking the date — this space had real churn through 2026 (an early claim that "Claude Code now reads AGENTS.md too" turned out to be inaccurate/outdated relative to Anthropic's own more recent, more corroborated statements). If you're reading this later than mid-2026, quickly re-check whether Anthropic shipped native support before assuming the import workaround is still necessary.

## Native skill support, not just the AGENTS.md summary (checked, current as of July 2026)

Better news than "just read the summary file": **Agent Skills (the `SKILL.md` format itself) is now an open standard**, and both of the two agents you asked about read the actual `skills/<name>/` folders natively, full progressive disclosure included — not only via `AGENTS.md`:

- **Claude Code — CLI and VS Code extension are the same engine.** Confirmed: the VS Code extension bundles the same `claude` binary as the terminal CLI — same `CLAUDE.md`, same `.claude/skills/`, same everything. Copy a `skills/<name>/` folder to `.claude/skills/<name>/` (project-scoped, versioned with the repo) or `~/.claude/skills/<name>/` (personal, all projects) and both the CLI and the VS Code extension pick it up identically — no separate setup for the extension.
- **OpenAI Codex — CLI, IDE extension, and ChatGPT desktop app all share skill discovery.** Codex scans `.agents/skills/` from your working directory up to the repo root, at every one of those surfaces per OpenAI's own docs. Copy the same `skills/<name>/` folder to `.agents/skills/<name>/` and Codex loads it the same way Claude Code loads `.claude/skills/`.

Practical tip from the open-standard community: if you want one copy of a skill to serve both agents without duplicating files, symlink it into both locations — `.claude/skills/<name>` and `.agents/skills/<name>` both pointing at the same folder. The `SKILL.md` format is identical; nothing in this repo's skills needs to change to support this.

`AGENTS.md` at this repo's root remains useful as a *fallback/summary* for agents that don't (yet) support the Agent Skills folder convention at all (older tool versions, or agents that only read a single instructions file) — but for Claude Code and Codex specifically, installing the actual `skills/<name>/` folder natively is the better integration, not just a fallback.

## Verifying the integration actually worked

See `INTEGRATION-CHECK.md` at the repo root — a concrete way to confirm a given agent actually loaded a skill (mechanical check per tool, plus an agent-agnostic "canary question" per skill that only has the right answer if the file was actually read).

## 1. Tool-call references (the two genuinely Claude-specific spots)
A few lines in each `SKILL.md` mention Claude-specific tools by name:
- **"Visualizer"** (architecture/flow diagrams) → any agent: just emit a Mermaid diagram in the markdown output, or an SVG/PNG file, wherever a diagram is called for.
- **`present_files` / `/mnt/user-data/outputs/`** (Claude's file-delivery convention) → any agent: write to your own working/output directory and hand it back however your harness delivers files to the user (a file path, a PR, a zip, whatever's native to your tool).

Every other instruction (read this reference file, run this CLI command, follow this checklist) is tool-agnostic already.

## 2. Discovery mechanism
Claude (and Claude Code) auto-discovers **Claude Skills** by scanning a `SKILL.md` frontmatter `description` field and loading the matching skill on demand — that's the `skills/<name>/` format. For every other agent, discovery is now solved by the root `AGENTS.md` (see above) — it points to the right `skills/<chain>-defi-architect/SKILL.md` per task, so most agents don't need any extra setup. The one remaining manual step: `AGENTS.md` is a summary, not a substitute — once your agent identifies the right chain, it should still actually read that skill's full `SKILL.md` (and pull in its `references/*.md` as instructed) rather than working from the summary alone.

## 3. What doesn't need changing
The actual technical content — chain defaults, coding standards, testing patterns, audit checklists, the agency-audit-methodology phases, wallet setup, deploy commands — is written for the target blockchain ecosystem's own tooling (Foundry/Hardhat/cast, cw-multitest/CosmJS/zigchaind, Anchor/LiteSVM/solana CLI), not for Claude. That part is already portable as-is.

## Multi-agent portability
See `multi-agent/README.md` — the role/dependency structure (`multi-agent/portable-role-spec/roles.yaml`) is deliberately framework-agnostic for exactly this reason; `multi-agent/claude-code-agent-teams/` is the Claude-Code-specific implementation of the same structure.
