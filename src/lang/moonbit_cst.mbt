///|
/// Lossless CST parser for MoonBit source & interface files (`.mbt`, `.mbti`).
/// Exploits MoonBit's native `///|` block-independent architecture (`CommutativeBlocks`),
/// parses top-level declarations (`fn`, `test`, `struct`, `enum`, `suberror`, `trait`,
/// `impl`, `type`, `const`, `let`) with semantic signatures, AND recursively decomposes:
/// - `struct` bodies into `CommutativeByKey` `FieldDecl` entries!
/// - `enum` / `suberror` bodies into `CommutativeByKey` `VariantDecl` entries!
/// - `fn` / `test` / `impl` bodies into statement-level `Block` children!
pub fn parse_moonbit_cst(source : String) -> @cst.CstNode {
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let decls : Array[@cst.CstNode] = []
  let mut anon_counter = 0

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia(recognize_moonbit_sep=true)
    if sc.is_eof() {
      let root = @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        decls,
        ordering=@cst.CommutativeBlocks,
        trailing_trivia=triv,
        span=@cst.ByteSpan::new(0, source.length()),
      )
      let (reindexed, _) = @cst.reindex_tree(root)
      return reindexed
    }

    let decl_start = sc.pos
    // Consume leading `#attribute(...)` lines as part of declaration header
    while sc.peek() == Some('#') && !sc.starts_with("#|") {
      sc.advance()
      let _ = sc.scan_ident(allow_hyphen=true)
      if sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      }
      let _ = sc.collect_c_like_trivia(recognize_moonbit_sep=false)
    }

    // Consume visibility / async / extern modifiers to inspect primary keyword
    let kw_probe = sc.pos
    let mut primary_kw = sc.scan_ident()
    while primary_kw == "pub" ||
          primary_kw == "priv" ||
          primary_kw == "async" ||
          primary_kw == "readonly" ||
          primary_kw == "extern" {
      let _ = sc.consume_spaces()
      if sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      } else if sc.peek() == Some('"') {
        let _ = sc.scan_quoted_string()
      }
      let _ = sc.collect_c_like_trivia(recognize_moonbit_sep=false)
      primary_kw = sc.scan_ident()
    }

    match primary_kw {
      "fn" =>
        decls.push(
          parse_mbt_fn_or_impl(sc, ids, triv, decl_start, @cst.FnDecl, "fn"),
        )
      "test" => {
        let (node, next_anon) = parse_mbt_test_decl(
          sc, ids, triv, decl_start, anon_counter,
        )
        anon_counter = next_anon
        decls.push(node)
      }
      "struct" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.StructDecl,
            "struct",
            @cst.FieldDecl,
          ),
        )
      "enum" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.EnumDecl,
            "enum",
            @cst.VariantDecl,
          ),
        )
      "suberror" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.SuberrorDecl,
            "suberror",
            @cst.VariantDecl,
          ),
        )
      "trait" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.TraitDecl,
            "trait",
            @cst.FieldDecl,
          ),
        )
      "impl" =>
        decls.push(
          parse_mbt_fn_or_impl(sc, ids, triv, decl_start, @cst.ImplDecl, "impl"),
        )
      "let" | "const" | "type" | "typealias" | "fnalias" => {
        let kind = match primary_kw {
          "const" => @cst.ConstDecl
          "let" => @cst.LetDecl
          _ => @cst.TypeDecl
        }
        decls.push(
          parse_mbt_simple_decl(sc, ids, triv, decl_start, kind, primary_kw),
        )
      }
      _ => {
        sc.pos = kw_probe
        let line = sc.consume_to_eol(include_newline=true)
        let prefix = sc.slice_chars(decl_start, kw_probe)
        decls.push(
          @cst.CstNode::leaf(
            id=ids.alloc(),
            @cst.Stmt,
            prefix + line,
            leading_trivia=triv,
          ),
        )
      }
    }
  }

  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    decls,
    ordering=@cst.CommutativeBlocks,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
/// Scan a MoonBit declaration name (`foo` or `Type::method` or `[T] Type::method`).
fn scan_mbt_qualified_name(sc : Scanner) -> String {
  let _ = sc.collect_c_like_trivia()
  if sc.peek() == Some('[') {
    let _ = sc.skip_balanced_group()
    let _ = sc.collect_c_like_trivia()
  }
  let first = sc.scan_ident()
  if first.is_empty() {
    return ""
  }
  if sc.starts_with("::") {
    sc.advance(count=2)
    let second = sc.scan_ident()
    if !second.is_empty() {
      return first + "::" + second
    }
  }
  first
}

