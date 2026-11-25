///|
/// Primary 3-way syntax-aware CST merge entry point!
/// 1. Computes baseline line-`diff3` conflict count for side-by-side metrics.
/// 2. Checks algebraic fast-paths (`Left == Right`, `Base == Left`, `Base == Right`).
/// 3. Parses `(Base, Left, Right)` into lossless CSTs and executes recursive structural
///    3-way CST merging (`CommutativeByKey`, `CommutativeBlocks`, `Sequential`, sub-line token merge).
/// 4. Runs the **Post-Merge Syntactic & Duplicate-Key Soundness Gate**: if `MoonGraft` produces
///    a conflict-free output, it re-parses and validates the merged document; if any syntax or
///    duplicate-signature invariant is violated, it safely falls back to `diff3`!
pub fn merge_3way(
  base_text : String,
  left_text : String,
  right_text : String,
  options : MergeOptions,
) -> MergeResult {
  let baseline_d3 = @diff3.merge_lines_diff3(
    base_text,
    left_text,
    right_text,
    style=options.style,
    labels=options.labels,
  )
  let line_conflicts = baseline_d3.conflict_count
  let events : Array[ResolutionEvent] = []

  // Algebraic Law 1: Idempotency (`merge(O, A, A) == A`)
  if left_text == right_text {
    events.push({
      kind: FastPathIdentical,
      target: "file",
      detail: "Left and Right revisions are byte-for-byte identical",
    })
    return {
      merged_text: left_text,
      conflict_count: 0,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: true,
      safety_fallback_used: false,
      events,
    }
  }

  // Algebraic Law 2: Identity (`merge(O, O, B) == B` and `merge(O, A, O) == A`)
  if base_text == left_text {
    events.push({
      kind: FastPathTrivialSide,
      target: "file",
      detail: "Left matches Base; fast-forwarded to Right",
    })
    return {
      merged_text: right_text,
      conflict_count: 0,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: true,
      safety_fallback_used: false,
      events,
    }
  }
  if base_text == right_text {
    events.push({
      kind: FastPathTrivialSide,
      target: "file",
      detail: "Right matches Base; fast-forwarded to Left",
    })
    return {
      merged_text: left_text,
      conflict_count: 0,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: true,
      safety_fallback_used: false,
      events,
    }
  }

  if options.language == @cst.PlainText {
    let pt_d3 = @diff3.merge_lines_diff3(
      base_text,
      left_text,
      right_text,
      style=options.style,
      labels=options.labels,
      enable_subline=options.enable_subline,
    )
    return {
      merged_text: pt_d3.text,
      conflict_count: pt_d3.conflict_count,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: pt_d3.conflict_count == 0,
      safety_fallback_used: false,
      events,
    }
  }

  let base_cst = @lang.parse_cst(base_text, options.language)
  let left_cst = @lang.parse_cst(left_text, options.language)
  let right_cst = @lang.parse_cst(right_text, options.language)

  // If any input already has severe syntax errors before merging, fall back conservatively to `diff3`
  if base_cst.has_error || left_cst.has_error || right_cst.has_error {
    events.push({
      kind: SafetyFallbackToDiff3,
      target: "file",
      detail: "Input revision contained syntax errors; used conservative line diff3",
    })
    return {
      merged_text: baseline_d3.text,
      conflict_count: baseline_d3.conflict_count,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: false,
      safety_fallback_used: true,
      events,
    }
  }

  let (merged_cst, cst_conflicts) = merge_cst_node(
    base_cst, left_cst, right_cst, options, events,
  )
  let merged_text = merged_cst.unparse()

  if cst_conflicts == 0 && options.verify_syntax {
    let (ok, issues) = @lang.verify_well_formed(merged_text, options.language)
    if !ok {
      events.push({
        kind: SafetyFallbackToDiff3,
        target: "post-merge-verifier",
        detail: "Post-merge soundness check rejected candidate (" +
        issues.join("; ") +
        "); fell back to line diff3",
      })
      return {
        merged_text: baseline_d3.text,
        conflict_count: baseline_d3.conflict_count,
        line_diff3_conflicts: line_conflicts,
        language: options.language,
        syntax_valid: false,
        safety_fallback_used: true,
        events,
      }
    }
    return {
      merged_text,
      conflict_count: 0,
      line_diff3_conflicts: line_conflicts,
      language: options.language,
      syntax_valid: true,
      safety_fallback_used: false,
      events,
    }
  }

  {
    merged_text,
    conflict_count: cst_conflicts,
    line_diff3_conflicts: line_conflicts,
    language: options.language,
    syntax_valid: cst_conflicts == 0,
    safety_fallback_used: false,
    events,
  }
}

///|
/// Recursive 3-way CST node merger dispatching on `exact_hash`, `structural_hash`,
/// `CommutativeByKey`, `CommutativeBlocks`, `Sequential`, and leaf token/line `diff3`.
pub fn merge_cst_node(
  base : @cst.CstNode,
  left : @cst.CstNode,
  right : @cst.CstNode,
  options : MergeOptions,
  events : Array[ResolutionEvent],
) -> (@cst.CstNode, Int32) {
  if left.exact_hash == right.exact_hash {
    return (left, 0)
  }
  if base.exact_hash == left.exact_hash {
    return (right, 0)
  }
  if base.exact_hash == right.exact_hash {
    return (left, 0)
  }
  if base.structural_hash == left.structural_hash &&
    base.structural_hash != right.structural_hash {
    return (right, 0)
  }
  if base.structural_hash == right.structural_hash &&
    base.structural_hash != left.structural_hash {
    return (left, 0)
  }

  // Interior container merge
  if !base.is_leaf() &&
    !left.is_leaf() &&
    !right.is_leaf() &&
    left.kind == right.kind &&
    base.kind == left.kind {
    let recurse = fn(
      b : @cst.CstNode,
      l : @cst.CstNode,
      r : @cst.CstNode,
    ) -> (@cst.CstNode, Int32) {
      merge_cst_node(b, l, r, options, events)
    }
    match left.ordering {
      @cst.CommutativeByKey | @cst.CommutativeBlocks =>
        return merge_commutative_containers(
          base, left, right, options, events, recurse,
        )
      @cst.Sequential =>
        return merge_sequential_containers(
          base, left, right, options, events, recurse,
        )
    }
  }

  // Leaf or incompatible kind modification: attempt subline/line `diff3`
  let b_txt = base.unparse()
  let l_txt = left.unparse()
  let r_txt = right.unparse()
  let d3 = @diff3.merge_lines_diff3(
    b_txt,
    l_txt,
    r_txt,
    style=options.style,
    labels=options.labels,
    enable_subline=options.enable_subline,
  )
  if d3.subline_resolved > 0 && d3.conflict_count == 0 {
    events.push({
      kind: SublineTokenMerge,
      target: left.signature.unwrap_or(left.kind.label()),
      detail: "Merged disjoint intra-line token changes",
    })
  } else if d3.conflict_count > 0 {
    events.push({
      kind: ConflictLocalized,
      target: left.signature.unwrap_or(left.kind.label()),
      detail: "Localized true conflict to AST leaf span",
    })
  }
  (
    @cst.CstNode::leaf(
      id=0,
      if d3.conflict_count > 0 {
        @cst.ConflictBlock
      } else {
        left.kind
      },
      d3.text,
      signature=left.signature,
      has_error=d3.conflict_count > 0,
    ),
    d3.conflict_count,
  )
}

