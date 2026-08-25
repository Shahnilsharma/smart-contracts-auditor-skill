# Toolchain compatibility — verify every run, don't assume

Version drift between Rust, Solana CLI (Agave), and Anchor CLI/`anchor-lang` is the single most common source of broken builds in this ecosystem. Confirm current versions rather than trusting memory — this file records known historical failure patterns, not a live version pin.

## Known failure patterns (check if hit, don't assume still current)

- **`anchor-lang` (Cargo.toml) vs `anchor --version` mismatch**: build may succeed with a warning or fail outright depending on how far apart they are. Always match them exactly, or upgrade both together.
- **Anchor 0.30.x + Rust ≥1.80**: historically broke due to a `time` crate incompatibility (unknown feature `proc_macro_span_shrink`). Fixed in later Anchor releases — if hit, either pin Rust to an older toolchain for that Anchor version or upgrade Anchor.
- **Anchor CLI install source**: the actively maintained fork moved to `solana-foundation/anchor` (previously `coral-xyz/anchor`) — install via AVM (`avm install latest && avm use latest`) rather than a stale `cargo install` command copied from an old tutorial.
- **Solana CLI is now "Agave"**: the validator/CLI client formerly "Solana Labs" is now maintained as Agave (Anza). Install/update via the current official install script — check `solana.com`/Anza docs for the current script URL rather than reusing an old one, this has changed.
- **GLIBC version errors running `anchor`**: usually a platform-tools/Rust-toolchain mismatch on Linux — check `references/solana-cluster-defaults.md`-adjacent troubleshooting sources (or ask the user for their `anchor --version` / `solana --version` / `rustc --version` output) before guessing a fix.

## Before writing code, always confirm

```bash
anchor --version
solana --version      # look for "Agave" in the client string
rustc --version
cat Cargo.toml | grep anchor-lang   # if project exists already
```
If versions look inconsistent with each other, resolve that first — most "weird" build errors in this stack trace back to a version mismatch, not actual code bugs.
