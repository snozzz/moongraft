///|
/// Detect source `Language` from file path/extension and optional content heuristics.
pub fn detect_language(
  path : StringView,
  content~ : String = "",
) -> @cst.Language {
  let p = path.to_owned()
  let lower = p.to_lower()
  // Extract basename
  let mut base = lower
  for seg in lower.split("/") {
    base = seg.to_owned()
  }
  if base == "moon.pkg" ||
    base == "moon.mod" ||
    base == "moon.pkg.json" ||
    base == "moon.mod.json" {
    return @cst.MoonManifest
  }
  if lower.has_suffix(".mbt") || lower.has_suffix(".mbti") {
    return @cst.MoonBit
  }
  if lower.has_suffix(".json") || lower.has_suffix(".jsonc") {
    return @cst.Json
  }
  if lower.has_suffix(".toml") {
    return @cst.Toml
  }
  if lower.has_suffix(".yaml") || lower.has_suffix(".yml") {
    return @cst.Yaml
  }
  if lower.has_suffix(".ts") ||
    lower.has_suffix(".tsx") ||
    lower.has_suffix(".js") ||
    lower.has_suffix(".jsx") ||
    lower.has_suffix(".mjs") {
    return @cst.TypeScript
  }
  if lower.has_suffix(".py") {
    return @cst.Python
  }
  if lower.has_suffix(".rs") {
    return @cst.Rust
  }
  if lower.has_suffix(".go") {
    return @cst.Go
  }
  if lower.has_suffix(".c") ||
    lower.has_suffix(".h") ||
    lower.has_suffix(".cpp") ||
    lower.has_suffix(".cc") ||
    lower.has_suffix(".cxx") ||
    lower.has_suffix(".hpp") ||
    lower.has_suffix(".hh") {
    return @cst.Cpp
  }

  // Content heuristics when merging temporary `%O %A %B` Git paths without extension
  let trimmed = content.trim()
  if trimmed.has_prefix("{") || trimmed.has_prefix("[") {
    if trimmed.contains("\":") {
      return @cst.Json
    }
    if trimmed.has_prefix("[") &&
      trimmed.contains("]\n") &&
      trimmed.contains("=") {
      return @cst.Toml
    }
  }
  if content.contains("///|") || content.contains("pub fn ") {
    return @cst.MoonBit
  }
  if trimmed.has_prefix("import {") && content.contains("\"moonbitlang/") {
    return @cst.MoonManifest
  }
  if trimmed.has_prefix("package ") && content.contains("\nfunc ") {
    return @cst.Go
  }
  if content.contains("#include <") || content.contains("#include \"") {
    return @cst.Cpp
  }
  if content.contains("def ") && content.contains(":\n") {
    return @cst.Python
  }
  @cst.PlainText
}

///|
/// Parse source text into a lossless `CstNode` according to `lang`.
/// Guarantees `parse_cst(source, lang).unparse() == source` across all languages.
pub fn parse_cst(source : String, lang : @cst.Language) -> @cst.CstNode {
  let tree = match lang {
    @cst.MoonBit => parse_moonbit_cst(source)
    @cst.MoonManifest => parse_moon_manifest_cst(source)
    @cst.Json => parse_json_cst(source)
    @cst.Toml => parse_toml_cst(source)
    @cst.Yaml => parse_yaml_cst(source)
    @cst.TypeScript | @cst.Rust | @cst.Go | @cst.Cpp =>
      parse_c_family_code_cst(source, lang)
    @cst.Python => parse_python_cst(source)
    @cst.PlainText => parse_plaintext_cst(source)
  }
  tree
}

///|
fn parse_plaintext_cst(source : String) -> @cst.CstNode {
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let lines : Array[@cst.CstNode] = []
  while !sc.is_eof() {
    let line = sc.consume_to_eol(include_newline=true)
    lines.push(@cst.CstNode::leaf(id=ids.alloc(), @cst.RawLine, line))
  }
  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    lines,
    ordering=@cst.Sequential,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
/// Structural & lexical soundness check used by the post-merge safety gate.
/// Checks:
/// 1. `tree.has_error == false` (no unclosed strings, malformed JSON/TOML entries, etc.)
/// 2. Globally balanced braces/brackets/parens outside string literals & comments
/// 3. Zero duplicate keys/signatures in `CommutativeByKey` / `CommutativeBlocks` containers.
pub fn verify_well_formed(
  source : String,
  lang : @cst.Language,
) -> (Bool, Array[String]) {
  let issues : Array[String] = []
  let tree = parse_cst(source, lang)
  if tree.has_error {
    issues.push("CST parser reported syntax error fragment")
  }
  if !check_global_delimiters_balanced(source, lang) {
    issues.push("Unbalanced delimiters or unclosed string literal")
  }
  let dups = @cst.find_duplicate_signatures(tree)
  for d in dups {
    issues.push("Duplicate semantic key/declaration: " + d)
  }
  (issues.is_empty(), issues)
}

///|
fn check_global_delimiters_balanced(
  source : String,
  lang : @cst.Language,
) -> Bool {
  let sc = Scanner::new(source)
  let allow_hash = lang == @cst.Toml || lang == @cst.Yaml || lang == @cst.Python
  let stack : Array[Char] = []
  while !sc.is_eof() {
    let ch = sc.peek().unwrap()
    if ch == '"' || (ch == '\'' && lang != @cst.Rust && lang != @cst.MoonBit) {
      if sc.starts_with("\"\"\"") || sc.starts_with("'''") {
        let delim = sc.slice_chars(sc.pos, sc.pos + 3)
        sc.advance(count=3)
        let mut closed = false
        while !sc.is_eof() {
          if sc.starts_with(delim) {
            sc.advance(count=3)
            closed = true
            break
          }
          if sc.peek() == Some('\\') {
            sc.advance(count=2)
          } else {
            sc.advance()
          }
        }
        if !closed {
          return false
        }
      } else {
        let (_, _, ok) = sc.scan_quoted_string(
          allow_multiline=lang != @cst.Json,
        )
        if !ok {
          return false
        }
      }
    } else if ch == '\'' && (lang == @cst.MoonBit || lang == @cst.Rust) {
      // In MoonBit/Rust, `'a'` is char literal while `'lifetime` (Rust) has no closing quote!
      if lang == @cst.MoonBit {
        let (_, _, ok) = sc.scan_quoted_string()
        if !ok {
          return false
        }
      } else {
        sc.advance()
      }
    } else if ch == '`' && (lang == @cst.Go || lang == @cst.TypeScript) {
      sc.advance()
      let mut closed = false
      while !sc.is_eof() {
        if sc.peek() == Some('`') {
          sc.advance()
          closed = true
          break
        }
        if lang == @cst.TypeScript && sc.peek() == Some('\\') {
          sc.advance(count=2)
        } else {
          sc.advance()
        }
      }
      if !closed {
        return false
      }
    } else if sc.starts_with("#|") {
      let _ = sc.consume_to_eol(include_newline=true)
    } else if !allow_hash && sc.starts_with("//") {
      let _ = sc.consume_to_eol(include_newline=true)
    } else if allow_hash && ch == '#' {
      let _ = sc.consume_to_eol(include_newline=true)
    } else if !allow_hash && sc.starts_with("/*") {
      sc.advance(count=2)
      let mut closed = false
      while !sc.is_eof() {
        if sc.starts_with("*/") {
          sc.advance(count=2)
          closed = true
          break
        }
        sc.advance()
      }
      if !closed {
        return false
      }
    } else if ch == '{' {
      stack.push('}')
      sc.advance()
    } else if ch == '(' {
      stack.push(')')
      sc.advance()
    } else if ch == '[' {
      stack.push(']')
      sc.advance()
    } else if ch == '}' || ch == ')' || ch == ']' {
      if stack.is_empty() || stack[stack.length() - 1] != ch {
        return false
      }
      let _ = stack.pop()
      sc.advance()
    } else {
      sc.advance()
    }
  }
  stack.is_empty()
}
