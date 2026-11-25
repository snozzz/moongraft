///|
/// Line-offset index for $O(\log L)$ conversion from UTF-16 code-unit offset to 1-based `LineCol`.
#derive(@debug.Debug)
pub struct SourceMap {
  line_starts : Array[Int32]
  total_len : Int32
}

///|
/// Build a `SourceMap` from source text.
pub fn SourceMap::from_source(source : String) -> SourceMap {
  let starts : Array[Int32] = [0]
  let len = source.length()
  let mut idx = 0
  for ch in source {
    idx += ch.utf16_len()
    if ch == '\n' && idx <= len {
      starts.push(idx)
    }
  }
  { line_starts: starts, total_len: len, }
}

///|
/// Convert a 0-based offset to a 1-based `(line, column)` pair via binary search.
pub fn SourceMap::lookup(self : SourceMap, offset : Int32) -> LineCol {
  let clamped = if offset < 0 {
    0
  } else if offset > self.total_len {
    self.total_len
  } else {
    offset
  }
  let mut lo = 0
  let mut hi = self.line_starts.length() - 1
  while lo < hi {
    let mid = lo + (hi - lo + 1) / 2
    if self.line_starts[mid] <= clamped {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  let line_start = self.line_starts[lo]
  { line: lo + 1, column: clamped - line_start + 1, }
}

///|
/// Render a compact S-expression of a CST for structural inspection and snapshot tests.
pub fn format_sexp(node : CstNode, max_depth~ : Int32 = 16) -> String {
  let buf = StringBuilder()
  fn emit(n : CstNode, depth : Int32) -> Unit {
    let indent = "  ".repeat(depth)
    buf.write_string(indent)
    buf.write_string("(")
    buf.write_string(n.kind.label())
    match n.signature {
      Some(sig) => {
        buf.write_string(" [")
        buf.write_string(sig)
        buf.write_string("]")
      }
      None => ()
    }
    if n.children.is_empty() {
      let preview = n.text
        .replace_all(old="\n", new="\\n")
        .replace_all(old="\r", new="\\r")
      buf.write_string(" \"")
      if preview.length() > 48 {
        buf.write_view(preview[:45])
        buf.write_string("...")
      } else {
        buf.write_string(preview)
      }
      buf.write_string("\")\n")
    } else if depth >= max_depth {
      buf.write_string(" ...)\n")
    } else {
      buf.write_string("\n")
      for child in n.children {
        emit(child, depth + 1)
      }
      buf.write_string(indent)
      buf.write_string(")\n")
    }
  }

  emit(node, 0)
  buf.to_string()
}
