#!/usr/bin/env bash
# install.sh — one-command installer for this suite's skills.
#
# Copies skill folder(s) from skills/ to the right location for your tool. No manual path-
# hunting, no remembering which directory Claude Code vs Codex vs claude.ai each expect.
#
# Usage:
#   ./install.sh                          interactive: pick a target, pick skill(s)
#   ./install.sh --claude-code all        install all 3 to this project's .claude/skills/
#   ./install.sh --claude-code evm        install just the EVM skill, project-scoped
#   ./install.sh --claude-code-personal all   install to ~/.claude/skills/ (all your projects)
#   ./install.sh --codex solana           install to this project's .agents/skills/
#   ./install.sh --to /custom/path evm    install to an arbitrary directory
#   ./install.sh --list                   show what would be installed where, do nothing
#
# Skill names accepted (with or without the -defi-architect suffix): cosmwasm, evm, solana,
# or the full names, or "all". Multiple names: ./install.sh --claude-code evm solana
#
# NOT for claude.ai (the browser chat interface) — there's no shell access from there. Use
# a dist/<name>.skill file and the in-app "upload skill" UI instead; see README.md.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_SKILLS=(cosmwasm-defi-architect evm-defi-architect solana-defi-architect)

usage() { sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

resolve_skill_name() {
  case "$1" in
    cosmwasm|cosmwasm-defi-architect) echo "cosmwasm-defi-architect" ;;
    evm|evm-defi-architect)           echo "evm-defi-architect" ;;
    solana|solana-defi-architect)     echo "solana-defi-architect" ;;
    *) echo "" ;;
  esac
}

install_one() {
  local skill="$1" dest_root="$2"
  local src="$SCRIPT_DIR/skills/$skill"
  local dest="$dest_root/$skill"

  if [ ! -f "$src/SKILL.md" ]; then
    echo "  FAIL: $src/SKILL.md not found — is this script still inside the repo?" >&2
    return 1
  fi

  mkdir -p "$dest"
  cp -r "$src/." "$dest/"

  # Verify, don't assume — same discipline as check_dist_matches_source.sh.
  if [ -f "$dest/SKILL.md" ] && diff -q "$src/SKILL.md" "$dest/SKILL.md" > /dev/null 2>&1; then
    echo "  OK: $skill -> $dest"
  else
    echo "  FAIL: copy to $dest did not verify — check permissions and retry" >&2
    return 1
  fi
}

# --- parse args ---
if [ $# -eq 0 ]; then
  echo "No arguments given — running interactively."
  echo ""
  echo "Where do you want to install?"
  echo "  1) This project's Claude Code   (.claude/skills/)"
  echo "  2) Your personal Claude Code    (~/.claude/skills/, all projects)"
  echo "  3) This project's Codex         (.agents/skills/)"
  echo "  4) Custom path"
  read -rp "Choice [1-4]: " choice
  case "$choice" in
    1) MODE="claude-code" ;;
    2) MODE="claude-code-personal" ;;
    3) MODE="codex" ;;
    4) read -rp "Path: " CUSTOM_PATH; MODE="custom" ;;
    *) echo "Unrecognized choice, aborting." >&2; exit 1 ;;
  esac
  echo ""
  echo "Which skill(s)? (cosmwasm / evm / solana / all, space-separated)"
  read -rp "> " -a SKILL_ARGS
else
  MODE=""
  CUSTOM_PATH=""
  SKILL_ARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --claude-code) MODE="claude-code"; shift ;;
      --claude-code-personal) MODE="claude-code-personal"; shift ;;
      --codex) MODE="codex"; shift ;;
      --to) MODE="custom"; CUSTOM_PATH="$2"; shift 2 ;;
      --list) MODE="list"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) SKILL_ARGS+=("$1"); shift ;;
    esac
  done
fi

if [ -z "${MODE:-}" ]; then
  echo "No target specified. Use --claude-code, --claude-code-personal, --codex, or --to <path>." >&2
  usage
  exit 1
fi

# --- resolve skill list ---
SELECTED=()
for arg in "${SKILL_ARGS[@]:-}"; do
  [ -z "$arg" ] && continue
  if [ "$arg" = "all" ]; then
    SELECTED=("${ALL_SKILLS[@]}")
    break
  fi
  resolved="$(resolve_skill_name "$arg")"
  if [ -z "$resolved" ]; then
    echo "Unrecognized skill name: '$arg' (expected: cosmwasm, evm, solana, or all)" >&2
    exit 1
  fi
  SELECTED+=("$resolved")
done

if [ ${#SELECTED[@]} -eq 0 ]; then
  echo "No skill(s) specified. Use one or more of: cosmwasm evm solana all" >&2
  exit 1
fi

# --- resolve destination ---
case "$MODE" in
  claude-code) DEST_ROOT="$(pwd)/.claude/skills" ;;
  claude-code-personal) DEST_ROOT="$HOME/.claude/skills" ;;
  codex) DEST_ROOT="$(pwd)/.agents/skills" ;;
  custom) DEST_ROOT="$CUSTOM_PATH" ;;
  list)
    echo "Would install: ${SELECTED[*]}"
    echo "(specify a target with --claude-code / --claude-code-personal / --codex / --to <path> to see the destination)"
    exit 0
    ;;
  *) echo "Internal error: unhandled mode $MODE" >&2; exit 1 ;;
esac

echo ""
echo "Installing to: $DEST_ROOT"
FAIL=0
for skill in "${SELECTED[@]}"; do
  install_one "$skill" "$DEST_ROOT" || FAIL=1
done

echo ""
if [ "$FAIL" -ne 0 ]; then
  echo "One or more installs failed — see FAIL lines above."
  exit 1
fi

echo "Done. Next step — verify it actually loaded, don't assume:"
echo "  Claude Code: run /skills and confirm the skill(s) are listed, then ask a canary"
echo "  question from INTEGRATION-CHECK.md in a FRESH session (not this one)."
echo "  Codex: check the Skills panel (ChatGPT desktop) or ask 'what skills do you have'."
