///|
test "concurrent creation of identical container section ([dev-dependencies] / scripts) merges inner keys" {
  let base_toml = "[package]\nname = \"app\"\n"
  let left_toml = "[package]\nname = \"app\"\n\n[dev-dependencies]\ninsta = \"1.40\"\n"
  let right_toml = "[package]\nname = \"app\"\n\n[dev-dependencies]\nproptest = \"1.5\"\n"
  let res = @merger.merge_3way(
    base_toml,
    left_toml,
    right_toml,
    @merger.MergeOptions::for_language(@cst.Toml),
  )
  assert_eq(res.conflict_count, 0)
  assert_true(res.syntax_valid)
  assert_true(res.merged_text.contains("insta = \"1.40\""))
  assert_true(res.merged_text.contains("proptest = \"1.5\""))

  let base_json = "{\n  \"name\": \"pkg\"\n}\n"
  let left_json = "{\n  \"name\": \"pkg\",\n  \"scripts\": {\n    \"build\": \"moon build\"\n  }\n}\n"
  let right_json = "{\n  \"name\": \"pkg\",\n  \"scripts\": {\n    \"test\": \"moon test\"\n  }\n}\n"
  let jres = @merger.merge_3way(
    base_json,
    left_json,
    right_json,
    @merger.MergeOptions::for_language(@cst.Json),
  )
  assert_eq(jres.conflict_count, 0)
  assert_true(jres.syntax_valid)
  assert_true(jres.merged_text.contains("\"build\": \"moon build\""))
  assert_true(jres.merged_text.contains("\"test\": \"moon test\""))
}

///|
test "malformed input triggers conservative diff3 safety fallback instead of corrupt CST weave" {
  let broken_base = "{\n  \"a\": 1\n  \"missing_comma\": 2\n}\n"
  let left = "{\n  \"a\": 10\n  \"missing_comma\": 2\n}\n"
  let right = "{\n  \"a\": 1\n  \"missing_comma\": 20\n}\n"
  let res = @merger.merge_3way(
    broken_base,
    left,
    right,
    @merger.MergeOptions::for_language(@cst.Json),
  )
  assert_true(res.safety_fallback_used)
}
