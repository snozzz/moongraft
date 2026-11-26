///|
/// Built-in benchmark scenario for reproducible evaluation against line-based `diff3`.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct BenchmarkCase {
  id : String
  title : String
  path : String
  language : @cst.Language
  expect_clean : Bool
  base : String
  left : String
  right : String
  must_contain : Array[String]
}

///|
/// Per-case evaluation outcome comparing `MoonGraft` against standard `diff3`.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct CaseOutcome {
  id : String
  title : String
  language : String
  expect_clean : Bool
  diff3_conflicts : Int32
  moongraft_conflicts : Int32
  syntax_valid : Bool
  passed_expectation : Bool
}

///|
/// Aggregate evaluation summary across all benchmark scenarios.
#derive(Eq, @debug.Debug, ToJson)
pub(all) struct SuiteSummary {
  total_cases : Int32
  expected_clean_cases : Int32
  expected_conflict_cases : Int32
  diff3_clean_on_resolvable : Int32
  moongraft_clean_on_resolvable : Int32
  true_conflicts_preserved : Int32
  all_assertions_passed : Bool
  outcomes : Array[CaseOutcome]
}

///|
/// Curated 16-scenario multi-language benchmark corpus covering parallel AI agent edits,
/// Move+Edit refactorings, trailing-comma traps, nested config merges, and true-conflict safety!
pub fn builtin_benchmark_corpus() -> Array[BenchmarkCase] {
  [
    {
      id: "mbt-parallel-blocks",
      title: "MoonBit parallel ///| top-level functions at EOF",
      path: "src/parser.mbt",
      language: @cst.MoonBit,
      expect_clean: true,
      base: "///|\npub fn parse_int(s : String) -> Int {\n  0\n}\n",
      left: "///|\npub fn parse_int(s : String) -> Int {\n  0\n}\n\n///|\npub fn parse_bool(s : String) -> Bool {\n  s == \"true\"\n}\n",
      right: "///|\npub fn parse_int(s : String) -> Int {\n  0\n}\n\n///|\npub fn parse_ident(s : String) -> String {\n  s\n}\n",
      must_contain: ["pub fn parse_bool", "pub fn parse_ident"],
    },
    {
      id: "mbt-move-and-edit",
      title: "MoonBit Move + Edit composition across ///| blocks",
      path: "src/engine.mbt",
      language: @cst.MoonBit,
      expect_clean: true,
      base: "///|\npub fn helper() -> Int {\n  1\n}\n\n///|\npub fn compute(x : Int) -> Int {\n  let step = x + 1\n  step * 2\n}\n",
      left: "///|\npub fn compute(x : Int) -> Int {\n  let step = x + 1\n  step * 2\n}\n\n///|\npub fn helper() -> Int {\n  1\n}\n",
      right: "///|\npub fn helper() -> Int {\n  1\n}\n\n///|\npub fn compute(x : Int) -> Int {\n  let step = x + 42\n  step * 2\n}\n",
      must_contain: ["let step = x + 42", "pub fn helper()"],
    },
    {
      id: "mbt-struct-fields",
      title: "MoonBit parallel struct field additions",
      path: "src/config.mbt",
      language: @cst.MoonBit,
      expect_clean: true,
      base: "///|\npub struct ServerConfig {\n  host : String\n  port : Int\n}\n",
      left: "///|\npub struct ServerConfig {\n  host : String\n  port : Int\n  tls_enabled : Bool\n}\n",
      right: "///|\npub struct ServerConfig {\n  host : String\n  port : Int\n  max_conns : Int\n}\n",
      must_contain: ["tls_enabled : Bool", "max_conns : Int"],
    },
    {
      id: "mbt-enum-variants",
      title: "MoonBit parallel enum variant additions",
      path: "src/ast.mbt",
      language: @cst.MoonBit,
      expect_clean: true,
      base: "///|\npub(all) enum Expr {\n  Lit(Int)\n  Add(Expr, Expr)\n}\n",
      left: "///|\npub(all) enum Expr {\n  Lit(Int)\n  Add(Expr, Expr)\n  Mul(Expr, Expr)\n}\n",
      right: "///|\npub(all) enum Expr {\n  Lit(Int)\n  Add(Expr, Expr)\n  Neg(Expr)\n}\n",
      must_contain: ["Mul(Expr, Expr)", "Neg(Expr)"],
    },
    {
      id: "mbt-subline-sig",
      title: "MoonBit intra-line disjoint parameter & return type edit",
      path: "src/rpc.mbt",
      language: @cst.MoonBit,
      expect_clean: true,
      base: "///|\npub fn call_rpc(endpoint : String, timeout_ms : Int) -> Bool {\n  true\n}\n",
      left: "///|\npub fn call_rpc(service_url : String, timeout_ms : Int) -> Bool {\n  true\n}\n",
      right: "///|\npub fn call_rpc(endpoint : String, timeout_ms : Int) -> Result[Bool, Error] {\n  Ok(true)\n}\n",
      must_contain: ["service_url : String", "Result[Bool, Error]"],
    },
    {
      id: "moon-pkg-imports",
      title: "moon.pkg DSL parallel package import additions",
      path: "src/merger/moon.pkg",
      language: @cst.MoonManifest,
      expect_clean: true,
      base: "import {\n  \"moonbitlang/core/debug\",\n}\n",
      left: "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/hashmap\",\n}\n",
      right: "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/argparse\",\n}\n",
      must_contain: [
        "\"moonbitlang/core/hashmap\"", "\"moonbitlang/core/argparse\"",
      ],
    },
    {
      id: "json-trailing-comma",
      title: "package.json parallel dependency append (trailing-comma trap)",
      path: "package.json",
      language: @cst.Json,
      expect_clean: true,
      base: "{\n  \"name\": \"web-ui\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\"\n  }\n}\n",
      left: "{\n  \"name\": \"web-ui\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\",\n    \"lucide-react\": \"^0.460.0\"\n  }\n}\n",
      right: "{\n  \"name\": \"web-ui\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\",\n    \"zustand\": \"^5.0.0\"\n  }\n}\n",
      must_contain: ["\"lucide-react\"", "\"zustand\""],
    },
    {
      id: "json-keyed-array",
      title: "JSON array of keyed plugin objects merged by id",
      path: "plugins.json",
      language: @cst.Json,
      expect_clean: true,
      base: "{\n  \"plugins\": [\n    { \"id\": \"core\", \"enabled\": true }\n  ]\n}\n",
      left: "{\n  \"plugins\": [\n    { \"id\": \"core\", \"enabled\": true },\n    { \"id\": \"metrics\", \"enabled\": true }\n  ]\n}\n",
      right: "{\n  \"plugins\": [\n    { \"id\": \"core\", \"enabled\": true },\n    { \"id\": \"tracing\", \"enabled\": false }\n  ]\n}\n",
      must_contain: ["\"metrics\"", "\"tracing\""],
    },
    {
      id: "toml-cargo-deps",
      title: "Cargo.toml inline table + parallel dependency additions",
      path: "Cargo.toml",
      language: @cst.Toml,
      expect_clean: true,
      base: "[package]\nname = \"agent\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = { version = \"1.0\", features = [\"std\"] }\n",
      left: "[package]\nname = \"agent\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = { version = \"1.0\", features = [\"std\"], default-features = false }\nclap = \"4.5\"\n",
      right: "[package]\nname = \"agent\"\nversion = \"0.1.0\"\n\n[dependencies]\nserde = { version = \"1.0\", features = [\"std\"], optional = true }\ntracing = \"0.1\"\n",
      must_contain: [
        "default-features = false", "optional = true", "clap = \"4.5\"", "tracing = \"0.1\"",
      ],
    },
    {
      id: "yaml-gha-steps",
      title: "GitHub Actions ci.yml parallel named workflow steps",
      path: ".github/workflows/ci.yml",
      language: @cst.Yaml,
      expect_clean: true,
      base: "name: CI\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - name: Checkout\n        uses: actions/checkout@v4\n",
      left: "name: CI\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - name: Checkout\n        uses: actions/checkout@v4\n      - name: Run linter\n        run: moon check\n",
      right: "name: CI\njobs:\n  check:\n    runs-on: ubuntu-latest\n    steps:\n      - name: Checkout\n        uses: actions/checkout@v4\n      - name: Run unit tests\n        run: moon test\n",
      must_contain: ["name: Run linter", "name: Run unit tests"],
    },
    {
      id: "ts-imports-and-class",
      title: "TypeScript parallel imports and class fields/methods",
      path: "src/service.ts",
      language: @cst.TypeScript,
      expect_clean: true,
      base: "import { Logger } from \"./logger\";\n\nexport class ApiService {\n  host: string;\n}\n",
      left: "import { Logger } from \"./logger\";\nimport { Cache } from \"./cache\";\n\nexport class ApiService {\n  host: string;\n  cacheSize: number;\n}\n",
      right: "import { Logger } from \"./logger\";\nimport { Metrics } from \"./metrics\";\n\nexport class ApiService {\n  host: string;\n  timeoutMs: number;\n}\n",
      must_contain: [
        "import { Cache }", "import { Metrics }", "cacheSize: number;", "timeoutMs: number;",
      ],
    },
    {
      id: "py-imports-and-methods",
      title: "Python parallel imports and class methods",
      path: "agent/runner.py",
      language: @cst.Python,
      expect_clean: true,
      base: "import os\n\nclass AgentRunner:\n    def ping(self):\n        return True\n",
      left: "import os\nimport json\n\nclass AgentRunner:\n    def ping(self):\n        return True\n\n    def dump_state(self):\n        return json.dumps({})\n",
      right: "import os\nimport time\n\nclass AgentRunner:\n    def ping(self):\n        return True\n\n    def uptime(self):\n        return time.time()\n",
      must_contain: [
        "import json", "import time", "def dump_state", "def uptime",
      ],
    },
    {
      id: "rs-use-and-struct",
      title: "Rust parallel use statements and struct fields",
      path: "src/lib.rs",
      language: @cst.Rust,
      expect_clean: true,
      base: "use std::fmt;\n\npub struct Context {\n    pub id: u64,\n}\n",
      left: "use std::fmt;\nuse std::collections::HashMap;\n\npub struct Context {\n    pub id: u64,\n    pub tags: HashMap<String, String>,\n}\n",
      right: "use std::fmt;\nuse std::sync::Arc;\n\npub struct Context {\n    pub id: u64,\n    pub parent: Option<Arc<Context>>,\n}\n",
      must_contain: [
        "use std::collections::HashMap;", "use std::sync::Arc;", "pub tags:", "pub parent:",
      ],
    },
    {
      id: "go-imports-and-methods",
      title: "Go parallel grouped imports, struct fields, and receiver methods",
      path: "internal/router/server.go",
      language: @cst.Go,
      expect_clean: true,
      base: "package router\n\nimport (\n\t\"context\"\n)\n\ntype Server struct {\n\tAddr string\n}\n\nfunc (s *Server) Start(ctx context.Context) error {\n\treturn nil\n}\n",
      left: "package router\n\nimport (\n\t\"context\"\n\t\"log/slog\"\n)\n\ntype Server struct {\n\tAddr string\n\tLogger *slog.Logger\n}\n\nfunc (s *Server) Start(ctx context.Context) error {\n\treturn nil\n}\n\nfunc (s *Server) Healthz() string {\n\treturn \"ok\"\n}\n",
      right: "package router\n\nimport (\n\t\"context\"\n\t\"time\"\n)\n\ntype Server struct {\n\tAddr string\n\tReadTimeout time.Duration\n}\n\nfunc (s *Server) Start(ctx context.Context) error {\n\treturn nil\n}\n\nfunc (s *Server) Shutdown() error {\n\treturn nil\n}\n",
      must_contain: [
        "\"log/slog\"", "\"time\"", "Logger *slog.Logger", "ReadTimeout time.Duration",
        "func (s *Server) Healthz()", "func (s *Server) Shutdown()",
      ],
    },
    {
      id: "cpp-includes-and-functions",
      title: "C/C++ parallel #include directives and moved+edited free function",
      path: "src/checksum.cpp",
      language: @cst.Cpp,
      expect_clean: true,
      base: "#include <cstdint>\n\nuint32_t step_hash(uint32_t h, uint32_t b) {\n  uint32_t prime = 16777619u;\n  return (h ^ b) * prime;\n}\n\nuint32_t seed_hash() {\n  return 2166136261u;\n}\n",
      left: "#include <cstdint>\n#include <cstddef>\n\nuint32_t seed_hash() {\n  return 2166136261u;\n}\n\nuint32_t step_hash(uint32_t h, uint32_t b) {\n  uint32_t prime = 16777619u;\n  return (h ^ (b & 0xffu)) * prime;\n}\n",
      right: "#include <cstdint>\n#include <array>\n\nuint32_t step_hash(uint32_t h, uint32_t b) {\n  uint32_t prime = 16777619u;\n  return (h ^ b) * prime;\n}\n\nuint32_t seed_hash() {\n  return 2166136261u;\n}\n\nbool is_nonzero_digest(uint32_t h) {\n  return h != 0u;\n}\n",
      must_contain: [
        "#include <cstddef>", "#include <array>", "b & 0xffu", "bool is_nonzero_digest(",
      ],
    },
    {
      id: "conflict-delete-modify",
      title: "True Conflict Safety: JSON Delete vs Modify",
      path: "policy.json",
      language: @cst.Json,
      expect_clean: false,
      base: "{\n  \"allow_admin\": false,\n  \"max_tokens\": 4096\n}\n",
      left: "{\n  \"allow_admin\": false\n}\n",
      right: "{\n  \"allow_admin\": false,\n  \"max_tokens\": 8192\n}\n",
      must_contain: ["<<<<<<<", "8192"],
    },
    {
      id: "conflict-same-key-scalar",
      title: "True Conflict Safety: TOML conflicting version bump",
      path: "Cargo.toml",
      language: @cst.Toml,
      expect_clean: false,
      base: "[package]\nname = \"core\"\nversion = \"1.0.0\"\n",
      left: "[package]\nname = \"core\"\nversion = \"1.1.0\"\n",
      right: "[package]\nname = \"core\"\nversion = \"2.0.0\"\n",
      must_contain: ["<<<<<<<", "1.1.0", "2.0.0"],
    },
    {
      id: "conflict-mbt-body-clash",
      title: "True Conflict Safety: MoonBit conflicting return expression",
      path: "src/limit.mbt",
      language: @cst.MoonBit,
      expect_clean: false,
      base: "///|\npub fn default_port() -> Int {\n  8080\n}\n",
      left: "///|\npub fn default_port() -> Int {\n  8081\n}\n",
      right: "///|\npub fn default_port() -> Int {\n  9090\n}\n",
      must_contain: ["<<<<<<<", "8081", "9090"],
    },
  ]
}

///|
/// Execute the full built-in benchmark corpus and compute comparative metrics.
pub fn run_benchmark_suite() -> SuiteSummary {
  let cases = builtin_benchmark_corpus()
  let outcomes : Array[CaseOutcome] = Array(capacity=cases.length())
  let mut expected_clean = 0
  let mut expected_conflict = 0
  let mut diff3_clean = 0
  let mut mg_clean = 0
  let mut true_conflicts_ok = 0
  let mut all_ok = true

  for c in cases {
    let res = @merger.merge_3way(
      c.base,
      c.left,
      c.right,
      @merger.MergeOptions::for_language(c.language),
    )
    let mut contains_all = true
    for needle in c.must_contain {
      if !res.merged_text.contains(needle) {
        contains_all = false
      }
    }
    let passed = if c.expect_clean {
      expected_clean += 1
      if res.line_diff3_conflicts == 0 {
        diff3_clean += 1
      }
      if res.conflict_count == 0 && res.syntax_valid {
        mg_clean += 1
      }
      res.conflict_count == 0 && res.syntax_valid && contains_all
    } else {
      expected_conflict += 1
      if res.conflict_count >= 1 && contains_all {
        true_conflicts_ok += 1
      }
      res.conflict_count >= 1 && contains_all
    }
    if !passed {
      all_ok = false
    }
    outcomes.push({
      id: c.id,
      title: c.title,
      language: c.language.slug(),
      expect_clean: c.expect_clean,
      diff3_conflicts: res.line_diff3_conflicts,
      moongraft_conflicts: res.conflict_count,
      syntax_valid: res.syntax_valid,
      passed_expectation: passed,
    })
  }

  {
    total_cases: cases.length(),
    expected_clean_cases: expected_clean,
    expected_conflict_cases: expected_conflict,
    diff3_clean_on_resolvable: diff3_clean,
    moongraft_clean_on_resolvable: mg_clean,
    true_conflicts_preserved: true_conflicts_ok,
    all_assertions_passed: all_ok,
    outcomes,
  }
}

///|
/// Format `SuiteSummary` as a clean Markdown benchmark table.
pub fn render_suite_markdown(summary : SuiteSummary) -> String {
  let buf = StringBuilder()
  buf.write_string("## MoonGraft vs Line `diff3` Benchmark Suite\n\n")
  buf.write_string("- **Total Scenarios**: ")
  buf.write_string(summary.total_cases.to_string())
  buf.write_string("\n- **Resolvable Structural Scenarios Resolved**: **")
  buf.write_string(summary.moongraft_clean_on_resolvable.to_string())
  buf.write_string(" / ")
  buf.write_string(summary.expected_clean_cases.to_string())
  buf.write_string("** (vs Line `diff3`: ")
  buf.write_string(summary.diff3_clean_on_resolvable.to_string())
  buf.write_string(" / ")
  buf.write_string(summary.expected_clean_cases.to_string())
  buf.write_string(")\n- **True Conflicts Soundly Preserved**: **")
  buf.write_string(summary.true_conflicts_preserved.to_string())
  buf.write_string(" / ")
  buf.write_string(summary.expected_conflict_cases.to_string())
  buf.write_string("**\n\n")
  buf.write_string(
    "| Case ID | Language | Expected | Line `diff3` Conflicts | `MoonGraft` Conflicts | Syntax Valid | Status |\n",
  )
  buf.write_string("| :--- | :--- | :--- | :---: | :---: | :---: | :---: |\n")
  for o in summary.outcomes {
    buf.write_string("| `")
    buf.write_string(o.id)
    buf.write_string("` | `")
    buf.write_string(o.language)
    buf.write_string("` | ")
    buf.write_string(if o.expect_clean { "Clean" } else { "Conflict" })
    buf.write_string(" | ")
    buf.write_string(o.diff3_conflicts.to_string())
    buf.write_string(" | ")
    buf.write_string(o.moongraft_conflicts.to_string())
    buf.write_string(" | ")
    buf.write_string(if o.syntax_valid { "Yes" } else { "N/A" })
    buf.write_string(" | ")
    buf.write_string(if o.passed_expectation { "PASS" } else { "FAIL" })
    buf.write_string(" |\n")
  }
  buf.to_string()
}

///|
/// Format structural AST diff edits for human CLI inspection (`moongraft diff`).
pub fn render_structural_diff(
  old_path : String,
  new_path : String,
  lang : @cst.Language,
  edits : Array[@matcher.StructuralEdit],
) -> String {
  let buf = StringBuilder()
  buf.write_string("--- ")
  buf.write_string(old_path)
  buf.write_string(" (")
  buf.write_string(lang.slug())
  buf.write_string(")\n+++ ")
  buf.write_string(new_path)
  buf.write_string("\n")
  if edits.is_empty() {
    buf.write_string("No structural AST changes detected.\n")
    return buf.to_string()
  }
  for e in edits {
    let badge = match e.kind {
      @matcher.Inserted => "[+ INSERT]  "
      @matcher.Deleted => "[- DELETE]  "
      @matcher.Modified => "[~ MODIFY]  "
      @matcher.Moved => "[> MOVED]   "
      @matcher.MovedAndModified => "[* MOVE+MOD]"
      @matcher.FormattingChanged => "[. FORMAT]  "
    }
    buf.write_string(badge)
    buf.write_string(" ")
    buf.write_string(e.summary)
    match (e.old_line, e.new_line) {
      (Some(ol), Some(nl)) => {
        buf.write_string(" (L")
        buf.write_string(ol.to_string())
        buf.write_string(" -> L")
        buf.write_string(nl.to_string())
        buf.write_string(")")
      }
      (Some(ol), None) => {
        buf.write_string(" (at L")
        buf.write_string(ol.to_string())
        buf.write_string(")")
      }
      (None, Some(nl)) => {
        buf.write_string(" (at L")
        buf.write_string(nl.to_string())
        buf.write_string(")")
      }
      (None, None) => ()
    }
    buf.write_string("\n")
  }
  buf.to_string()
}

///|
/// Generate ready-to-paste `.gitattributes` rules enabling `moongraft` as Git merge driver.
pub fn generate_gitattributes_snippet() -> String {
  let s =
    #|# MoonGraft syntax-aware 3-way CST merge driver
    #|*.mbt         merge=moongraft
    #|*.mbti        merge=moongraft
    #|moon.pkg      merge=moongraft
    #|moon.mod      merge=moongraft
    #|*.json        merge=moongraft
    #|*.jsonc       merge=moongraft
    #|*.toml        merge=moongraft
    #|*.yaml        merge=moongraft
    #|*.yml         merge=moongraft
    #|*.ts          merge=moongraft
    #|*.tsx         merge=moongraft
    #|*.js          merge=moongraft
    #|*.py          merge=moongraft
    #|*.rs          merge=moongraft
    #|
  s
}

///|
/// Generate ready-to-paste `.gitconfig` snippet registering the `moongraft` driver.
pub fn generate_gitconfig_snippet() -> String {
  let s =
    #|[merge]
    #|    conflictStyle = diff3
    #|[merge "moongraft"]
    #|    name = MoonGraft syntax-aware 3-way CST merge driver
    #|    driver = moongraft merge %O %A %B -o %A -p %P -L %X -L %Y -L %P
    #|
  s
}
