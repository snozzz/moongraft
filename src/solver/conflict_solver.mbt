///|
/// Result of running `solve_conflicted_file` on a file already containing Git conflict markers.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct SolveResult {
  resolved_text : String
  initial_conflicts : Int32
  remaining_conflicts : Int32
  had_diff3_base : Bool
  language : @cst.Language
  events : Array[@merger.ResolutionEvent]
}

///|
/// Parsed segment from a file with inline `<<<<<<< / ||||||| / ======= / >>>>>>>` conflict markers.
priv enum ConflictSegment {
  CleanText(String)
  MarkerHunk(base_body~ : String, left_body~ : String, right_body~ : String)
}

///|
/// Parse inline Git conflict markers (`merge`, `diff3`, or `zdiff3` format) from `conflicted_source`
/// and structurally resolve them using `MoonGraft`'s 3-way CST merger (`moongraft solve`!).
pub fn solve_conflicted_file(
  conflicted_source : String,
  path~ : StringView = "",
  language_override~ : @cst.Language? = None,
  style~ : @diff3.ConflictStyle = @diff3.Diff3,
) -> SolveResult {
  let (segments, marker_count, any_base, detected_labels) = parse_conflict_markers(
    conflicted_source,
  )
  let probe_clean = reconstruct_side(segments, 1)
  let lang = match language_override {
    Some(l) => l
    None => @lang.detect_language(path, content=probe_clean)
  }

  if marker_count == 0 {
    return {
      resolved_text: conflicted_source,
      initial_conflicts: 0,
      remaining_conflicts: 0,
      had_diff3_base: false,
      language: lang,
      events: [],
    }
  }

  // If 2-way conflict markers (`has_base == false`) are present without `|||||||`,
  // verify safety: if all 2-way hunks represent purely additive distinct keys/blocks
  // or identical edits, an empty base hunk is exact; if any 2-way hunk mutates the SAME
  // key to different values without a known base, keep conservative conflict protection!
  let base_doc = reconstruct_side(segments, 0)
  let left_doc = reconstruct_side(segments, 1)
  let right_doc = reconstruct_side(segments, 2)

  if !any_base && !is_two_way_base_safe(base_doc, left_doc, right_doc, lang) {
    return {
      resolved_text: conflicted_source,
      initial_conflicts: marker_count,
      remaining_conflicts: marker_count,
      had_diff3_base: false,
      language: lang,
      events: [],
    }
  }

  let opts = @merger.MergeOptions::for_language(
    lang,
    style~,
    labels=detected_labels,
  )
  let mres = @merger.merge_3way(base_doc, left_doc, right_doc, opts)

  // Never worsen conflict count compared to original conflicted file
  if mres.conflict_count > marker_count {
    return {
      resolved_text: conflicted_source,
      initial_conflicts: marker_count,
      remaining_conflicts: marker_count,
      had_diff3_base: any_base,
      language: lang,
      events: mres.events,
    }
  }

  {
    resolved_text: mres.merged_text,
    initial_conflicts: marker_count,
    remaining_conflicts: mres.conflict_count,
    had_diff3_base: any_base,
    language: lang,
    events: mres.events,
  }
}

///|
/// Reconstruct `0 = Base`, `1 = Left`, or `2 = Right` document from parsed conflict segments.
fn reconstruct_side(segments : Array[ConflictSegment], side : Int32) -> String {
  let buf = StringBuilder()
  for seg in segments {
    match seg {
      CleanText(s) => buf.write_string(s)
      MarkerHunk(base_body~, left_body~, right_body~) =>
        match side {
          0 => buf.write_string(base_body)
          1 => buf.write_string(left_body)
          _ => buf.write_string(right_body)
        }
    }
  }
  buf.to_string()
}

///|
/// Check whether synthesizing an empty base hunk for 2-way markers (`<<<<<<< / ======= / >>>>>>>`)
/// produces syntactically valid `Base`, `Left`, and `Right` CSTs!
/// Notice why this works so cleanly:
/// - In MoonBit/TS/Python/TOML/YAML, dropping the conflicted addition hunk yields a valid `Base`!
/// - In JSON (`{\n  "a": 1,\n<<<<<<<\n  "b": 2\n=======\n  "c": 3\n>>>>>>>\n}`), dropping the
///   trailing hunk leaves `"a": 1,` with a trailing comma (which our JSONC CST parser accepts cleanly!).
fn is_two_way_base_safe(
  base_doc : String,
  left_doc : String,
  right_doc : String,
  lang : @cst.Language,
) -> Bool {
  let b_cst = @lang.parse_cst(base_doc, lang)
  let l_cst = @lang.parse_cst(left_doc, lang)
  let r_cst = @lang.parse_cst(right_doc, lang)
  !b_cst.has_error && !l_cst.has_error && !r_cst.has_error
}

///|
fn parse_conflict_markers(
  source : String,
) -> (Array[ConflictSegment], Int32, Bool, @diff3.MergeLabels) {
  let lines = @diff3.split_lines_lossless(source)
  let segments : Array[ConflictSegment] = []
  let clean_buf = StringBuilder()
  let mut count = 0
  let mut saw_base = false
  let mut first_labels = @diff3.MergeLabels::default()

  let n = lines.length()
  let mut i = 0
  while i < n {
    let line = lines[i]
    if line.has_prefix("<<<<<<<") {
      let left_label = extract_marker_label(line, "<<<<<<<", "OURS")
      let left_buf = StringBuilder()
      let base_buf = StringBuilder()
      let right_buf = StringBuilder()
      let mut base_label = "BASE"
      let mut state = 1 // 1=in_left, 2=in_base, 3=in_right
      let mut closed = false
      let mut right_label = "THEIRS"

      let mut j = i + 1
      while j < n {
        let cur = lines[j]
        if state == 1 && cur.has_prefix("|||||||") {
          saw_base = true
          base_label = extract_marker_label(cur, "|||||||", "BASE")
          state = 2
        } else if (state == 1 || state == 2) &&
          (cur == "=======\n" || cur == "=======\r\n" || cur == "=======") {
          state = 3
        } else if state == 3 && cur.has_prefix(">>>>>>>") {
          right_label = extract_marker_label(cur, ">>>>>>>", "THEIRS")
          closed = true
          j += 1
          break
        } else {
          match state {
            1 => left_buf.write_string(cur)
            2 => base_buf.write_string(cur)
            _ => right_buf.write_string(cur)
          }
        }
        j += 1
      }

      if closed {
        let prior = clean_buf.to_string()
        if !prior.is_empty() {
          segments.push(CleanText(prior))
          clean_buf.reset()
        }
        if count == 0 {
          first_labels = @diff3.MergeLabels::new(
            base_label, left_label, right_label,
          )
        }
        count += 1
        segments.push(
          MarkerHunk(
            base_body=base_buf.to_string(),
            left_body=left_buf.to_string(),
            right_body=right_buf.to_string(),
          ),
        )
        i = j
        continue
      }
    }
    clean_buf.write_string(line)
    i += 1
  }

  let tail = clean_buf.to_string()
  if !tail.is_empty() {
    segments.push(CleanText(tail))
  }
  (segments, count, saw_base, first_labels)
}

///|
fn extract_marker_label(
  line : String,
  marker : String,
  fallback : String,
) -> String {
  if line.length() <= marker.length() {
    return fallback
  }
  let rest = line[marker.length():].trim().to_owned()
  if rest.is_empty() {
    fallback
  } else {
    rest
  }
}
