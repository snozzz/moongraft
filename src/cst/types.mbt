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
  Go
  Cpp
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
    Go => "go"
    Cpp => "cpp"
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
    "go" | "golang" => Some(Go)
    "c" | "cpp" | "cc" | "cxx" | "c++" | "h" | "hpp" | "hh" => Some(Cpp)
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

///|
/// Concrete syntax categories unified across supported languages.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) enum SyntaxKind {
  SourceFile
  ModuleBlock
  ImportGroup
  ImportItem
  FnDecl
  TestDecl
  StructDecl
  EnumDecl
  SuberrorDecl
  TraitDecl
  ImplDecl
  TypeDecl
  ConstDecl
  LetDecl
  ClassDecl
  InterfaceDecl
  FieldDecl
  VariantDecl
  ParamList
  Param
  Block
  Stmt
  Expr
  ObjectNode
  ObjectEntry
  ArrayNode
  ArrayElement
  TableSection
  ArrayOfTablesSection
  KeyValue
  MappingNode
  MappingEntry
  SequenceNode
  SequenceItem
  Attribute
  DelimiterGroup
  Punctuation
  Keyword
  Identifier
  StringLiteral
  NumberLiteral
  BoolLiteral
  NullLiteral
  Operator
  RawLine
  ConflictBlock
  ErrorFragment
}

///|
/// Human-readable label for S-expressions and structural diff reports.
pub fn SyntaxKind::label(self : SyntaxKind) -> String {
  match self {
    SourceFile => "SourceFile"
    ModuleBlock => "ModuleBlock"
    ImportGroup => "ImportGroup"
    ImportItem => "ImportItem"
    FnDecl => "FnDecl"
    TestDecl => "TestDecl"
    StructDecl => "StructDecl"
    EnumDecl => "EnumDecl"
    SuberrorDecl => "SuberrorDecl"
    TraitDecl => "TraitDecl"
    ImplDecl => "ImplDecl"
    TypeDecl => "TypeDecl"
    ConstDecl => "ConstDecl"
    LetDecl => "LetDecl"
    ClassDecl => "ClassDecl"
    InterfaceDecl => "InterfaceDecl"
    FieldDecl => "FieldDecl"
    VariantDecl => "VariantDecl"
    ParamList => "ParamList"
    Param => "Param"
    Block => "Block"
    Stmt => "Stmt"
    Expr => "Expr"
    ObjectNode => "ObjectNode"
    ObjectEntry => "ObjectEntry"
    ArrayNode => "ArrayNode"
    ArrayElement => "ArrayElement"
    TableSection => "TableSection"
    ArrayOfTablesSection => "ArrayOfTablesSection"
    KeyValue => "KeyValue"
    MappingNode => "MappingNode"
    MappingEntry => "MappingEntry"
    SequenceNode => "SequenceNode"
    SequenceItem => "SequenceItem"
    Attribute => "Attribute"
    DelimiterGroup => "DelimiterGroup"
    Punctuation => "Punctuation"
    Keyword => "Keyword"
    Identifier => "Identifier"
    StringLiteral => "StringLiteral"
    NumberLiteral => "NumberLiteral"
    BoolLiteral => "BoolLiteral"
    NullLiteral => "NullLiteral"
    Operator => "Operator"
    RawLine => "RawLine"
    ConflictBlock => "ConflictBlock"
    ErrorFragment => "ErrorFragment"
  }
}

///|
/// Integer tag for deterministic hashing of `SyntaxKind`.
pub fn SyntaxKind::tag(self : SyntaxKind) -> UInt64 {
  match self {
    SourceFile => 1UL
    ModuleBlock => 2UL
    ImportGroup => 3UL
    ImportItem => 4UL
    FnDecl => 5UL
    TestDecl => 6UL
    StructDecl => 7UL
    EnumDecl => 8UL
    SuberrorDecl => 9UL
    TraitDecl => 10UL
    ImplDecl => 11UL
    TypeDecl => 12UL
    ConstDecl => 13UL
    LetDecl => 14UL
    ClassDecl => 15UL
    InterfaceDecl => 16UL
    FieldDecl => 17UL
    VariantDecl => 18UL
    ParamList => 19UL
    Param => 20UL
    Block => 21UL
    Stmt => 22UL
    Expr => 23UL
    ObjectNode => 24UL
    ObjectEntry => 25UL
    ArrayNode => 26UL
    ArrayElement => 27UL
    TableSection => 28UL
    ArrayOfTablesSection => 29UL
    KeyValue => 30UL
    MappingNode => 31UL
    MappingEntry => 32UL
    SequenceNode => 33UL
    SequenceItem => 34UL
    Attribute => 35UL
    DelimiterGroup => 36UL
    Punctuation => 37UL
    Keyword => 38UL
    Identifier => 39UL
    StringLiteral => 40UL
    NumberLiteral => 41UL
    BoolLiteral => 42UL
    NullLiteral => 43UL
    Operator => 44UL
    RawLine => 45UL
    ConflictBlock => 46UL
    ErrorFragment => 47UL
  }
}

///|
/// Whether a syntax kind represents a named/keyed declaration or container
/// suitable for signature-guided matching.
pub fn SyntaxKind::is_declaration_or_entry(self : SyntaxKind) -> Bool {
  match self {
    ImportItem
    | FnDecl
    | TestDecl
    | StructDecl
    | EnumDecl
    | SuberrorDecl
    | TraitDecl
    | ImplDecl
    | TypeDecl
    | ConstDecl
    | LetDecl
    | ClassDecl
    | InterfaceDecl
    | FieldDecl
    | VariantDecl
    | ObjectEntry
    | TableSection
    | ArrayOfTablesSection
    | KeyValue
    | MappingEntry
    | SequenceItem => true
    _ => false
  }
}

///|
/// Byte/UTF-16 span `[start, end)` in the original source string.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) struct ByteSpan {
  start : Int32
  end : Int32
}

///|
/// Create a `ByteSpan`.
pub fn ByteSpan::new(start : Int32, end : Int32) -> ByteSpan {
  { start, end, }
}

///|
/// Length of the span in code units.
pub fn ByteSpan::len(self : ByteSpan) -> Int32 {
  if self.end >= self.start {
    self.end - self.start
  } else {
    0
  }
}

///|
/// 1-based line and column coordinate for human-readable diagnostics.
#derive(Eq, @debug.Debug, Hash, ToJson)
pub(all) struct LineCol {
  line : Int32
  column : Int32
}
