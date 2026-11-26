///|
test "all 18 built-in multi-language benchmark cases pass with 100% accuracy" {
  let summary = @report.run_benchmark_suite()
  assert_eq(summary.total_cases, 18)
  assert_eq(summary.expected_clean_cases, 15)
  assert_eq(summary.expected_conflict_cases, 3)
  assert_eq(summary.moongraft_clean_on_resolvable, 15)
  assert_eq(summary.true_conflicts_preserved, 3)
  assert_true(summary.all_assertions_passed)
  assert_true(
    summary.diff3_clean_on_resolvable < summary.moongraft_clean_on_resolvable,
  )
}

///|
test "algebraic merge laws: idempotency, identity, and commutativity across full corpus" {
  let corpus = @report.builtin_benchmark_corpus()
  for c in corpus {
    let opts = @merger.MergeOptions::for_language(c.language)

    let idem_l = @merger.merge_3way(c.base, c.left, c.left, opts)
    assert_eq(idem_l.conflict_count, 0)
    assert_eq(idem_l.merged_text, c.left)

    let idem_r = @merger.merge_3way(c.base, c.right, c.right, opts)
    assert_eq(idem_r.conflict_count, 0)
    assert_eq(idem_r.merged_text, c.right)

    let id_left = @merger.merge_3way(c.base, c.base, c.right, opts)
    assert_eq(id_left.conflict_count, 0)
    assert_eq(id_left.merged_text, c.right)

    let id_right = @merger.merge_3way(c.base, c.left, c.base, opts)
    assert_eq(id_right.conflict_count, 0)
    assert_eq(id_right.merged_text, c.left)

    if c.expect_clean &&
      (
        c.language == @cst.Json ||
        c.language == @cst.MoonManifest ||
        c.language == @cst.Toml
      ) {
      let ab = @merger.merge_3way(c.base, c.left, c.right, opts)
      let ba = @merger.merge_3way(c.base, c.right, c.left, opts)
      assert_eq(ab.conflict_count, 0)
      assert_eq(ba.conflict_count, 0)
      assert_eq(ab.merged_text, ba.merged_text)
    }
  }
}
