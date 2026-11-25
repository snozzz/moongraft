///|
/// Lossless CST parser for TOML (`Cargo.toml`, `pyproject.toml`, config files).
/// Organizes top-level keys and `[table]` / `[[array_of_tables]]` sections into
/// `CommutativeByKey` containers, and parses inline tables `{ ... }` recursively!
pub fn parse_toml_cst(source : String) -> @cst.CstNode {
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let file_children : Array[@cst.CstNode] = []
  let preamble_entries : Array[@cst.CstNode] = []
  let mut current_section_header : @cst.CstNode? = None
  let mut current_section_kind : @cst.SyntaxKind = @cst.TableSection
  let mut current_section_sig : String? = None
  let mut current_section_lead : Array[@cst.Trivia] = []
  let mut current_section_items : Array[@cst.CstNode] = []
  let array_table_counts : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])

  fn flush_section() -> Unit {
    match current_section_header {
      Some(hdr) => {
        let all_items : Array[@cst.CstNode] = [hdr]
        for item in current_section_items {
          all_items.push(item)
        }
        let sec_ordering = if current_section_kind == @cst.TableSection {
          @cst.CommutativeByKey
        } else {
          @cst.CommutativeByKey
        }
        file_children.push(
          @cst.CstNode::interior(
            id=ids.alloc(),
            current_section_kind,
            all_items,
            ordering=sec_ordering,
            signature=current_section_sig,
            leading_trivia=current_section_lead,
          ),
        )
        current_section_header = None
        current_section_items = []
        current_section_lead = []
      }
      None =>
        if !preamble_entries.is_empty() {
          file_children.push(
            @cst.CstNode::interior(
              id=ids.alloc(),
              @cst.TableSection,
              preamble_entries.copy(),
              ordering=@cst.CommutativeByKey,
              signature=Some("table:__root__"),
            ),
          )
          preamble_entries.clear()
        }
    }
  }

  while !sc.is_eof() {
    let triv = collect_toml_trivia(sc)
    if sc.is_eof() {
      if !triv.is_empty() {
        flush_section()
        let root = @cst.CstNode::interior(
          id=ids.alloc(),
          @cst.SourceFile,
          file_children,
          ordering=@cst.CommutativeByKey,
          trailing_trivia=triv,
          span=@cst.ByteSpan::new(0, source.length()),
        )
        let (reindexed, _) = @cst.reindex_tree(root)
        return reindexed
      }
      break
    }

    if sc.peek() == Some('[') {
      flush_section()
      let hdr_start = sc.pos
      let is_array_table = sc.starts_with("[[")
      let raw_line = sc.consume_to_eol(include_newline=false)
      let trail = sc.collect_trailing_line_trivia(
        allow_slash_comment=false,
        allow_hash_comment=true,
      )
      let trimmed_hdr = raw_line.trim().to_owned()
      let valid_hdr = if is_array_table {
        trimmed_hdr.has_prefix("[[") && trimmed_hdr.has_suffix("]]")
      } else {
        trimmed_hdr.has_prefix("[") && trimmed_hdr.has_suffix("]")
      }
      let inner_name = if is_array_table && trimmed_hdr.length() >= 4 {
        trimmed_hdr[2:trimmed_hdr.length() - 2].trim().to_owned()
      } else if trimmed_hdr.length() >= 2 {
        trimmed_hdr[1:trimmed_hdr.length() - 1].trim().to_owned()
      } else {
        trimmed_hdr
      }
      current_section_kind = if is_array_table {
        @cst.ArrayOfTablesSection
      } else {
        @cst.TableSection
      }
      if is_array_table {
        let idx = array_table_counts.get(inner_name).unwrap_or(0)
        array_table_counts.set(inner_name, idx + 1)
        current_section_sig = Some("aot:" + inner_name + "#" + idx.to_string())
      } else {
        current_section_sig = Some("table:" + inner_name)
      }
      current_section_lead = triv
      current_section_header = Some(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Keyword,
          raw_line,
          signature=Some("header:" + inner_name),
          trailing_trivia=trail,
          span=@cst.ByteSpan::new(sc.offsets[hdr_start], sc.byte_offset()),
          has_error=!valid_hdr,
        ),
      )
    } else {
      let kv_node = parse_toml_kv(sc, ids, triv)
      match current_section_header {
        Some(_) => current_section_items.push(kv_node)
        None => preamble_entries.push(kv_node)
      }
    }
  }

  flush_section()
  let _ = array_table_counts
  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    file_children,
    ordering=@cst.CommutativeByKey,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
fn collect_toml_trivia(sc : Scanner) -> Array[@cst.Trivia] {
  let out : Array[@cst.Trivia] = []
  while !sc.is_eof() {
    match sc.consume_spaces() {
      Some(sp) => {
        out.push(sp)
        continue
      }
      None => ()
    }
    match sc.consume_newline() {
      Some(nl) => {
        out.push(nl)
        continue
      }
      None => ()
    }
    if sc.peek() == Some('#') {
      let text = sc.consume_to_eol(include_newline=true)
      out.push(@cst.Trivia::new(@cst.LineComment, text))
      continue
    }
    break
  }
  out
}

///|
fn parse_toml_kv(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
) -> @cst.CstNode {
  let start_pos = sc.pos
  // Scan dotted or quoted TOML key up to `=`
  let key_start = sc.pos
  while !sc.is_eof() {
    match sc.peek() {
      Some('=') | Some('\n') | Some('\r') => break
      Some('"') | Some('\'') => {
        let _ = sc.scan_quoted_string()
      }
      _ => sc.advance()
    }
  }
  let raw_key_part = sc.slice_chars(key_start, sc.pos)
  let norm_key = raw_key_part.trim().to_owned()
  if sc.peek() != Some('=') {
    let rest = sc.consume_to_eol(include_newline=true)
    return @cst.CstNode::leaf(
      id=ids.alloc(),
      @cst.ErrorFragment,
      raw_key_part + rest,
      leading_trivia=leading,
      span=@cst.ByteSpan::new(sc.offsets[start_pos], sc.byte_offset()),
      has_error=true,
    )
  }

  let key_leaf = @cst.CstNode::leaf(
    id=ids.alloc(),
    @cst.Identifier,
    raw_key_part,
    has_error=norm_key.is_empty(),
  )
  sc.advance() // '='
  let eq_spaces = match sc.consume_spaces() {
    Some(sp) => [sp]
    None => []
  }
  let eq_leaf = @cst.CstNode::leaf(
    id=ids.alloc(),
    @cst.Operator,
    "=",
    trailing_trivia=eq_spaces,
  )

  let val_node = parse_toml_value(sc, ids)
  let trail = sc.collect_trailing_line_trivia(
    allow_slash_comment=false,
    allow_hash_comment=true,
  )
  @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.KeyValue,
    [key_leaf, eq_leaf, val_node],
    signature=Some("key:" + norm_key),
    leading_trivia=leading,
    trailing_trivia=trail,
    span=@cst.ByteSpan::new(sc.offsets[start_pos], sc.byte_offset()),
    has_error=norm_key.is_empty() || val_node.has_error,
  )
}

///|
fn parse_toml_value(sc : Scanner, ids : IdGen) -> @cst.CstNode {
  match sc.peek() {
    Some('{') => parse_toml_inline_table(sc, ids)
    Some('[') => {
      let s = sc.pos
      let ok = sc.skip_balanced_group(allow_hash_comment=true)
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.ArrayNode,
        sc.slice_chars(s, sc.pos),
        has_error=!ok,
      )
    }
    Some('"') | Some('\'') => {
      let s = sc.pos
      if sc.starts_with("\"\"\"") || sc.starts_with("'''") {
        let delim = sc.slice_chars(sc.pos, sc.pos + 3)
        sc.advance(count=3)
        let mut closed = false
        while !sc.is_eof() {
          if sc.starts_with(delim) {
            sc.advance(count=3)
            closed = true
            break
          }
          if sc.peek() == Some('\\') {
            sc.advance(count=2)
          } else {
            sc.advance()
          }
        }
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.StringLiteral,
          sc.slice_chars(s, sc.pos),
          has_error=!closed,
        )
      } else {
        let (raw, _, closed) = sc.scan_quoted_string()
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.StringLiteral,
          raw,
          has_error=!closed,
        )
      }
    }
    _ => {
      let s = sc.pos
      while !sc.is_eof() {
        match sc.peek() {
          Some('\n') | Some('\r') | Some('#') => break
          _ => sc.advance()
        }
      }
      // Trim trailing horizontal spaces so inline comment stays in trailing trivia
      let mut end_p = sc.pos
      while end_p > s &&
            (sc.chars[end_p - 1] == ' ' || sc.chars[end_p - 1] == '\t') {
        end_p -= 1
      }
      sc.pos = end_p
      let raw = sc.slice_chars(s, sc.pos)
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.Expr,
        raw,
        has_error=raw.trim().is_empty(),
      )
    }
  }
}

///|
fn parse_toml_inline_table(sc : Scanner, ids : IdGen) -> @cst.CstNode {
  let s_off = sc.byte_offset()
  sc.advance() // '{'
  let children : Array[@cst.CstNode] = [
    @cst.CstNode::leaf(id=ids.alloc(), @cst.Punctuation, "{"),
  ]
  let mut has_err = false
  while !sc.is_eof() {
    let triv = collect_toml_trivia(sc)
    if sc.peek() == Some('}') {
      sc.advance()
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          "}",
          leading_trivia=triv,
        ),
      )
      return @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.ObjectNode,
        children,
        ordering=@cst.CommutativeByKey,
        span=@cst.ByteSpan::new(s_off, sc.byte_offset()),
        has_error=has_err,
      )
    }
    // Scan key up to `=`
    let k_start = sc.pos
    while !sc.is_eof() {
      match sc.peek() {
        Some('=') | Some('}') | Some(',') | Some('\n') => break
        _ => sc.advance()
      }
    }
    let k_raw = sc.slice_chars(k_start, sc.pos)
    let k_norm = k_raw.trim().to_owned()
    if sc.peek() != Some('=') {
      has_err = true
      if sc.pos == k_start && !sc.is_eof() {
        sc.advance()
      }
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.ErrorFragment,
          sc.slice_chars(k_start, sc.pos),
          leading_trivia=triv,
          has_error=true,
        ),
      )
      continue
    }
    sc.advance() // '='
    let eq_sp = match sc.consume_spaces() {
      Some(sp) => [sp]
      None => []
    }
    // Scan inline value up to `,` or `}`
    let v_start = sc.pos
    while !sc.is_eof() {
      match sc.peek() {
        Some(',') | Some('}') => break
        Some('[') | Some('{') => {
          let ok = sc.skip_balanced_group(allow_hash_comment=true)
          if !ok {
            has_err = true
          }
        }
        Some('"') | Some('\'') => {
          let (_, _, ok) = sc.scan_quoted_string()
          if !ok {
            has_err = true
          }
        }
        _ => sc.advance()
      }
    }
    let mut v_end = sc.pos
    while v_end > v_start &&
          (sc.chars[v_end - 1] == ' ' || sc.chars[v_end - 1] == '\t') {
      v_end -= 1
    }
    sc.pos = v_end
    let v_raw = sc.slice_chars(v_start, sc.pos)
    let entry = @cst.CstNode::interior(
      id=ids.alloc(),
      @cst.ObjectEntry,
      [
        @cst.CstNode::leaf(id=ids.alloc(), @cst.Identifier, k_raw),
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Operator,
          "=",
          trailing_trivia=eq_sp,
        ),
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Expr,
          v_raw,
          has_error=v_raw.trim().is_empty(),
        ),
      ],
      signature=Some("key:" + k_norm),
      leading_trivia=triv,
    )
    children.push(entry)
    let after_sp = collect_toml_trivia(sc)
    if sc.peek() == Some(',') {
      sc.advance()
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          ",",
          leading_trivia=after_sp,
        ),
      )
    } else if sc.peek() == Some('}') {
      sc.advance()
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          "}",
          leading_trivia=after_sp,
        ),
      )
      return @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.ObjectNode,
        children,
        ordering=@cst.CommutativeByKey,
        span=@cst.ByteSpan::new(s_off, sc.byte_offset()),
        has_error=has_err,
      )
    }
  }
  @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.ObjectNode,
    children,
    ordering=@cst.CommutativeByKey,
    span=@cst.ByteSpan::new(s_off, sc.byte_offset()),
    has_error=true,
  )
}
