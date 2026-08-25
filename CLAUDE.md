@AGENTS.md

## Claude-specific notes

This repo is primarily distributed as three Claude **Skills** (`skills/<chain>-defi-architect/`, each a self-contained `SKILL.md` + `references/` + `scripts/`) — if you're Claude or Claude Code, prefer loading the relevant skill directly (via `/mnt/skills/user/<name>/` or your project's `.claude/skills/<name>/`) over reading this file, since the skill format gives you progressive disclosure (metadata always loaded, body loaded on trigger, reference files loaded on demand) rather than dumping everything into context at once.

If this repo is instead just sitting in your working directory as a coding project (no skill installed), the `@AGENTS.md` import above gives you the same cross-tool instructions every other agent reads. Team/multiagent mode: see `multi-agent/claude-code-agent-teams/` if Agent Teams is enabled (`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`).
