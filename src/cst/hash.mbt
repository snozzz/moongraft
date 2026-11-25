///|
/// FNV-1a 64-bit offset basis and prime for fast deterministic Merkle hashing.
const FNV_OFFSET_BASIS : UInt64 = 0xcbf29ce484222325UL

///|
const FNV_PRIME : UInt64 = 0x100000001b3UL

///|
/// Mix a 64-bit value using SplitMix64 avalanche finalizer to eliminate clustering.
pub fn avalanche64(x : UInt64) -> UInt64 {
  let mut z = x
  z = (z ^ (z >> 30)) * 0xbf58476d1ce4e5b9UL
  z = (z ^ (z >> 27)) * 0x94d049bb133111ebUL
  z ^ (z >> 31)
}

///|
/// Feed a 64-bit integer word into a running FNV-1a hash state.
pub fn hash_u64(state : UInt64, word : UInt64) -> UInt64 {
  let mixed = (state ^ word) * FNV_PRIME
  avalanche64(mixed)
}

///|
/// Feed every Unicode scalar of `s` into a running 64-bit hash state.
pub fn hash_str(state : UInt64, s : StringView) -> UInt64 {
  let mut h = state
  h = (h ^ s.length().reinterpret_as_uint().to_uint64()) * FNV_PRIME
  for ch in s {
    let code = ch.to_int().reinterpret_as_uint().to_uint64()
    h = (h ^ code) * FNV_PRIME
  }
  h
}

///|
/// Hash a string ignoring pure whitespace differences while keeping string literals
/// and non-space characters intact.
pub fn hash_normalized_code_str(state : UInt64, s : StringView) -> UInt64 {
  let trimmed = s.trim()
  let mut h = state
  let mut in_string : Char? = None
  let mut escaped = false
  let mut prev_space = false
  for ch in trimmed {
    let code = ch.to_int().reinterpret_as_uint().to_uint64()
    match in_string {
      Some(quote) => {
        h = (h ^ code) * FNV_PRIME
        if escaped {
          escaped = false
        } else if ch == '\\' {
          escaped = true
        } else if ch == quote {
          in_string = None
        }
      }
      None =>
        if ch == '"' || ch == '\'' {
          in_string = Some(ch)
          prev_space = false
          h = (h ^ code) * FNV_PRIME
        } else if ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n' {
          if !prev_space {
            prev_space = true
            h = (h ^ 32UL) * FNV_PRIME
          }
        } else {
          prev_space = false
          h = (h ^ code) * FNV_PRIME
        }
    }
  }
  avalanche64(h)
}

///|
/// Compute initial hash seed for a syntax kind.
pub fn seed_for_kind(kind : SyntaxKind, ordering : ChildOrdering) -> UInt64 {
  let ord_tag : UInt64 = match ordering {
    Sequential => 11UL
    CommutativeByKey => 23UL
    CommutativeBlocks => 37UL
  }
  hash_u64(hash_u64(FNV_OFFSET_BASIS, kind.tag()), ord_tag)
}
