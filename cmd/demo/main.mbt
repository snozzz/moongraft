///|
/// Zero-FFI cross-backend minimal runnable showcase (`moon run cmd/demo`).
/// Runs identically on `wasm-gc`, `wasm`, `native`, and `js` targets.
fn main {
  println("================================================================")
  println("  MoonGraft Minimal Runnable Demo (Pure MoonBit CST 3-Way Merge)")
  println("================================================================\n")

  // Demo 1: MoonBit Move + Edit composition across ///| blocks
  let mbt_base =
    #|///|
    #|pub fn parse_header(line : String) -> String {
    #|  line.trim().to_owned()
    #|}
    #|
    #|///|
    #|pub fn compute_checksum(seed : Int, step : Int) -> Int {
    #|  let acc = seed + step
    #|  acc * 31
    #|}
    #|
  let mbt_ours =
    #|///|
    #|pub fn compute_checksum(seed : Int, step : Int) -> Int {
    #|  let acc = seed + step
    #|  acc * 31
    #|}
    #|
    #|///|
    #|pub fn parse_header(line : String) -> String {
    #|  line.trim().to_owned()
    #|}
    #|
    #|///|
    #|pub fn format_digest(v : Int) -> String {
    #|  "digest:" + v.to_string()
    #|}
    #|
  let mbt_theirs =
    #|///|
    #|pub fn parse_header(line : String) -> String {
    #|  line.trim().to_owned()
    #|}
    #|
    #|///|
    #|pub fn compute_checksum(seed : Int, step : Int) -> Int {
    #|  let acc = seed + step * 2
    #|  acc * 31
    #|}
    #|
    #|///|
    #|pub fn verify_digest(v : Int) -> Bool {
    #|  v >= 0
    #|}
    #|

  let res_mbt = @moongraft.merge(
    mbt_base,
    mbt_ours,
    mbt_theirs,
    path="src/digest.mbt",
  )
  println(
    "[1/4] MoonBit Move + Edit Merge -> Line diff3 conflicts: \{res_mbt.line_diff3_conflicts}, MoonGraft conflicts: \{res_mbt.conflict_count} (syntax_valid=\{res_mbt.syntax_valid})",
  )
  println(res_mbt.merged_text)

  // Demo 2: package.json Trailing-Comma Trap
  let json_base = "{\n  \"name\": \"demo\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\"\n  }\n}\n"
  let json_ours = "{\n  \"name\": \"demo\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\",\n    \"zod\": \"^3.23.8\"\n  }\n}\n"
  let json_theirs = "{\n  \"name\": \"demo\",\n  \"dependencies\": {\n    \"react\": \"^19.0.0\",\n    \"vite\": \"^6.0.0\"\n  }\n}\n"
  let res_json = @moongraft.merge(
    json_base,
    json_ours,
    json_theirs,
    path="package.json",
  )
  println(
    "[2/4] package.json Trailing-Comma Merge -> Line diff3 conflicts: \{res_json.line_diff3_conflicts}, MoonGraft conflicts: \{res_json.conflict_count}",
  )
  println(res_json.merged_text)

  // Demo 3: Cross-branch rename & stale call-site hazard detection
  let ren_base = "///|\npub fn read_cfg(raw : String) -> Int {\n  if raw.is_empty() { 0 } else { 1 }\n}\n"
  let ren_ours = "///|\npub fn load_cfg(raw : String) -> Int {\n  if raw.is_empty() { 0 } else { 1 }\n}\n"
  let ren_theirs = "///|\npub fn read_cfg(raw : String) -> Int {\n  if raw.is_empty() { 0 } else { 1 }\n}\n\n///|\npub fn boot() -> Int {\n  read_cfg(\"prod\")\n}\n"
  let analysis = @moongraft.analyze_renames(
    ren_base,
    ren_ours,
    ren_theirs,
    path="src/cfg.mbt",
  )
  println(
    "[3/4] Cross-Branch Rename Audit -> Detected \{analysis.renames.length()} rename(s), \{analysis.hazards.length()} stale call-site hazard(s):",
  )
  for h in analysis.hazards {
    println("  ! \{h.suggestion}")
  }
  println("")

  // Demo 4: Full 16-scenario multi-language benchmark summary
  let suite = @moongraft.evaluate_corpus()
  println("[4/4] Multi-Language Evaluation Corpus Summary:")
  println(@report.render_suite_markdown(suite))
}
