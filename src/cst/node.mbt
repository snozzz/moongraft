///|
/// Immutable Concrete Syntax Tree (CST) node preserving 100% of original source bytes
/// (`node.unparse() == original_source`) while carrying precomputed structural and
/// exact 64-bit Merkle hashes, subtree height, and semantic declaration signatures.
#derive(Eq, @debug.Debug)
pub(all) struct CstNode {
  id : Int32
  kind : SyntaxKind
  ordering : ChildOrdering
  signature : String?
  text : String
  children : Array[CstNode]
  leading_trivia : Array[Trivia]
  trailing_trivia : Array[Trivia]
  span : ByteSpan
  structural_hash : UInt64
  exact_hash : UInt64
  height : Int32
  size : Int32
  has_error : Bool
}

///|
/// Construct a leaf CST token node.
pub fn CstNode::leaf(
  id~ : Int32,
  kind : SyntaxKind,
  text : String,
  signature~ : String? = None,
  leading_trivia~ : Array[Trivia] = [],
  trailing_trivia~ : Array[Trivia] = [],
  span~ : ByteSpan = ByteSpan::new(0, 0),
  has_error~ : Bool = false,
) -> CstNode {
  let base_seed = seed_for_kind(kind, Sequential)
  let sig_hash = match signature {
    Some(sig) => hash_str(base_seed, sig)
    None => base_seed
  }
  let structural_hash = hash_normalized_code_str(sig_hash, text)
  let mut exact = hash_str(sig_hash, text)
  for t in leading_trivia {
    exact = hash_str(exact, t.text)
  }
  for t in trailing_trivia {
    exact = hash_str(exact, t.text)
  }
  {
    id,
    kind,
    ordering: Sequential,
    signature,
    text,
    children: [],
    leading_trivia,
    trailing_trivia,
    span,
    structural_hash,
    exact_hash: avalanche64(exact),
    height: 1,
    size: 1,
    has_error: has_error || kind == ErrorFragment,
  }
}

///|
/// Construct an interior CST container node from child nodes.
pub fn CstNode::interior(
  id~ : Int32,
  kind : SyntaxKind,
  children : Array[CstNode],
  ordering~ : ChildOrdering = Sequential,
  signature~ : String? = None,
  leading_trivia~ : Array[Trivia] = [],
  trailing_trivia~ : Array[Trivia] = [],
  span~ : ByteSpan = ByteSpan::new(0, 0),
  has_error~ : Bool = false,
) -> CstNode {
  let base_seed = seed_for_kind(kind, ordering)
  let sig_seed = match signature {
    Some(sig) => hash_str(base_seed, sig)
    None => base_seed
  }
  let mut struct_h = sig_seed
  let mut comm_xor = 0UL
  let mut comm_sum = 0UL
  let mut exact_h = sig_seed
  for t in leading_trivia {
    exact_h = hash_str(exact_h, t.text)
  }
  let mut max_child_height = 0
  let mut total_size = 1
  let mut child_err = has_error || kind == ErrorFragment
  for child in children {
    match ordering {
      Sequential => struct_h = hash_u64(struct_h, child.structural_hash)
      CommutativeByKey | CommutativeBlocks =>
        if child.kind != Punctuation {
          let mixed = avalanche64(child.structural_hash)
          comm_xor = comm_xor ^ mixed
          comm_sum = comm_sum + mixed
        }
    }
    exact_h = hash_u64(exact_h, child.exact_hash)
    if child.height > max_child_height {
      max_child_height = child.height
    }
    total_size += child.size
    if child.has_error {
      child_err = true
    }
  }
  match ordering {
    Sequential => struct_h = avalanche64(struct_h)
    CommutativeByKey | CommutativeBlocks =>
      struct_h = hash_u64(hash_u64(struct_h, comm_xor), comm_sum)
  }
  for t in trailing_trivia {
    exact_h = hash_str(exact_h, t.text)
  }
  {
    id,
    kind,
    ordering,
    signature,
    text: "",
    children,
    leading_trivia,
    trailing_trivia,
    span,
    structural_hash: struct_h,
    exact_hash: avalanche64(exact_h),
    height: max_child_height + 1,
    size: total_size,
    has_error: child_err,
  }
}

///|
/// True if this node has no children (token/raw leaf).
pub fn CstNode::is_leaf(self : CstNode) -> Bool {
  self.children.is_empty()
}

///|
/// Write the complete lossless source representation of `self` to `buf`.
pub fn CstNode::write_to(self : CstNode, buf : StringBuilder) -> Unit {
  write_trivia(buf, self.leading_trivia)
  if self.children.is_empty() {
    buf.write_string(self.text)
  } else {
    for child in self.children {
      child.write_to(buf)
    }
  }
  write_trivia(buf, self.trailing_trivia)
}

///|
/// Reconstruct the exact lossless source text represented by `self`.
pub fn CstNode::unparse(self : CstNode) -> String {
  let buf = StringBuilder()
  self.write_to(buf)
  buf.to_string()
}

///|
/// Return the semantic body text of a node WITHOUT outer leading/trailing trivia.
pub fn CstNode::trimmed_source(self : CstNode) -> String {
  let buf = StringBuilder()
  if self.children.is_empty() {
    buf.write_string(self.text)
  } else {
    for child in self.children {
      child.write_to(buf)
    }
  }
  buf.to_string().trim().to_owned()
}

///|
/// Create a copy of `self` with updated `leading_trivia` and/or `trailing_trivia`,
/// recomputing `exact_hash` while preserving `structural_hash`.
pub fn CstNode::with_trivia(
  self : CstNode,
  leading_trivia~ : Array[Trivia] = self.leading_trivia,
  trailing_trivia~ : Array[Trivia] = self.trailing_trivia,
) -> CstNode {
  if self.children.is_empty() {
    CstNode::leaf(
      id=self.id,
      self.kind,
      self.text,
      signature=self.signature,
      leading_trivia~,
      trailing_trivia~,
      span=self.span,
      has_error=self.has_error,
    )
  } else {
    CstNode::interior(
      id=self.id,
      self.kind,
      self.children,
      ordering=self.ordering,
      signature=self.signature,
      leading_trivia~,
      trailing_trivia~,
      span=self.span,
      has_error=self.has_error,
    )
  }
}

///|
/// Reassign dense preorder node IDs `0 .. N-1` across an entire CST tree.
pub fn reindex_tree(root : CstNode, start_id~ : Int32 = 0) -> (CstNode, Int32) {
  let my_id = start_id
  let mut next_id = start_id + 1
  if root.children.is_empty() {
    let updated = { ..root, id: my_id, }
    (updated, next_id)
  } else {
    let new_children : Array[CstNode] = Array(capacity=root.children.length())
    for child in root.children {
      let (re_child, after_child) = reindex_tree(child, start_id=next_id)
      new_children.push(re_child)
      next_id = after_child
    }
    let updated = CstNode::interior(
      id=my_id,
      root.kind,
      new_children,
      ordering=root.ordering,
      signature=root.signature,
      leading_trivia=root.leading_trivia,
      trailing_trivia=root.trailing_trivia,
      span=root.span,
      has_error=root.has_error,
    )
    (updated, next_id)
  }
}

///|
/// Flatten a CST into a preorder array indexed by dense `node.id`.
pub fn collect_preorder(root : CstNode) -> Array[CstNode] {
  let out : Array[CstNode] = Array(capacity=root.size)
  fn visit(n : CstNode) -> Unit {
    out.push(n)
    for c in n.children {
      visit(c)
    }
  }

  visit(root)
  out
}

///|
/// Detect duplicate semantic signatures inside any `CommutativeByKey` or
/// `CommutativeBlocks` container (used by post-merge soundness verification).
pub fn find_duplicate_signatures(root : CstNode) -> Array[String] {
  let duplicates : Array[String] = []
  fn inspect_node(node : CstNode) -> Unit {
    match node.ordering {
      CommutativeByKey | CommutativeBlocks => {
        let seen : @hashmap.HashMap[String, Int32] = @hashmap.HashMap([])
        for child in node.children {
          match child.signature {
            Some(sig) =>
              if !sig.has_prefix("anon:") {
                let prev = seen.get(sig).unwrap_or(0)
                if prev == 1 {
                  duplicates.push(sig)
                }
                seen.set(sig, prev + 1)
              }
            None => ()
          }
        }
      }
      Sequential => ()
    }
    for child in node.children {
      inspect_node(child)
    }
  }

  inspect_node(root)
  duplicates
}
