///|
/// Decompose a container's children into `(optional_open_punct,optional_header, semantic_items, optional_close_punct, had_trailing_comma)`.
priv struct ContainerParts {
  open_punct : @cst.CstNode?
  header_node : @cst.CstNode?
  items : Array[@cst.CstNode]
  close_punct : @cst.CstNode?
  had_trailing_comma : Bool
}

///|
fn split_container_parts(node : @cst.CstNode) -> ContainerParts {
  let cs = node.children
  let n = cs.length()
  if n == 0 {
    return {
      open_punct: None,
      header_node: None,
      items: [],
      close_punct: None,
      had_trailing_comma: false,
    }
  }

  let mut start = 0
  let mut end = n
  let mut open_punct : @cst.CstNode? = None
  let mut header_node : @cst.CstNode? = None
  let mut close_punct : @cst.CstNode? = None

  // Check `{` / `[` or `import {` (`Keyword` on `ImportGroup`!)
  if (
      node.kind == @cst.ObjectNode ||
      node.kind == @cst.ArrayNode ||
      node.kind == @cst.Block
    ) &&
    cs[0].kind == @cst.Punctuation &&
    (cs[0].text == "{" || cs[0].text == "[") {
    open_punct = Some(cs[0])
    start = 1
  } else if node.kind == @cst.ImportGroup && cs[0].kind == @cst.Keyword {
    open_punct = Some(cs[0])
    start = 1
  } else if (
      node.kind == @cst.TableSection ||
      node.kind == @cst.ArrayOfTablesSection ||
      node.kind == @cst.ClassDecl
    ) &&
    cs[0].kind == @cst.Keyword {
    header_node = Some(cs[0])
    start = 1
  }

  if end > start &&
    cs[end - 1].kind == @cst.Punctuation &&
    (
      cs[end - 1].text == "}" ||
      cs[end - 1].text == "]" ||
      cs[end - 1].text.has_prefix("}")
    ) {
    close_punct = Some(cs[end - 1])
    end -= 1
  }

  let items : Array[@cst.CstNode] = []
  let mut last_non_close_was_comma = false
  for i = start; i < end; i = i + 1 {
    if cs[i].kind == @cst.Punctuation && cs[i].text == "," {
      // Preserve any inline comment on `,` by attaching it to the preceding item's trailing trivia!
      if !items.is_empty() && !cs[i].trailing_trivia.is_empty() {
        let prev = items.pop().unwrap()
        let merged_trail = prev.trailing_trivia.copy()
        for t in cs[i].trailing_trivia {
          merged_trail.push(t)
        }
        items.push(prev.with_trivia(trailing_trivia=merged_trail))
      }
      last_non_close_was_comma = true
    } else {
      items.push(cs[i])
      last_non_close_was_comma = false
    }
  }

  {
    open_punct,
    header_node,
    items,
    close_punct,
    had_trailing_comma: last_non_close_was_comma,
  }
}

///|
/// Canonical lookup key for an item inside a `CommutativeByKey` or `CommutativeBlocks` container.
fn item_merge_key(item : @cst.CstNode, fallback_idx : Int32) -> String {
  match item.signature {
    Some(sig) =>
      if !sig.has_prefix("anon:") {
        sig
      } else {
        "hash:" +
        item.structural_hash.to_string() +
        "#" +
        fallback_idx.to_string()
      }
    None => "raw:" + item.kind.label() + ":" + item.structural_hash.to_string()
  }
}

///|
/// Compute a deterministic merged key ordering from `b_keys`, `l_keys`, and `r_keys`:
/// - Respects reordering on `Left` if `Right` kept `Base`'s relative order, and vice versa!
/// - Inserts newly added keys from `Left` and `Right` right after their anchor predecessor
///   in `Left`/`Right`, breaking ties deterministically by lexicographical key (`k1 < k2`)
///   so `merge(O, A, B)` and `merge(O, B, A)` are 100% commutative on parallel additions!
fn weave_commutative_key_order(
  b_keys : Array[String],
  l_keys : Array[String],
  r_keys : Array[String],
) -> (Array[String], Bool) {
  let b_pos : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
  for i = 0; i < b_keys.length(); i = i + 1 {
    b_pos.set(b_keys[i], i)
  }

  fn relative_base_order_changed(
    side_keys : Array[String],
    base_pos : @hashmap.HashMap[String, Int32],
  ) -> Bool {
    let mut prev = -1
    for k in side_keys {
      match base_pos.get(k) {
        Some(p) => {
          if p < prev {
            return true
          }
          prev = p
        }
        None => ()
      }
    }
    false
  }

  let l_reordered = relative_base_order_changed(l_keys, b_pos)
  let r_reordered = relative_base_order_changed(r_keys, b_pos)

  // Choose spine order for existing keys
  let spine : Array[String] = []
  let in_spine : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])
  let primary_existing = if l_reordered && !r_reordered {
    l_keys
  } else if r_reordered && !l_reordered {
    r_keys
  } else {
    b_keys
  }
  for k in primary_existing {
    if b_pos.contains(k) && !in_spine.contains(k) {
      spine.push(k)
      in_spine.set(k, true)
    }
  }
  for k in b_keys {
    if !in_spine.contains(k) {
      spine.push(k)
      in_spine.set(k, true)
    }
  }

  // Bucket new keys (`!b_pos.contains(k)`) by the nearest preceding spine key (`"__HEAD__"` if before all spine keys)
  let buckets : @hashmap.HashMap[String, Array[String]] = @hashmap.HashMap([])
  let added_seen : @hashmap.HashMap[String, Bool] = @hashmap.HashMap([])

  fn collect_new_from_side(side : Array[String]) -> Unit {
    let mut anchor = "__HEAD__"
    for k in side {
      if b_pos.contains(k) {
        anchor = k
      } else if !added_seen.contains(k) {
        added_seen.set(k, true)
        match buckets.get(anchor) {
          Some(arr) => arr.push(k)
          None => buckets.set(anchor, [k])
        }
      }
    }
  }

  collect_new_from_side(l_keys)
  collect_new_from_side(r_keys)

  fn emit_bucket(anchor : String, out : Array[String]) -> Unit {
    match buckets.get(anchor) {
      Some(arr) => {
        let sorted = arr.copy()
        sorted.sort()
        for k in sorted {
          out.push(k)
        }
      }
      None => ()
    }
  }

  let result : Array[String] = []
  emit_bucket("__HEAD__", result)
  for sk in spine {
    result.push(sk)
    emit_bucket(sk, result)
  }
  (result, l_reordered || r_reordered)
}

///|
/// Detect indentation prefix used by existing entries in a container.
fn infer_entry_indent(
  b_items : Array[@cst.CstNode],
  l_items : Array[@cst.CstNode],
  r_items : Array[@cst.CstNode],
) -> String {
  for list in [l_items, r_items, b_items] {
    for item in list {
      for t in item.leading_trivia {
        if t.kind == @cst.Whitespace && !t.text.is_empty() {
          return t.text
        }
      }
    }
  }
  "  "
}

///|
/// Merge three `CommutativeByKey` or `CommutativeBlocks` CST containers (`base`, `left`, `right`),
/// calling `recurse_node` for nested modified containers!
pub fn merge_commutative_containers(
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
  let b_parts = split_container_parts(base)
  let l_parts = split_container_parts(left)
  let r_parts = split_container_parts(right)

  let b_map : @hashmap.HashMap[String, @cst.CstNode] = @hashmap.HashMap([])
  let l_map : @hashmap.HashMap[String, @cst.CstNode] = @hashmap.HashMap([])
  let r_map : @hashmap.HashMap[String, @cst.CstNode] = @hashmap.HashMap([])
  let b_keys : Array[String] = []
  let l_keys : Array[String] = []
  let r_keys : Array[String] = []

  for i = 0; i < b_parts.items.length(); i = i + 1 {
    let it = b_parts.items[i]
    let k = item_merge_key(it, i)
    if !b_map.contains(k) {
      b_map.set(k, it)
      b_keys.push(k)
    }
  }
  for i = 0; i < l_parts.items.length(); i = i + 1 {
    let it = l_parts.items[i]
    let k = item_merge_key(it, i)
    if !l_map.contains(k) {
      l_map.set(k, it)
      l_keys.push(k)
    }
  }
  for i = 0; i < r_parts.items.length(); i = i + 1 {
    let it = r_parts.items[i]
    let k = item_merge_key(it, i)
    if !r_map.contains(k) {
      r_map.set(k, it)
      r_keys.push(k)
    }
  }

  let (merged_order, any_reordered) = weave_commutative_key_order(
    b_keys, l_keys, r_keys,
  )

  let merged_items : Array[@cst.CstNode] = []
  let mut total_conflicts = 0
  let mut added_from_left = 0
  let mut added_from_right = 0

  for key in merged_order {
    let b_opt = b_map.get(key)
    let l_opt = l_map.get(key)
    let r_opt = r_map.get(key)

    match (b_opt, l_opt, r_opt) {
      (Some(bn), Some(ln), Some(rn)) =>
        if ln.exact_hash == rn.exact_hash {
          merged_items.push(ln)
        } else if bn.exact_hash == ln.exact_hash {
          if any_reordered {
            events.push({
              kind: MoveAndEditComposed,
              target: key,
              detail: "Composed branch reordering with semantic edit on `" +
              key +
              "`",
            })
          }
          merged_items.push(rn)
        } else if bn.exact_hash == rn.exact_hash {
          if any_reordered {
            events.push({
              kind: MoveAndEditComposed,
              target: key,
              detail: "Composed branch reordering with semantic edit on `" +
              key +
              "`",
            })
          }
          merged_items.push(ln)
        } else if bn.structural_hash == ln.structural_hash &&
          bn.structural_hash != rn.structural_hash {
          events.push({
            kind: FormattingReconciled,
            target: key,
            detail: "Preserved Right semantic change over Left formatting-only change",
          })
          merged_items.push(rn)
        } else if bn.structural_hash == rn.structural_hash &&
          bn.structural_hash != ln.structural_hash {
          events.push({
            kind: FormattingReconciled,
            target: key,
            detail: "Preserved Left semantic change over Right formatting-only change",
          })
          merged_items.push(ln)
        } else if ln.structural_hash == rn.structural_hash {
          events.push({
            kind: FormattingReconciled,
            target: key,
            detail: "Collapsed structurally equivalent edits on `" + key + "`",
          })
          merged_items.push(ln)
        } else {
          // Both branches modified semantics of `key` -> recurse into `key`'s CST!
          let (sub_merged, sub_conflicts) = recurse_node(bn, ln, rn)
          if sub_conflicts == 0 {
            events.push({
              kind: RecursiveContainerMerge,
              target: key,
              detail: "Merged concurrent inner edits inside `" + key + "`",
            })
          }
          total_conflicts += sub_conflicts
          merged_items.push(sub_merged)
        }
      (Some(bn), None, Some(rn)) =>
        if bn.structural_hash == rn.structural_hash {
          // Clean deletion by Left
          ()
        } else {
          events.push({
            kind: DeleteModifyConflict,
            target: key,
            detail: "Left deleted `" + key + "` while Right modified it",
          })
          let (cnode, cc) = make_conflict_node(
            bn.unparse(),
            "",
            rn.unparse(),
            options,
          )
          total_conflicts += cc
          merged_items.push(cnode)
        }
      (Some(bn), Some(ln), None) =>
        if bn.structural_hash == ln.structural_hash {
          // Clean deletion by Right
          ()
        } else {
          events.push({
            kind: DeleteModifyConflict,
            target: key,
            detail: "Right deleted `" + key + "` while Left modified it",
          })
          let (cnode, cc) = make_conflict_node(
            bn.unparse(),
            ln.unparse(),
            "",
            options,
          )
          total_conflicts += cc
          merged_items.push(cnode)
        }
      (Some(_), None, None) => () // Both deleted `key`
      (None, Some(ln), None) => {
        added_from_left += 1
        merged_items.push(ln)
      }
      (None, None, Some(rn)) => {
        added_from_right += 1
        merged_items.push(rn)
      }
      (None, Some(ln), Some(rn)) =>
        // Both branches independently added `key` (`Add-Add`)!
        if ln.structural_hash == rn.structural_hash {
          events.push({
            kind: DuplicateDeduped,
            target: key,
            detail: "Deduplicated identical concurrent addition of `" +
            key +
            "`",
          })
          merged_items.push(ln)
        } else if !ln.is_leaf() && !rn.is_leaf() && ln.kind == rn.kind {
          // E.g. both branches added `[dev-dependencies]` or `"scripts": { ... }` with disjoint inner keys!
          let empty_base = make_synthetic_empty_partner(ln)
          let (sub_node, sub_c) = recurse_node(empty_base, ln, rn)
          if sub_c == 0 {
            events.push({
              kind: RecursiveContainerMerge,
              target: key,
              detail: "Merged two newly added containers sharing key `" +
              key +
              "`",
            })
          }
          total_conflicts += sub_c
          merged_items.push(sub_node)
        } else {
          events.push({
            kind: ConflictLocalized,
            target: key,
            detail: "Conflicting concurrent additions for `" + key + "`",
          })
          let (cnode, cc) = make_conflict_node(
            "",
            ln.unparse(),
            rn.unparse(),
            options,
          )
          total_conflicts += cc
          merged_items.push(cnode)
        }
      (None, None, None) => ()
    }
  }

  if added_from_left > 0 && added_from_right > 0 && total_conflicts == 0 {
    let ev_kind = if left.ordering == @cst.CommutativeBlocks {
      ParallelBlockWeave
    } else {
      CommutativeKeyWeave
    }
    events.push({
      kind: ev_kind,
      target: left.signature.unwrap_or(left.kind.label()),
      detail: "Wove " +
      added_from_left.to_string() +
      " Left addition(s) and " +
      added_from_right.to_string() +
      " Right addition(s) without conflict",
    })
  }

  // Merge container header if present (`[table]`, `class Foo`)
  let merged_header : @cst.CstNode? = match
    (b_parts.header_node, l_parts.header_node, r_parts.header_node) {
    (Some(bh), Some(lh), Some(rh)) =>
      if lh.exact_hash == rh.exact_hash || bh.exact_hash == rh.exact_hash {
        Some(lh)
      } else if bh.exact_hash == lh.exact_hash {
        Some(rh)
      } else {
        let (hm, hc) = recurse_node(bh, lh, rh)
        total_conflicts += hc
        Some(hm)
      }
    (_, Some(lh), _) => Some(lh)
    (_, _, Some(rh)) => Some(rh)
    _ => None
  }

  let chosen_lead = if base.leading_trivia == left.leading_trivia {
    right.leading_trivia
  } else {
    left.leading_trivia
  }
  let chosen_trail = if base.trailing_trivia == left.trailing_trivia {
    right.trailing_trivia
  } else {
    left.trailing_trivia
  }

  // Reassemble delimited `{ ... }` vs headered vs top-level container
  match (l_parts.open_punct, l_parts.close_punct) {
    (Some(open_p), Some(close_p)) => {
      let raw_preview = left.unparse() + right.unparse()
      let is_multiline = raw_preview.contains("\n")
      let indent = infer_entry_indent(
        b_parts.items,
        l_parts.items,
        r_parts.items,
      )
      let want_trailing_comma = (
          l_parts.had_trailing_comma || r_parts.had_trailing_comma
        ) &&
        options.language != @cst.Json
      let uses_commas = left.kind == @cst.ObjectNode ||
        left.kind == @cst.ImportGroup
      if uses_commas {
        let assembled = reassemble_delimited_entries(
          open_p,
          merged_items,
          close_p,
          left.kind,
          left.ordering,
          left.signature,
          chosen_lead,
          chosen_trail,
          want_trailing_comma,
          indent,
          is_multiline,
          events,
        )
        (assembled, total_conflicts)
      } else {
        // Brace block without commas (`struct` fields, `enum` variants, TS `class` members)
        let out_children : Array[@cst.CstNode] = [open_p]
        for i = 0; i < merged_items.length(); i = i + 1 {
          let mut it = merged_items[i]
          if is_multiline &&
            !@cst.render_trivia(it.leading_trivia).contains("\n") &&
            !@cst.render_trivia(
              out_children[out_children.length() - 1].trailing_trivia,
            ).contains("\n") {
            let nl_lead = [@cst.Trivia::newline(), @cst.Trivia::spaces(indent)]
            it = it.with_trivia(leading_trivia=nl_lead)
          }
          if is_multiline &&
            it.kind != @cst.ConflictBlock &&
            !it.unparse().has_suffix("\n") {
            let tr = it.trailing_trivia.copy()
            tr.push(@cst.Trivia::newline())
            it = it.with_trivia(trailing_trivia=tr)
          }
          out_children.push(it)
        }
        out_children.push(close_p)
        (
          @cst.CstNode::interior(
            id=0,
            left.kind,
            out_children,
            ordering=left.ordering,
            signature=left.signature,
            leading_trivia=chosen_lead,
            trailing_trivia=chosen_trail,
          ),
          total_conflicts,
        )
      }
    }
    _ => {
      let final_children : Array[@cst.CstNode] = []
      match merged_header {
        Some(h) => final_children.push(h)
        None => ()
      }
      let uses_mbt_sep = options.language == @cst.MoonBit &&
        left.kind == @cst.SourceFile &&
        (
          left.unparse().contains("///|") ||
          right.unparse().contains("///|") ||
          base.unparse().contains("///|")
        )
      let normalized_items = normalize_moonbit_block_separators(
        merged_items, uses_mbt_sep,
      )
      for i = 0; i < normalized_items.length(); i = i + 1 {
        let mut it = normalized_items[i]
        // Ensure newline separation between consecutive line-based entries (`ImportItem`, `KeyValue`, `MappingEntry`, `FnDecl`)
        if !final_children.is_empty() {
          let prev_str = final_children[final_children.length() - 1].unparse()
          let cur_lead = @cst.render_trivia(it.leading_trivia)
          if !prev_str.has_suffix("\n") && !cur_lead.has_prefix("\n") {
            let lead_with_nl : Array[@cst.Trivia] = [@cst.Trivia::newline()]
            for t in it.leading_trivia {
              lead_with_nl.push(t)
            }
            it = it.with_trivia(leading_trivia=lead_with_nl)
          }
        }
        final_children.push(it)
      }
      (
        @cst.CstNode::interior(
          id=0,
          left.kind,
          final_children,
          ordering=left.ordering,
          signature=left.signature,
          leading_trivia=chosen_lead,
          trailing_trivia=chosen_trail,
        ),
        total_conflicts,
      )
    }
  }
}

///|
/// Create a minimal empty base node matching `template`'s structure when both branches
/// independently add a container with the same key (`"scripts": { ... }` or `[dev-dependencies]`).
fn make_synthetic_empty_partner(template : @cst.CstNode) -> @cst.CstNode {
  if template.kind == @cst.ObjectEntry && template.children.length() == 3 {
    let val = template.children[2]
    if val.kind == @cst.ObjectNode {
      let empty_obj = @cst.CstNode::interior(
        id=0,
        @cst.ObjectNode,
        [
          @cst.CstNode::leaf(id=1, @cst.Punctuation, "{"),
          @cst.CstNode::leaf(id=2, @cst.Punctuation, "}"),
        ],
        ordering=@cst.CommutativeByKey,
      )
      return @cst.CstNode::interior(
        id=0,
        @cst.ObjectEntry,
        [template.children[0], template.children[1], empty_obj],
        signature=template.signature,
      )
    }
  }
  if template.kind == @cst.MappingEntry && template.children.length() >= 2 {
    let empty_map = @cst.CstNode::interior(
      id=0,
      @cst.MappingNode,
      [],
      ordering=@cst.CommutativeByKey,
    )
    return @cst.CstNode::interior(
      id=0,
      @cst.MappingEntry,
      [template.children[0], empty_map],
      signature=template.signature,
    )
  }
  if template.kind == @cst.TableSection && !template.children.is_empty() {
    return @cst.CstNode::interior(
      id=0,
      @cst.TableSection,
      [template.children[0]],
      ordering=@cst.CommutativeByKey,
      signature=template.signature,
    )
  }
  @cst.CstNode::interior(
    id=0,
    template.kind,
    [],
    ordering=template.ordering,
    signature=template.signature,
  )
}
