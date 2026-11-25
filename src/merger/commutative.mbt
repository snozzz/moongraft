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

