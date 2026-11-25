///|
test "top-level facade merge, structural_diff, solve_conflicts, and JSON bridge" {
  let base = "import {\n  \"moonbitlang/core/json\",\n}\n"
  let left = "import {\n  \"moonbitlang/core/json\",\n  \"moonbitlang/core/bench\",\n}\n"
  let right = "import {\n  \"moonbitlang/core/json\",\n  \"moonbitlang/core/env\",\n}\n"

  let res = @moongraft.merge(base, left, right, path="moon.pkg")
  assert_true(res.is_clean())
  assert_true(res.merged_text.contains("\"moonbitlang/core/bench\""))
  assert_true(res.merged_text.contains("\"moonbitlang/core/env\""))

  let edits = @moongraft.structural_diff(base, res.merged_text, path="moon.pkg")
  assert_eq(edits.length(), 2)

  let json_str = @moongraft.playground_merge_json(
    "moon.pkg", base, left, right, "diff3",
  )
  assert_true(json_str.contains("\"moongraft_conflicts\": 0"))
}
