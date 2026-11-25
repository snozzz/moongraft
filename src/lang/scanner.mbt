///|
/// Monotonic ID generator for CST construction.
pub struct IdGen {
  mut next : Int32
}

///|
/// Create a new `IdGen` starting at `0`.
pub fn IdGen::new() -> IdGen {
  { next: 0, }
}

///|
/// Allocate the next dense node ID.
pub fn IdGen::alloc(self : IdGen) -> Int32 {
  let id = self.next
  self.next += 1
  id
}

///|
/// Random-access character array cursor over UTF-32 `Char` slices with exact
/// UTF-16 byte/unit offsets so slicing `source[start:end]` is $O(1)$ and 100% lossless.
pub struct Scanner {
  source : String
  chars : Array[Char]
  offsets : Array[Int32]
  len : Int32
  mut pos : Int32
}

///|
/// Build a `Scanner` over `source`.
pub fn Scanner::new(source : String) -> Scanner {
  let chars : Array[Char] = Array(capacity=source.length())
  let offsets : Array[Int32] = Array(capacity=source.length() + 1)
  let mut off = 0
  for ch in source {
    offsets.push(off)
    chars.push(ch)
    off += ch.utf16_len()
  }
  offsets.push(off)
  { source, chars, offsets, len: chars.length(), pos: 0, }
}

///|
/// True if the cursor reached end of input.
pub fn Scanner::is_eof(self : Scanner) -> Bool {
  self.pos >= self.len
}

///|
/// Current UTF-16 offset into `source`.
pub fn Scanner::byte_offset(self : Scanner) -> Int32 {
  self.offsets[self.pos]
}

///|
/// Peek character at `self.pos + delta` without advancing.
pub fn Scanner::peek(self : Scanner, delta~ : Int32 = 0) -> Char? {
  let idx = self.pos + delta
  if idx >= 0 && idx < self.len {
    Some(self.chars[idx])
  } else {
    None
  }
}

///|
/// Advance by `count` characters.
pub fn Scanner::advance(self : Scanner, count~ : Int32 = 1) -> Unit {
  let target = self.pos + count
  self.pos = if target > self.len { self.len } else { target }
}

///|
/// Slice exact substring from character index `start_pos` to `end_pos`.
pub fn Scanner::slice_chars(
  self : Scanner,
  start_pos : Int32,
  end_pos : Int32,
) -> String {
  let s = if start_pos < 0 {
    0
  } else if start_pos > self.len {
    self.len
  } else {
    start_pos
  }
  let e = if end_pos < s {
    s
  } else if end_pos > self.len {
    self.len
  } else {
    end_pos
  }
  self.source[self.offsets[s]:self.offsets[e]].to_owned()
}

///|
/// Check whether characters starting at `self.pos` match `prefix`.
pub fn Scanner::starts_with(self : Scanner, prefix : StringView) -> Bool {
  let mut k = 0
  for ch in prefix {
    match self.peek(delta=k) {
      Some(c) => if c != ch { return false }
      None => return false
    }
    k += 1
  }
  true
}

///|
/// Consume horizontal whitespace (`' '` and `'\t'`).
pub fn Scanner::consume_spaces(self : Scanner) -> @cst.Trivia? {
  let start = self.pos
  while !self.is_eof() {
    match self.peek() {
      Some(' ') | Some('\t') => self.advance()
      _ => break
    }
  }
  if self.pos > start {
    Some(@cst.Trivia::spaces(self.slice_chars(start, self.pos)))
  } else {
    None
  }
}

///|
/// Consume a single newline (`\n` or `\r\n`).
pub fn Scanner::consume_newline(self : Scanner) -> @cst.Trivia? {
  match self.peek() {
    Some('\n') => {
      self.advance()
      Some(@cst.Trivia::newline())
    }
    Some('\r') =>
      if self.peek(delta=1) == Some('\n') {
        self.advance(count=2)
        Some(@cst.Trivia::newline(text="\r\n"))
      } else {
        self.advance()
        Some(@cst.Trivia::newline(text="\r"))
      }
    _ => None
  }
}

///|
/// Consume until end of current line (including trailing `\n` or `\r\n` if `include_newline`).
pub fn Scanner::consume_to_eol(
  self : Scanner,
  include_newline~ : Bool = true,
) -> String {
  let start = self.pos
  while !self.is_eof() {
    match self.peek() {
      Some('\n') => {
        if include_newline {
          self.advance()
        }
        break
      }
      Some('\r') => {
        if include_newline {
          if self.peek(delta=1) == Some('\n') {
            self.advance(count=2)
          } else {
            self.advance()
          }
        }
        break
      }
      _ => self.advance()
    }
  }
  self.slice_chars(start, self.pos)
}

///|
/// Scan a quoted string literal (`"..."` or `'...'`), handling `\` escapes.
/// Returns `(raw_literal_text, unescaped_inner_text, closed_cleanly)`.
pub fn Scanner::scan_quoted_string(
  self : Scanner,
  allow_multiline~ : Bool = false,
) -> (String, String, Bool) {
  let start = self.pos
  let quote = match self.peek() {
    Some(q) => q
    None => return ("", "", false)
  }
  self.advance()
  let inner = StringBuilder()
  let mut closed = false
  while !self.is_eof() {
    let ch = self.peek().unwrap()
    if ch == '\\' {
      self.advance()
      match self.peek() {
        Some(esc) => {
          self.advance()
          match esc {
            'n' => inner.write_char('\n')
            'r' => inner.write_char('\r')
            't' => inner.write_char('\t')
            '"' => inner.write_char('"')
            '\'' => inner.write_char('\'')
            '\\' => inner.write_char('\\')
            _ => inner.write_char(esc)
          }
        }
        None => break
      }
    } else if ch == quote {
      self.advance()
      closed = true
      break
    } else if !allow_multiline && (ch == '\n' || ch == '\r') {
      break
    } else {
      inner.write_char(ch)
      self.advance()
    }
  }
  (self.slice_chars(start, self.pos), inner.to_string(), closed)
}

///|
/// Collect C/JS/MoonBit-style trivia (`//`, `///`, `///|`, `/* ... */`, whitespace, newlines).
pub fn Scanner::collect_c_like_trivia(
  self : Scanner,
  recognize_moonbit_sep~ : Bool = false,
  allow_hash_comment~ : Bool = false,
) -> Array[@cst.Trivia] {
  let out : Array[@cst.Trivia] = []
  while !self.is_eof() {
    match self.consume_spaces() {
      Some(sp) => {
        out.push(sp)
        continue
      }
      None => ()
    }
    match self.consume_newline() {
      Some(nl) => {
        out.push(nl)
        continue
      }
      None => ()
    }
    if recognize_moonbit_sep && self.starts_with("///|") {
      let text = self.consume_to_eol(include_newline=true)
      out.push(@cst.Trivia::new(@cst.BlockSeparator, text))
      continue
    }
    if self.starts_with("///") {
      let text = self.consume_to_eol(include_newline=true)
      out.push(@cst.Trivia::new(@cst.DocComment, text))
      continue
    }
    if self.starts_with("//") {
      let text = self.consume_to_eol(include_newline=true)
      out.push(@cst.Trivia::new(@cst.LineComment, text))
      continue
    }
    if allow_hash_comment && self.peek() == Some('#') && !self.starts_with("#|") {
      let text = self.consume_to_eol(include_newline=true)
      out.push(@cst.Trivia::new(@cst.LineComment, text))
      continue
    }
    if self.starts_with("/*") {
      let start = self.pos
      self.advance(count=2)
      while !self.is_eof() {
        if self.starts_with("*/") {
          self.advance(count=2)
          break
        }
        self.advance()
      }
      out.push(
        @cst.Trivia::new(@cst.BlockComment, self.slice_chars(start, self.pos)),
      )
      continue
    }
    break
  }
  out
}

///|
/// Collect horizontal trailing trivia on the SAME line (optional spaces + inline comment + single newline).
pub fn Scanner::collect_trailing_line_trivia(
  self : Scanner,
  allow_slash_comment~ : Bool = true,
  allow_hash_comment~ : Bool = false,
) -> Array[@cst.Trivia] {
  let out : Array[@cst.Trivia] = []
  match self.consume_spaces() {
    Some(sp) => out.push(sp)
    None => ()
  }
  if allow_slash_comment && self.starts_with("//") && !self.starts_with("///|") {
    let text = self.consume_to_eol(include_newline=true)
    out.push(@cst.Trivia::new(@cst.LineComment, text))
    return out
  }
  if allow_hash_comment && self.peek() == Some('#') {
    let text = self.consume_to_eol(include_newline=true)
    out.push(@cst.Trivia::new(@cst.LineComment, text))
    return out
  }
  match self.consume_newline() {
    Some(nl) => out.push(nl)
    None => ()
  }
  out
}

///|
/// Check whether `ch` can start an ASCII/Unicode identifier.
pub fn is_ident_start(ch : Char) -> Bool {
  (ch >= 'a' && ch <= 'z') ||
  (ch >= 'A' && ch <= 'Z') ||
  ch == '_' ||
  ch == '$' ||
  ch.to_int() > 127
}

///|
/// Check whether `ch` can continue an identifier.
pub fn is_ident_continue(ch : Char) -> Bool {
  is_ident_start(ch) || (ch >= '0' && ch <= '9') || ch == '-'
}

///|
/// Scan an identifier starting at `self.pos`.
pub fn Scanner::scan_ident(
  self : Scanner,
  allow_hyphen~ : Bool = false,
) -> String {
  let start = self.pos
  match self.peek() {
    Some(ch) => if !is_ident_start(ch) { return "" }
    None => return ""
  }
  self.advance()
  while !self.is_eof() {
    let ch = self.peek().unwrap()
    if (ch >= 'a' && ch <= 'z') ||
      (ch >= 'A' && ch <= 'Z') ||
      (ch >= '0' && ch <= '9') ||
      ch == '_' ||
      ch == '$' ||
      ch.to_int() > 127 ||
      (allow_hyphen && ch == '-') {
      self.advance()
    } else {
      break
    }
  }
  self.slice_chars(start, self.pos)
}

///|
/// Advance over a balanced delimiter expression (`{...}`, `(...)`, `[...]`),
/// safely skipping strings, character literals, raw `#|...` lines, and comments.
/// Returns `(consumed_cleanly)` boolean indicating whether closing delimiter matched.
pub fn Scanner::skip_balanced_group(
  self : Scanner,
  allow_hash_comment~ : Bool = false,
) -> Bool {
  let open = match self.peek() {
    Some('{') => '{'
    Some('(') => '('
    Some('[') => '['
    _ => return false
  }
  let close = match open {
    '{' => '}'
    '(' => ')'
    _ => ']'
  }
  let stack : Array[Char] = [close]
  self.advance()
  while !self.is_eof() && !stack.is_empty() {
    let ch = self.peek().unwrap()
    if ch == '"' ||
      (
        ch == '\'' &&
        (
          self.peek(delta=1) == Some('\\') ||
          self.peek(delta=2) == Some('\'') ||
          !is_ident_start(self.peek(delta=1).unwrap_or(' '))
        )
      ) {
      if self.starts_with("\"\"\"") || self.starts_with("'''") {
        let delim = self.slice_chars(self.pos, self.pos + 3)
        self.advance(count=3)
        while !self.is_eof() && !self.starts_with(delim) {
          if self.peek() == Some('\\') {
            self.advance(count=2)
          } else {
            self.advance()
          }
        }
        if self.starts_with(delim) {
          self.advance(count=3)
        }
      } else {
        let _ = self.scan_quoted_string(allow_multiline=true)
      }
    } else if ch == '`' {
      self.advance()
      while !self.is_eof() {
        let c2 = self.peek().unwrap()
        if c2 == '\\' {
          self.advance(count=2)
        } else if c2 == '`' {
          self.advance()
          break
        } else {
          self.advance()
        }
      }
    } else if self.starts_with("#|") {
      let _ = self.consume_to_eol(include_newline=true)
    } else if self.starts_with("//") {
      let _ = self.consume_to_eol(include_newline=true)
    } else if allow_hash_comment && ch == '#' {
      let _ = self.consume_to_eol(include_newline=true)
    } else if self.starts_with("/*") {
      self.advance(count=2)
      while !self.is_eof() {
        if self.starts_with("*/") {
          self.advance(count=2)
          break
        }
        self.advance()
      }
    } else if ch == '{' {
      stack.push('}')
      self.advance()
    } else if ch == '(' {
      stack.push(')')
      self.advance()
    } else if ch == '[' {
      stack.push(']')
      self.advance()
    } else if ch == '}' || ch == ')' || ch == ']' {
      let expected = stack[stack.length() - 1]
      if ch == expected {
        let _ = stack.pop()
        self.advance()
      } else {
        // Mismatched delimiter: record failure without looping forever
        self.advance()
        return false
      }
    } else {
      self.advance()
    }
  }
  stack.is_empty()
}
