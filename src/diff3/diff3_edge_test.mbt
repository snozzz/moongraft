///|
test "regression: atomic string and semver literals never splice across conflicting versions" {
  // Regression test for Bug #1 caught during verification:
  // "1.1.0" vs "2.0.0" over "1.0.0" MUST conflict rather than splicing into "2.1.0"!
  let base = "version = \"1.0.0\"\n"
  let left = "version = \"1.1.0\"\n"
  let right = "version = \"2.0.0\"\n"
  let out = @diff3.merge_lines_diff3(base, left, right, enable_subline=true)
  assert_eq(out.conflict_count, 1)
  assert_false(out.text.contains("\"2.1.0\""))

  let b_num = "const TIMEOUT_SEC : Double = 1.50\n"
  let l_num = "const TIMEOUT_SEC : Double = 1.75\n"
  let r_num = "const TIMEOUT_SEC : Double = 2.50\n"
  let out_num = @diff3.merge_lines_diff3(
    b_num,
    l_num,
    r_num,
    enable_subline=true,
  )
  assert_eq(out_num.conflict_count, 1)
}

///|
test "CRLF line endings and final line without trailing newline round-trip cleanly" {
  let base = "first\r\nsecond\r\nthird"
  let left = "first_mod\r\nsecond\r\nthird"
  let right = "first\r\nsecond\r\nthird_mod"
  let out = @diff3.merge_lines_diff3(base, left, right)
  assert_eq(out.conflict_count, 0)
  assert_eq(out.text, "first_mod\r\nsecond\r\nthird_mod")
}

///|
test "standard 2-way merge style omits base section while custom labels render accurately" {
  let labels = @diff3.MergeLabels::new("ancestor", "branch-a", "branch-b")
  let out = @diff3.merge_lines_diff3(
    "x = 0\n",
    "x = 1\n",
    "x = 2\n",
    style=@diff3.Merge,
    labels~,
  )
  assert_eq(out.conflict_count, 1)
  assert_true(out.text.contains("<<<<<<< branch-a\n"))
  assert_false(out.text.contains("|||||||"))
  assert_true(out.text.contains(">>>>>>> branch-b\n"))
}
