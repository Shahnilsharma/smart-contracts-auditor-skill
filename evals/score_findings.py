#!/usr/bin/env python3
"""
score_findings.py — score a real agent run's reported findings against a fixture's
ground-truth vulnerability list (EVAL-METHODOLOGY.md, Layer 3).

HONEST LIMITATION, stated up front: matching "does finding X count as having found
ground-truth item Y" is not a solved, fully-automatable problem for this domain — two
descriptions of the same underlying bug can use completely different wording. This script
does heuristic candidate-matching (keyword/line-number overlap) and asks for human
confirmation on ambiguous cases rather than pretending to fully automate judgment calls
a security reviewer should actually make. Treat its output as a structured worksheet, not
a final score, unless you've reviewed every match it proposes.

Usage:
  python3 score_findings.py <ground_truth.json> <findings.json>

<findings.json> format — write this from the agent's actual reported findings:
[
  {
    "title": "...",
    "category": "...",
    "severity": "Critical|High|Medium|Low|Informational",
    "location": "...",           // e.g. "swap(), line 60" — free text, matched heuristically
    "poc_executed": true/false,  // per Phase 6.5 — was an actual test run and shown, not just described?
    "notes": "..."
  },
  ...
]
"""
import json
import re
import sys


def normalize_location(loc: str) -> set:
    """Extract comparable tokens from a location string: function names, line numbers."""
    if not loc:
        return set()
    tokens = set(re.findall(r"[A-Za-z_][A-Za-z0-9_]*\(\)|line[s]?\s*\d+(?:-\d+)?|#?\d+", loc.lower()))
    words = set(w for w in re.findall(r"[a-z_]{4,}", loc.lower()) if w not in {"line", "lines"})
    return tokens | words


def candidate_score(gt_item: dict, finding: dict) -> float:
    """Heuristic overlap score, 0.0-1.0. Higher = more likely to be the same issue.
    NOT a confirmed match — see module docstring."""
    gt_loc = normalize_location(gt_item.get("location", ""))
    f_loc = normalize_location(finding.get("location", ""))
    loc_overlap = len(gt_loc & f_loc) / max(len(gt_loc), 1) if gt_loc else 0.0

    gt_cat_words = set(re.findall(r"[a-z]{4,}", gt_item.get("category", "").lower()))
    f_cat_words = set(re.findall(r"[a-z]{4,}", finding.get("category", "").lower()))
    cat_overlap = len(gt_cat_words & f_cat_words) / max(len(gt_cat_words), 1) if gt_cat_words else 0.0

    gt_desc_words = set(re.findall(r"[a-z]{5,}", gt_item.get("description", "").lower()))
    f_desc_words = set(
        re.findall(r"[a-z]{5,}", (finding.get("description", "") + " " + finding.get("title", "")).lower())
    )
    desc_overlap = len(gt_desc_words & f_desc_words) / max(len(gt_desc_words), 1) if gt_desc_words else 0.0

    return 0.5 * loc_overlap + 0.25 * cat_overlap + 0.25 * desc_overlap


def main():
    if len(sys.argv) != 3:
        print(__doc__)
        sys.exit(1)

    gt_path, findings_path = sys.argv[1], sys.argv[2]
    gt = json.load(open(gt_path))
    findings = json.load(open(findings_path))

    vulns = gt["vulnerabilities"]
    print(f"Ground truth: {gt['fixture']} — {len(vulns)} planted vulnerabilities")
    print(f"Findings under evaluation: {len(findings)}")
    print()

    MATCH_THRESHOLD = 0.3  # below this, don't even propose it as a candidate — tune per use

    matched_gt_ids = set()
    matched_finding_idxs = set()
    print("=== Candidate matches (heuristic — REVIEW EACH ONE, don't trust blindly) ===")
    for gi, v in enumerate(vulns):
        best_fi, best_score = None, 0.0
        for fi, f in enumerate(findings):
            s = candidate_score(v, f)
            if s > best_score:
                best_fi, best_score = fi, s
        if best_score >= MATCH_THRESHOLD:
            print(f"  {v['id']} ({v['severity']}, {v['category']}) <-> finding #{best_fi} "
                  f"\"{findings[best_fi].get('title', '')[:60]}\" — heuristic score {best_score:.2f}")
            matched_gt_ids.add(v["id"])
            matched_finding_idxs.add(best_fi)
        else:
            print(f"  {v['id']} ({v['severity']}, {v['category']}) — NO CANDIDATE MATCH FOUND (likely a miss)")

    print()
    recall = len(matched_gt_ids) / len(vulns) if vulns else 0.0
    precision = len(matched_finding_idxs) / len(findings) if findings else 0.0
    f1 = (2 * precision * recall / (precision + recall)) if (precision + recall) > 0 else 0.0

    print("=== Scores (based on heuristic candidate matches above — confirm before trusting) ===")
    print(f"  Recall:    {recall:.0%}  ({len(matched_gt_ids)}/{len(vulns)} ground-truth items have a candidate match)")
    print(f"  Precision: {precision:.0%}  ({len(matched_finding_idxs)}/{len(findings)} reported findings matched something real)")
    print(f"  F1:        {f1:.2f}")

    print()
    print("=== PoC-validation compliance (Phase 6.5 gate) ===")
    high_sev = [f for f in findings if f.get("severity") in ("Critical", "High")]
    validated = [f for f in high_sev if f.get("poc_executed") is True]
    if high_sev:
        print(f"  {len(validated)}/{len(high_sev)} Critical/High findings have poc_executed=true "
              f"({len(validated)/len(high_sev):.0%} compliance)")
        for f in high_sev:
            if not f.get("poc_executed"):
                print(f"    NOT VALIDATED: \"{f.get('title', '')[:70]}\" — should be downgraded "
                      f"or explicitly marked unconfirmed per agency-audit-methodology.md Phase 6.5")
    else:
        print("  No Critical/High findings reported — nothing to check here.")


if __name__ == "__main__":
    main()
