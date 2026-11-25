# MoonGraft Architecture & Verification Report

## 1. Design Philosophy & Safety Invariants

Syntax-aware 3-way code merging faces an asymmetric risk profile: **a false conflict costs developer time, whereas a silent bad merge corrupts a repository**. `MoonGraft` is architected around four formal invariants:

1. **Lossless CST Round-Trip Invariant**:
   $$\forall s \in \Sigma^*, L \in \text{Languages}:\quad \text{unparse}(\text{parse}(s, L)) \equiv s$$
   Every byte of whitespace, comments (`//`, `///`, `#`, `/* ... */`), CRLF/LF line endings, and MoonBit `///|` separators is attached as `leading_trivia` or `trailing_trivia` on immutable `CstNode` values.
2. **Algebraic Merge Laws**:
   - **Idempotency**: $\text{merge}(O, A, A) = A$
   - **Left & Right Identity**: $\text{merge}(O, O, B) = B$ and $\text{merge}(O, A, O) = A$
   - **Commutativity on Keyed Containers**: When branches $A$ and $B$ perform non-conflicting insertions/edits on `CommutativeByKey` containers (JSON objects, TOML tables, `moon.pkg` imports), deterministic anchor + lexicographical tie-breaking guarantees $\text{merge}(O, A, B) = \text{merge}(O, B, A)$.
3. **Zero Silent Data Loss on True Conflicts**:
   `Delete-Modify`, `Modify-Delete`, and conflicting scalar `Add-Add` / `Modify-Modify` edits always emit localized Git conflict markers (`diff3`, `zdiff3`, or `merge`).
4. **Post-Merge Syntactic & Duplicate-Signature Soundness Gate**:
   Every candidate clean merge ($0$ conflicts) is re-parsed by `verify_well_formed(merged_text, lang)` to check (a) zero parser error fragments, (b) balanced global delimiters outside strings/comments, and (c) zero duplicate semantic signatures (`find_duplicate_signatures`). If any check fails, `MoonGraft` automatically falls back to conservative line-based `diff3`.

---

## 2. Core Pipeline Stages

### Stage 1: Dual-Hash Lossless CST (`src/cst`)
Each `CstNode` precomputes two 64-bit hashes during bottom-up construction:
- **`structural_hash`**: Computed over normalized non-whitespace tokens (while keeping whitespace inside string literals intact!). For `CommutativeByKey` and `CommutativeBlocks` containers, child hashes are combined via SplitMix64 avalanche + **order-independent `(XOR, modular sum)`** so reordering imports, JSON keys, or MoonBit `///|` functions yields the exact same `structural_hash`.
- **`exact_hash`**: Sequential FNV-1a + SplitMix64 over all tokens and trivia, enabling $O(1)$ fast paths when formatting is untouched.

### Stage 2: Six Lossless Language Frontends (`src/lang`)
- **MoonBit (`.mbt`, `.mbti`)**: Treats top-level `///|` blocks as `CommutativeBlocks`, extracts qualified signatures (`fn:Type::method`, `test:name`, `struct:Name`, `enum:Name`, `suberror:Name`, `impl:...`), decomposes `struct`/`enum`/`suberror` bodies into `CommutativeByKey` field/variant blocks, and splits function bodies into statement-level `Block` nodes.
- **MoonBit Manifests (`moon.pkg`, `moon.mod`)**: Parses `import { ... }` and `import { ... } for "test"` into `CommutativeByKey` `ImportGroup` nodes, plus `options(...)`, `pkgtype(...)`, and module metadata assignments.
- **JSON / JSONC**: Recursive-descent CST for nested objects (`CommutativeByKey`), arrays (auto-extracting `"elem:id=..."` / `"elem:name=..."` signatures for keyed object arrays!), comments, and trailing commas.
- **TOML**: Section-level `[table]` and `[[array_of_tables]]` containers plus recursive parsing of inline tables `{ version = "1.0", features = [...] }`.
- **YAML**: Indentation-tracking parser for nested block mappings (`CommutativeByKey`), multiline `|`/`>` scalars, and sequence items keyed by `- name:` / `- id:` (e.g., GitHub Actions steps and Kubernetes containers).
- **TypeScript / JavaScript, Python & Rust**: Consecutive `import` / `from ... import` / `use` statements grouped into `CommutativeByKey` `ImportGroup` nodes, plus class/struct/trait/function declarations with nested member/statement blocks.

### Stage 3: Two-Phase GumTree + Signature Matching (`src/matcher`)
1. **Top-Down Height-Indexed Merkle Phase**: Matches maximal identical subtrees from height $H_{\max}$ down to $1$, resolving ambiguous duplicates via parent signature context and positional proximity. Isomorphic binding on commutative containers pairs children by `(signature, structural_hash)` rather than raw index.
2. **Signature & Bottom-Up Dice Recovery Phase**: Pairs modified declarations across moves via semantic signatures, recovers unnamed blocks via Dice similarity ($\frac{2|D_1 \cap D_2|}{|D_1| + |D_2|} \ge 0.45$), aligns sequential statements with Patience diff, and identifies moved declarations via Longest Increasing Subsequence (LIS) complement.

### Stage 4: 3-Way Weaving, Rename Analysis & Octopus Workspace Merge (`src/merger`, `src/refactor`, `src/workspace`)
- **Separator Synthesis (`separators.mbt`)**: Strips raw `,` tokens before weaving commutative entries and synthesizes exact commas and indentation during reassembly—eliminating the JSON/`moon.pkg` trailing-comma conflict class.
- **Cross-Branch Rename Hazard Detector (`src/refactor`)**: Computes body token multiset Dice similarity ($\ge 65\%$) between unmatched removed and added declarations to detect renames and warn (or optionally rewrite) when another branch introduces new references to the stale name.
- **Multi-Agent Octopus Reconciler (`src/workspace`)**: Iteratively folds $K$ parallel agent file-trees over a shared base snapshot.

---

## 3. Real Bugs Caught & Prevented by the Verification Harness

In accordance with **Dimension 04 (开发与验证能力)**, `MoonGraft` was developed inside a tight verification closed-loop (`moon test` + 16-case corpus + `scripts/verify_harness.py` invoking real `git merge-file` and `moon check`). Below are **four real bugs** caught and fixed by our verification harness during engineering, each preserved as a permanent regression test:

1. **Critical Soundness Bug — Sub-Line Semver/String Literal Splicing (`src/diff3/diff3_edge_test.mbt`)**:
   - *Symptom*: In `conflict-same-key-scalar`, `Base` had `version = "1.0.0"`, `Left` bumped to `"1.1.0"`, and `Right` bumped to `"2.0.0"`. Early character-class sub-line tokenization split `"1.0.0"` on `.` into separate tokens `"1"`, `"."`, `"0"`, `"."`, `"0"`, causing `try_subline_merge` to splice both edits into `"2.1.0"` with 0 conflicts!
   - *Fix & Regression*: Redesigned `tokenize_line` so quoted string literals (`"..."`, `'...'`) and numeric/version literals (`[0-9][0-9A-Za-z._-]*`) are strictly indivisible atomic tokens. Added permanent regression test in `src/diff3/diff3_edge_test.mbt`.
2. **Keyed JSON Array Bracket Stripping (`src/merger/commutative.mbt`)**:
   - *Symptom*: Keyed object arrays (`[{"id": "core"}, ...]`) delegated to `merge_commutative_containers`, where `split_container_parts` initially checked only `{` and `}`, treating `[` and `]` as ordinary items and triggering a false conflict in `json-keyed-array`.
   - *Fix*: Generalized delimiter extraction in `split_container_parts` to handle both `{ ... }` and `[ ... ]`.
3. **YAML `MappingEntry` Fixed-Tuple Recursion (`src/merger/sequential.mbt`)**:
   - *Symptom*: Parallel additions to GitHub Actions `steps:` (`yaml-gha-steps`) failed to recurse from `MappingEntry("key:steps")` into its child `SequenceNode` because `@cst.MappingEntry` was omitted from `is_fixed_tuple_node`.
   - *Fix*: Registered `@cst.MappingEntry` in `is_fixed_tuple_node`, enabling clean recursive weaving of named YAML workflow steps.
4. **Rust Lifetime Annotations vs Single-Quoted Literals (`src/lang/code_cst.mbt`)**:
   - *Symptom*: Property matrix test `lang_matrix_test.mbt` on `pub fn trim_view<'a>(input: &'a str) -> &'a str { ... }` caught `scan_quoted_string()` consuming from the first `'a` to the second `'a` across generic parameters and skipping `{`.
   - *Fix*: Added `is_rust_lifetime_token` lookahead distinguishing `'lifetime` identifiers from `'c'`/`'\n'` character literals and JS/TS single-quoted strings.
