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

///|
/// Extract lexical word tokens from a declaration body (excluding its signature name)
/// to measure body similarity across potential symbol renames.
fn body_token_multiset(
  node : @cst.CstNode,
  ignore_ident : String,
) -> (@hashmap.HashMap[String, Int32], Int32) {
  let counts : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
  let mut total = 0
  let src = node.trimmed_source()
  let sc = @lang.Scanner::new(src)
  while !sc.is_eof() {
    match sc.peek() {
      Some(ch) =>
        if @lang.is_ident_start(ch) {
          let w = sc.scan_ident()
          if w != ignore_ident && w.length() >= 2 {
            counts.set(w, counts.get(w).unwrap_or(0) + 1)
            total += 1
          }
        } else if ch >= '0' && ch <= '9' {
          let s = sc.pos
          while !sc.is_eof() {
            let c = sc.peek().unwrap()
            if (c >= '0' && c <= '9') || c == '.' {
              sc.advance()
            } else {
              break
            }
          }
          let num = sc.slice_chars(s, sc.pos)
          counts.set(num, counts.get(num).unwrap_or(0) + 1)
          total += 1
        } else if ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '=' {
          let op = ch.to_string()
          counts.set(op, counts.get(op).unwrap_or(0) + 1)
          total += 1
          sc.advance()
        } else {
          sc.advance()
        }
      None => break
    }
  }
  (counts, total)
}

///|
/// Compute integer Dice similarity percentage `[0..100]` between two token multisets.
fn dice_similarity_pct(
  a_map : @hashmap.HashMap[String, Int32],
  a_total : Int32,
  b_map : @hashmap.HashMap[String, Int32],
  b_total : Int32,
) -> Int32 {
  if a_total == 0 && b_total == 0 {
    return 100
  }
  if a_total == 0 || b_total == 0 {
    return 0
  }
  let mut overlap = 0
  a_map.each(fn(tok, a_cnt) {
    let b_cnt = b_map.get(tok).unwrap_or(0)
    overlap += if a_cnt < b_cnt { a_cnt } else { b_cnt }
  })
  200 * overlap / (a_total + b_total)
}

///|
/// Collect top-level and nested declarations keyed by `signature`.
fn collect_named_decls(
  root : @cst.CstNode,
) -> @hashmap.HashMap[String, @cst.CstNode] {
  let map : @hashmap.HashMap[String, @cst.CstNode] = @hashmap.HashMap([])
  fn visit(n : @cst.CstNode) -> Unit {
    match n.signature {
      Some(sig) =>
        if (
            sig.has_prefix("fn:") ||
            sig.has_prefix("def:") ||
            sig.has_prefix("method:") ||
            sig.has_prefix("struct:") ||
            sig.has_prefix("enum:") ||
            sig.has_prefix("class:") ||
            sig.has_prefix("interface:")
          ) &&
          !map.contains(sig) {
          map.set(sig, n)
        }
      None => ()
    }
    for c in n.children {
      visit(c)
    }
  }

  visit(root)
  map
}

///|
/// Detect high-confidence declaration renames (`Dice >= 65%`) between `base_cst` and `side_cst`.
pub fn detect_branch_renames(
  branch_name : String,
  base_cst : @cst.CstNode,
  side_cst : @cst.CstNode,
) -> Array[SymbolRename] {
  let b_decls = collect_named_decls(base_cst)
  let s_decls = collect_named_decls(side_cst)

  let removed : Array[(String, @cst.CstNode)] = []
  b_decls.each(fn(sig, node) {
    if !s_decls.contains(sig) {
      removed.push((sig, node))
    }
  })

  let added : Array[(String, @cst.CstNode)] = []
  s_decls.each(fn(sig, node) {
    if !b_decls.contains(sig) {
      added.push((sig, node))
    }
  })

  removed.sort_by(fn(a, b) { a.0.compare(b.0) })
  added.sort_by(fn(a, b) { a.0.compare(b.0) })

  let used_added = Array::make(added.length(), false)
  let renames : Array[SymbolRename] = []

  for rem in removed {
    let (old_sig, old_node) = rem
    let old_ident = bare_name_of_signature(old_sig)
    let (old_bag, old_tot) = body_token_multiset(old_node, old_ident)
    let mut best_idx = -1
    let mut best_sim = 64 // Require >= 65% Dice similarity

    for j = 0; j < added.length(); j = j + 1 {
      if used_added[j] || added[j].1.kind != old_node.kind {
        continue
      }
      let (new_sig, new_node) = added[j]
      let new_ident = bare_name_of_signature(new_sig)
      let (new_bag, new_tot) = body_token_multiset(new_node, new_ident)
      let sim = dice_similarity_pct(old_bag, old_tot, new_bag, new_tot)
      if sim > best_sim {
        best_sim = sim
        best_idx = j
      }
    }

    if best_idx >= 0 {
      used_added[best_idx] = true
      let new_sig = added[best_idx].0
      let new_ident = bare_name_of_signature(new_sig)
      if old_ident != new_ident &&
        !old_ident.is_empty() &&
        !new_ident.is_empty() {
        renames.push({
          branch: branch_name,
          syntax_kind: old_node.kind.label(),
          old_signature: old_sig,
          new_signature: new_sig,
          old_identifier: old_ident,
          new_identifier: new_ident,
          similarity_pct: best_sim,
        })
      }
    }
  }
  renames
}

///|
/// Count standalone identifier occurrences of `ident` inside `source` (ignoring comments & strings).
pub fn count_identifier_occurrences(source : String, ident : String) -> Int32 {
  if ident.is_empty() {
    return 0
  }
  let sc = @lang.Scanner::new(source)
  let mut count = 0
  while !sc.is_eof() {
    let _ = sc.collect_c_like_trivia(allow_hash_comment=true)
    if sc.is_eof() {
      break
    }
    match sc.peek() {
      Some('"') | Some('\'') => {
        let _ = sc.scan_quoted_string(allow_multiline=true)
      }
      Some(ch) =>
        if @lang.is_ident_start(ch) {
          let w = sc.scan_ident()
          if w == ident {
            count += 1
          }
        } else {
          sc.advance()
        }
      None => break
    }
  }
  count
}

///|
/// Rewrite standalone lexical occurrences of `old_ident` -> `new_ident` outside comments & string literals!
pub fn rewrite_identifier_lossless(
  source : String,
  old_ident : String,
  new_ident : String,
) -> (String, Int32) {
  if old_ident.is_empty() || old_ident == new_ident {
    return (source, 0)
  }
  let sc = @lang.Scanner::new(source)
  let out = StringBuilder()
  let mut replaced = 0

  while !sc.is_eof() {
    let triv_start = sc.pos
    let _ = sc.collect_c_like_trivia(allow_hash_comment=true)
    if sc.pos > triv_start {
      out.write_string(sc.slice_chars(triv_start, sc.pos))
    }
    if sc.is_eof() {
      break
    }
    match sc.peek() {
      Some('"') | Some('\'') => {
        let (raw_lit, _, _) = sc.scan_quoted_string(allow_multiline=true)
        out.write_string(raw_lit)
      }
      Some(ch) =>
        if @lang.is_ident_start(ch) {
          let w = sc.scan_ident()
          if w == old_ident {
            out.write_string(new_ident)
            replaced += 1
          } else {
            out.write_string(w)
          }
        } else {
          out.write_char(ch)
          sc.advance()
        }
      None => break
    }
  }
  (out.to_string(), replaced)
}

///|
/// Analyze 3-way revisions `(base, left, right)` for cross-branch declaration renames
/// and stale call-site semantic hazards!
pub fn analyze_cross_branch_renames(
  base_src : String,
  left_src : String,
  right_src : String,
  lang : @cst.Language,
) -> RefactorAnalysis {
  let base_cst = @lang.parse_cst(base_src, lang)
  let left_cst = @lang.parse_cst(left_src, lang)
  let right_cst = @lang.parse_cst(right_src, lang)

  let l_renames = detect_branch_renames("left", base_cst, left_cst)
  let r_renames = detect_branch_renames("right", base_cst, right_cst)
  let all_renames : Array[SymbolRename] = []
  let hazards : Array[SemanticHazard] = []

  for ren in l_renames {
    all_renames.push(ren)
    let base_cnt = count_identifier_occurrences(base_src, ren.old_identifier)
    let right_cnt = count_identifier_occurrences(right_src, ren.old_identifier)
    if right_cnt > base_cnt {
      let added_refs = right_cnt - base_cnt
      hazards.push({
        rename: ren,
        referencing_branch: "right",
        stale_identifier: ren.old_identifier,
        occurrence_count: added_refs,
        suggestion: "Branch `left` renamed `" +
        ren.old_identifier +
        "` -> `" +
        ren.new_identifier +
        "`, while `right` added " +
        added_refs.to_string() +
        " new reference(s) to `" +
        ren.old_identifier +
        "`",
      })
    }
  }

  for ren in r_renames {
    all_renames.push(ren)
    let base_cnt = count_identifier_occurrences(base_src, ren.old_identifier)
    let left_cnt = count_identifier_occurrences(left_src, ren.old_identifier)
    if left_cnt > base_cnt {
      let added_refs = left_cnt - base_cnt
      hazards.push({
        rename: ren,
        referencing_branch: "left",
        stale_identifier: ren.old_identifier,
        occurrence_count: added_refs,
        suggestion: "Branch `right` renamed `" +
        ren.old_identifier +
        "` -> `" +
        ren.new_identifier +
        "`, while `left` added " +
        added_refs.to_string() +
        " new reference(s) to `" +
        ren.old_identifier +
        "`",
      })
    }
  }

  { renames: all_renames, hazards, }
}
