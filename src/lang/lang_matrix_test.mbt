///|
test "MoonBit complex syntax: generics, suberror, raw #| strings, .mbti interfaces, and impl blocks" {
  let complex_mbt =
    #|///|
    #|/// Error family for wire decoding.
    #|#derive(Eq, Debug)
    #|pub(all) suberror WireError {
    #|  Truncated(expected~ : Int, actual~ : Int)
    #|  InvalidTag(Byte)
    #|}
    #|
    #|///|
    #|pub fn[T : Eq + Hash] dedup_items(items : Array[T]) -> Array[T] {
    #|  let banner =
    #|    #| line 1 with { braces } and "quotes"
    #|    #| line 2 with [ brackets ]
    #|  let _ = banner
    #|  items
    #|}
    #|
    #|///|
    #|pub impl Show for WireError with output(self, logger) {
    #|  let _ = self
    #|  logger.write_string("WireError")
    #|}
    #|
  let cst = @lang.parse_cst(complex_mbt, @cst.MoonBit)
  assert_eq(cst.unparse(), complex_mbt)
  assert_false(cst.has_error)
  let (ok, issues) = @lang.verify_well_formed(complex_mbt, @cst.MoonBit)
  assert_true(ok)
  assert_eq(issues.length(), 0)

  let mbti_src =
    #|package "snozzz/moongraft/src/cst"
    #|
    #|pub fn avalanche64(UInt64) -> UInt64
    #|
    #|pub struct ByteSpan {
    #|  start : Int
    #|  end : Int
    #|}
    #|
  let mbti_cst = @lang.parse_cst(mbti_src, @cst.MoonBit)
  assert_eq(mbti_cst.unparse(), mbti_src)
  assert_false(mbti_cst.has_error)
}

///|
test "Rust lifetime annotations do not false-trigger unclosed single-quote errors" {
  let rust_src =
    #|use std::borrow::Cow;
    #|
    #|#[derive(Debug, Clone)]
    #|pub struct View<'a> {
    #|    pub slice: &'a str,
    #|    pub owned: Cow<'a, str>,
    #|}
    #|
    #|pub fn trim_view<'a>(input: &'a str) -> &'a str {
    #|    input.trim()
    #|}
    #|
  let cst = @lang.parse_cst(rust_src, @cst.Rust)
  assert_eq(cst.unparse(), rust_src)
  let (ok, _) = @lang.verify_well_formed(rust_src, @cst.Rust)
  assert_true(ok)
}

///|
test "YAML multiline block scalars and TOML array-of-tables round-trip losslessly" {
  let yaml_doc =
    #|name: Release
    #|jobs:
    #|  publish:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - name: Script
    #|        run: |
    #|          echo "building..."
    #|          moon test
    #|
  let y_cst = @lang.parse_cst(yaml_doc, @cst.Yaml)
  assert_eq(y_cst.unparse(), yaml_doc)
  let (y_ok, _) = @lang.verify_well_formed(yaml_doc, @cst.Yaml)
  assert_true(y_ok)

  let toml_aot =
    #|[[bin]]
    #|name = "moongraft"
    #|path = "src/main.rs"
    #|
    #|[[bin]]
    #|name = "moongraft-lsp"
    #|path = "src/lsp.rs"
    #|
  let t_cst = @lang.parse_cst(toml_aot, @cst.Toml)
  assert_eq(t_cst.unparse(), toml_aot)
  let (t_ok, _) = @lang.verify_well_formed(toml_aot, @cst.Toml)
  assert_true(t_ok)
}

///|
test "Python multiline parenthesized imports and decorated class methods round-trip" {
  let py_src =
    #|from typing import (
    #|    Dict,
    #|    List,
    #|    Optional,
    #|)
    #|import sys
    #|
    #|class Service:
    #|    @staticmethod
    #|    def version() -> str:
    #|        return "0.1.0"
    #|
    #|    async def handle(self, req: Dict[str, str]) -> Optional[str]:
    #|        return req.get("id")
    #|
  let cst = @lang.parse_cst(py_src, @cst.Python)
  assert_eq(cst.unparse(), py_src)
  let (ok, _) = @lang.verify_well_formed(py_src, @cst.Python)
  assert_true(ok)
}
