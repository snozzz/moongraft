///|
/// Split text into lines while preserving each line's exact line-ending (`"\n"`, `"\r\n"`, or `""` for final unterminated line).
pub fn split_lines_lossless(text : String) -> Array[String] {
  if text.is_empty() {
    return []
  }
  let lines : Array[String] = []
  let buf = StringBuilder()
  for ch in text {
    buf.write_char(ch)
    if ch == '\n' {
      lines.push(buf.to_string())
      buf.reset()
    }
  }
  let rem = buf.to_string()
  if !rem.is_empty() {
    lines.push(rem)
  }
  lines
}

///|
/// Extract a match table `matched[base_idx] = Some(side_idx)` from `@diff.Diff` edits.
fn compute_base_matches(
  base : Array[String],
  side : Array[String],
) -> Array[Int32?] {
  let map : Array[Int32?] = Array::make(base.length(), None)
  let d = @diff.Diff(old=base[:], new=side[:], algorithm=@diff.Patience)
  for edit in d.edits() {
    match edit {
      @diff.Equal(old_index~, new_index~, len~) =>
        for k = 0; k < len; k = k + 1 {
          map[old_index + k] = Some(new_index + k)
        }
      _ => ()
    }
  }
  map
}

///|
/// Check exact equality of two string slices.
fn slices_equal(a : ArrayView[String], b : ArrayView[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i = 0; i < a.length(); i = i + 1 {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
/// Copy an `ArrayView[String]` into an owned `Array[String]`.
fn copy_slice(v : ArrayView[String]) -> Array[String] {
  let out : Array[String] = Array(capacity=v.length())
  for item in v {
    out.push(item)
  }
  out
}

