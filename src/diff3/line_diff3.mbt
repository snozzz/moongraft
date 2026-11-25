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

///|
/// Tokenize a single line into fine-grained lexical atoms while keeping string literals
/// (`"..."`, `'...'`) and numeric/version literals (`1.2.3`) strictly atomic so sub-line
/// merge never splices inside a scalar literal!
fn tokenize_line(line : String) -> Array[String] {
  let tokens : Array[String] = []
  let chars : Array[Char] = []
  for ch in line {
    chars.push(ch)
  }
  let n = chars.length()
  let mut i = 0
  while i < n {
    let ch = chars[i]
    if ch == '"' || ch == '\'' {
      let quote = ch
      let buf = StringBuilder()
      buf.write_char(ch)
      i += 1
      while i < n {
        let c = chars[i]
        buf.write_char(c)
        i += 1
        if c == '\\' && i < n {
          buf.write_char(chars[i])
          i += 1
        } else if c == quote {
          break
        }
      }
      tokens.push(buf.to_string())
    } else if ch >= '0' && ch <= '9' {
      let buf = StringBuilder()
      while i < n {
        let c = chars[i]
        if (c >= '0' && c <= '9') ||
          (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          c == '.' ||
          c == '_' ||
          c == '-' {
          buf.write_char(c)
          i += 1
        } else {
          break
        }
      }
      tokens.push(buf.to_string())
    } else if (ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || ch == '_' {
      let buf = StringBuilder()
      while i < n {
        let c = chars[i]
        if (c >= 'a' && c <= 'z') ||
          (c >= 'A' && c <= 'Z') ||
          (c >= '0' && c <= '9') ||
          c == '_' {
          buf.write_char(c)
          i += 1
        } else {
          break
        }
      }
      tokens.push(buf.to_string())
    } else if ch == ' ' || ch == '\t' {
      let buf = StringBuilder()
      while i < n && (chars[i] == ' ' || chars[i] == '\t') {
        buf.write_char(chars[i])
        i += 1
      }
      tokens.push(buf.to_string())
    } else {
      tokens.push(ch.to_string())
      i += 1
    }
  }
  tokens
}

///|
/// Attempt a safe token-level 3-way merge when `base`, `left`, and `right` are each a single line
/// and Left/Right modify strictly separated token spans with at least one unchanged anchor token
/// separating the two edits.
pub fn try_subline_merge(
  base_line : String,
  left_line : String,
  right_line : String,
) -> String? {
  let b_toks = tokenize_line(base_line)
  let l_toks = tokenize_line(left_line)
  let r_toks = tokenize_line(right_line)
  if b_toks.length() < 3 {
    return None
  }
  let m_bl = compute_base_matches(b_toks, l_toks)
  let m_br = compute_base_matches(b_toks, r_toks)

  let out = StringBuilder()
  let mut bi = 0
  let mut li = 0
  let mut ri = 0
  let mut last_was_edit = false
  let n = b_toks.length()

  while bi < n {
    let sync_here = match (m_bl[bi], m_br[bi]) {
      (Some(l_pos), Some(r_pos)) => l_pos == li && r_pos == ri
      _ => false
    }
    if sync_here {
      out.write_string(b_toks[bi])
      bi += 1
      li += 1
      ri += 1
      last_was_edit = false
    } else {
      let mut next_b = bi
      let mut found : (Int32, Int32, Int32)? = None
      while next_b < n {
        match (m_bl[next_b], m_br[next_b]) {
          (Some(lp), Some(rp)) =>
            if lp >= li && rp >= ri {
              found = Some((next_b, lp, rp))
              break
            }
          _ => ()
        }
        next_b += 1
      }
      let (end_b, end_l, end_r) = match found {
        Some(triple) => triple
        None => (n, l_toks.length(), r_toks.length())
      }
      let b_seg = b_toks[bi:end_b]
      let l_seg = l_toks[li:end_l]
      let r_seg = r_toks[ri:end_r]
      let l_same = slices_equal(b_seg, l_seg)
      let r_same = slices_equal(b_seg, r_seg)
      if l_same && !r_same {
        if last_was_edit {
          return None
        }
        for t in r_seg {
          out.write_string(t)
        }
        last_was_edit = true
      } else if !l_same && r_same {
        if last_was_edit {
          return None
        }
        for t in l_seg {
          out.write_string(t)
        }
        last_was_edit = true
      } else if slices_equal(l_seg, r_seg) {
        for t in l_seg {
          out.write_string(t)
        }
        last_was_edit = true
      } else {
        return None
      }
      bi = end_b
      li = end_l
      ri = end_r
    }
  }

  let l_tail = l_toks[li:]
  let r_tail = r_toks[ri:]
  if l_tail.is_empty() && r_tail.is_empty() {
    Some(out.to_string())
  } else if l_tail.is_empty() && !last_was_edit {
    for t in r_tail {
      out.write_string(t)
    }
    Some(out.to_string())
  } else if r_tail.is_empty() && !last_was_edit {
    for t in l_tail {
      out.write_string(t)
    }
    Some(out.to_string())
  } else if slices_equal(l_tail, r_tail) {
    for t in l_tail {
      out.write_string(t)
    }
    Some(out.to_string())
  } else {
    None
  }
}

///|
/// Ensure every line inside a conflict block terminates with `\n` so Git conflict
/// markers always start cleanly at column 1.
fn ensure_trailing_newline_lines(lines : Array[String]) -> Array[String] {
  if lines.is_empty() {
    return []
  }
  let out = lines.copy()
  let last_idx = out.length() - 1
  if !out[last_idx].has_suffix("\n") {
    out[last_idx] = out[last_idx] + "\n"
  }
  out
}

///|
/// Render a sequence of `Hunk3` regions using the requested Git `ConflictStyle`.
pub fn render_hunks(
  hunks : Array[Hunk3],
  style : ConflictStyle,
  labels : MergeLabels,
) -> (String, Int32) {
  let buf = StringBuilder()
  let mut conflicts = 0
  for hunk in hunks {
    match hunk {
      Clean(lines) =>
        for line in lines {
          buf.write_string(line)
        }
      Conflict(base~, left~, right~) => {
        let mut b_arr = base
        let mut l_arr = left
        let mut r_arr = right
        if style == ZDiff3 {
          let mut pre = 0
          while pre < l_arr.length() &&
                pre < r_arr.length() &&
                l_arr[pre] == r_arr[pre] {
            buf.write_string(l_arr[pre])
            pre += 1
          }
          if pre > 0 {
            l_arr = copy_slice(l_arr[pre:])
            r_arr = copy_slice(r_arr[pre:])
            let b_trim = if pre <= b_arr.length() {
              pre
            } else {
              b_arr.length()
            }
            b_arr = copy_slice(b_arr[b_trim:])
          }
          let suffix_acc : Array[String] = []
          while !l_arr.is_empty() &&
                !r_arr.is_empty() &&
                l_arr[l_arr.length() - 1] == r_arr[r_arr.length() - 1] {
            let line = l_arr[l_arr.length() - 1]
            suffix_acc.push(line)
            let _ = l_arr.pop()
            let _ = r_arr.pop()
            if !b_arr.is_empty() && b_arr[b_arr.length() - 1] == line {
              let _ = b_arr.pop()
            }
          }
          if l_arr.is_empty() && r_arr.is_empty() {
            for i = suffix_acc.length() - 1; i >= 0; i = i - 1 {
              buf.write_string(suffix_acc[i])
            }
            continue
          }
          conflicts += 1
          buf.write_string("<<<<<<< ")
          buf.write_string(labels.left)
          buf.write_string("\n")
          for line in ensure_trailing_newline_lines(l_arr) {
            buf.write_string(line)
          }
          buf.write_string("||||||| ")
          buf.write_string(labels.base)
          buf.write_string("\n")
          for line in ensure_trailing_newline_lines(b_arr) {
            buf.write_string(line)
          }
          buf.write_string("=======\n")
          for line in ensure_trailing_newline_lines(r_arr) {
            buf.write_string(line)
          }
          buf.write_string(">>>>>>> ")
          buf.write_string(labels.right)
          buf.write_string("\n")
          for i = suffix_acc.length() - 1; i >= 0; i = i - 1 {
            buf.write_string(suffix_acc[i])
          }
        } else {
          conflicts += 1
          buf.write_string("<<<<<<< ")
          buf.write_string(labels.left)
          buf.write_string("\n")
          for line in ensure_trailing_newline_lines(l_arr) {
            buf.write_string(line)
          }
          if style == Diff3 {
            buf.write_string("||||||| ")
            buf.write_string(labels.base)
            buf.write_string("\n")
            for line in ensure_trailing_newline_lines(b_arr) {
              buf.write_string(line)
            }
          }
          buf.write_string("=======\n")
          for line in ensure_trailing_newline_lines(r_arr) {
            buf.write_string(line)
          }
          buf.write_string(">>>>>>> ")
          buf.write_string(labels.right)
          buf.write_string("\n")
        }
      }
    }
  }
  (buf.to_string(), conflicts)
}

///|
/// Perform Patience-based 3-way line `diff3` (with optional intra-line token merge).
pub fn merge_lines_diff3(
  base_text : String,
  left_text : String,
  right_text : String,
  style~ : ConflictStyle = Diff3,
  labels~ : MergeLabels = MergeLabels::default(),
  enable_subline~ : Bool = false,
) -> Diff3Outcome {
  if left_text == right_text {
    return {
      text: left_text,
      conflict_count: 0,
      hunks: [Clean(split_lines_lossless(left_text))],
      subline_resolved: 0,
    }
  }
  if base_text == left_text {
    return {
      text: right_text,
      conflict_count: 0,
      hunks: [Clean(split_lines_lossless(right_text))],
      subline_resolved: 0,
    }
  }
  if base_text == right_text {
    return {
      text: left_text,
      conflict_count: 0,
      hunks: [Clean(split_lines_lossless(left_text))],
      subline_resolved: 0,
    }
  }

  let b_lines = split_lines_lossless(base_text)
  let l_lines = split_lines_lossless(left_text)
  let r_lines = split_lines_lossless(right_text)
  let m_bl = compute_base_matches(b_lines, l_lines)
  let m_br = compute_base_matches(b_lines, r_lines)

  let hunks : Array[Hunk3] = []
  let clean_acc : Array[String] = []
  let mut subline_resolved = 0

  fn flush_clean() -> Unit {
    if !clean_acc.is_empty() {
      hunks.push(Clean(clean_acc.copy()))
      clean_acc.clear()
    }
  }

  let mut bi = 0
  let mut li = 0
  let mut ri = 0
  let nb = b_lines.length()

  while bi < nb {
    let synced = match (m_bl[bi], m_br[bi]) {
      (Some(lp), Some(rp)) => lp == li && rp == ri
      _ => false
    }
    if synced {
      clean_acc.push(b_lines[bi])
      bi += 1
      li += 1
      ri += 1
    } else {
      let mut probe_b = bi
      let mut anchor : (Int32, Int32, Int32)? = None
      while probe_b < nb {
        match (m_bl[probe_b], m_br[probe_b]) {
          (Some(lp), Some(rp)) =>
            if lp >= li && rp >= ri {
              anchor = Some((probe_b, lp, rp))
              break
            }
          _ => ()
        }
        probe_b += 1
      }
      let (end_b, end_l, end_r) = match anchor {
        Some(t) => t
        None => (nb, l_lines.length(), r_lines.length())
      }
      let b_seg = b_lines[bi:end_b]
      let l_seg = l_lines[li:end_l]
      let r_seg = r_lines[ri:end_r]
      let l_unchanged = slices_equal(b_seg, l_seg)
      let r_unchanged = slices_equal(b_seg, r_seg)

      if l_unchanged && !r_unchanged {
        for line in r_seg {
          clean_acc.push(line)
        }
      } else if !l_unchanged && r_unchanged {
        for line in l_seg {
          clean_acc.push(line)
        }
      } else if slices_equal(l_seg, r_seg) {
        for line in l_seg {
          clean_acc.push(line)
        }
      } else if enable_subline &&
        b_seg.length() == 1 &&
        l_seg.length() == 1 &&
        r_seg.length() == 1 {
        match try_subline_merge(b_seg[0], l_seg[0], r_seg[0]) {
          Some(merged_line) => {
            clean_acc.push(merged_line)
            subline_resolved += 1
          }
          None => {
            flush_clean()
            hunks.push(
              Conflict(
                base=copy_slice(b_seg),
                left=copy_slice(l_seg),
                right=copy_slice(r_seg),
              ),
            )
          }
        }
      } else {
        flush_clean()
        hunks.push(
          Conflict(
            base=copy_slice(b_seg),
            left=copy_slice(l_seg),
            right=copy_slice(r_seg),
          ),
        )
      }
      bi = end_b
      li = end_l
      ri = end_r
    }
  }

  let l_rem = l_lines[li:]
  let r_rem = r_lines[ri:]
  if !l_rem.is_empty() || !r_rem.is_empty() {
    if l_rem.is_empty() {
      for line in r_rem {
        clean_acc.push(line)
      }
    } else if r_rem.is_empty() {
      for line in l_rem {
        clean_acc.push(line)
      }
    } else if slices_equal(l_rem, r_rem) {
      for line in l_rem {
        clean_acc.push(line)
      }
    } else {
      flush_clean()
      hunks.push(
        Conflict(base=[], left=copy_slice(l_rem), right=copy_slice(r_rem)),
      )
    }
  }
  flush_clean()

  let (rendered, conflict_count) = render_hunks(hunks, style, labels)
  { text: rendered, conflict_count, hunks, subline_resolved, }
}
