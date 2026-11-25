///|
test "lossless leaf and interior unparse preserves exact trivia" {
  let entry_a = @cst.CstNode::leaf(
    id=1,
    @cst.ObjectEntry,
    "\"a\": 1",
    signature=Some("key:a"),
    leading_trivia=[@cst.Trivia::spaces("  ")],
    trailing_trivia=[@cst.Trivia::newline()],
  )
  let comma = @cst.CstNode::leaf(id=2, @cst.Punctuation, ",")
  let entry_b = @cst.CstNode::leaf(
    id=3,
    @cst.ObjectEntry,
    "\"b\": 2",
    signature=Some("key:b"),
    leading_trivia=[@cst.Trivia::newline(), @cst.Trivia::spaces("  ")],
    trailing_trivia=[@cst.Trivia::newline()],
  )
  let obj = @cst.CstNode::interior(
    id=0,
    @cst.ObjectNode,
    [entry_a, comma, entry_b],
    ordering=@cst.CommutativeByKey,
    leading_trivia=[@cst.Trivia::new(@cst.LineComment, "// header\n")],
  )
  let rendered = obj.unparse()
  assert_eq(rendered, "// header\n  \"a\": 1\n,\n  \"b\": 2\n")
}

///|
test "commutative structural hash is invariant under child reordering and trivia edits" {
  let k1_left = @cst.CstNode::leaf(
    id=1,
    @cst.ImportItem,
    "\"moonbitlang/core/json\"",
    signature=Some("import:moonbitlang/core/json"),
    leading_trivia=[@cst.Trivia::spaces("  ")],
    trailing_trivia=[@cst.Trivia::newline()],
  )
  let k2_left = @cst.CstNode::leaf(
    id=2,
    @cst.ImportItem,
    "\"moonbitlang/core/buffer\"",
    signature=Some("import:moonbitlang/core/buffer"),
    leading_trivia=[@cst.Trivia::spaces("  ")],
    trailing_trivia=[@cst.Trivia::newline()],
  )
  let group_ab = @cst.CstNode::interior(
    id=0,
    @cst.ImportGroup,
    [k1_left, k2_left],
    ordering=@cst.CommutativeByKey,
  )

  let k2_right = k2_left.with_trivia(leading_trivia=[
    @cst.Trivia::spaces("    "),
  ])
  let k1_right = k1_left.with_trivia(leading_trivia=[
    @cst.Trivia::spaces("    "),
  ])
  let group_ba = @cst.CstNode::interior(
    id=0,
    @cst.ImportGroup,
    [k2_right, k1_right],
    ordering=@cst.CommutativeByKey,
  )

  assert_eq(group_ab.structural_hash, group_ba.structural_hash)
  assert_true(group_ab.exact_hash != group_ba.exact_hash)
}

///|
test "source map lookup and duplicate signature detection" {
  let src = "line1\nline2\n  fn foo() {}\n"
  let sm = @cst.SourceMap::from_source(src)
  assert_eq(sm.lookup(0), { line: 1, column: 1, })
  assert_eq(sm.lookup(6), { line: 2, column: 1, })
  assert_eq(sm.lookup(14), { line: 3, column: 3, })

  let d1 = @cst.CstNode::leaf(
    id=1,
    @cst.FnDecl,
    "fn f() {}",
    signature=Some("fn:f"),
  )
  let d2 = @cst.CstNode::leaf(
    id=2,
    @cst.FnDecl,
    "fn f() { 1 }",
    signature=Some("fn:f"),
  )
  let file = @cst.CstNode::interior(
    id=0,
    @cst.SourceFile,
    [d1, d2],
    ordering=@cst.CommutativeBlocks,
  )
  let dups = @cst.find_duplicate_signatures(file)
  assert_eq(dups, ["fn:f"])
}
