///|
/// Lossless recursive-descent parser for JSON and JSONC (comments + trailing commas).
/// Produces `ObjectNode` (`CommutativeByKey` keyed by `"key:<name>"`) and `ArrayNode`
/// (automatically extracting `"elem:<id>"` signatures when array elements are keyed objects).
pub fn parse_json_cst(source : String) -> @cst.CstNode {
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let root_children : Array[@cst.CstNode] = []
  let leading = sc.collect_c_like_trivia()
  if sc.is_eof() {
    return @cst.CstNode::leaf(
      id=ids.alloc(),
      @cst.SourceFile,
      "",
      leading_trivia=leading,
      span=@cst.ByteSpan::new(0, source.length()),
    )
  }
  let val = parse_json_value(sc, ids, leading)
  root_children.push(val)
  let trailing = sc.collect_c_like_trivia()
  if !sc.is_eof() {
    let err_start = sc.byte_offset()
    let rest = sc.slice_chars(sc.pos, sc.len)
    sc.pos = sc.len
    root_children.push(
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.ErrorFragment,
        rest,
        leading_trivia=trailing,
        span=@cst.ByteSpan::new(err_start, source.length()),
        has_error=true,
      ),
    )
    let (reindexed, _) = @cst.reindex_tree(
      @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        root_children,
        span=@cst.ByteSpan::new(0, source.length()),
        has_error=true,
      ),
    )
    return reindexed
  }
  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    root_children,
    trailing_trivia=trailing,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
fn parse_json_value(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
) -> @cst.CstNode {
  let start_off = sc.byte_offset()
  match sc.peek() {
    Some('{') => parse_json_object(sc, ids, leading)
    Some('[') => parse_json_array(sc, ids, leading)
    Some('"') => {
      let (raw, _, closed) = sc.scan_quoted_string()
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.StringLiteral,
        raw,
        leading_trivia=leading,
        span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
        has_error=!closed,
      )
    }
    Some('t') =>
      if sc.starts_with("true") {
        sc.advance(count=4)
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.BoolLiteral,
          "true",
          leading_trivia=leading,
          span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
        )
      } else {
        consume_json_error_atom(sc, ids, leading, start_off)
      }
    Some('f') =>
      if sc.starts_with("false") {
        sc.advance(count=5)
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.BoolLiteral,
          "false",
          leading_trivia=leading,
          span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
        )
      } else {
        consume_json_error_atom(sc, ids, leading, start_off)
      }
    Some('n') =>
      if sc.starts_with("null") {
        sc.advance(count=4)
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.NullLiteral,
          "null",
          leading_trivia=leading,
          span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
        )
      } else {
        consume_json_error_atom(sc, ids, leading, start_off)
      }
    Some(c) =>
      if (c >= '0' && c <= '9') || c == '-' {
        let num_start = sc.pos
        if c == '-' {
          sc.advance()
        }
        let mut has_digit = false
        while !sc.is_eof() {
          let ch = sc.peek().unwrap()
          if ch >= '0' && ch <= '9' {
            has_digit = true
            sc.advance()
          } else if ch == '.' ||
            ch == 'e' ||
            ch == 'E' ||
            ch == '+' ||
            ch == '-' {
            sc.advance()
          } else {
            break
          }
        }
        let raw = sc.slice_chars(num_start, sc.pos)
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.NumberLiteral,
          raw,
          leading_trivia=leading,
          span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
          has_error=!has_digit,
        )
      } else {
        consume_json_error_atom(sc, ids, leading, start_off)
      }
    None =>
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.ErrorFragment,
        "",
        leading_trivia=leading,
        span=@cst.ByteSpan::new(start_off, start_off),
        has_error=true,
      )
  }
}

///|
fn consume_json_error_atom(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  start_off : Int32,
) -> @cst.CstNode {
  let s = sc.pos
  while !sc.is_eof() {
    match sc.peek() {
      Some(',') | Some('}') | Some(']') | Some('\n') | Some('\r') => break
      _ => sc.advance()
    }
  }
  if sc.pos == s && !sc.is_eof() {
    sc.advance()
  }
  @cst.CstNode::leaf(
    id=ids.alloc(),
    @cst.ErrorFragment,
    sc.slice_chars(s, sc.pos),
    leading_trivia=leading,
    span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
    has_error=true,
  )
}

///|
fn parse_json_object(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
) -> @cst.CstNode {
  let start_off = sc.byte_offset()
  sc.advance() // '{'
  let children : Array[@cst.CstNode] = [
    @cst.CstNode::leaf(
      id=ids.alloc(),
      @cst.Punctuation,
      "{",
      span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
    ),
  ]
  let mut has_err = false
  let mut expecting_entry_after_comma = false

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia()
    match sc.peek() {
      Some('}') => {
        let close_off = sc.byte_offset()
        sc.advance()
        children.push(
          @cst.CstNode::leaf(
            id=ids.alloc(),
            @cst.Punctuation,
            "}",
            leading_trivia=triv,
            span=@cst.ByteSpan::new(close_off, sc.byte_offset()),
          ),
        )
        return @cst.CstNode::interior(
          id=ids.alloc(),
          @cst.ObjectNode,
          children,
          ordering=@cst.CommutativeByKey,
          leading_trivia=leading,
          span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
          has_error=has_err,
        )
      }
      Some('"') => {
        expecting_entry_after_comma = false
        let entry_start = sc.byte_offset()
        let (key_raw, key_unescaped, key_closed) = sc.scan_quoted_string()
        let key_node = @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.StringLiteral,
          key_raw,
          span=@cst.ByteSpan::new(entry_start, sc.byte_offset()),
          has_error=!key_closed,
        )
        if !key_closed {
          has_err = true
        }
        let colon_lead = sc.collect_c_like_trivia()
        let entry_parts : Array[@cst.CstNode] = [key_node]
        if sc.peek() == Some(':') {
          let c_off = sc.byte_offset()
          sc.advance()
          entry_parts.push(
            @cst.CstNode::leaf(
              id=ids.alloc(),
              @cst.Punctuation,
              ":",
              leading_trivia=colon_lead,
              span=@cst.ByteSpan::new(c_off, sc.byte_offset()),
            ),
          )
          let val_lead = sc.collect_c_like_trivia()
          let val_node = parse_json_value(sc, ids, val_lead)
          if val_node.has_error {
            has_err = true
          }
          entry_parts.push(val_node)
        } else {
          has_err = true
          entry_parts.push(
            @cst.CstNode::leaf(
              id=ids.alloc(),
              @cst.ErrorFragment,
              "",
              leading_trivia=colon_lead,
              has_error=true,
            ),
          )
        }
        let entry_node = @cst.CstNode::interior(
          id=ids.alloc(),
          @cst.ObjectEntry,
          entry_parts,
          signature=Some("key:" + key_unescaped),
          leading_trivia=triv,
          span=@cst.ByteSpan::new(entry_start, sc.byte_offset()),
          has_error=has_err,
        )
        children.push(entry_node)

        // Optional comma separator before next entry
        let after_entry_triv = sc.collect_c_like_trivia()
        if sc.peek() == Some(',') {
          let comma_off = sc.byte_offset()
          sc.advance()
          let comma_trail = sc.collect_trailing_line_trivia(
            allow_slash_comment=true,
          )
          children.push(
            @cst.CstNode::leaf(
              id=ids.alloc(),
              @cst.Punctuation,
              ",",
              leading_trivia=after_entry_triv,
              trailing_trivia=comma_trail,
              span=@cst.ByteSpan::new(comma_off, sc.byte_offset()),
            ),
          )
          expecting_entry_after_comma = true
        } else if sc.peek() == Some('}') {
          let close_off = sc.byte_offset()
          sc.advance()
          children.push(
            @cst.CstNode::leaf(
              id=ids.alloc(),
              @cst.Punctuation,
              "}",
              leading_trivia=after_entry_triv,
              span=@cst.ByteSpan::new(close_off, sc.byte_offset()),
            ),
          )
          return @cst.CstNode::interior(
            id=ids.alloc(),
            @cst.ObjectNode,
            children,
            ordering=@cst.CommutativeByKey,
            leading_trivia=leading,
            span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
            has_error=has_err,
          )
        } else {
          // Missing comma between two entries: syntax error!
          has_err = true
          if !after_entry_triv.is_empty() {
            children.push(
              @cst.CstNode::leaf(
                id=ids.alloc(),
                @cst.ErrorFragment,
                "",
                leading_trivia=after_entry_triv,
                has_error=true,
              ),
            )
          }
        }
      }
      _ => {
        has_err = true
        let _ = expecting_entry_after_comma
        let bad = consume_json_error_atom(sc, ids, triv, sc.byte_offset())
        children.push(bad)
      }
    }
  }

  // Unclosed '{'
  @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.ObjectNode,
    children,
    ordering=@cst.CommutativeByKey,
    leading_trivia=leading,
    span=@cst.ByteSpan::new(start_off, sc.byte_offset()),
    has_error=true,
  )
}

