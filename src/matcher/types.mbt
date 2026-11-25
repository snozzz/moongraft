///|
/// Provenance of how two CST nodes were matched during two-phase GumTree matching.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum MatchReason {
  Unmatched
  IsomorphicSubtree
  SignatureMatched
  DiceContainer
  SequenceAligned
}

///|
/// Bidirectional node-ID mapping between a `src` CST (`0 .. src_size-1`) and
/// a `dst` CST (`0 .. dst_size-1`).
#derive(@debug.Debug)
pub(all) struct TreeMapping {
  src_nodes : Array[@cst.CstNode]
  dst_nodes : Array[@cst.CstNode]
  src_parents : Array[Int32]
  dst_parents : Array[Int32]
  src_to_dst : Array[Int32]
  dst_to_src : Array[Int32]
  reasons : Array[MatchReason]
}

///|
/// Create an empty `TreeMapping` for `src_root` and `dst_root`.
pub fn TreeMapping::new(
  src_root : @cst.CstNode,
  dst_root : @cst.CstNode,
) -> TreeMapping {
  let src_nodes = @cst.collect_preorder(src_root)
  let dst_nodes = @cst.collect_preorder(dst_root)
  let src_parents = build_parent_table(src_root, src_nodes.length())
  let dst_parents = build_parent_table(dst_root, dst_nodes.length())
  let src_to_dst = Array::make(src_nodes.length(), -1)
  let dst_to_src = Array::make(dst_nodes.length(), -1)
  let reasons = Array::make(src_nodes.length(), Unmatched)
  {
    src_nodes,
    dst_nodes,
    src_parents,
    dst_parents,
    src_to_dst,
    dst_to_src,
    reasons,
  }
}

///|
fn build_parent_table(root : @cst.CstNode, count : Int32) -> Array[Int32] {
  let parents = Array::make(count, -1)
  fn walk(node : @cst.CstNode) -> Unit {
    for child in node.children {
      if child.id >= 0 && child.id < count {
        parents[child.id] = node.id
      }
      walk(child)
    }
  }

  walk(root)
  parents
}

///|
/// True if `src_id` is already matched.
pub fn TreeMapping::is_src_matched(self : TreeMapping, src_id : Int32) -> Bool {
  src_id >= 0 &&
  src_id < self.src_to_dst.length() &&
  self.src_to_dst[src_id] >= 0
}

///|
/// True if `dst_id` is already matched.
pub fn TreeMapping::is_dst_matched(self : TreeMapping, dst_id : Int32) -> Bool {
  dst_id >= 0 &&
  dst_id < self.dst_to_src.length() &&
  self.dst_to_src[dst_id] >= 0
}

///|
/// Link `src_id <-> dst_id` if both are currently unmatched.
pub fn TreeMapping::link(
  self : TreeMapping,
  src_id : Int32,
  dst_id : Int32,
  reason : MatchReason,
) -> Bool {
  if self.is_src_matched(src_id) || self.is_dst_matched(dst_id) {
    return false
  }
  self.src_to_dst[src_id] = dst_id
  self.dst_to_src[dst_id] = src_id
  self.reasons[src_id] = reason
  true
}

///|
/// Lookup destination partner ID for `src_id`.
pub fn TreeMapping::dst_for(self : TreeMapping, src_id : Int32) -> Int32? {
  if self.is_src_matched(src_id) {
    Some(self.src_to_dst[src_id])
  } else {
    None
  }
}

///|
/// Lookup source partner ID for `dst_id`.
pub fn TreeMapping::src_for(self : TreeMapping, dst_id : Int32) -> Int32? {
  if self.is_dst_matched(dst_id) {
    Some(self.dst_to_src[dst_id])
  } else {
    None
  }
}

///|
/// High-level structural edit action reported by `moongraft diff`.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum EditKind {
  Inserted
  Deleted
  Modified
  Moved
  MovedAndModified
  FormattingChanged
}

///|
/// Single structural AST change entry between two revisions.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct StructuralEdit {
  kind : EditKind
  syntax_kind : String
  signature : String?
  old_line : Int32?
  new_line : Int32?
  summary : String
}
