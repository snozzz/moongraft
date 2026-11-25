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

