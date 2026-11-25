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

