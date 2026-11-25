///|
test "JSON trailing-comma append trap: standard diff3 conflicts while MoonGraft weaves valid JSON" {
  let base =
    #|{
    #|  "name": "demo",
    #|  "dependencies": {
    #|    "react": "^19.0.0"
    #|  }
    #|}
    #|
  let left =
    #|{
    #|  "name": "demo",
    #|  "dependencies": {
    #|    "react": "^19.0.0",
    #|    "zod": "^3.23.0"
    #|  }
    #|}
    #|
  let right =
    #|{
    #|  "name": "demo",
    #|  "dependencies": {
    #|    "react": "^19.0.0",
    #|    "vite": "^6.0.0"
    #|  }
    #|}
    #|
  let res = @merger.merge_3way(
    base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.Json),
  )
  assert_true(res.line_diff3_conflicts >= 1)
  assert_eq(res.conflict_count, 0)
  assert_true(res.syntax_valid)
  assert_true(res.merged_text.contains("\"zod\": \"^3.23.0\""))
  assert_true(res.merged_text.contains("\"vite\": \"^6.0.0\""))

  // Commutativity law: `merge(O, A, B) == merge(O, B, A)`!
  let res_swapped = @merger.merge_3way(
    base,
    right,
    left,
    @merger.MergeOptions::for_language(@cst.Json),
  )
  assert_eq(res.merged_text, res_swapped.merged_text)
}

///|
test "MoonBit Move + Edit composition: Left reorders ///| blocks while Right edits moved function body" {
  let base =
    #|///|
    #|pub fn first() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|pub fn target(x : Int) -> Int {
    #|  let a = x + 1
    #|  let b = a * 2
    #|  b
    #|}
    #|
  let left =
    #|///|
    #|pub fn target(x : Int) -> Int {
    #|  let a = x + 1
    #|  let b = a * 2
    #|  b
    #|}
    #|
    #|///|
    #|pub fn first() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|pub fn added_by_agent_a() -> String {
    #|  "ok"
    #|}
    #|
  let right =
    #|///|
    #|pub fn first() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|pub fn target(x : Int) -> Int {
    #|  let a = x + 100
    #|  let b = a * 2
    #|  b
    #|}
    #|
    #|///|
    #|pub fn added_by_agent_b() -> Bool {
    #|  true
    #|}
    #|
  let res = @merger.merge_3way(
    base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.MoonBit),
  )
  assert_true(res.line_diff3_conflicts >= 1)
  assert_eq(res.conflict_count, 0)
  assert_true(res.syntax_valid)
  assert_true(res.merged_text.contains("let a = x + 100"))
  assert_true(res.merged_text.contains("pub fn added_by_agent_a()"))
  assert_true(res.merged_text.contains("pub fn added_by_agent_b()"))
}

///|
test "moon.pkg parallel import additions weave cleanly without conflict" {
  let base =
    #|import {
    #|  "moonbitlang/core/debug",
    #|}
    #|
  let left =
    #|import {
    #|  "moonbitlang/core/debug",
    #|  "moonbitlang/core/hashmap",
    #|}
    #|
  let right =
    #|import {
    #|  "moonbitlang/core/debug",
    #|  "moonbitlang/core/argparse",
    #|}
    #|
  let res = @merger.merge_3way(
    base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.MoonManifest),
  )
  assert_eq(res.conflict_count, 0)
  assert_true(res.syntax_valid)
  assert_true(res.merged_text.contains("\"moonbitlang/core/hashmap\""))
  assert_true(res.merged_text.contains("\"moonbitlang/core/argparse\""))
}

///|
test "true Delete-Modify conflict is soundly flagged (zero silent data loss)" {
  let base =
    #|{
    #|  "keep": true,
    #|  "critical_limit": 100
    #|}
    #|
  let left =
    #|{
    #|  "keep": true
    #|}
    #|
  let right =
    #|{
    #|  "keep": true,
    #|  "critical_limit": 500
    #|}
    #|
  let res = @merger.merge_3way(
    base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.Json),
  )
  assert_eq(res.conflict_count, 1)
  assert_true(res.merged_text.contains("<<<<<<< OURS"))
  assert_true(res.merged_text.contains("500"))
}

///|
test "Cargo.toml inline table + parallel dependency sections merge cleanly" {
  let base =
    #|[package]
    #|name = "demo"
    #|version = "0.1.0"
    #|
    #|[dependencies]
    #|serde = { version = "1.0", features = ["std"] }
    #|
  let left =
    #|[package]
    #|name = "demo"
    #|version = "0.1.0"
    #|
    #|[dependencies]
    #|serde = { version = "1.0", features = ["std"], default-features = false }
    #|anyhow = "1.0"
    #|
  let right =
    #|[package]
    #|name = "demo"
    #|version = "0.1.0"
    #|
    #|[dependencies]
    #|serde = { version = "1.0", features = ["std"], optional = true }
    #|tokio = "1.40"
    #|
  let res = @merger.merge_3way(
    base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.Toml),
  )
  assert_eq(res.conflict_count, 0)
  assert_true(res.syntax_valid)
  assert_true(res.merged_text.contains("default-features = false"))
  assert_true(res.merged_text.contains("optional = true"))
  assert_true(res.merged_text.contains("anyhow = \"1.0\""))
  assert_true(res.merged_text.contains("tokio = \"1.40\""))
}
