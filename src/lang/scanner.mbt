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

