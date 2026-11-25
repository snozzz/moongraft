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

