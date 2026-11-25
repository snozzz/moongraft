///|
test "top-level facade merge, structural_diff, solve_conflicts, and snapshot inspection" {
  let base = "import {\n  \"moonbitlang/core/json\",\n}\n"
  let left = "import {\n  \"moonbitlang/core/json\",\n  \"moonbitlang/core/bench\",\n}\n"
  let right = "import {\n  \"moonbitlang/core/json\",\n  \"moonbitlang/core/env\",\n}\n"

  let res = @moongraft.merge(base, left, right, path="moon.pkg")
  assert_true(res.is_clean())
  inspect(
    res.merged_text,
    content=(
      #|import {
      #|  "moonbitlang/core/json",
      #|  "moonbitlang/core/env",
      #|  "moonbitlang/core/bench",
      #|}
      #|
    ),
  )

  let edits = @moongraft.structural_diff(base, res.merged_text, path="moon.pkg")
  json_inspect(edits, content=[
    {
      "kind": "Inserted",
      "syntax_kind": "ImportItem",
      "signature": "import:moonbitlang/core/env",
      "new_line": 1,
      "summary": "Inserted ImportItem `import:moonbitlang/core/env`",
    },
    {
      "kind": "Inserted",
      "syntax_kind": "ImportItem",
      "signature": "import:moonbitlang/core/bench",
      "new_line": 1,
      "summary": "Inserted ImportItem `import:moonbitlang/core/bench`",
    },
  ])

  let json_str = @moongraft.playground_merge_json(
    "moon.pkg", base, left, right, "diff3",
  )
  assert_true(json_str.contains("\"moongraft_conflicts\": 0"))
}
