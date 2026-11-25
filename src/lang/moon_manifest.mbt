///|
/// Lossless CST parser for MoonBit manifests (`moon.pkg` DSL and `moon.mod` DSL).
/// Supports:
/// - `import { "pkg/a", "pkg/b" @alias, }` and `import { ... } for "test"` / `for "wbtest"`
/// - `options(...)`, `pkgtype(...)`
/// - `moon.mod` assignments (`name = "..."`, `keywords = [...]`, `deps = ...`)
pub fn parse_moon_manifest_cst(source : String) -> @cst.CstNode {
  // If legacy JSON manifest (`moon.pkg.json` / `moon.mod.json`), delegate to JSON CST!
  let trimmed = source.trim()
  if trimmed.has_prefix("{") {
    return parse_json_cst(source)
  }

  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let items : Array[@cst.CstNode] = []

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia()
    if sc.is_eof() {
      let root = @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        items,
        ordering=@cst.CommutativeByKey,
        trailing_trivia=triv,
        span=@cst.ByteSpan::new(0, source.length()),
      )
      let (reindexed, _) = @cst.reindex_tree(root)
      return reindexed
    }

    if sc.starts_with("import") &&
      (
        sc.peek(delta=6) == Some(' ') ||
        sc.peek(delta=6) == Some('\t') ||
        sc.peek(delta=6) == Some('{') ||
        sc.peek(delta=6) == Some('\n')
      ) {
      items.push(parse_manifest_import_block(sc, ids, triv))
    } else if sc.starts_with("options") &&
      (sc.peek(delta=7) == Some('(') || sc.peek(delta=7) == Some(' ')) {
      items.push(parse_manifest_call_block(sc, ids, triv, "options"))
    } else if sc.starts_with("pkgtype") &&
      (sc.peek(delta=7) == Some('(') || sc.peek(delta=7) == Some(' ')) {
      items.push(parse_manifest_call_block(sc, ids, triv, "pkgtype"))
    } else {
      items.push(parse_manifest_assignment_or_stmt(sc, ids, triv))
    }
  }

  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    items,
    ordering=@cst.CommutativeByKey,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

