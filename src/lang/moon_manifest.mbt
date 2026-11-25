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

///|
fn parse_manifest_import_block(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
) -> @cst.CstNode {
  let start_off = sc.byte_offset()
  let hdr_start = sc.pos
  sc.advance(count=6) // "import"
  while !sc.is_eof() && sc.peek() != Some('{') {
    sc.advance()
  }
  if sc.peek() != Some('{') {
    let raw = sc.slice_chars(hdr_start, sc.pos)
    return @cst.CstNode::leaf(
      id=ids.alloc(),
      @cst.ErrorFragment,
      raw,
      leading_trivia=leading,
      has_error=true,
    )
  }
  sc.advance() // '{'
  let open_hdr = sc.slice_chars(hdr_start, sc.pos)
  let children : Array[@cst.CstNode] = [
    @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, open_hdr),
  ]
  let mut has_err = false

  while !sc.is_eof() {
    let item_triv = sc.collect_c_like_trivia()
    if sc.peek() == Some('}') {
      let close_start = sc.pos
      sc.advance() // '}'
      // Check optional `for "test"` / `for "wbtest"` suffix on same line
      let saved_after_brace = sc.pos
      let _ = sc.consume_spaces()
      let mut scope_tag = "main"
      if sc.starts_with("for") {
        sc.advance(count=3)
        let _ = sc.consume_spaces()
        if sc.peek() == Some('"') {
          let (_, inner, ok) = sc.scan_quoted_string()
          if ok && !inner.is_empty() {
            scope_tag = inner
          }
        }
      } else {
        sc.pos = saved_after_brace
      }
      let close_raw = sc.slice_chars(close_start, sc.pos)
      let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          close_raw,
          leading_trivia=item_triv,
          trailing_trivia=trail,
        ),
      )
      return @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.ImportGroup,
        children,
        ordering=@cst.CommutativeByKey,
        signature=Some("imports:" + scope_tag),
        leading_trivia=leading,
        span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
        has_error=has_err,
      )
    }

    // Parse a single import entry `"pkg/path"` or `"pkg/path" @alias`
    let entry_start = sc.pos
    let mut mod_name = ""
    if sc.peek() == Some('"') {
      let (_, unesc, closed) = sc.scan_quoted_string()
      mod_name = unesc
      if !closed {
        has_err = true
      }
    }
    while !sc.is_eof() {
      match sc.peek() {
        Some(',') | Some('}') | Some('\n') | Some('\r') => break
        Some('/') => if sc.starts_with("//") { break } else { sc.advance() }
        _ => sc.advance()
      }
    }
    let mut entry_end = sc.pos
    while entry_end > entry_start &&
          (sc.chars[entry_end - 1] == ' ' || sc.chars[entry_end - 1] == '\t') {
      entry_end -= 1
    }
    sc.pos = entry_end
    let entry_raw = sc.slice_chars(entry_start, sc.pos)
    let sig_key = if !mod_name.is_empty() {
      "import:" + mod_name
    } else {
      "import:" + entry_raw.trim().to_owned()
    }
    children.push(
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.ImportItem,
        entry_raw,
        signature=Some(sig_key),
        leading_trivia=item_triv,
        has_error=entry_raw.trim().is_empty(),
      ),
    )

    let sep_triv = sc.collect_c_like_trivia()
    if sc.peek() == Some(',') {
      sc.advance()
      let comma_trail = sc.collect_trailing_line_trivia(
        allow_slash_comment=true,
      )
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          ",",
          leading_trivia=sep_triv,
          trailing_trivia=comma_trail,
        ),
      )
    } else if !sep_triv.is_empty() {
      // Carry trivia into closing `}` on next loop iteration by rewinding?
      // Better: attach `sep_triv` directly as trailing_trivia on last child!
      let last = children.pop().unwrap()
      let combined_trail = last.trailing_trivia.copy()
      for t in sep_triv {
        combined_trail.push(t)
      }
      children.push(last.with_trivia(trailing_trivia=combined_trail))
    }
  }

  @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.ImportGroup,
    children,
    ordering=@cst.CommutativeByKey,
    signature=Some("imports:main"),
    leading_trivia=leading,
    span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
    has_error=true,
  )
}

///|
fn parse_manifest_call_block(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  kw : String,
) -> @cst.CstNode {
  let start_pos = sc.pos
  sc.advance(count=kw.length())
  let _ = sc.consume_spaces()
  let mut ok = true
  if sc.peek() == Some('(') {
    ok = sc.skip_balanced_group()
  } else {
    let _ = sc.consume_to_eol(include_newline=false)
    ok = false
  }
  let raw = sc.slice_chars(start_pos, sc.pos)
  let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
  @cst.CstNode::leaf(
    id=ids.alloc(),
    @cst.Stmt,
    raw,
    signature=Some("call:" + kw),
    leading_trivia=leading,
    trailing_trivia=trail,
    has_error=!ok,
  )
}

///|
fn parse_manifest_assignment_or_stmt(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
) -> @cst.CstNode {
  let start_pos = sc.pos
  let ident = sc.scan_ident(allow_hyphen=true)
  if !ident.is_empty() {
    let _ = sc.consume_spaces()
    if sc.peek() == Some('=') {
      sc.advance()
      let _ = sc.consume_spaces()
      let mut ok = true
      match sc.peek() {
        Some('[') | Some('{') | Some('(') => ok = sc.skip_balanced_group()
        Some('"') => {
          let (_, _, closed) = sc.scan_quoted_string(allow_multiline=true)
          ok = closed
        }
        _ =>
          while !sc.is_eof() {
            match sc.peek() {
              Some('\n') | Some('\r') => break
              Some('/') =>
                if sc.starts_with("//") {
                  break
                } else {
                  sc.advance()
                }
              _ => sc.advance()
            }
          }
      }
      let raw = sc.slice_chars(start_pos, sc.pos)
      let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
      return @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.KeyValue,
        raw,
        signature=Some("key:" + ident),
        leading_trivia=leading,
        trailing_trivia=trail,
        has_error=!ok,
      )
    }
  }
  let rest = sc.consume_to_eol(include_newline=true)
  let full = sc.slice_chars(start_pos, sc.pos - rest.length()) + rest
  @cst.CstNode::leaf(id=ids.alloc(), @cst.RawLine, full, leading_trivia=leading)
}
