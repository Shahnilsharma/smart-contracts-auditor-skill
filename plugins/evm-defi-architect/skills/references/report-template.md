# Professional report formatting — title page, structure, color, typography

Researched against how real firms actually format deliverables (Trail of Bits, OpenZeppelin, ConsenSys Diligence, Spearbit/Cantina, Halborn, Code4rena-style reports) before writing this — not invented. The audit report from `agency-audit-methodology.md` Phase 7 has the right *content* structure already; this file is the *presentation* layer on top of it — use it whenever the user wants a polished deliverable (asks for a "report," a "PDF," a "Word doc," something to "send to a client/investor," or anything implying a document rather than a chat answer), not for a quick in-chat summary of a couple of findings.

## When to use this vs. plain markdown

- Quick in-chat findings summary, a couple of issues, exploratory back-and-forth → plain markdown in the conversation, no need for this.
- "Write up the audit report," "give me something I can send to the team/investors," "make this look professional," anything implying a standalone document → follow this file, produce a `.docx` (read the `docx` skill first — it's a separate skill with real gotchas, don't wing the XML) or a well-structured `.md`/`.pdf` if the user specifically wants those instead.

## Document structure, in order (this is what real firms ship)

1. **Cover / title page** (own page, page break after)
2. **Table of contents** (auto-generated from heading levels — see docx notes below)
3. **Disclaimer** (short — see wording below)
4. **Scope & methodology recap** (Phase 0/7 content — commit hash, files in/out of scope, trust assumptions, tools used)
5. **Executive summary** (1-2 paragraphs of narrative + a **findings summary table**, color-coded by severity — this is the single most-copied section from a real report, don't skip the table)
6. **Detailed findings** (one per finding, structured fields — see below)
7. **Coverage traceability matrix** (from the chain's `audit-checklist.md` — OWASP SC Top 10 / Sealevel Attacks / Oak Security mapping)
8. **Appendix** (fix-review status table if applicable, tool versions used, full scope file list)

## Cover page contents

Centered, generous whitespace, in this order:
- Report title: `"<Project Name>" Smart Contract Security Assessment` (or "Audit Report" — firms use both; either is fine)
- Chain/ecosystem (e.g. "CosmWasm — ZIGChain", "Solidity — Ethereum Sepolia", "Anchor — Solana Devnet")
- Prepared for: `<client/project name>`
- Prepared by: name whoever is running this (a person, a team name, or "Claude via the evm-defi-architect skill" if no other identity was given — don't fabricate a firm name)
- Date, and a version/revision number if this is a re-issue after fix-review
- If team mode was used: list the roles that contributed (architect / contract-engineer / qa-fuzzer / static-analyst / auditor), not fabricated individual human names

## Disclaimer wording (adapt, don't skip)

> This report is provided for informational purposes only and does not constitute investment, legal, or financial advice. Automated and AI-assisted analysis was used as part of this review — see this suite's `LIMITATIONS-AND-COMPARISON.md` for what that does and doesn't guarantee. No audit can guarantee the complete absence of vulnerabilities. The scope of this review is limited to the files and commit listed in the Scope section; anything outside that scope was not reviewed.

## Findings summary table (executive summary)

| ID | Title | Severity | Status |
|---|---|---|---|
| EVM-01 | Reentrancy in swap() | 🔴 Critical | Unresolved |
| EVM-02 | Missing slippage protection | 🟠 High | Acknowledged |
| ... | | | |

Severity color convention (matches the standard used across security tooling and this suite's own severity tables) — apply as **text color or cell shading**, not just the word:
- **Critical** — dark red (`#780000` / RGB 120,0,0)
- **High** — red (`#DC0000` / RGB 220,0,0)
- **Medium** — orange (`#FD8C00` / RGB 253,140,0)
- **Low** — amber/yellow (`#FDC500` / RGB 253,197,0) — use dark text on this one, not white, for contrast
- **Informational** — blue or gray (`#4A90D9` or `#6B7280`)

## Detailed finding format (one per finding, in the findings section)

```
### [EVM-01] Reentrancy in swap() allows draining pool reserves
**Severity:** Critical (impact: High — direct fund loss; likelihood: High — no special
access required, exploitable by any caller with a malicious token)
**Location:** Pool.sol, swap(), lines 60-69
**Status:** Unresolved

**Description:** ...
**Impact:** ...
**Proof of Concept:** <the executed test from Phase 6.5 — reference it, show the result>
**Recommendation:** ...
```
Title uses the finding ID + a plain-language summary (not just the category name). Severity line always states both impact and likelihood, per this suite's risk-matrix methodology — never severity with no reasoning shown. A horizontal rule or page-appropriate spacing between findings; each finding's severity heading in its matching color per the table above.

## Typography conventions (apply whichever your output format supports)

- Finding titles: **bold**, and colored per severity where the format supports text color (docx/HTML) — plain bold-only where it doesn't (plain markdown).
- Code/file paths/function names: `monospace` inline, fenced code blocks for excerpts — never plain prose for a code reference.
- Section headers: consistent heading hierarchy (H1 = report title only, H2 = major sections, H3 = individual findings) so a generated table of contents nests correctly.
- Emphasis: bold for severity/status labels and finding titles; *italics* sparingly for a scope caveat or a reviewer's aside, not for whole paragraphs; avoid underline in digital documents (a docx/PDF convention leftover from typewriters that now visually collides with hyperlinks) — use bold or color instead of underline for emphasis.
- Don't overuse all-caps or exclamation points for severity — the color + the word "Critical"/"High" is the convention, not shouting.

## Producing this as an actual `.docx` (read the `docx` skill first, every time — don't improvise the XML)

Concretely, per that skill's documented API:
- Cover page: a `Paragraph` sequence with large centered `TextRun`s, ending in a `PageBreak` (must be inside a `Paragraph`, not standalone).
- TOC: use built-in `HeadingLevel.*` on every section/finding heading — a custom style without `outlineLevel` won't appear in the generated TOC.
- Severity color: `TextRun({ text: "Critical", color: "780000", bold: true })` for inline severity labels; for the summary table, `TableCell` with `shading: { type: ShadingType.CLEAR, fill: "780000" }` (never `SOLID` — it renders black per that skill's own documented gotcha) and white/light `TextRun` color inside for contrast on the darker severities.
- Findings summary table: `columnWidths` on the table **and** `width` on every cell (both DXA), or it breaks in Google Docs per that skill's own warning.
- After writing the file, render and actually look at it (`soffice.py --headless --convert-to pdf` then `pdftoppm`) before delivering — don't assume the XML rendered as intended.

## Producing this as markdown/PDF instead

If the user wants markdown (for a GitHub-flavored render) or a PDF via the `pdf` skill instead of `.docx`: use the same structure and section order above; for severity color in markdown, GitHub/most renderers support neither arbitrary text color nor table-cell shading, so use the colored-circle emoji convention shown in the findings-summary-table example above (🔴🟠🟡🔵) alongside the word, plus **bold** for the word itself — that combination is the practical markdown-native equivalent of a color-coded badge. For PDF, follow the `pdf` skill's own guidance for anything beyond a straight markdown-to-PDF conversion (real color/layout control in PDF has its own toolchain, don't assume markdown's limitations apply).
