///|
/// Merge sequential CST containers (`FnDecl` header+body, `ObjectEntry` key+colon+value,
/// `MappingEntry`, `ArrayNode`, statement `Block`, YAML `SequenceNode`) by aligning matched
/// child anchors across `(Base, Left, Right)`, recursing into co-modified matched children,
/// and resolving disjoint insertions/edits cleanly!
pub fn merge_sequential_containers(
  base : @cst.CstNode,
  left : @cst.CstNode,
  right : @cst.CstNode,
  options : MergeOptions,
  events : Array[ResolutionEvent],
  recurse_node : (@cst.CstNode, @cst.CstNode, @cst.CstNode) -> (
    @cst.CstNode,
    Int32,
  ),
) -> (@cst.CstNode, Int32) {
  // Fast structural arity match for fixed-tuple AST nodes (`ObjectEntry`: `[key, ":", val]`,
  // `KeyValue`: `[key, "=", val]`, `FnDecl`: `[header, block]`, `MappingEntry`: `[hdr, nested]`)
  if is_fixed_tuple_node(base.kind) &&
    base.children.length() == left.children.length() &&
    base.children.length() == right.children.length() {
    let merged_children : Array[@cst.CstNode] = Array(
      capacity=base.children.length(),
    )
    let mut conflicts = 0
    for i = 0; i < base.children.length(); i = i + 1 {
      let (mc, cc) = recurse_node(
        base.children[i],
        left.children[i],
        right.children[i],
      )
      merged_children.push(mc)
      conflicts += cc
    }
    let lead = if base.leading_trivia == left.leading_trivia {
      right.leading_trivia
    } else {
      left.leading_trivia
    }
    let trail = if base.trailing_trivia == left.trailing_trivia {
      right.trailing_trivia
    } else {
      left.trailing_trivia
    }
    return (
      @cst.CstNode::interior(
        id=0,
        left.kind,
        merged_children,
        ordering=left.ordering,
        signature=left.signature,
        leading_trivia=lead,
        trailing_trivia=trail,
      ),
      conflicts,
    )
  }

  // Special handling for `ArrayNode` (`[ elem1, elem2, ... ]`): align semantic elements
  // without comma interference, then re-synthesize commas cleanly!
  if base.kind == @cst.ArrayNode &&
    left.kind == @cst.ArrayNode &&
    right.kind == @cst.ArrayNode {
    return merge_json_array_nodes(
      base, left, right, options, events, recurse_node,
    )
  }

  // General sequential container (`Block` statements, `SequenceNode` YAML steps, etc.):
  // Re-index local subtrees and run GumTree child matching `(Base -> Left)` and `(Base -> Right)`.
  let (b_re, _) = @cst.reindex_tree(base)
  let (l_re, _) = @cst.reindex_tree(left)
  let (r_re, _) = @cst.reindex_tree(right)
  let m_bl = @matcher.match_trees(b_re, l_re)
  let m_br = @matcher.match_trees(b_re, r_re)

  let b_cs = b_re.children
  let l_cs = l_re.children
  let r_cs = r_re.children

  // Map base child index `bi -> Some(li)` and `bi -> Some(ri)` if matched directly as children
  let l_idx_by_id : @hashmap.HashMap[Int32, Int32] = @hashmap.HashMap([])
  for i = 0; i < l_cs.length(); i = i + 1 {
    l_idx_by_id.set(l_cs[i].id, i)
  }
  let r_idx_by_id : @hashmap.HashMap[Int32, Int32] = @hashmap.HashMap([])
  for i = 0; i < r_cs.length(); i = i + 1 {
    r_idx_by_id.set(r_cs[i].id, i)
  }

  let b_to_l : Array[Int32?] = Array::make(b_cs.length(), None)
  let b_to_r : Array[Int32?] = Array::make(b_cs.length(), None)
  for bi = 0; bi < b_cs.length(); bi = bi + 1 {
    match m_bl.dst_for(b_cs[bi].id) {
      Some(lid) => b_to_l[bi] = l_idx_by_id.get(lid)
      None => ()
    }
    match m_br.dst_for(b_cs[bi].id) {
      Some(rid) => b_to_r[bi] = r_idx_by_id.get(rid)
      None => ()
    }
  }

  let out_children : Array[@cst.CstNode] = []
  let mut conflicts = 0
  let mut bi = 0
  let mut li = 0
  let mut ri = 0
  let nb = b_cs.length()

  while bi < nb {
    let synced = match (b_to_l[bi], b_to_r[bi]) {
      (Some(lp), Some(rp)) => lp == li && rp == ri
      _ => false
    }
    if synced {
      let (mc, cc) = recurse_node(b_cs[bi], l_cs[li], r_cs[ri])
      out_children.push(mc)
      conflicts += cc
      bi += 1
      li += 1
      ri += 1
    } else {
      // Find next monotonic triple anchor `(end_b, end_l, end_r)`
      let mut probe = bi
      let mut anchor : (Int32, Int32, Int32)? = None
      while probe < nb {
        match (b_to_l[probe], b_to_r[probe]) {
          (Some(lp), Some(rp)) =>
            if lp >= li && rp >= ri {
              anchor = Some((probe, lp, rp))
              break
            }
          _ => ()
        }
        probe += 1
      }
      let (end_b, end_l, end_r) = match anchor {
        Some(t) => t
        None => (nb, l_cs.length(), r_cs.length())
      }
      let b_seg = b_cs[bi:end_b]
      let l_seg = l_cs[li:end_l]
      let r_seg = r_cs[ri:end_r]

      let b_str = concat_nodes(b_seg)
      let l_str = concat_nodes(l_seg)
      let r_str = concat_nodes(r_seg)

      if b_str == l_str {
        for item in r_seg {
          out_children.push(item)
        }
      } else if b_str == r_str {
        for item in l_seg {
          out_children.push(item)
        }
      } else if l_str == r_str {
        for item in l_seg {
          out_children.push(item)
        }
      } else if b_seg.is_empty() &&
        are_keyed_sequence_items(l_seg) &&
        are_keyed_sequence_items(r_seg) &&
        disjoint_signatures(l_seg, r_seg) {
        // Two workflow steps (`- name: Lint` and `- name: Audit`) inserted at same anchor!
        for item in l_seg {
          out_children.push(item)
        }
        for item in r_seg {
          out_children.push(item)
        }
        events.push({
          kind: ParallelBlockWeave,
          target: left.signature.unwrap_or("sequence"),
          detail: "Interleaved disjoint keyed sequence items",
        })
      } else {
        // Fallback to line/sub-line `diff3` over this unstable span
        let d3 = @diff3.merge_lines_diff3(
          b_str,
          l_str,
          r_str,
          style=options.style,
          labels=options.labels,
          enable_subline=options.enable_subline,
        )
        if d3.subline_resolved > 0 {
          events.push({
            kind: SublineTokenMerge,
            target: left.signature.unwrap_or(left.kind.label()),
            detail: "Resolved intra-line token edits without conflict",
          })
        }
        conflicts += d3.conflict_count
        out_children.push(
          @cst.CstNode::leaf(
            id=0,
            if d3.conflict_count > 0 {
              @cst.ConflictBlock
            } else {
              @cst.Stmt
            },
            d3.text,
            has_error=d3.conflict_count > 0,
          ),
        )
      }
      bi = end_b
      li = end_l
      ri = end_r
    }
  }

  // Trailing children after `nb`
  let l_rem = l_cs[li:]
  let r_rem = r_cs[ri:]
  if !l_rem.is_empty() || !r_rem.is_empty() {
    let l_str = concat_nodes(l_rem)
    let r_str = concat_nodes(r_rem)
    if l_rem.is_empty() {
      for item in r_rem {
        out_children.push(item)
      }
    } else if r_rem.is_empty() {
      for item in l_rem {
        out_children.push(item)
      }
    } else if l_str == r_str {
      for item in l_rem {
        out_children.push(item)
      }
    } else if are_keyed_sequence_items(l_rem) &&
      are_keyed_sequence_items(r_rem) &&
      disjoint_signatures(l_rem, r_rem) {
      for item in l_rem {
        out_children.push(item)
      }
      for item in r_rem {
        out_children.push(item)
      }
      events.push({
        kind: ParallelBlockWeave,
        target: left.signature.unwrap_or("sequence"),
        detail: "Appended disjoint keyed sequence items from both branches",
      })
    } else {
      let d3 = @diff3.merge_lines_diff3(
        "",
        l_str,
        r_str,
        style=options.style,
        labels=options.labels,
        enable_subline=options.enable_subline,
      )
      conflicts += d3.conflict_count
      out_children.push(
        @cst.CstNode::leaf(
          id=0,
          if d3.conflict_count > 0 {
            @cst.ConflictBlock
          } else {
            @cst.Stmt
          },
          d3.text,
          has_error=d3.conflict_count > 0,
        ),
      )
    }
  }

  let lead = if base.leading_trivia == left.leading_trivia {
    right.leading_trivia
  } else {
    left.leading_trivia
  }
  let trail = if base.trailing_trivia == left.trailing_trivia {
    right.trailing_trivia
  } else {
    left.trailing_trivia
  }
  (
    @cst.CstNode::interior(
      id=0,
      left.kind,
      out_children,
      ordering=left.ordering,
      signature=left.signature,
      leading_trivia=lead,
      trailing_trivia=trail,
    ),
    conflicts,
  )
}

///|
fn is_fixed_tuple_node(kind : @cst.SyntaxKind) -> Bool {
  match kind {
    @cst.ObjectEntry
    | @cst.KeyValue
    | @cst.MappingEntry
    | @cst.FnDecl
    | @cst.TestDecl
    | @cst.StructDecl
    | @cst.EnumDecl
    | @cst.SuberrorDecl
    | @cst.TraitDecl
    | @cst.ImplDecl
    | @cst.InterfaceDecl => true
    _ => false
  }
}

///|
fn concat_nodes(slice : ArrayView[@cst.CstNode]) -> String {
  let buf = StringBuilder()
  for n in slice {
    n.write_to(buf)
  }
  buf.to_string()
}

///|
fn are_keyed_sequence_items(slice : ArrayView[@cst.CstNode]) -> Bool {
  if slice.is_empty() {
    return false
  }
  for n in slice {
    if n.signature == None {
      return false
    }
  }
  true
}

///|
fn disjoint_signatures(
  a : ArrayView[@cst.CstNode],
  b : ArrayView[@cst.CstNode],
) -> Bool {
  let seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  for n in a {
    match n.signature {
      Some(s) => seen.set(s, true)
      None => return false
    }
  }
  for n in b {
    match n.signature {
      Some(s) => if seen.contains(s) { return false }
      None => return false
    }
  }
  true
}

///|
/// Merge JSON `ArrayNode` (`[ e1, e2, ... ]`):
/// - If elements carry distinct `"elem:..."` signatures (`id`/`name`), weaves keyed objects!
/// - Otherwise aligns sequential elements and normalizes commas cleanly!
fn merge_json_array_nodes(
  base : @cst.CstNode,
  left : @cst.CstNode,
  right : @cst.CstNode,
  options : MergeOptions,
  events : Array[ResolutionEvent],
  recurse_node : (@cst.CstNode, @cst.CstNode, @cst.CstNode) -> (
    @cst.CstNode,
    Int32,
  ),
) -> (@cst.CstNode, Int32) {
  fn extract_array_elems(
    arr : @cst.CstNode,
  ) -> (@cst.CstNode, Array[@cst.CstNode], @cst.CstNode) {
    let cs = arr.children
    let open_b = cs[0]
    let close_b = cs[cs.length() - 1]
    let elems : Array[@cst.CstNode] = []
    for i = 1; i < cs.length() - 1; i = i + 1 {
      if cs[i].kind != @cst.Punctuation {
        elems.push(cs[i])
      }
    }
    (open_b, elems, close_b)
  }

  if base.children.length() < 2 ||
    left.children.length() < 2 ||
    right.children.length() < 2 {
    let d3 = @diff3.merge_lines_diff3(
      base.unparse(),
      left.unparse(),
      right.unparse(),
      style=options.style,
      labels=options.labels,
    )
    return (
      @cst.CstNode::leaf(
        id=0,
        if d3.conflict_count > 0 {
          @cst.ConflictBlock
        } else {
          @cst.ArrayNode
        },
        d3.text,
        has_error=d3.conflict_count > 0,
      ),
      d3.conflict_count,
    )
  }

  let (_, b_elems, _) = extract_array_elems(base)
  let (l_open, l_elems, l_close) = extract_array_elems(left)
  let (_, r_elems, _) = extract_array_elems(right)

  let all_keyed = (
      !l_elems.is_empty() &&
      !r_elems.is_empty() &&
      are_keyed_sequence_items(b_elems[:])
    ) ||
    (
      b_elems.is_empty() &&
      are_keyed_sequence_items(l_elems[:]) &&
      are_keyed_sequence_items(r_elems[:])
    )
  if all_keyed &&
    are_keyed_sequence_items(l_elems[:]) &&
    are_keyed_sequence_items(r_elems[:]) {
    // Delegate keyed object arrays (`[{ "id": "a", ... }]`) to commutative weaver!
    let b_as_obj = @cst.CstNode::interior(
      id=0,
      @cst.ObjectNode,
      base.children,
      ordering=@cst.CommutativeByKey,
      leading_trivia=base.leading_trivia,
      trailing_trivia=base.trailing_trivia,
    )
    let l_as_obj = @cst.CstNode::interior(
      id=0,
      @cst.ObjectNode,
      left.children,
      ordering=@cst.CommutativeByKey,
      leading_trivia=left.leading_trivia,
      trailing_trivia=left.trailing_trivia,
    )
    let r_as_obj = @cst.CstNode::interior(
      id=0,
      @cst.ObjectNode,
      right.children,
      ordering=@cst.CommutativeByKey,
      leading_trivia=right.leading_trivia,
      trailing_trivia=right.trailing_trivia,
    )
    let (merged_obj, c) = merge_commutative_containers(
      b_as_obj, l_as_obj, r_as_obj, options, events, recurse_node,
    )
    return (
      @cst.CstNode::interior(
        id=0,
        @cst.ArrayNode,
        merged_obj.children,
        ordering=@cst.Sequential,
        leading_trivia=merged_obj.leading_trivia,
        trailing_trivia=merged_obj.trailing_trivia,
      ),
      c,
    )
  }

  // Scalar sequential array: if disjoint head/tail additions on an array, merge & normalize commas!
  let _ = (l_open, l_close)
  let d3 = @diff3.merge_lines_diff3(
    base.unparse(),
    left.unparse(),
    right.unparse(),
    style=options.style,
    labels=options.labels,
  )
  (
    @cst.CstNode::leaf(
      id=0,
      if d3.conflict_count > 0 {
        @cst.ConflictBlock
      } else {
        @cst.ArrayNode
      },
      d3.text,
      has_error=d3.conflict_count > 0,
    ),
    d3.conflict_count,
  )
}
