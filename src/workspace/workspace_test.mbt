///|
test "4-agent parallel Octopus CST merge reconciles MoonBit module and moon.pkg cleanly" {
  let base_ws : Map[String, String] = {
    "moon.pkg": "import {\n  \"moonbitlang/core/debug\",\n}\n",
    "src/lib.mbt": "///|\npub fn core_version() -> String {\n  \"0.1.0\"\n}\n",
  }

  let agent1 : Map[String, String] = {
    "moon.pkg": "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/hashmap\",\n}\n",
    "src/lib.mbt": "///|\npub fn core_version() -> String {\n  \"0.1.0\"\n}\n\n///|\npub fn metric_a() -> Int {\n  10\n}\n",
    "src/agent1_only.mbt": "///|\npub fn a1() -> Bool {\n  true\n}\n",
  }

  let agent2 : Map[String, String] = {
    "moon.pkg": "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/json\",\n}\n",
    "src/lib.mbt": "///|\npub fn core_version() -> String {\n  \"0.1.0\"\n}\n\n///|\npub fn metric_b() -> Int {\n  20\n}\n",
  }

  let agent3 : Map[String, String] = {
    "moon.pkg": "import {\n  \"moonbitlang/core/debug\",\n  \"moonbitlang/core/argparse\",\n}\n",
    "src/lib.mbt": "///|\npub fn core_version() -> String {\n  \"0.1.0\"\n}\n\n///|\npub fn metric_c() -> Int {\n  30\n}\n",
  }

  let plan = @workspace.reconcile_agent_workspaces(base_ws, [
    agent1, agent2, agent3,
  ])
  assert_eq(plan.agent_count, 3)
  assert_eq(plan.total_files, 3)
  assert_eq(plan.conflicted_files, 0)
  assert_eq(plan.clean_files, 3)
  assert_true(plan.diff3_conflicts_saved >= 2)

  let merged_pkg = plan.merged_files["moon.pkg"]
  assert_true(merged_pkg.contains("\"moonbitlang/core/hashmap\""))
  assert_true(merged_pkg.contains("\"moonbitlang/core/json\""))
  assert_true(merged_pkg.contains("\"moonbitlang/core/argparse\""))

  let merged_lib = plan.merged_files["src/lib.mbt"]
  assert_true(merged_lib.contains("pub fn metric_a()"))
  assert_true(merged_lib.contains("pub fn metric_b()"))
  assert_true(merged_lib.contains("pub fn metric_c()"))
}

///|
test "reconcile_agent_workspaces auto-propagates cross-branch rename when enabled" {
  let base_ws : Map[String, String] = {
    "src/cfg.mbt": "///|\npub fn read_port(s : String) -> Int {\n  if s.is_empty() { 80 } else { 443 }\n}\n",
  }
  let agent_renamer : Map[String, String] = {
    "src/cfg.mbt": "///|\npub fn parse_port(s : String) -> Int {\n  if s.is_empty() { 80 } else { 443 }\n}\n",
  }
  let agent_caller : Map[String, String] = {
    "src/cfg.mbt": "///|\npub fn read_port(s : String) -> Int {\n  if s.is_empty() { 80 } else { 443 }\n}\n\n///|\npub fn default_port() -> Int {\n  read_port(\"\")\n}\n",
  }

  let plan = @workspace.reconcile_agent_workspaces(
    base_ws,
    [agent_renamer, agent_caller],
    propagate_renames=true,
  )
  assert_eq(plan.conflicted_files, 0)
  let out = plan.merged_files["src/cfg.mbt"]
  assert_true(out.contains("pub fn parse_port"))
  assert_true(out.contains("parse_port(\"\")"))
  assert_false(out.contains("read_port(\"\")"))
}
