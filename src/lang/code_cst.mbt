///|
/// Lossless CST parser for TypeScript/JavaScript, Python, and Rust source files.
/// - Groups consecutive `import` / `from ... import` / `use` statements into
///   `ImportGroup` (`CommutativeByKey`) so parallel import edits merge with 0 conflicts!
/// - Parses `function` / `class` / `interface` / `type` / `def` / `fn` / `struct` / `enum` / `impl`
///   with semantic signatures and statement/method blocks so moved declarations and
///   parallel class-method additions merge cleanly!
pub fn parse_c_family_code_cst(
  source : String,
  lang : @cst.Language,
) -> @cst.CstNode {
  if lang == @cst.Python {
    return parse_python_cst(source)
  }
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let items : Array[@cst.CstNode] = []
  let pending_imports : Array[@cst.CstNode] = []
  let mut import_group_idx = 0

  fn flush_imports() -> Unit {
    if !pending_imports.is_empty() {
      let first_lead = pending_imports[0].leading_trivia
      let normalized = pending_imports.copy()
      normalized[0] = normalized[0].with_trivia(leading_trivia=[])
      items.push(
        @cst.CstNode::interior(
          id=ids.alloc(),
          @cst.ImportGroup,
          normalized,
          ordering=@cst.CommutativeByKey,
          signature=Some("imports#" + import_group_idx.to_string()),
          leading_trivia=first_lead,
        ),
      )
      import_group_idx += 1
      pending_imports.clear()
    }
  }

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia()
    if sc.is_eof() {
      flush_imports()
      let root = @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        items,
        ordering=@cst.CommutativeBlocks,
        trailing_trivia=triv,
        span=@cst.ByteSpan::new(0, source.length()),
      )
      let (reindexed, _) = @cst.reindex_tree(root)
      return reindexed
    }

    let decl_start = sc.pos
    // Skip attributes (`#[...]` in Rust or `@decorator` in TS)
    while (sc.peek() == Some('#') && sc.peek(delta=1) == Some('[')) ||
          sc.peek() == Some('@') {
      sc.advance()
      if sc.peek() == Some('[') {
        let _ = sc.skip_balanced_group()
      } else {
        let _ = sc.scan_ident()
        if sc.peek() == Some('(') {
          let _ = sc.skip_balanced_group()
        }
      }
      let _ = sc.collect_c_like_trivia()
    }

    let probe = sc.pos
    let mut kw = sc.scan_ident()
    while kw == "export" ||
          kw == "default" ||
          kw == "pub" ||
          kw == "async" ||
          kw == "unsafe" ||
          kw == "declare" ||
          kw == "abstract" {
      if kw == "pub" && sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      }
      let _ = sc.collect_c_like_trivia()
      kw = sc.scan_ident()
    }

    if kw == "import" || kw == "use" {
      sc.pos = decl_start
      let imp = scan_statement_until_semicolon_or_eol(
        sc,
        ids,
        triv,
        @cst.ImportItem,
        "import:",
      )
      pending_imports.push(imp)
      continue
    }

    flush_imports()
    match kw {
      "function" | "fn" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.FnDecl,
            "fn",
            false,
          ),
        )
      "class" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.ClassDecl,
            "class",
            true,
          ),
        )
      "interface" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.InterfaceDecl,
            "interface",
            true,
          ),
        )
      "struct" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.StructDecl,
            "struct",
            true,
          ),
        )
      "enum" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.EnumDecl,
            "enum",
            true,
          ),
        )
      "trait" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.TraitDecl,
            "trait",
            true,
          ),
        )
      "impl" =>
        items.push(
          parse_c_family_block_decl(
            sc,
            ids,
            triv,
            decl_start,
            @cst.ImplDecl,
            "impl",
            true,
          ),
        )
      "const" | "let" | "var" | "type" | "static" => {
        let _ = sc.consume_spaces()
        let mut name = sc.scan_ident()
        if name == "mut" {
          let _ = sc.consume_spaces()
          name = sc.scan_ident()
        }
        sc.pos = decl_start
        let kind = if kw == "type" { @cst.TypeDecl } else { @cst.ConstDecl }
        let sig_prefix = kw + ":" + name
        items.push(
          scan_statement_until_semicolon_or_eol(
            sc,
            ids,
            triv,
            kind,
            sig_prefix,
            fixed_sig=!name.is_empty(),
          ),
        )
      }
      _ => {
        sc.pos = probe
        sc.pos = decl_start
        items.push(
          scan_statement_until_semicolon_or_eol(sc, ids, triv, @cst.Stmt, ""),
        )
      }
    }
  }

  flush_imports()
  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    items,
    ordering=@cst.CommutativeBlocks,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
fn scan_statement_until_semicolon_or_eol(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  kind : @cst.SyntaxKind,
  sig_prefix : String,
  fixed_sig~ : Bool = false,
) -> @cst.CstNode {
  let s = sc.pos
  let mut has_err = false
  while !sc.is_eof() {
    match sc.peek() {
      Some(';') => {
        sc.advance()
        break
      }
      Some('\n') | Some('\r') => break
      Some('{') | Some('(') | Some('[') => {
        let ok = sc.skip_balanced_group()
        if !ok {
          has_err = true
        }
      }
      Some('"') => {
        let (_, _, ok) = sc.scan_quoted_string()
        if !ok {
          has_err = true
        }
      }
      Some('\'') =>
        if sc.peek(delta=1) == Some('\\') ||
          sc.peek(delta=2) == Some('\'') ||
          has_closing_single_quote_on_line(sc) {
          let (_, _, ok) = sc.scan_quoted_string()
          if !ok {
            has_err = true
          }
        } else {
          sc.advance()
        }
      Some('/') => if sc.starts_with("//") { break } else { sc.advance() }
      _ => sc.advance()
    }
  }
  let raw = sc.slice_chars(s, sc.pos)
  let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
  let sig = if fixed_sig {
    Some(sig_prefix)
  } else if !sig_prefix.is_empty() {
    Some(sig_prefix + raw.trim().to_owned())
  } else {
    None
  }
  @cst.CstNode::leaf(
    id=ids.alloc(),
    kind,
    raw,
    signature=sig,
    leading_trivia=leading,
    trailing_trivia=trail,
    has_error=has_err,
  )
}

