///|
/// File-level status in a multi-agent workspace reconciliation plan.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum FileMergeStatus {
  Unchanged
  AddedCleanly
  DeletedCleanly
  ModifiedSingleAgent
  MergedStructurallyClean
  ConflictedFile
}

///|
/// Per-file outcome when reconciling 2 or more parallel AI agent workspaces.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct FileReconcileReport {
  path : String
  language : String
  status : FileMergeStatus
  conflict_count : Int32
  line_diff3_conflicts : Int32
  merged_content : String?
  semantic_hazards : Array[@refactor.SemanticHazard]
}

///|
/// Aggregate result of reconciling `K` parallel agent branches (`Octopus CST Merge`!).
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct WorkspaceMergePlan {
  agent_count : Int32
  total_files : Int32
  clean_files : Int32
  conflicted_files : Int32
  diff3_conflicts_saved : Int32
  merged_files : Map[String, String]
  file_reports : Array[FileReconcileReport]
}

