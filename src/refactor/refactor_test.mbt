///|
test "detects function rename and flags cross-branch stale call-site hazard" {
  let base =
    #|///|
    #|pub fn parse_config(raw : String) -> Int {
    #|  let trimmed = raw.trim()
    #|  if trimmed.is_empty() { 0 } else { 1 }
    #|}
    #|
  let left =
    #|///|
    #|pub fn load_config(raw : String) -> Int {
    #|  let trimmed = raw.trim()
    #|  if trimmed.is_empty() { 0 } else { 1 }
    #|}
    #|
  let right =
    #|///|
    #|pub fn parse_config(raw : String) -> Int {
    #|  let trimmed = raw.trim()
    #|  if trimmed.is_empty() { 0 } else { 1 }
    #|}
    #|
    #|///|
    #|pub fn boot() -> Int {
    #|  parse_config("default")
    #|}
    #|
  let analysis = @refactor.analyze_cross_branch_renames(
    base,
    left,
    right,
    @cst.MoonBit,
  )
  assert_eq(analysis.renames.length(), 1)
  assert_eq(analysis.renames[0].old_identifier, "parse_config")
  assert_eq(analysis.renames[0].new_identifier, "load_config")
  assert_true(analysis.renames[0].similarity_pct >= 80)

  assert_eq(analysis.hazards.length(), 1)
  assert_eq(analysis.hazards[0].referencing_branch, "right")
  assert_eq(analysis.hazards[0].occurrence_count, 1)

  // Verify lossless call-site propagation leaves string literals untouched
  let (propagated, count) = @refactor.rewrite_identifier_lossless(
    "let msg = \"parse_config\"; parse_config(msg)\n", "parse_config", "load_config",
  )
  assert_eq(count, 1)
  assert_eq(propagated, "let msg = \"parse_config\"; load_config(msg)\n")
}
