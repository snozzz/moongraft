///|
test "diff3 merges disjoint line regions cleanly" {
  let base = "a\nb\nc\nd\ne\n"
  let left = "a_left\nb\nc\nd\ne\n"
  let right = "a\nb\nc\nd\ne_right\n"
  let out = @diff3.merge_lines_diff3(base, left, right)
  assert_eq(out.conflict_count, 0)
  assert_eq(out.text, "a_left\nb\nc\nd\ne_right\n")
}

///|
test "diff3 collapses identical concurrent modifications (false conflict)" {
  let base = "let x = 1\nlet y = 2\n"
  let left = "let x = 42\nlet y = 2\n"
  let right = "let x = 42\nlet y = 2\n"
  let out = @diff3.merge_lines_diff3(base, left, right)
  assert_eq(out.conflict_count, 0)
  assert_eq(out.text, "let x = 42\nlet y = 2\n")
}

///|
test "diff3 emits standard markers on true conflict and zdiff3 trims common wrapper" {
  let base = "{\n  \"port\": 8080\n}\n"
  let left = "{\n  \"host\": \"0.0.0.0\",\n  \"port\": 8081,\n  \"tls\": true\n}\n"
  let right = "{\n  \"host\": \"0.0.0.0\",\n  \"port\": 9090,\n  \"tls\": true\n}\n"

  let d3 = @diff3.merge_lines_diff3(base, left, right, style=@diff3.Diff3)
  assert_eq(d3.conflict_count, 1)
  assert_true(d3.text.contains("<<<<<<< OURS"))
  assert_true(d3.text.contains("||||||| BASE"))

  let zd3 = @diff3.merge_lines_diff3(base, left, right, style=@diff3.ZDiff3)
  assert_eq(zd3.conflict_count, 1)
  assert_true(
    zd3.text.has_prefix("{\n  \"host\": \"0.0.0.0\",\n<<<<<<< OURS\n"),
  )
  assert_true(zd3.text.has_suffix(">>>>>>> THEIRS\n  \"tls\": true\n}\n"))
}

///|
test "subline token merge resolves separated edits on single signature line" {
  let base = "pub fn connect(host : String, port : Int, timeout : Int) -> Bool\n"
  let left = "pub fn connect(endpoint : String, port : Int, timeout : Int) -> Bool\n"
  let right = "pub fn connect(host : String, port : Int, timeout : Int) -> Result[Bool, Error]\n"
  let out = @diff3.merge_lines_diff3(base, left, right, enable_subline=true)
  assert_eq(out.conflict_count, 0)
  assert_eq(out.subline_resolved, 1)
  assert_eq(
    out.text,
    "pub fn connect(endpoint : String, port : Int, timeout : Int) -> Result[Bool, Error]\n",
  )
}
