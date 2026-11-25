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

