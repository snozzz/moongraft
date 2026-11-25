///|
/// Detected symbol rename between `Base` and a modified branch (`Left` or `Right`),
/// discovered via normalized body token Dice similarity on unmatched declarations.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct SymbolRename {
  branch : String
  syntax_kind : String
  old_signature : String
  new_signature : String
  old_identifier : String
  new_identifier : String
  similarity_pct : Int32
}

///|
/// Semantic hazard warning when Branch A renames `foo -> bar` while Branch B introduces
/// new call-sites referencing the stale identifier `foo`!
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct SemanticHazard {
  rename : SymbolRename
  referencing_branch : String
  stale_identifier : String
  occurrence_count : Int32
  suggestion : String
}

///|
/// Result of cross-branch rename & semantic reference analysis.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct RefactorAnalysis {
  renames : Array[SymbolRename]
  hazards : Array[SemanticHazard]
}

///|
/// Extract bare identifier from a canonical signature (`"fn:Type::parse"` -> `"parse"`, `"fn:load"` -> `"load"`).
pub fn bare_name_of_signature(sig : String) -> String {
  let mut after_colon = sig
  match sig.find(":") {
    Some(idx) => after_colon = sig[idx + 1:].to_owned()
    None => ()
  }
  match after_colon.find("::") {
    Some(idx2) => after_colon[idx2 + 2:].to_owned()
    None => after_colon
  }
}

