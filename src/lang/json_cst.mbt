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

