///|
test "Unicode CJK, emoji, and multiline trivia preservation in CST" {
  let doc = "// 中文注释 🚀\n///|\npub fn greet() -> String {\n  \"你好 🌍\"\n}\n"
  let sm = @cst.SourceMap::from_source(doc)
  let leaf = @cst.CstNode::leaf(
    id=0,
    @cst.FnDecl,
    "pub fn greet() -> String {\n  \"你好 🌍\"\n}\n",
    signature=Some("fn:greet"),
    leading_trivia=[
      @cst.Trivia::new(@cst.LineComment, "// 中文注释 🚀\n"),
      @cst.Trivia::block_sep(),
    ],
  )
  assert_eq(leaf.unparse(), doc)
  assert_eq(@cst.extract_comments(leaf.leading_trivia).length(), 1)
  assert_eq(
    @cst.detect_indent_unit("{\n    \"a\": 1,\n    \"b\": 2\n}\n"),
    "    ",
  )
  assert_eq(@cst.detect_indent_unit("{\n\t\"a\": 1,\n\t\"b\": 2\n}\n"), "\t")
  assert_true(sm.lookup(15).line >= 2)
}

///|
test "hash_normalized_code_str preserves whitespace inside string literals while normalizing outer whitespace" {
  let h1 = @cst.hash_normalized_code_str(0UL, "let   s =  \"a   b\" ")
  let h2 = @cst.hash_normalized_code_str(0UL, "let s = \"a   b\"")
  let h3 = @cst.hash_normalized_code_str(0UL, "let s = \"a b\"")
  assert_eq(h1, h2)
  assert_true(h1 != h3)
}

///|
test "reindex_tree assigns contiguous preorder IDs and format_sexp truncates long leaves cleanly" {
  let c1 = @cst.CstNode::leaf(
    id=99,
    @cst.StringLiteral,
    "\"abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ\"",
  )
  let c2 = @cst.CstNode::leaf(id=42, @cst.NumberLiteral, "12345")
  let parent = @cst.CstNode::interior(id=77, @cst.ArrayNode, [c1, c2])
  let (re, count) = @cst.reindex_tree(parent)
  assert_eq(count, 3)
  let flat = @cst.collect_preorder(re)
  assert_eq(flat.length(), 3)
  assert_eq(flat[0].id, 0)
  assert_eq(flat[1].id, 1)
  assert_eq(flat[2].id, 2)
  let sexp = @cst.format_sexp(re)
  assert_true(sexp.contains("...\""))
}
