# Changelog

All notable changes to `MoonGraft` (`snozzz/moongraft`) are documented in this file.

## [0.1.0] - 2026-11-25

### Added
- **Lossless Concrete Syntax Tree (`src/cst`)**: Immutable Red-Green trivia-preserving CST nodes, dual 64-bit SplitMix64/FNV-1a structural (commutative multiset) and exact Merkle hashes, `SourceMap` line/column lookup, duplicate signature detector, and S-expression formatter.
- **3-Way Line & Sub-Line Fallback Engine (`src/diff3`)**: Patience/Myers 3-way `diff3`, zealous `zdiff3` common prefix/suffix hoisting, standard `merge`/`diff3`/`zdiff3` marker rendering, and atomic-literal-safe intra-line token merge.
- **Six Lossless Language Parsers (`src/lang`)**: Full-fidelity round-trip parsers and structural well-formedness validators for MoonBit (`.mbt`/`.mbti`), MoonBit manifests (`moon.pkg`/`moon.mod`), JSON/JSONC, TOML, YAML, and TypeScript/JavaScript, Python, and Rust.
- **Two-Phase GumTree + Signature Matcher (`src/matcher`)**: Top-down height-priority isomorphic subtree matching, semantic signature declaration matching across moves, bottom-up Dice container recovery, Patience child alignment, and LIS move detection.
- **3-Way Structural CST Merger (`src/merger`)**: Commutative key/block weaving, Move + Edit composition, comma and `///|` separator normalization, concurrent new-section merging, Delete-Modify conflict protection, and post-merge syntactic soundness gate.
- **Post-Facto Conflict Solver (`src/solver`)**: `moongraft solve` parser and resolver for existing `<<<<<<< / ||||||| / ======= / >>>>>>>` and 2-way conflict markers.
- **Rename & Stale Reference Analyzer (`src/refactor`)**: Cross-branch declaration rename detection via Dice body token similarity and stale call-site hazard reporting/rewriting.
- **Multi-Agent Octopus Workspace Reconciler (`src/workspace`)**: N-way iterative CST merge across $K$ parallel agent file snapshots.
- **CLI, Web Workbench & Verification Harness**: Cross-target `moongraft` CLI (`merge`, `solve`, `diff`, `inspect`, `bench-suite`, `setup`), browser playground (`web/index.html`), `moon bench` microbenchmarks, and `scripts/verify_harness.py` (120 randomized trials + real `git merge-file` & `moon check` verification).
