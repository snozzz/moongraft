///|
extern "js" fn is_browser_runtime() -> Bool =
  #| function() {
  #|   return typeof window !== "undefined" || (typeof process === "undefined");
  #| }

///|
extern "js" fn register_browser_api(
  merge_fn : (String, String, String, String, String) -> String,
  solve_fn : (String, String, String) -> String,
  suite_fn : () -> String,
) -> Unit =
  #| function(merge_fn, solve_fn, suite_fn) {
  #|   globalThis.MoonGraft = {
  #|     mergeJson: merge_fn,
  #|     solveJson: solve_fn,
  #|     runSuiteJson: suite_fn,
  #|   };
  #| }

///|
extern "js" fn read_file_ffi(path : String) -> FixedArray[String] =
  #| function(path) {
  #|   try {
  #|     const fs = require("node:fs");
  #|     return ["ok", fs.readFileSync(path, "utf8")];
  #|   } catch (e) {
  #|     return ["err", String(e && e.message ? e.message : e)];
  #|   }
  #| }

///|
extern "js" fn write_file_ffi(path : String, content : String) -> String =
  #| function(path, content) {
  #|   try {
  #|     const fs = require("node:fs");
  #|     fs.writeFileSync(path, content, "utf8");
  #|     return "";
  #|   } catch (e) {
  #|     return String(e && e.message ? e.message : e);
  #|   }
  #| }

///|
extern "js" fn write_stdout_raw(text : String) -> Unit =
  #| function(text) {
  #|   if (typeof process !== "undefined" && process.stdout) {
  #|     process.stdout.write(text);
  #|   } else {
  #|     console.log(text);
  #|   }
  #| }

///|
extern "js" fn write_stderr_line(text : String) -> Unit =
  #| function(text) {
  #|   if (typeof process !== "undefined" && process.stderr) {
  #|     process.stderr.write(text + "\n");
  #|   } else {
  #|     console.error(text);
  #|   }
  #| }

///|
fn io_read_file(path : String) -> Result[String, String] {
  let pair = read_file_ffi(path)
  if pair.length() >= 2 && pair[0] == "ok" {
    Ok(pair[1])
  } else if pair.length() >= 2 {
    Err(pair[1])
  } else {
    Err("Failed to read file: " + path)
  }
}

///|
fn io_write_file(path : String, content : String) -> Result[Unit, String] {
  let err = write_file_ffi(path, content)
  if err.is_empty() {
    Ok(())
  } else {
    Err(err)
  }
}

///|
fn io_print_raw(text : String) -> Unit {
  write_stdout_raw(text)
}

///|
fn io_eprintln(text : String) -> Unit {
  write_stderr_line(text)
}

///|
fn maybe_init_browser_mode() -> Bool {
  if is_browser_runtime() {
    register_browser_api(
      fn(path, base, left, right, style) {
        @moongraft.playground_merge_json(path, base, left, right, style)
      },
      fn(path, conflicted, style) {
        let st = @diff3.ConflictStyle::from_str(style).unwrap_or(@diff3.Diff3)
        let res = @moongraft.solve_conflicts(conflicted, path~, style=st)
        let j : Json = ToJson::to_json(res)
        j.stringify(indent=2)
      },
      fn() {
        let s = @moongraft.evaluate_corpus()
        let j : Json = ToJson::to_json(s)
        j.stringify(indent=2)
      },
    )
    true
  } else {
    false
  }
}
