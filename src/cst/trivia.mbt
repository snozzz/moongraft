///|
/// Non-semantic formatting & comment trivia preserved losslessly on CST nodes.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum TriviaKind {
  Whitespace
  Newline
  LineComment
  DocComment
  BlockSeparator
  BlockComment
}

///|
/// Single piece of trivia (whitespace, newline, `///|` separator, or comment).
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) struct Trivia {
  kind : TriviaKind
  text : String
}

///|
/// Construct a trivia piece.
pub fn Trivia::new(kind : TriviaKind, text : String) -> Trivia {
  { kind, text, }
}

///|
/// Construct whitespace trivia (`' '` or `'\t'` runs).
pub fn Trivia::spaces(text : String) -> Trivia {
  { kind: Whitespace, text, }
}

///|
/// Construct newline trivia (`"\n"` or `"\r\n"`).
pub fn Trivia::newline(text~ : String = "\n") -> Trivia {
  { kind: Newline, text, }
}

///|
/// Construct a MoonBit `///|` block separator trivia piece.
pub fn Trivia::block_sep(text~ : String = "///|\n") -> Trivia {
  { kind: BlockSeparator, text, }
}

///|
/// True if this trivia contains a comment or doc comment that carries human intent
/// and therefore must never be silently discarded during structural merges.
pub fn Trivia::has_comment(self : Trivia) -> Bool {
  match self.kind {
    LineComment | DocComment | BlockComment => true
    Whitespace | Newline | BlockSeparator => false
  }
}

///|
/// Render an array of trivia pieces into a `StringBuilder`.
pub fn write_trivia(buf : StringBuilder, items : Array[Trivia]) -> Unit {
  for item in items {
    buf.write_string(item.text)
  }
}

///|
/// Concatenate trivia pieces to a `String`.
pub fn render_trivia(items : Array[Trivia]) -> String {
  let buf = StringBuilder()
  write_trivia(buf, items)
  buf.to_string()
}

///|
/// Extract all comment trivia from an array of trivia pieces.
pub fn extract_comments(items : Array[Trivia]) -> Array[Trivia] {
  let out : Array[Trivia] = []
  for item in items {
    if item.has_comment() {
      out.push(item)
    }
  }
  out
}

///|
/// Detect the dominant single-level indentation unit in source text
/// (e.g. `"  "`, `"    "`, or `"\t"`), defaulting to `"  "`.
pub fn detect_indent_unit(source : String) -> String {
  let mut two_space = 0
  let mut four_space = 0
  let mut tabs = 0
  for line_view in source.split("\n") {
    let line = line_view.to_owned()
    if line.has_prefix("\t") {
      tabs += 1
    } else if line.has_prefix("    ") && !line.has_prefix("      ") {
      four_space += 1
    } else if line.has_prefix("  ") && !line.has_prefix("    ") {
      two_space += 1
    }
  }
  if tabs > two_space && tabs > four_space {
    "\t"
  } else if four_space > two_space * 2 && four_space > 0 {
    "    "
  } else {
    "  "
  }
}
