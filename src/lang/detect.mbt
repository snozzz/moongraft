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
    @cst.TypeScript | @cst.Rust => parse_c_family_code_cst(source, lang)
    @cst.Python => parse_python_cst(source)
    @cst.PlainText => parse_plaintext_cst(source)
  }
  tree
}

