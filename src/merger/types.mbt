///|
/// Category of structural resolution applied by `MoonGraft` during 3-way CST merging.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum ResolutionKind {
  FastPathIdentical
  FastPathTrivialSide
  CommutativeKeyWeave
  ParallelBlockWeave
  MoveAndEditComposed
  RecursiveContainerMerge
  FormattingReconciled
  DuplicateDeduped
  CommaSeparatorSynthesized
  SublineTokenMerge
  ConflictLocalized
  DeleteModifyConflict
  SafetyFallbackToDiff3
}

///|
/// Record explaining a structural decision made by `MoonGraft` (supports explainable AI/tooling audits).
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct ResolutionEvent {
  kind : ResolutionKind
  target : String
  detail : String
}

///|
/// Configuration options controlling 3-way CST merge behavior.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct MergeOptions {
  language : @cst.Language
  style : @diff3.ConflictStyle
  labels : @diff3.MergeLabels
  enable_subline : Bool
  verify_syntax : Bool
}

///|
/// Default `MergeOptions` for a detected `Language`.
pub fn MergeOptions::for_language(
  language : @cst.Language,
  style~ : @diff3.ConflictStyle = @diff3.Diff3,
  labels~ : @diff3.MergeLabels = @diff3.MergeLabels::default(),
) -> MergeOptions {
  { language, style, labels, enable_subline: true, verify_syntax: true, }
}

///|
/// Complete output of `merge_3way`, including merged source text, conflict count,
/// explainable resolution log, and baseline comparison against standard line `diff3`.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct MergeResult {
  merged_text : String
  conflict_count : Int32
  line_diff3_conflicts : Int32
  language : @cst.Language
  syntax_valid : Bool
  safety_fallback_used : Bool
  events : Array[ResolutionEvent]
}

///|
/// True if the merge completed with zero conflicts.
pub fn MergeResult::is_clean(self : MergeResult) -> Bool {
  self.conflict_count == 0
}
