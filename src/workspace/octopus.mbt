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

///|
/// Perform N-way Octopus CST Merge on a single file across `K >= 1` parallel agent edits
/// sharing `base_text` as common ancestor!
/// Iteratively folds agent revisions `(acc, agent_i)` over `base_text` while optionally
/// propagating unambiguous symbol renames when `propagate_renames == true`.
pub fn merge_n_way_file(
  path : StringView,
  base_text : String,
  agent_versions : Array[String],
  style~ : @diff3.ConflictStyle = @diff3.Diff3,
  propagate_renames~ : Bool = false,
) -> (@merger.MergeResult, Array[@refactor.SemanticHazard]) {
  let lang = @lang.detect_language(path, content=base_text)
  let opts = @merger.MergeOptions::for_language(lang, style~)
  if agent_versions.is_empty() {
    return (
      {
        merged_text: base_text,
        conflict_count: 0,
        line_diff3_conflicts: 0,
        language: lang,
        syntax_valid: true,
        safety_fallback_used: false,
        events: [],
      },
      [],
    )
  }
  if agent_versions.length() == 1 {
    let single = @merger.merge_3way(
      base_text,
      agent_versions[0],
      base_text,
      opts,
    )
    return (single, [])
  }

  let mut acc_text = agent_versions[0]
  let mut total_conflicts = 0
  let mut total_d3_conflicts = 0
  let all_events : Array[@merger.ResolutionEvent] = []
  let all_hazards : Array[@refactor.SemanticHazard] = []
  let mut all_valid = true
  let mut any_fallback = false

  for i = 1; i < agent_versions.length(); i = i + 1 {
    let mut rhs = agent_versions[i]
    let ref_info = @refactor.analyze_cross_branch_renames(
      base_text, acc_text, rhs, lang,
    )
    for h in ref_info.hazards {
      if propagate_renames {
        if h.referencing_branch == "right" {
          let (rewritten, _) = @refactor.rewrite_identifier_lossless(
            rhs,
            h.rename.old_identifier,
            h.rename.new_identifier,
          )
          rhs = rewritten
        } else {
          let (rewritten, _) = @refactor.rewrite_identifier_lossless(
            acc_text,
            h.rename.old_identifier,
            h.rename.new_identifier,
          )
          acc_text = rewritten
        }
      } else {
        all_hazards.push(h)
      }
    }

    let step = @merger.merge_3way(base_text, acc_text, rhs, opts)
    acc_text = step.merged_text
    total_conflicts += step.conflict_count
    total_d3_conflicts += step.line_diff3_conflicts
    if !step.syntax_valid {
      all_valid = false
    }
    if step.safety_fallback_used {
      any_fallback = true
    }
    for ev in step.events {
      all_events.push(ev)
    }
    // If unresolved conflict markers were emitted, stop folding further clean CST passes on broken text
    if step.conflict_count > 0 {
      for k = i + 1; k < agent_versions.length(); k = k + 1 {
        let d3 = @diff3.merge_lines_diff3(
          base_text,
          acc_text,
          agent_versions[k],
          style~,
        )
        acc_text = d3.text
        total_conflicts += d3.conflict_count
        total_d3_conflicts += d3.conflict_count
      }
      break
    }
  }

  (
    {
      merged_text: acc_text,
      conflict_count: total_conflicts,
      line_diff3_conflicts: total_d3_conflicts,
      language: lang,
      syntax_valid: all_valid && total_conflicts == 0,
      safety_fallback_used: any_fallback,
      events: all_events,
    },
    all_hazards,
  )
}

///|
/// Reconcile `K` parallel AI agent file-trees (`Array[Map[String, String]]`) against a
/// common `base_files` snapshot (`Map[String, String]`), handling file creations, deletions,
/// and N-way structural CST file merges across the entire repository!
pub fn reconcile_agent_workspaces(
  base_files : Map[String, String],
  agent_trees : Array[Map[String, String]],
  propagate_renames~ : Bool = false,
) -> WorkspaceMergePlan {
  let path_set : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for p, _ in base_files {
    path_set.set(p, true)
  }
  for tree in agent_trees {
    for p, _ in tree {
      path_set.set(p, true)
    }
  }

  let all_paths : Array[String] = []
  path_set.each(fn(p, _) { all_paths.push(p) })
  all_paths.sort()

  let merged_files : Map[String, String] = Map([])
  let reports : Array[FileReconcileReport] = []
  let mut clean_files = 0
  let mut conflicted_files = 0
  let mut diff3_saved = 0

  for path in all_paths {
    let base_opt = base_files.get(path)
    match base_opt {
      Some(b_content) => {
        let mut deleted_by_any = false
        let modified_versions : Array[String] = []
        for tree in agent_trees {
          match tree.get(path) {
            None => deleted_by_any = true
            Some(v) => if v != b_content { modified_versions.push(v) }
          }
        }

        let sample = if !modified_versions.is_empty() {
          modified_versions[0]
        } else {
          b_content
        }
        let lang = @lang.detect_language(path, content=sample)

        if !deleted_by_any && modified_versions.is_empty() {
          merged_files[path] = b_content
          clean_files += 1
          reports.push({
            path,
            language: lang.slug(),
            status: Unchanged,
            conflict_count: 0,
            line_diff3_conflicts: 0,
            merged_content: Some(b_content),
            semantic_hazards: [],
          })
        } else if deleted_by_any && modified_versions.is_empty() {
          clean_files += 1
          reports.push({
            path,
            language: lang.slug(),
            status: DeletedCleanly,
            conflict_count: 0,
            line_diff3_conflicts: 0,
            merged_content: None,
            semantic_hazards: [],
          })
        } else if deleted_by_any && !modified_versions.is_empty() {
          // Delete-Modify conflict at file granularity!
          let (c_text, _) = @diff3.render_hunks(
            [
              @diff3.Conflict(
                base=@diff3.split_lines_lossless(b_content),
                left=[],
                right=@diff3.split_lines_lossless(modified_versions[0]),
              ),
            ],
            @diff3.Diff3,
            @diff3.MergeLabels::new(
              "BASE", "DELETED_BY_AGENT", "MODIFIED_BY_AGENT",
            ),
          )
          merged_files[path] = c_text
          conflicted_files += 1
          reports.push({
            path,
            language: lang.slug(),
            status: ConflictedFile,
            conflict_count: 1,
            line_diff3_conflicts: 1,
            merged_content: Some(c_text),
            semantic_hazards: [],
          })
        } else if modified_versions.length() == 1 {
          merged_files[path] = modified_versions[0]
          clean_files += 1
          reports.push({
            path,
            language: lang.slug(),
            status: ModifiedSingleAgent,
            conflict_count: 0,
            line_diff3_conflicts: 0,
            merged_content: Some(modified_versions[0]),
            semantic_hazards: [],
          })
        } else {
          let (mres, hazards) = merge_n_way_file(
            path,
            b_content,
            modified_versions,
            propagate_renames~,
          )
          merged_files[path] = mres.merged_text
          if mres.conflict_count == 0 {
            clean_files += 1
            if mres.line_diff3_conflicts > 0 {
              diff3_saved += mres.line_diff3_conflicts
            }
            reports.push({
              path,
              language: lang.slug(),
              status: MergedStructurallyClean,
              conflict_count: 0,
              line_diff3_conflicts: mres.line_diff3_conflicts,
              merged_content: Some(mres.merged_text),
              semantic_hazards: hazards,
            })
          } else {
            conflicted_files += 1
            reports.push({
              path,
              language: lang.slug(),
              status: ConflictedFile,
              conflict_count: mres.conflict_count,
              line_diff3_conflicts: mres.line_diff3_conflicts,
              merged_content: Some(mres.merged_text),
              semantic_hazards: hazards,
            })
          }
        }
      }
      None => {
        // Newly added file by one or more agents
        let additions : Array[String] = []
        for tree in agent_trees {
          match tree.get(path) {
            Some(v) => additions.push(v)
            None => ()
          }
        }
        let lang = @lang.detect_language(
          path,
          content=if !additions.is_empty() { additions[0] } else { "" },
        )
        if additions.length() == 1 {
          merged_files[path] = additions[0]
          clean_files += 1
          reports.push({
            path,
            language: lang.slug(),
            status: AddedCleanly,
            conflict_count: 0,
            line_diff3_conflicts: 0,
            merged_content: Some(additions[0]),
            semantic_hazards: [],
          })
        } else {
          // Two agents created the same new file path (`e.g. moon.pkg` or `utils.mbt`) -> merge over `""`!
          let (mres, hazards) = merge_n_way_file(
            path,
            "",
            additions,
            propagate_renames~,
          )
          merged_files[path] = mres.merged_text
          if mres.conflict_count == 0 {
            clean_files += 1
            diff3_saved += mres.line_diff3_conflicts
            reports.push({
              path,
              language: lang.slug(),
              status: AddedCleanly,
              conflict_count: 0,
              line_diff3_conflicts: mres.line_diff3_conflicts,
              merged_content: Some(mres.merged_text),
              semantic_hazards: hazards,
            })
          } else {
            conflicted_files += 1
            reports.push({
              path,
              language: lang.slug(),
              status: ConflictedFile,
              conflict_count: mres.conflict_count,
              line_diff3_conflicts: mres.line_diff3_conflicts,
              merged_content: Some(mres.merged_text),
              semantic_hazards: hazards,
            })
          }
        }
      }
    }
  }

  {
    agent_count: agent_trees.length(),
    total_files: all_paths.length(),
    clean_files,
    conflicted_files,
    diff3_conflicts_saved: diff3_saved,
    merged_files,
    file_reports: reports,
  }
}
