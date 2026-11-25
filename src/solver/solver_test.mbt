///|
test "solver resolves diff3 conflict markers in MoonBit source file" {
  let conflicted =
    #|///|
    #|pub fn base_fn() -> Int {
    #|  42
    #|}
    #|
    #|<<<<<<< HEAD
    #|///|
    #|pub fn agent_left() -> String {
    #|  "left"
    #|}
    #|||||||| merged common ancestors
    #|=======
    #|///|
    #|pub fn agent_right() -> Bool {
    #|  true
    #|}
    #|>>>>>>> feature/right
    #|
  let solved = @solver.solve_conflicted_file(conflicted, path="lib.mbt")
  assert_eq(solved.initial_conflicts, 1)
  assert_eq(solved.remaining_conflicts, 0)
  assert_true(solved.had_diff3_base)
  assert_true(solved.resolved_text.contains("pub fn agent_left()"))
  assert_true(solved.resolved_text.contains("pub fn agent_right()"))
}

///|
test "solver resolves 2-way conflict markers in package.json without diff3 base" {
  let conflicted_json =
    #|{
    #|  "name": "app",
    #|  "dependencies": {
    #|    "react": "^19.0.0",
    #|<<<<<<< HEAD
    #|    "zod": "^3.23.0"
    #|=======
    #|    "swr": "^2.2.5"
    #|>>>>>>> feat-swr
    #|  }
    #|}
    #|
  let solved = @solver.solve_conflicted_file(
    conflicted_json,
    path="package.json",
  )
  assert_eq(solved.initial_conflicts, 1)
  assert_eq(solved.remaining_conflicts, 0)
  assert_false(solved.had_diff3_base)
  assert_true(solved.resolved_text.contains("\"zod\": \"^3.23.0\""))
  assert_true(solved.resolved_text.contains("\"swr\": \"^2.2.5\""))
  let (valid, _) = @lang.verify_well_formed(solved.resolved_text, @cst.Json)
  assert_true(valid)
}
