///|
/// Supported source languages for syntax-aware CST parsing and 3-way merging.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum Language {
  MoonBit
  MoonManifest
  Json
  Toml
  Yaml
  TypeScript
  Python
  Rust
  PlainText
}

///|
/// Canonical short identifier for CLI flags and JSON diagnostics.
pub fn Language::slug(self : Language) -> String {
  match self {
    MoonBit => "moonbit"
    MoonManifest => "moon-manifest"
    Json => "json"
    Toml => "toml"
    Yaml => "yaml"
    TypeScript => "typescript"
    Python => "python"
    Rust => "rust"
    PlainText => "plaintext"
  }
}

///|
/// Parse a language identifier from user CLI option or language tag.
pub fn Language::from_slug(name : StringView) -> Language? {
  let normalized = name.to_owned().to_lower()
  match normalized {
    "moonbit" | "mbt" | "mbti" => Some(MoonBit)
    "moon-manifest" | "moon.pkg" | "moon.mod" | "manifest" => Some(MoonManifest)
    "json" | "jsonc" => Some(Json)
    "toml" => Some(Toml)
    "yaml" | "yml" => Some(Yaml)
    "typescript" | "ts" | "tsx" | "javascript" | "js" | "jsx" =>
      Some(TypeScript)
    "python" | "py" => Some(Python)
    "rust" | "rs" => Some(Rust)
    "text" | "txt" | "plaintext" => Some(PlainText)
    _ => None
  }
}

///|
/// Ordering semantics of child nodes inside a container CST node.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum ChildOrdering {
  Sequential
  CommutativeByKey
  CommutativeBlocks
}

