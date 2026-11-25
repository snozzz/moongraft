///|
/// High-level public library entry point: perform syntax-aware 3-way CST merge on `(base, left, right)`.
///
/// # Example
/// ```mbt check
/// test {
///   let base = "import {\n  \"moonbitlang/core/debug\",\n}\n"
///   let ours = "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/hashmap\",\n}\n"
///   let theirs = "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/json\",\n}\n"
///   let res = @moongraft.merge(base, ours, theirs, path="moon.pkg")
///   inspect(res.conflict_count, content="0")
///   inspect(res.syntax_valid, content="true")
/// }
/// ```
pub fn merge(
  base : String,
  left : String,
  right : String,
  path~ : StringView = "",
  language~ : @cst.Language? = None,
  style~ : @diff3.ConflictStyle = @diff3.Diff3,
  labels~ : @diff3.MergeLabels = @diff3.MergeLabels::default(),
) -> @merger.MergeResult {
  let lang = match language {
    Some(l) => l
    None => @lang.detect_language(path, content=left)
  }
  let opts = @merger.MergeOptions::for_language(lang, style~, labels~)
  @merger.merge_3way(base, left, right, opts)
}

///|
/// Resolve inline Git conflict markers (`<<<<<<< / ||||||| / ======= / >>>>>>>`) in `conflicted_text`.
///
/// # Example
/// ```mbt check
/// test {
///   let conflicted = "{\n  \"a\": 1,\n<<<<<<< HEAD\n  \"b\": 2\n=======\n  \"c\": 3\n>>>>>>> branch\n}\n"
///   let solved = @moongraft.solve_conflicts(conflicted, path="config.json")
///   inspect(solved.initial_conflicts, content="1")
///   inspect(solved.remaining_conflicts, content="0")
/// }
/// ```
pub fn solve_conflicts(
  conflicted_text : String,
  path~ : StringView = "",
  language~ : @cst.Language? = None,
  style~ : @diff3.ConflictStyle = @diff3.Diff3,
) -> @solver.SolveResult {
  @solver.solve_conflicted_file(
    conflicted_text,
    path~,
    language_override=language,
    style~,
  )
}

///|
/// Compute syntax-aware structural AST edits (including `Moved` and `MovedAndModified` declarations).
///
/// # Example
/// ```mbt check
/// test {
///   let old_src = "{\n  \"a\": 1\n}\n"
///   let new_src = "{\n  \"a\": 1,\n  \"b\": 2\n}\n"
///   let edits = @moongraft.structural_diff(old_src, new_src, path="data.json")
///   inspect(edits.length(), content="1")
/// }
/// ```
pub fn structural_diff(
  old_text : String,
  new_text : String,
  path~ : StringView = "",
  language~ : @cst.Language? = None,
) -> Array[@matcher.StructuralEdit] {
  let lang = match language {
    Some(l) => l
    None => @lang.detect_language(path, content=new_text)
  }
  let old_cst = @lang.parse_cst(old_text, lang)
  let new_cst = @lang.parse_cst(new_text, lang)
  @matcher.summarize_structural_diff(old_text, old_cst, new_text, new_cst)
}

///|
/// Analyze 3-way branches for declaration renames and cross-branch stale call-site semantic hazards.
pub fn analyze_renames(
  base : String,
  left : String,
  right : String,
  path~ : StringView = "",
  language~ : @cst.Language? = None,
) -> @refactor.RefactorAnalysis {
  let lang = match language {
    Some(l) => l
    None => @lang.detect_language(path, content=left)
  }
  @refactor.analyze_cross_branch_renames(base, left, right, lang)
}

///|
/// Reconcile `K` parallel AI coding agent file-trees against a shared `base_files` snapshot.
pub fn reconcile_workspaces(
  base_files : Map[String, String],
  agent_trees : Array[Map[String, String]],
  propagate_renames~ : Bool = false,
) -> @workspace.WorkspaceMergePlan {
  @workspace.reconcile_agent_workspaces(
    base_files,
    agent_trees,
    propagate_renames~,
  )
}

///|
/// Parse source into a lossless CST and render its S-expression debug view.
pub fn inspect_cst_sexp(
  source : String,
  path~ : StringView = "",
  language~ : @cst.Language? = None,
) -> String {
  let lang = match language {
    Some(l) => l
    None => @lang.detect_language(path, content=source)
  }
  let tree = @lang.parse_cst(source, lang)
  @cst.format_sexp(tree)
}

///|
/// Run the built-in 16-case multi-language evaluation benchmark suite.
pub fn evaluate_corpus() -> @report.SuiteSummary {
  @report.run_benchmark_suite()
}

///|
/// JSON-in / JSON-out bridge used by the browser playground and external language bindings.
pub fn playground_merge_json(
  path : String,
  base : String,
  left : String,
  right : String,
  style_name : String,
) -> String {
  let style = @diff3.ConflictStyle::from_str(style_name).unwrap_or(@diff3.Diff3)
  let lang = @lang.detect_language(path, content=left)
  let mg_res = merge(base, left, right, path~, language=Some(lang), style~)
  let d3_res = @diff3.merge_lines_diff3(base, left, right, style~)
  let ref_res = analyze_renames(base, left, right, language=Some(lang))
  let sexp = inspect_cst_sexp(mg_res.merged_text, language=Some(lang))
  let payload : Json = {
    "language": lang.slug(),
    "moongraft_text": mg_res.merged_text,
    "moongraft_conflicts": mg_res.conflict_count,
    "diff3_text": d3_res.text,
    "diff3_conflicts": d3_res.conflict_count,
    "syntax_valid": mg_res.syntax_valid,
    "safety_fallback_used": mg_res.safety_fallback_used,
    "events": ToJson::to_json(mg_res.events),
    "renames": ToJson::to_json(ref_res.renames),
    "hazards": ToJson::to_json(ref_res.hazards),
    "merged_cst_sexp": sexp,
  }
  payload.stringify(indent=2)
}
