///|
test "lossless CST round-trip across all six language families" {
  let json_src =
    #|{
    #|  // app metadata
    #|  "name": "moongraft",
    #|  "dependencies": {
    #|    "core": "^1.0.0",
    #|    "cli": "^2.1.0"
    #|  },
    #|  "items": [
    #|    { "id": "a", "val": 1 },
    #|    { "id": "b", "val": 2 }
    #|  ]
    #|}
    #|
  let json_cst = @lang.parse_cst(json_src, @cst.Json)
  assert_eq(json_cst.unparse(), json_src)
  assert_false(json_cst.has_error)

  let toml_src =
    #|[package]
    #|name = "moongraft"
    #|version = "0.1.0" # semver
    #|
    #|[dependencies]
    #|serde = { version = "1.0", features = ["derive"] }
    #|tokio = "1.39"
    #|
  let toml_cst = @lang.parse_cst(toml_src, @cst.Toml)
  assert_eq(toml_cst.unparse(), toml_src)
  assert_false(toml_cst.has_error)

  let yaml_src =
    #|name: CI
    #|on:
    #|  push:
    #|    branches:
    #|      - main
    #|jobs:
    #|  build:
    #|    runs-on: ubuntu-latest
    #|    steps:
    #|      - name: Checkout
    #|        uses: actions/checkout@v4
    #|      - name: Run moon test
    #|        run: moon test
    #|
  let yaml_cst = @lang.parse_cst(yaml_src, @cst.Yaml)
  assert_eq(yaml_cst.unparse(), yaml_src)
  assert_false(yaml_cst.has_error)

  let manifest_src =
    #|import {
    #|  "moonbitlang/core/debug",
    #|  "snozzz/moongraft/src/cst" @cst,
    #|}
    #|
    #|options(
    #|  targets: {
    #|    "io_js.mbt": [ "js" ],
    #|  },
    #|)
    #|
  let man_cst = @lang.parse_cst(manifest_src, @cst.MoonManifest)
  assert_eq(man_cst.unparse(), manifest_src)
  assert_false(man_cst.has_error)

  let mbt_src =
    #|///|
    #|#derive(Eq, Debug)
    #|pub struct Config {
    #|  host : String
    #|  port : Int
    #|}
    #|
    #|///|
    #|pub fn Config::endpoint(self : Config) -> String {
    #|  let h = self.host
    #|  h + ":" + self.port.to_string()
    #|}
    #|
    #|///|
    #|test "endpoint format" {
    #|  let c = { host: "127.0.0.1", port: 8080 }
    #|  assert_eq(c.endpoint(), "127.0.0.1:8080")
    #|}
    #|
  let mbt_cst = @lang.parse_cst(mbt_src, @cst.MoonBit)
  assert_eq(mbt_cst.unparse(), mbt_src)
  assert_false(mbt_cst.has_error)

  let ts_src =
    #|import { readFile } from "node:fs";
    #|import { resolve } from "node:path";
    #|
    #|export class Router {
    #|  routes: string[];
    #|}
    #|
    #|export function boot(port: number): void {
    #|  console.log(port);
    #|}
    #|
  let ts_cst = @lang.parse_cst(ts_src, @cst.TypeScript)
  assert_eq(ts_cst.unparse(), ts_src)
  assert_false(ts_cst.has_error)

  let py_src =
    #|import os
    #|from pathlib import Path
    #|
    #|class Worker:
    #|    def start(self):
    #|        return True
    #|
    #|def main():
    #|    w = Worker()
    #|    return w.start()
    #|
  let py_cst = @lang.parse_cst(py_src, @cst.Python)
  assert_eq(py_cst.unparse(), py_src)
  assert_false(py_cst.has_error)
}

///|
test "language auto-detection and well-formedness verification" {
  assert_eq(@lang.detect_language("src/merger/merge.mbt"), @cst.MoonBit)
  assert_eq(@lang.detect_language("src/cst/moon.pkg"), @cst.MoonManifest)
  assert_eq(@lang.detect_language("moon.mod"), @cst.MoonManifest)
  assert_eq(@lang.detect_language("Cargo.toml"), @cst.Toml)
  assert_eq(@lang.detect_language(".github/workflows/ci.yml"), @cst.Yaml)
  assert_eq(@lang.detect_language("package.json"), @cst.Json)
  assert_eq(@lang.detect_language("app/server.ts"), @cst.TypeScript)
  assert_eq(@lang.detect_language("scripts/verify.py"), @cst.Python)

  let (ok_good, _) = @lang.verify_well_formed(
    "{\"a\": 1, \"b\": 2}\n",
    @cst.Json,
  )
  assert_true(ok_good)

  // Missing comma between JSON properties must fail well-formedness gate!
  let (ok_missing_comma, _) = @lang.verify_well_formed(
    "{\n  \"a\": 1\n  \"b\": 2\n}\n",
    @cst.Json,
  )
  assert_false(ok_missing_comma)

  // Duplicate JSON key must fail well-formedness gate!
  let (ok_dup_key, _) = @lang.verify_well_formed(
    "{\n  \"a\": 1,\n  \"a\": 2\n}\n",
    @cst.Json,
  )
  assert_false(ok_dup_key)
}
