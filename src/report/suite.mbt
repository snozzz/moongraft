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

