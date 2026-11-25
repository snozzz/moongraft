///|
/// Git-compatible conflict marker rendering style.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum ConflictStyle {
  Merge
  Diff3
  ZDiff3
}

///|
/// Parse conflict marker style from CLI flag value.
pub fn ConflictStyle::from_str(s : StringView) -> ConflictStyle? {
  match s.to_owned().to_lower() {
    "merge" | "standard" => Some(Merge)
    "diff3" => Some(Diff3)
    "zdiff3" | "zealous" => Some(ZDiff3)
    _ => None
  }
}

///|
/// Labels attached to conflict markers (`<<<<<<< left_label`, `||||||| base_label`, `>>>>>>> right_label`).
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) struct MergeLabels {
  base : String
  left : String
  right : String
}

///|
/// Default labels matching Git `merge-file`.
pub fn MergeLabels::default() -> MergeLabels {
  { base: "BASE", left: "OURS", right: "THEIRS", }
}

///|
/// Custom labels from `-L` CLI options.
pub fn MergeLabels::new(
  base : String,
  left : String,
  right : String,
) -> MergeLabels {
  { base, left, right, }
}

///|
/// A 3-way hunk produced by aligning `Base`, `Left`, and `Right` line or token sequences.
#derive(Eq, @debug.Debug, ToJson)
pub(all) enum Hunk3 {
  Clean(Array[String])
  Conflict(base~ : Array[String], left~ : Array[String], right~ : Array[String])
}

///|
/// Result of running 3-way `diff3` over text inputs.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct Diff3Outcome {
  text : String
  conflict_count : Int32
  hunks : Array[Hunk3]
  subline_resolved : Int32
}
