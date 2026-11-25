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

///|
fn parse_c_family_block_decl(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  decl_start : Int32,
  kind : @cst.SyntaxKind,
  tag : String,
  commutative_members : Bool,
) -> @cst.CstNode {
  let _ = sc.collect_c_like_trivia()
  if sc.peek() == Some('<') {
    while !sc.is_eof() && sc.peek() != Some('>') {
      sc.advance()
    }
    if sc.peek() == Some('>') {
      sc.advance()
    }
    let _ = sc.collect_c_like_trivia()
  }
  let name = sc.scan_ident()
  while !sc.is_eof() {
    match sc.peek() {
      Some('{') => break
      Some(';') => {
        sc.advance()
        let raw = sc.slice_chars(decl_start, sc.pos)
        let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
        return @cst.CstNode::leaf(
          id=ids.alloc(),
          kind,
          raw,
          signature=if !name.is_empty() { Some(tag + ":" + name) } else { None },
          leading_trivia=leading,
          trailing_trivia=trail,
        )
      }
      Some('(') | Some('[') => {
        let _ = sc.skip_balanced_group()
      }
      Some('"') => {
        let _ = sc.scan_quoted_string()
      }
      Some('\'') =>
        if sc.peek(delta=1) == Some('\\') ||
          sc.peek(delta=2) == Some('\'') ||
          !is_rust_lifetime_token(sc) {
          let _ = sc.scan_quoted_string()
        } else {
          sc.advance()
        }
      _ => sc.advance()
    }
  }
  if sc.peek() == Some('{') {
    let hdr = sc.slice_chars(decl_start, sc.pos)
    let hdr_leaf = @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, hdr)
    let body = if commutative_members {
      parse_mbt_member_block(sc, ids, @cst.FieldDecl)
    } else {
      parse_brace_statement_block(sc, ids)
    }
    let sig_name = if !name.is_empty() {
      name
    } else {
      hdr.trim().to_owned().replace_all(old=" ", new="")
    }
    @cst.CstNode::interior(
      id=ids.alloc(),
      kind,
      [hdr_leaf, body],
      signature=Some(tag + ":" + sig_name),
      leading_trivia=leading,
      has_error=body.has_error,
    )
  } else {
    let raw = sc.slice_chars(decl_start, sc.pos)
    @cst.CstNode::leaf(
      id=ids.alloc(),
      kind,
      raw,
      signature=if !name.is_empty() { Some(tag + ":" + name) } else { None },
      leading_trivia=leading,
      has_error=true,
    )
  }
}

///|
/// Indentation-based lossless CST parser for Python (`import` / `from ... import`,
/// `def` / `async def`, `class` with nested method declarations).
pub fn parse_python_cst(source : String) -> @cst.CstNode {
  let ids = IdGen::new()
  let lines = split_yaml_lines(source)
  let n = lines.length()
  let items : Array[@cst.CstNode] = []
  let pending_imports : Array[@cst.CstNode] = []
  let mut import_group_idx = 0

  fn flush_py_imports() -> Unit {
    if !pending_imports.is_empty() {
      let first_lead = pending_imports[0].leading_trivia
      let copy_imps = pending_imports.copy()
      copy_imps[0] = copy_imps[0].with_trivia(leading_trivia=[])
      items.push(
        @cst.CstNode::interior(
          id=ids.alloc(),
          @cst.ImportGroup,
          copy_imps,
          ordering=@cst.CommutativeByKey,
          signature=Some("imports#" + import_group_idx.to_string()),
          leading_trivia=first_lead,
        ),
      )
      import_group_idx += 1
      pending_imports.clear()
    }
  }

  let mut i = 0
  while i < n {
    let lead : Array[@cst.Trivia] = []
    while i < n && lines[i].is_blank_or_comment {
      let k = if lines[i].trimmed.has_prefix("#") {
        @cst.LineComment
      } else {
        @cst.Whitespace
      }
      lead.push(@cst.Trivia::new(k, lines[i].raw))
      i += 1
    }
    if i >= n {
      flush_py_imports()
      let root = @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        items,
        ordering=@cst.CommutativeBlocks,
        trailing_trivia=lead,
        span=@cst.ByteSpan::new(0, source.length()),
      )
      let (reindexed, _) = @cst.reindex_tree(root)
      return reindexed
    }

    let tr = lines[i].trimmed
    if lines[i].indent == 0 &&
      (tr.has_prefix("import ") || tr.has_prefix("from ")) {
      let imp_buf = StringBuilder()
      imp_buf.write_string(lines[i].raw)
      let has_open_paren = tr.contains("(") && !tr.contains(")")
      i += 1
      if has_open_paren {
        while i < n {
          imp_buf.write_string(lines[i].raw)
          if lines[i].trimmed.contains(")") {
            i += 1
            break
          }
          i += 1
        }
      }
      let raw_imp = imp_buf.to_string()
      pending_imports.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.ImportItem,
          raw_imp,
          signature=Some("import:" + raw_imp.trim().to_owned()),
          leading_trivia=lead,
        ),
      )
      continue
    }

    flush_py_imports()
    // Collect optional `@decorator` lines at indent 0
    let dec_buf = StringBuilder()
    while i < n && lines[i].indent == 0 && lines[i].trimmed.has_prefix("@") {
      dec_buf.write_string(lines[i].raw)
      i += 1
    }
    if i >= n {
      items.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Attribute,
          dec_buf.to_string(),
          leading_trivia=lead,
        ),
      )
      break
    }

    let cur = lines[i]
    if cur.indent == 0 &&
      (
        cur.trimmed.has_prefix("def ") ||
        cur.trimmed.has_prefix("async def ") ||
        cur.trimmed.has_prefix("class ")
      ) {
      let is_class = cur.trimmed.has_prefix("class ")
      let name = extract_py_decl_name(cur.trimmed)
      let hdr_text = dec_buf.to_string() + cur.raw
      i += 1
      if is_class {
        // Parse class body methods as `CommutativeBlocks`!
        let methods : Array[@cst.CstNode] = [
          @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, hdr_text),
        ]
        while i < n {
          let m_lead : Array[@cst.Trivia] = []
          let saved_m = i
          while i < n && lines[i].is_blank_or_comment {
            let k = if lines[i].trimmed.has_prefix("#") {
              @cst.LineComment
            } else {
              @cst.Whitespace
            }
            m_lead.push(@cst.Trivia::new(k, lines[i].raw))
            i += 1
          }
          if i >= n || lines[i].indent == 0 {
            i = saved_m
            break
          }
          let m_indent = lines[i].indent
          let m_buf = StringBuilder()
          while i < n &&
                lines[i].indent == m_indent &&
                lines[i].trimmed.has_prefix("@") {
            m_buf.write_string(lines[i].raw)
            i += 1
          }
          if i < n &&
            lines[i].indent == m_indent &&
            (
              lines[i].trimmed.has_prefix("def ") ||
              lines[i].trimmed.has_prefix("async def ")
            ) {
            let m_name = extract_py_decl_name(lines[i].trimmed)
            m_buf.write_string(lines[i].raw)
            i += 1
            while i < n {
              if lines[i].is_blank_or_comment {
                let mut look = i
                while look < n && lines[look].is_blank_or_comment {
                  look += 1
                }
                if look < n && lines[look].indent > m_indent {
                  m_buf.write_string(lines[i].raw)
                  i += 1
                  continue
                } else {
                  break
                }
              }
              if lines[i].indent > m_indent {
                m_buf.write_string(lines[i].raw)
                i += 1
              } else {
                break
              }
            }
            methods.push(
              @cst.CstNode::leaf(
                id=ids.alloc(),
                @cst.FnDecl,
                m_buf.to_string(),
                signature=Some("method:" + m_name),
                leading_trivia=m_lead,
              ),
            )
          } else if i < n {
            m_buf.write_string(lines[i].raw)
            i += 1
            methods.push(
              @cst.CstNode::leaf(
                id=ids.alloc(),
                @cst.Stmt,
                m_buf.to_string(),
                leading_trivia=m_lead,
              ),
            )
          }
        }
        items.push(
          @cst.CstNode::interior(
            id=ids.alloc(),
            @cst.ClassDecl,
            methods,
            ordering=@cst.CommutativeBlocks,
            signature=Some("class:" + name),
            leading_trivia=lead,
          ),
        )
      } else {
        // Top-level `def` with statement children
        let stmts : Array[@cst.CstNode] = [
          @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, hdr_text),
        ]
        while i < n {
          if lines[i].is_blank_or_comment {
            let mut look = i
            while look < n && lines[look].is_blank_or_comment {
              look += 1
            }
            if look < n && lines[look].indent > 0 {
              stmts.push(
                @cst.CstNode::leaf(id=ids.alloc(), @cst.Stmt, lines[i].raw),
              )
              i += 1
              continue
            } else {
              break
            }
          }
          if lines[i].indent > 0 {
            stmts.push(
              @cst.CstNode::leaf(id=ids.alloc(), @cst.Stmt, lines[i].raw),
            )
            i += 1
          } else {
            break
          }
        }
        items.push(
          @cst.CstNode::interior(
            id=ids.alloc(),
            @cst.FnDecl,
            stmts,
            ordering=@cst.Sequential,
            signature=Some("def:" + name),
            leading_trivia=lead,
          ),
        )
      }
    } else {
      let stmt_text = dec_buf.to_string() + cur.raw
      i += 1
      items.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Stmt,
          stmt_text,
          leading_trivia=lead,
        ),
      )
    }
  }

  flush_py_imports()
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

