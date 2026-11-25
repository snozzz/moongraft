///|
/// Execute Two-Phase GumTree + Semantic-Signature CST Matching between `src_root` and `dst_root`:
/// 1. **Phase 1 (Top-Down Isomorphic Merkle Matching)**: Matches maximal structurally identical
///    subtrees from highest height down, naturally discovering cross-file code moves.
/// 2. **Phase 2 (Signature-Guided & Bottom-Up Dice Recovery)**: Pairs modified declarations by
///    semantic signature (`fn:name`, `key:prop`, `table:section`, `import:pkg`) even across moves,
///    recovers unnamed containers via Dice descendant similarity, and aligns sequential children
///    via Patience LCS.
pub fn match_trees(
  src_root : @cst.CstNode,
  dst_root : @cst.CstNode,
) -> TreeMapping {
  let mapping = TreeMapping::new(src_root, dst_root)
  if src_root.structural_hash == dst_root.structural_hash &&
    src_root.kind == dst_root.kind {
    bind_isomorphic_subtree(mapping, src_root, dst_root)
    return mapping
  }

  // Always anchor root SourceFile <-> SourceFile
  if src_root.kind == @cst.SourceFile && dst_root.kind == @cst.SourceFile {
    let _ = mapping.link(src_root.id, dst_root.id, DiceContainer)
  }

  // Phase 1: Top-down height-indexed isomorphic subtree matching
  let max_h = if src_root.height > dst_root.height {
    src_root.height
  } else {
    dst_root.height
  }
  let src_by_h : Array[Array[@cst.CstNode]] = Array(capacity=max_h + 1)
  let dst_by_h : Array[Array[@cst.CstNode]] = Array(capacity=max_h + 1)
  for _i = 0; _i <= max_h; _i = _i + 1 {
    src_by_h.push([])
    dst_by_h.push([])
  }
  for n in mapping.src_nodes {
    if n.id != src_root.id && n.kind != @cst.Punctuation {
      src_by_h[n.height].push(n)
    }
  }
  for n in mapping.dst_nodes {
    if n.id != dst_root.id && n.kind != @cst.Punctuation {
      dst_by_h[n.height].push(n)
    }
  }

  for h = max_h; h >= 1; h = h - 1 {
    let s_list = src_by_h[h]
    let d_list = dst_by_h[h]
    if s_list.is_empty() || d_list.is_empty() {
      continue
    }
    // Group unmatched destination nodes at height `h` by `(kind.tag(), structural_hash)`
    let buckets : @hashmap.HashMap[(UInt64, UInt64), Array[@cst.CstNode]] = @hashmap.HashMap([],
    )
    for dn in d_list {
      if !mapping.is_dst_matched(dn.id) &&
        (h >= 2 || dn.signature != None || dn.text.length() >= 8) {
        let key = (dn.kind.tag(), dn.structural_hash)
        match buckets.get(key) {
          Some(arr) => arr.push(dn)
          None => buckets.set(key, [dn])
        }
      }
    }

    for sn in s_list {
      if mapping.is_src_matched(sn.id) {
        continue
      }
      if h == 1 && sn.signature == None && sn.text.length() < 8 {
        continue
      }
      let key = (sn.kind.tag(), sn.structural_hash)
      match buckets.get(key) {
        Some(cands) => {
          let avail : Array[@cst.CstNode] = []
          for c in cands {
            if !mapping.is_dst_matched(c.id) {
              avail.push(c)
            }
          }
          if avail.length() == 1 {
            bind_isomorphic_subtree(mapping, sn, avail[0])
          } else if avail.length() > 1 {
            let best = choose_best_ambiguous_partner(mapping, sn, avail)
            bind_isomorphic_subtree(mapping, sn, best)
          }
        }
        None => ()
      }
    }
  }

  // Phase 2A: Signature-guided container/declaration matching (handles Move + Edit!)
  match_by_semantic_signatures(mapping)

  // Phase 2B: Bottom-up Dice similarity container recovery
  recover_containers_bottom_up(mapping, src_root)

  // Phase 2C: Align unmatched sequential leaf/child sequences inside matched containers
  align_children_of_matched_containers(mapping)

  mapping
}

///|
fn choose_best_ambiguous_partner(
  mapping : TreeMapping,
  sn : @cst.CstNode,
  avail : Array[@cst.CstNode],
) -> @cst.CstNode {
  let s_parent = mapping.src_parents[sn.id]
  let mapped_s_parent = if s_parent >= 0 {
    mapping.src_to_dst[s_parent]
  } else {
    -1
  }
  let mut best = avail[0]
  let mut best_score = -1000000
  for cand in avail {
    let mut score = 0
    if sn.signature != None && sn.signature == cand.signature {
      score += 10000
    }
    let d_parent = mapping.dst_parents[cand.id]
    if mapped_s_parent >= 0 && d_parent == mapped_s_parent {
      score += 5000
    } else if s_parent >= 0 && d_parent >= 0 {
      let sp_sig = mapping.src_nodes[s_parent].signature
      let dp_sig = mapping.dst_nodes[d_parent].signature
      if sp_sig != None && sp_sig == dp_sig {
        score += 2000
      }
    }
    let dist = if sn.id >= cand.id { sn.id - cand.id } else { cand.id - sn.id }
    score -= dist
    if score > best_score {
      best_score = score
      best = cand
    }
  }
  best
}

///|
/// Recursively bind two structurally equal subtrees, respecting commutative child ordering
/// when children were reordered!
fn bind_isomorphic_subtree(
  mapping : TreeMapping,
  sn : @cst.CstNode,
  dn : @cst.CstNode,
) -> Unit {
  let _ = mapping.link(sn.id, dn.id, IsomorphicSubtree)
  if sn.children.is_empty() || dn.children.is_empty() {
    return
  }
  match sn.ordering {
    @cst.Sequential =>
      if sn.children.length() == dn.children.length() {
        for i = 0; i < sn.children.length(); i = i + 1 {
          bind_isomorphic_subtree(mapping, sn.children[i], dn.children[i])
        }
      }
    @cst.CommutativeByKey | @cst.CommutativeBlocks => {
      // Match children by `(signature, structural_hash)` first so reordered blocks map accurately!
      let d_used = Array::make(dn.children.length(), false)
      for sc in sn.children {
        if sc.kind == @cst.Punctuation {
          continue
        }
        let mut matched_idx = -1
        for j = 0; j < dn.children.length(); j = j + 1 {
          if !d_used[j] &&
            dn.children[j].kind == sc.kind &&
            dn.children[j].structural_hash == sc.structural_hash &&
            (sc.signature == None || dn.children[j].signature == sc.signature) {
            matched_idx = j
            break
          }
        }
        if matched_idx >= 0 {
          d_used[matched_idx] = true
          bind_isomorphic_subtree(mapping, sc, dn.children[matched_idx])
        }
      }
    }
  }
}

///|
/// Match modified declarations/entries sharing `(SyntaxKind, signature)`, preferring
/// partners under an already-matched parent, then falling back to file-global signature
/// matching for moved + modified top-level declarations!
fn match_by_semantic_signatures(mapping : TreeMapping) -> Unit {
  let dst_by_sig : @hashmap.HashMap[(UInt64, String), Array[@cst.CstNode]] = @hashmap.HashMap([],
  )
  for dn in mapping.dst_nodes {
    if !mapping.is_dst_matched(dn.id) {
      match dn.signature {
        Some(sig) =>
          if !sig.has_prefix("anon:") {
            let k = (dn.kind.tag(), sig)
            match dst_by_sig.get(k) {
              Some(arr) => arr.push(dn)
              None => dst_by_sig.set(k, [dn])
            }
          }
        None => ()
      }
    }
  }

  // Preorder pass so outer containers (`TableSection`, `ClassDecl`, `ObjectEntry`) link BEFORE
  // their nested entries (`KeyValue`, `FnDecl`), giving inner entries matched parent context!
  for sn in mapping.src_nodes {
    if mapping.is_src_matched(sn.id) {
      continue
    }
    match sn.signature {
      Some(sig) =>
        if !sig.has_prefix("anon:") {
          let k = (sn.kind.tag(), sig)
          match dst_by_sig.get(k) {
            Some(cands) => {
              let avail : Array[@cst.CstNode] = []
              for c in cands {
                if !mapping.is_dst_matched(c.id) {
                  avail.push(c)
                }
              }
              if !avail.is_empty() {
                // For local property keys (`key:port`), require either same matched parent OR
                // unique global signature if top-level declaration (`fn:...`, `struct:...`, `table:...`)
                let s_parent = mapping.src_parents[sn.id]
                let mapped_sp = if s_parent >= 0 {
                  mapping.src_to_dst[s_parent]
                } else {
                  -1
                }
                let mut same_parent_cand : @cst.CstNode? = None
                for c in avail {
                  if mapped_sp >= 0 && mapping.dst_parents[c.id] == mapped_sp {
                    same_parent_cand = Some(c)
                    break
                  }
                }
                let chosen : @cst.CstNode? = match same_parent_cand {
                  Some(c) => Some(c)
                  None =>
                    if is_movable_declaration_sig(sig) && avail.length() == 1 {
                      Some(avail[0])
                    } else {
                      None
                    }
                }
                match chosen {
                  Some(partner) => {
                    let _ = mapping.link(sn.id, partner.id, SignatureMatched)
                  }
                  None => ()
                }
              }
            }
            None => ()
          }
        }
      None => ()
    }
  }
}

///|
fn is_movable_declaration_sig(sig : String) -> Bool {
  sig.has_prefix("fn:") ||
  sig.has_prefix("def:") ||
  sig.has_prefix("method:") ||
  sig.has_prefix("test:") ||
  sig.has_prefix("struct:") ||
  sig.has_prefix("enum:") ||
  sig.has_prefix("suberror:") ||
  sig.has_prefix("trait:") ||
  sig.has_prefix("impl:") ||
  sig.has_prefix("class:") ||
  sig.has_prefix("interface:") ||
  sig.has_prefix("table:") ||
  sig.has_prefix("imports:") ||
  sig.has_prefix("item:") ||
  sig.has_prefix("elem:")
}

///|
/// Bottom-up post-order recovery of unnamed containers (`Block`, `ObjectNode`, `ArrayNode`,
/// `MappingNode`, `SequenceNode`) via matched-parent structural correspondence or Dice similarity.
fn recover_containers_bottom_up(
  mapping : TreeMapping,
  node : @cst.CstNode,
) -> Unit {
  for child in node.children {
    recover_containers_bottom_up(mapping, child)
  }
  if node.is_leaf() || mapping.is_src_matched(node.id) {
    return
  }

  // Fast path: if `node`'s parent is already matched to `dp`, and `dp` has a single unmatched
  // child of the exact same `SyntaxKind` (e.g., the body `Block` of a matched `FnDecl` or
  // the value `ObjectNode` of a matched `ObjectEntry`), link them directly!
  let sp = mapping.src_parents[node.id]
  if sp >= 0 && mapping.is_src_matched(sp) {
    let dp_id = mapping.src_to_dst[sp]
    let dp = mapping.dst_nodes[dp_id]
    let same_kind_unmatched : Array[@cst.CstNode] = []
    for dc in dp.children {
      if !dc.is_leaf() && dc.kind == node.kind && !mapping.is_dst_matched(dc.id) {
        same_kind_unmatched.push(dc)
      }
    }
    if same_kind_unmatched.length() == 1 {
      let _ = mapping.link(node.id, same_kind_unmatched[0].id, DiceContainer)
      return
    }
  }

  // General GumTree Dice similarity over matched descendants
  let src_desc = collect_subtree_ids(node)
  let candidate_ids : @hashmap.HashMap[Int32, Bool] = @hashmap.HashMap([])
  for sid in src_desc {
    if mapping.is_src_matched(sid) {
      let mut cur = mapping.dst_parents[mapping.src_to_dst[sid]]
      while cur >= 0 {
        if !mapping.is_dst_matched(cur) &&
          mapping.dst_nodes[cur].kind == node.kind {
          candidate_ids.set(cur, true)
        }
        cur = mapping.dst_parents[cur]
      }
    }
  }

  let mut best_dst = -1
  let mut best_num = 0
  let mut best_den = 1
  candidate_ids.each(fn(cand_id, _) {
    let cand = mapping.dst_nodes[cand_id]
    let cand_desc = collect_subtree_ids(cand)
    let cand_set : @hashmap.HashMap[Int32, Bool] = @hashmap.HashMap([])
    for did in cand_desc {
      cand_set.set(did, true)
    }
    let mut common = 0
    for sid in src_desc {
      if mapping.is_src_matched(sid) &&
        cand_set.get(mapping.src_to_dst[sid]).unwrap_or(false) {
        common += 1
      }
    }
    let num = 2 * common
    let den = src_desc.length() + cand_desc.length()
    // Require Dice >= 0.45 (`20 * common >= 9 * den` avoids float rounding!)
    if 20 * common >= 9 * den && num * best_den > best_num * den {
      best_dst = cand_id
      best_num = num
      best_den = den
    }
  })

  if best_dst >= 0 {
    let _ = mapping.link(node.id, best_dst, DiceContainer)
  }
}

///|
fn collect_subtree_ids(root : @cst.CstNode) -> Array[Int32] {
  let ids : Array[Int32] = []
  fn walk(n : @cst.CstNode) -> Unit {
    for c in n.children {
      ids.push(c.id)
      walk(c)
    }
  }

  walk(root)
  ids
}

///|
/// Align remaining unmatched leaf/statement children inside matched containers using Patience diff
/// over `(kind.tag(), structural_hash)` and declaration headers (`Keyword` at child slot 0).
fn align_children_of_matched_containers(mapping : TreeMapping) -> Unit {
  for sn in mapping.src_nodes {
    if sn.is_leaf() || !mapping.is_src_matched(sn.id) {
      continue
    }
    let dn = mapping.dst_nodes[mapping.src_to_dst[sn.id]]
    // If slot 0 is a declaration header `Keyword` on both (`fn foo(...)` -> `fn foo(x : Int)`), match it!
    if !sn.children.is_empty() &&
      !dn.children.is_empty() &&
      sn.children[0].kind == @cst.Keyword &&
      dn.children[0].kind == @cst.Keyword &&
      !mapping.is_src_matched(sn.children[0].id) &&
      !mapping.is_dst_matched(dn.children[0].id) {
      let _ = mapping.link(
        sn.children[0].id,
        dn.children[0].id,
        SequenceAligned,
      )
    }

    // Align unmatched non-punctuation children by structural hash via Patience diff
    let s_unmatched : Array[@cst.CstNode] = []
    let s_keys : Array[(UInt64, UInt64)] = []
    for sc in sn.children {
      if !mapping.is_src_matched(sc.id) && sc.kind != @cst.Punctuation {
        s_unmatched.push(sc)
        s_keys.push((sc.kind.tag(), sc.structural_hash))
      }
    }
    let d_unmatched : Array[@cst.CstNode] = []
    let d_keys : Array[(UInt64, UInt64)] = []
    for dc in dn.children {
      if !mapping.is_dst_matched(dc.id) && dc.kind != @cst.Punctuation {
        d_unmatched.push(dc)
        d_keys.push((dc.kind.tag(), dc.structural_hash))
      }
    }
    if !s_unmatched.is_empty() && !d_unmatched.is_empty() {
      let diff = @diff.Diff(
        old=s_keys[:],
        new=d_keys[:],
        algorithm=@diff.Patience,
      )
      for edit in diff.edits() {
        match edit {
          @diff.Equal(old_index~, new_index~, len~) =>
            for k = 0; k < len; k = k + 1 {
              let _ = mapping.link(
                s_unmatched[old_index + k].id,
                d_unmatched[new_index + k].id,
                SequenceAligned,
              )
            }
          _ => ()
        }
      }
    }
  }
}

///|
/// Produce a human- and machine-readable structural AST edit summary between two versions
/// (powering `moongraft diff <old> <new>`!).
pub fn summarize_structural_diff(
  old_source : String,
  old_root : @cst.CstNode,
  new_source : String,
  new_root : @cst.CstNode,
) -> Array[StructuralEdit] {
  let mapping = match_trees(old_root, new_root)
  let old_sm = @cst.SourceMap::from_source(old_source)
  let new_sm = @cst.SourceMap::from_source(new_source)
  let edits : Array[StructuralEdit] = []

  // Detect moved sibling order among matched declarations inside each container
  let moved_src_ids : @hashmap.HashMap[Int32, Bool] = @hashmap.HashMap([])
  for sn in mapping.src_nodes {
    if !sn.is_leaf() && mapping.is_src_matched(sn.id) {
      let dn = mapping.dst_nodes[mapping.src_to_dst[sn.id]]
      let d_pos_of : @hashmap.HashMap[Int32, Int32] = @hashmap.HashMap([])
      for idx = 0; idx < dn.children.length(); idx = idx + 1 {
        d_pos_of.set(dn.children[idx].id, idx)
      }
      // Find Longest Increasing Subsequence (LIS) of destination indices among matched declarations;
      // items outside the LIS were structurally moved/reordered!
      let matched_pairs : Array[(Int32, Int32)] = []
      for sc in sn.children {
        if sc.kind.is_declaration_or_entry() && mapping.is_src_matched(sc.id) {
          let did = mapping.src_to_dst[sc.id]
          match d_pos_of.get(did) {
            Some(d_idx) => matched_pairs.push((sc.id, d_idx))
            None => moved_src_ids.set(sc.id, true)
          }
        }
      }
      let in_lis = compute_lis_membership(matched_pairs)
      for p in matched_pairs {
        if !in_lis.get(p.0).unwrap_or(false) {
          moved_src_ids.set(p.0, true)
        }
      }
    }
  }

  for sn in mapping.src_nodes {
    if !sn.kind.is_declaration_or_entry() {
      continue
    }
    let old_ln = Some(old_sm.lookup(sn.span.start).line)
    match mapping.dst_for(sn.id) {
      None =>
        edits.push({
          kind: Deleted,
          syntax_kind: sn.kind.label(),
          signature: sn.signature,
          old_line: old_ln,
          new_line: None,
          summary: "Deleted " + describe_node(sn),
        })
      Some(did) => {
        let dn = mapping.dst_nodes[did]
        let new_ln = Some(new_sm.lookup(dn.span.start).line)
        let was_moved = moved_src_ids.get(sn.id).unwrap_or(false)
        let sem_changed = sn.structural_hash != dn.structural_hash
        let exact_changed = sn.exact_hash != dn.exact_hash
        if was_moved && sem_changed {
          edits.push({
            kind: MovedAndModified,
            syntax_kind: sn.kind.label(),
            signature: sn.signature,
            old_line: old_ln,
            new_line: new_ln,
            summary: "Moved and modified " + describe_node(sn),
          })
        } else if was_moved {
          edits.push({
            kind: Moved,
            syntax_kind: sn.kind.label(),
            signature: sn.signature,
            old_line: old_ln,
            new_line: new_ln,
            summary: "Moved " + describe_node(sn),
          })
        } else if sem_changed {
          // Only report leaf-most declaration change so we don't double-report outer + inner if desired;
          // reporting top-level declaration gives crisp overview!
          edits.push({
            kind: Modified,
            syntax_kind: sn.kind.label(),
            signature: sn.signature,
            old_line: old_ln,
            new_line: new_ln,
            summary: "Modified " + describe_node(sn),
          })
        } else if exact_changed {
          edits.push({
            kind: FormattingChanged,
            syntax_kind: sn.kind.label(),
            signature: sn.signature,
            old_line: old_ln,
            new_line: new_ln,
            summary: "Reformatted " + describe_node(sn),
          })
        }
      }
    }
  }

  for dn in mapping.dst_nodes {
    if dn.kind.is_declaration_or_entry() && !mapping.is_dst_matched(dn.id) {
      let new_ln = Some(new_sm.lookup(dn.span.start).line)
      edits.push({
        kind: Inserted,
        syntax_kind: dn.kind.label(),
        signature: dn.signature,
        old_line: None,
        new_line: new_ln,
        summary: "Inserted " + describe_node(dn),
      })
    }
  }

  edits
}

///|
fn describe_node(n : @cst.CstNode) -> String {
  match n.signature {
    Some(sig) => n.kind.label() + " `" + sig + "`"
    None => n.kind.label()
  }
}

///|
/// Compute membership map of `src_id`s belonging to the Longest Increasing Subsequence
/// of destination positions `pairs = [(src_id, dst_idx)]`.
fn compute_lis_membership(
  pairs : Array[(Int32, Int32)],
) -> @hashmap.HashMap[Int32, Bool] {
  let out : @hashmap.HashMap[Int32, Bool] = @hashmap.HashMap([])
  let n = pairs.length()
  if n == 0 {
    return out
  }
  let dp = Array::make(n, 1)
  let prev = Array::make(n, -1)
  let mut best_len = 1
  let mut best_end = 0
  for i = 0; i < n; i = i + 1 {
    for j = 0; j < i; j = j + 1 {
      if pairs[j].1 < pairs[i].1 && dp[j] + 1 > dp[i] {
        dp[i] = dp[j] + 1
        prev[i] = j
      }
    }
    if dp[i] > best_len {
      best_len = dp[i]
      best_end = i
    }
  }
  let mut cur = best_end
  while cur >= 0 {
    out.set(pairs[cur].0, true)
    cur = prev[cur]
  }
  out
}
