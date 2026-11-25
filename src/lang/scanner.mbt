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

