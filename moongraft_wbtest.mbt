///|
test "whitebox sanity check on playground JSON schema keys" {
  let out = playground_merge_json(
    "demo.json", "{\n  \"a\": 1\n}\n", "{\n  \"a\": 1,\n  \"b\": 2\n}\n", "{\n  \"a\": 1,\n  \"c\": 3\n}\n",
    "diff3",
  )
  assert_true(out.contains("\"language\": \"json\""))
  assert_true(out.contains("\"syntax_valid\": true"))
}
