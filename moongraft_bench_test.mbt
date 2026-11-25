///|
fn build_synthetic_moonbit_file(
  fn_count : Int32,
  extra_suffix : String,
) -> String {
  let buf = StringBuilder()
  for i = 0; i < fn_count; i = i + 1 {
    if i > 0 {
      buf.write_string("\n")
    }
    buf.write_string("///|\npub fn worker_")
    buf.write_string(i.to_string())
    buf.write_string("(x : Int) -> Int {\n  let y = x + ")
    buf.write_string(i.to_string())
    buf.write_string("\n  y * 2\n}\n")
  }
  if !extra_suffix.is_empty() {
    buf.write_string("\n///|\n")
    buf.write_string(extra_suffix)
  }
  buf.to_string()
}

///|
fn build_synthetic_package_json(
  dep_count : Int32,
  has_extra : Bool,
  extra_key : String,
  extra_ver : String,
) -> String {
  let buf = StringBuilder()
  buf.write_string("{\n  \"name\": \"bench-app\",\n  \"dependencies\": {\n")
  for i = 0; i < dep_count; i = i + 1 {
    buf.write_string("    \"pkg-")
    buf.write_string(i.to_string())
    buf.write_string("\": \"^1.0.")
    buf.write_string(i.to_string())
    buf.write_string("\"")
    if i < dep_count - 1 || has_extra {
      buf.write_string(",")
    }
    buf.write_string("\n")
  }
  if has_extra {
    buf.write_string("    \"")
    buf.write_string(extra_key)
    buf.write_string("\": \"")
    buf.write_string(extra_ver)
    buf.write_string("\"\n")
  }
  buf.write_string("  }\n}\n")
  buf.to_string()
}

///|
test "bench: 80-function MoonBit 3-way CST merge" (b : @bench.T) {
  let base = build_synthetic_moonbit_file(80, "")
  let left = build_synthetic_moonbit_file(
    80, "pub fn agent_left_entry() -> Int {\n  101\n}\n",
  )
  let right = build_synthetic_moonbit_file(
    80, "pub fn agent_right_entry() -> Int {\n  202\n}\n",
  )
  b.bench(name="moonbit_80fn_3way_merge", fn() {
    let res = @moongraft.merge(base, left, right, path="bench.mbt")
    b.keep(res.conflict_count)
  })
}

///|
test "bench: 100-dependency package.json 3-way CST merge" (b : @bench.T) {
  let base = build_synthetic_package_json(100, false, "", "")
  let left = build_synthetic_package_json(100, true, "zod", "^3.23.8")
  let right = build_synthetic_package_json(100, true, "vite", "^6.0.0")
  b.bench(name="json_100dep_3way_merge", fn() {
    let res = @moongraft.merge(base, left, right, path="package.json")
    b.keep(res.conflict_count)
  })
}

///|
test "bench: 16-scenario multi-language benchmark corpus" (b : @bench.T) {
  b.bench(name="full_16case_corpus_eval", fn() {
    let s = @moongraft.evaluate_corpus()
    b.keep(s.moongraft_clean_on_resolvable)
  })
}
