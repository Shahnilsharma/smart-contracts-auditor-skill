#!/usr/bin/env bash
# check_dist_matches_source.sh — verifies every dist/<name>.skill is byte-for-byte identical
# to its skills/<name>/ source (excluding evals/, which package_skill.py deliberately omits
# from the distributable). Run this after any change to skills/ and before treating dist/ as
# current — added in response to an external review that found dist/ had drifted from source
# after several rounds of edits were never repackaged (see VERIFICATION.md, "Round 3").
#
# Usage: ./check_dist_matches_source.sh   (run from the repo root)
# Exit code 0 = all match, non-zero = drift detected, names the file(s).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$REPO_ROOT"

FAIL=0
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

for name in cosmwasm-defi-architect evm-defi-architect solana-defi-architect; do
  skill_file="dist/${name}.skill"
  src_dir="skills/${name}"

  if [ ! -f "$skill_file" ]; then
    echo "FAIL: $skill_file does not exist"
    FAIL=1
    continue
  fi

  extract_dir="$TMP/$name"
  mkdir -p "$extract_dir"
  unzip -q "$skill_file" -d "$extract_dir"

  # Compare everything except evals/ (deliberately excluded from the packaged .skill).
  if diff -rq \
      -x evals \
      "$src_dir" "$extract_dir/$name" > "$TMP/${name}.diff" 2>&1; then
    echo "OK: $skill_file matches $src_dir"
  else
    echo "FAIL: $skill_file has drifted from $src_dir"
    cat "$TMP/${name}.diff"
    FAIL=1
  fi
done

if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "Drift detected — rebuild with:"
  echo "  python3 -m scripts.package_skill /path/to/skills/<name> /path/to/dist"
  echo "(from Anthropic's skill-creator tools), then re-run this check."
  exit 1
fi

echo ""
echo "All dist/*.skill files match their skills/ source."

# --- plugins/<name>/skills/ drift check ---
# plugins/<name>/ is a generated wrapper that nests each skill one level deeper
# (plugins/<name>/skills/SKILL.md) so Claude Code's plugin-marketplace loader can find it —
# it only ever scans <plugin-source>/skills/, never the source root itself. skills/<name>/
# stays flat (SKILL.md at its own root) because install.sh and dist/*.skill both depend on
# that flat shape. Keep both in sync by hand; this catches silent drift between them.
echo ""
echo "=== Checking plugins/<name>/skills/ matches skills/<name>/ (excluding evals/) ==="
for name in cosmwasm-defi-architect evm-defi-architect solana-defi-architect; do
  plugin_dir="plugins/${name}/skills"
  src_dir="skills/${name}"
  if [ ! -d "$plugin_dir" ]; then
    echo "FAIL: $plugin_dir does not exist"
    FAIL=1
    continue
  fi
  if diff -rq -x evals -x .claude-plugin "$src_dir" "$plugin_dir" > "$TMP/${name}.plugin.diff" 2>&1; then
    echo "OK: $plugin_dir matches $src_dir"
  else
    echo "FAIL: $plugin_dir has drifted from $src_dir"
    cat "$TMP/${name}.plugin.diff"
    FAIL=1
  fi
  # plugin.json is copied separately (it lives one level up from skills/ in plugins/<name>/)
  # — diff it explicitly so an author/version edit in skills/<name>/ doesn't silently drift.
  if ! diff -q "skills/${name}/.claude-plugin/plugin.json" "plugins/${name}/.claude-plugin/plugin.json" > /dev/null 2>&1; then
    echo "FAIL: plugins/${name}/.claude-plugin/plugin.json has drifted from skills/${name}/.claude-plugin/plugin.json"
    FAIL=1
  fi
done
if [ "$FAIL" -ne 0 ]; then
  echo ""
  echo "plugins/ drift detected — re-copy SKILL.md/references/scripts/plugin.json from"
  echo "skills/<name>/ into plugins/<name>/ and re-run this check."
  exit 1
fi

# --- Triplicated shared-file drift check ---
# agency-audit-methodology.md and references/team-mode.md are intentionally duplicated
# byte-for-byte across all 3 skills (each skill must be self-contained — it can't reach
# outside its own folder at runtime). Nothing enforced that they stay identical until this
# check existed; an edit to one copy without propagating to the other two is a silent,
# undetected drift. Fails loudly if any of the 3 copies differ.
echo ""
echo "=== Checking agency-audit-methodology.md stays identical across all 3 skills (it's chain-agnostic by design) ==="
SHARED_FAIL=0
ref_hash=""
for name in cosmwasm-defi-architect evm-defi-architect solana-defi-architect; do
  f="skills/${name}/references/agency-audit-methodology.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $f does not exist (expected in all 3 skills)"
    SHARED_FAIL=1
    continue
  fi
  h="$(md5sum "$f" | cut -d' ' -f1)"
  if [ -z "$ref_hash" ]; then
    ref_hash="$h"
  elif [ "$h" != "$ref_hash" ]; then
    echo "FAIL: agency-audit-methodology.md has drifted — $f (md5 $h) does not match the other copies (md5 $ref_hash)"
    SHARED_FAIL=1
  fi
done
[ "$SHARED_FAIL" -eq 0 ] && echo "OK: agency-audit-methodology.md identical across all 3 skills"

echo ""
echo "=== Checking references/team-mode.md exists + has required sections in all 3 (NOT byte-identical by design — content is deliberately chain-specific, e.g. different testing-reference filenames per chain) ==="
for name in cosmwasm-defi-architect evm-defi-architect solana-defi-architect; do
  f="skills/${name}/references/team-mode.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $f does not exist"
    SHARED_FAIL=1
    continue
  fi
  missing=""
  for section in "## Roles" "## Spawn pattern" "## Fallback" "## Other agent frameworks"; do
    grep -q "^${section}" "$f" || missing="${missing} '${section}'"
  done
  if [ -n "$missing" ]; then
    echo "FAIL: $f missing required section(s):$missing"
    SHARED_FAIL=1
  else
    echo "OK: $f has all required sections"
  fi
done

echo ""
echo "=== Checking references/report-template.md exists + has required sections in all 3 (NOT byte-identical by design — worked examples are chain-specific) ==="
for name in cosmwasm-defi-architect evm-defi-architect solana-defi-architect; do
  f="skills/${name}/references/report-template.md"
  if [ ! -f "$f" ]; then
    echo "FAIL: $f does not exist"
    SHARED_FAIL=1
    continue
  fi
  missing=""
  for section in "## Document structure" "## Cover page contents" "## Findings summary table" "## Detailed finding format" "## Typography conventions"; do
    grep -q "^${section}" "$f" || missing="${missing} '${section}'"
  done
  if [ -n "$missing" ]; then
    echo "FAIL: $f missing required section(s):$missing"
    SHARED_FAIL=1
  else
    echo "OK: $f has all required sections"
  fi
done

if [ "$SHARED_FAIL" -ne 0 ]; then
  echo ""
  echo "Shared-file drift or missing-section detected in references/agency-audit-methodology.md,"
  echo "references/team-mode.md, or references/report-template.md — fix the file(s) named above,"
  echo "then re-run this check and rebuild dist/."
  exit 1
fi

echo ""
echo "=== Checking install.sh is syntactically valid and executable ==="
if [ ! -x "install.sh" ]; then
  echo "FAIL: install.sh missing or not executable (chmod +x install.sh)"
  exit 1
fi
if bash -n install.sh; then
  echo "OK: install.sh syntax valid"
else
  echo "FAIL: install.sh has a syntax error"
  exit 1
fi

# --- Eval JSON validity check ---
# evals.json and ground-truth/*.json now carry real structured content (FAIL_TO_PASS test
# code, scoring targets, ground-truth vulnerability lists) — a broken JSON file here fails
# silently for anyone trying to actually run an eval, and nothing else in this repo's tooling
# would catch it (evals/ is deliberately excluded from dist/, so quick_validate.py never sees
# it either). Added after a consistency-audit pass found this coverage gap.
echo ""
echo "=== Checking evals.json and ground-truth/*.json parse as valid JSON ==="
JSON_FAIL=0
for f in skills/*/evals/evals.json skills/*/evals/ground-truth/*.json; do
  if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
    echo "OK: $f"
  else
    echo "FAIL: $f does not parse as valid JSON"
    JSON_FAIL=1
  fi
done
if [ "$JSON_FAIL" -ne 0 ]; then
  echo ""
  echo "Invalid JSON detected in evals/ — fix before trusting any eval run against this repo state."
  exit 1
fi

# --- Claude Code plugin-marketplace manifest check ---
echo ""
echo "=== Checking .claude-plugin/marketplace.json and per-skill plugin.json parse as valid JSON, and every marketplace source resolves ==="
PLUGIN_FAIL=0
if [ ! -f ".claude-plugin/marketplace.json" ]; then
  echo "FAIL: .claude-plugin/marketplace.json does not exist"
  PLUGIN_FAIL=1
else
  if python3 -c "import json; json.load(open('.claude-plugin/marketplace.json'))" 2>/dev/null; then
    echo "OK: .claude-plugin/marketplace.json"
  else
    echo "FAIL: .claude-plugin/marketplace.json does not parse as valid JSON"
    PLUGIN_FAIL=1
  fi
  # Every plugin's "source" path must actually exist, and every listed plugin must have its
  # own plugin.json — a marketplace entry pointing at a renamed/removed skill folder would
  # fail silently for a real user running /plugin marketplace add, with no earlier signal
  # anywhere else in this repo's tooling.
  if ! python3 << 'PYEOF'
import json, os, sys
d = json.load(open(".claude-plugin/marketplace.json"))
fail = False
for p in d.get("plugins", []):
    name = p.get("name", "<unnamed>")
    src = p.get("source", "")
    resolved = os.path.normpath(src)
    if not os.path.isdir(resolved):
        print(f"FAIL: plugin '{name}' source '{src}' does not resolve to a directory")
        fail = True
    plugin_json = os.path.join(resolved, ".claude-plugin", "plugin.json")
    if not os.path.isfile(plugin_json):
        print(f"FAIL: plugin '{name}' missing {plugin_json}")
        fail = True
    # Claude Code's plugin loader only ever discovers skills under <source>/skills/ —
    # either <source>/skills/SKILL.md directly, or <source>/skills/<subdir>/SKILL.md.
    # A plugin whose source points at a folder with SKILL.md at its own root (no "skills"
    # wrapper) installs with 0 skills and no error — this caught that exact regression.
    skills_dir = os.path.join(resolved, "skills")
    direct = os.path.isfile(os.path.join(skills_dir, "SKILL.md"))
    nested = os.path.isdir(skills_dir) and any(
        os.path.isfile(os.path.join(skills_dir, d, "SKILL.md"))
        for d in os.listdir(skills_dir) if os.path.isdir(os.path.join(skills_dir, d))
    )
    if not (direct or nested):
        print(f"FAIL: plugin '{name}' source '{src}' has no discoverable SKILL.md under {skills_dir} — installs with 0 skills")
        fail = True
if fail:
    sys.exit(1)
print("OK: every marketplace.json plugin entry resolves to a real directory with its own plugin.json")
PYEOF
  then
    PLUGIN_FAIL=1
  fi
fi
for f in skills/*/.claude-plugin/plugin.json; do
  if python3 -c "import json; json.load(open('$f'))" 2>/dev/null; then
    echo "OK: $f"
  else
    echo "FAIL: $f does not parse as valid JSON"
    PLUGIN_FAIL=1
  fi
done
if [ "$PLUGIN_FAIL" -ne 0 ]; then
  echo ""
  echo "Plugin-marketplace manifest problem detected — /plugin marketplace add would fail or"
  echo "mislead a real user. Fix before publishing."
  exit 1
fi

echo ""
echo "All checks passed."
