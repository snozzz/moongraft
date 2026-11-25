///|
fn build_cli() -> @argparse.Command {
  let merge_cmd = @argparse.Command(
    "merge",
    about="Syntax-aware 3-way CST merge (drop-in Git merge.driver)",
    options=[
      @argparse.OptionArg(
        "output",
        short='o',
        long="output",
        about="Write merged output to file (e.g. %A in Git merge driver)",
      ),
      @argparse.OptionArg(
        "path",
        short='p',
        long="path",
        about="Logical file path %P for language detection",
      ),
      @argparse.OptionArg(
        "lang",
        long="lang",
        about="Explicit language override (moonbit, moon-manifest, json, toml, yaml, ts, py, rs)",
      ),
      @argparse.OptionArg(
        "style",
        short='s',
        long="style",
        about="Conflict marker style: diff3 (default), zdiff3, or merge",
        default_values=["diff3"],
      ),
      @argparse.OptionArg(
        "label",
        short='L',
        long="label",
        action=@argparse.Append,
        about="Conflict labels (up to 3: OURS, BASE, THEIRS)",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "json",
        long="json",
        about="Emit structured JSON merge report instead of raw merged text",
      ),
    ],
    positionals=[
      @argparse.PositionArg("base", about="Ancestor file (%O)"),
      @argparse.PositionArg("left", about="Current branch file (%A)"),
      @argparse.PositionArg("right", about="Other branch file (%B)"),
    ],
  )

  let solve_cmd = @argparse.Command(
    "solve",
    about="Structurally resolve existing Git conflict markers inside a file",
    options=[
      @argparse.OptionArg(
        "output",
        short='o',
        long="output",
        about="Write resolved output to file",
      ),
      @argparse.OptionArg(
        "lang",
        long="lang",
        about="Explicit language override",
      ),
      @argparse.OptionArg(
        "style",
        short='s',
        long="style",
        about="Conflict style for any remaining true conflicts",
        default_values=["diff3"],
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "in_place",
        short='i',
        long="in-place",
        about="Rewrite the conflicted file in place",
      ),
      @argparse.FlagArg(
        "json",
        long="json",
        about="Emit JSON resolution summary",
      ),
    ],
    positionals=[
      @argparse.PositionArg("file", about="Path to file with conflict markers"),
    ],
  )

  let diff_cmd = @argparse.Command(
    "diff",
    about="Syntax-aware structural AST diff (detects Moves, Move+Modifies, Reformats)",
    options=[
      @argparse.OptionArg(
        "lang",
        long="lang",
        about="Explicit language override",
      ),
    ],
    flags=[@argparse.FlagArg("json", long="json", about="Emit JSON edit list")],
    positionals=[
      @argparse.PositionArg("old", about="Old file path"),
      @argparse.PositionArg("new", about="New file path"),
    ],
  )

  let inspect_cmd = @argparse.Command(
    "inspect",
    about="Dump lossless CST S-expression for a source file",
    options=[
      @argparse.OptionArg(
        "lang",
        long="lang",
        about="Explicit language override",
      ),
    ],
    positionals=[@argparse.PositionArg("file", about="Source file to inspect")],
  )

  let bench_cmd = @argparse.Command(
    "bench-suite",
    about="Run built-in 16-case multi-language benchmark comparing MoonGraft vs line diff3",
    flags=[
      @argparse.FlagArg(
        "json",
        long="json",
        about="Emit machine-readable JSON summary",
      ),
    ],
  )

  let setup_cmd = @argparse.Command(
    "setup",
    about="Print Git .gitattributes and .gitconfig snippets for MoonGraft",
  )

  let rename_cmd = @argparse.Command(
    "analyze-renames",
    about="Detect cross-branch declaration renames and stale call-site semantic hazards",
    options=[
      @argparse.OptionArg(
        "path",
        short='p',
        long="path",
        about="Logical file path for language detection",
      ),
      @argparse.OptionArg(
        "lang",
        long="lang",
        about="Explicit language override",
      ),
    ],
    flags=[
      @argparse.FlagArg(
        "json",
        long="json",
        about="Emit machine-readable JSON rename & hazard report",
      ),
      @argparse.FlagArg(
        "fail_on_hazard",
        long="fail-on-hazard",
        about="Exit with status 1 when cross-branch stale references are detected",
      ),
    ],
    positionals=[
      @argparse.PositionArg("base", about="Ancestor file (%O)"),
      @argparse.PositionArg("left", about="Current branch file (%A)"),
      @argparse.PositionArg("right", about="Other branch file (%B)"),
    ],
  )

  @argparse.Command(
    "moongraft",
    version="0.1.0",
    about="MoonGraft: Syntax-aware 3-way CST merge engine & multi-agent Git merge driver",
    subcommand_required=true,
    arg_required_else_help=true,
    subcommands=[
      merge_cmd, solve_cmd, diff_cmd, inspect_cmd, rename_cmd, bench_cmd, setup_cmd,
    ],
  )
}

///|
fn first_val(m : @argparse.Matches, key : String) -> String? {
  match m.values.get(key) {
    Some(arr) => if !arr.is_empty() { Some(arr[0]) } else { None }
    None => None
  }
}

///|
fn flag_on(m : @argparse.Matches, key : String) -> Bool {
  m.flags.get(key).unwrap_or(false)
}

///|
fn parse_lang_opt(m : @argparse.Matches) -> @cst.Language? {
  match first_val(m, "lang") {
    Some(s) => @cst.Language::from_slug(s)
    None => None
  }
}

///|
fn main {
  if maybe_init_browser_mode() {
    return
  }
  let raw_args = @env.args()
  // Strip executable / script prefix (`node`, `main.js` or `./moongraft`)
  let user_argv : Array[String] = if raw_args.length() >= 2 &&
    (raw_args[0].has_suffix("node") || raw_args[0].has_suffix("nodejs")) {
    let slice : Array[String] = []
    for i = 2; i < raw_args.length(); i = i + 1 {
      slice.push(raw_args[i])
    }
    slice
  } else if raw_args.length() >= 1 {
    let slice : Array[String] = []
    for i = 1; i < raw_args.length(); i = i + 1 {
      slice.push(raw_args[i])
    }
    slice
  } else {
    []
  }

  let cmd = build_cli()
  match cmd.parse_outcome(argv=user_argv[:]) {
    @argparse.Help(text) => {
      io_print_raw(text)
      if !text.has_suffix("\n") {
        io_print_raw("\n")
      }
    }
    @argparse.Version(ver) => {
      io_print_raw(ver)
      if !ver.has_suffix("\n") {
        io_print_raw("\n")
      }
    }
    @argparse.Failed(err) => {
      io_eprintln("error: " + err.to_string())
      @env.exit(2)
    }
    @argparse.Parsed(matches) =>
      match matches.subcommand {
        Some(("merge", sub)) => run_merge_subcommand(sub)
        Some(("solve", sub)) => run_solve_subcommand(sub)
        Some(("diff", sub)) => run_diff_subcommand(sub)
        Some(("inspect", sub)) => run_inspect_subcommand(sub)
        Some(("analyze-renames", sub)) => run_analyze_renames_subcommand(sub)
        Some(("bench-suite", sub)) => run_bench_suite_subcommand(sub)
        Some(("setup", _)) => {
          io_print_raw("# --- .gitattributes ---\n")
          io_print_raw(@report.generate_gitattributes_snippet())
          io_print_raw("\n# --- .gitconfig / ~/.gitconfig ---\n")
          io_print_raw(@report.generate_gitconfig_snippet())
        }
        _ => io_print_raw(cmd.render_help() + "\n")
      }
  }
}

///|
fn run_merge_subcommand(sub : @argparse.Matches) -> Unit {
  let base_path = first_val(sub, "base").unwrap_or("")
  let left_path = first_val(sub, "left").unwrap_or("")
  let right_path = first_val(sub, "right").unwrap_or("")

  let base_src = match io_read_file(base_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let left_src = match io_read_file(left_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let right_src = match io_read_file(right_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }

  let logical_path = first_val(sub, "path").unwrap_or(left_path)
  let lang_opt = parse_lang_opt(sub)
  let style_str = first_val(sub, "style").unwrap_or("diff3")
  let style = @diff3.ConflictStyle::from_str(style_str).unwrap_or(@diff3.Diff3)

  let labels = match sub.values.get("label") {
    Some(ls) =>
      if ls.length() >= 3 {
        // Git `-L %X -L %Y -L %P` or `git merge-file -L ours -L base -L theirs`
        @diff3.MergeLabels::new(ls[1], ls[0], ls[2])
      } else if ls.length() == 2 {
        @diff3.MergeLabels::new("BASE", ls[0], ls[1])
      } else if ls.length() == 1 {
        @diff3.MergeLabels::new("BASE", ls[0], "THEIRS")
      } else {
        @diff3.MergeLabels::default()
      }
    None => @diff3.MergeLabels::default()
  }

  let result = @moongraft.merge(
    base_src,
    left_src,
    right_src,
    path=logical_path,
    language=lang_opt,
    style~,
    labels~,
  )

  match first_val(sub, "output") {
    Some(out_path) =>
      match io_write_file(out_path, result.merged_text) {
        Ok(_) => ()
        Err(e) => {
          io_eprintln("moongraft: " + e)
          @env.exit(2)
        }
      }
    None => if !flag_on(sub, "json") { io_print_raw(result.merged_text) }
  }

  if flag_on(sub, "json") {
    let j : Json = ToJson::to_json(result)
    io_print_raw(j.stringify(indent=2) + "\n")
  }

  // Standard Git merge driver exit protocol: 0 = clean merge, 1 = conflicts remain
  if result.conflict_count > 0 {
    @env.exit(1)
  }
}

///|
fn run_solve_subcommand(sub : @argparse.Matches) -> Unit {
  let file_path = first_val(sub, "file").unwrap_or("")
  let src = match io_read_file(file_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let lang_opt = parse_lang_opt(sub)
  let style_str = first_val(sub, "style").unwrap_or("diff3")
  let style = @diff3.ConflictStyle::from_str(style_str).unwrap_or(@diff3.Diff3)
  let solved = @moongraft.solve_conflicts(
    src,
    path=file_path,
    language=lang_opt,
    style~,
  )

  let target_out : String? = if flag_on(sub, "in_place") {
    Some(file_path)
  } else {
    first_val(sub, "output")
  }
  match target_out {
    Some(out_p) =>
      match io_write_file(out_p, solved.resolved_text) {
        Ok(_) => ()
        Err(e) => {
          io_eprintln("moongraft: " + e)
          @env.exit(2)
        }
      }
    None => if !flag_on(sub, "json") { io_print_raw(solved.resolved_text) }
  }

  if flag_on(sub, "json") {
    let j : Json = ToJson::to_json(solved)
    io_print_raw(j.stringify(indent=2) + "\n")
  }

  if solved.remaining_conflicts > 0 {
    @env.exit(1)
  }
}

///|
fn run_diff_subcommand(sub : @argparse.Matches) -> Unit {
  let old_path = first_val(sub, "old").unwrap_or("")
  let new_path = first_val(sub, "new").unwrap_or("")
  let old_src = match io_read_file(old_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let new_src = match io_read_file(new_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let lang = match parse_lang_opt(sub) {
    Some(l) => l
    None => @lang.detect_language(new_path, content=new_src)
  }
  let edits = @moongraft.structural_diff(
    old_src,
    new_src,
    path=new_path,
    language=Some(lang),
  )
  if flag_on(sub, "json") {
    let j : Json = ToJson::to_json(edits)
    io_print_raw(j.stringify(indent=2) + "\n")
  } else {
    io_print_raw(
      @report.render_structural_diff(old_path, new_path, lang, edits),
    )
  }
}

///|
fn run_inspect_subcommand(sub : @argparse.Matches) -> Unit {
  let file_path = first_val(sub, "file").unwrap_or("")
  let src = match io_read_file(file_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let sexp = @moongraft.inspect_cst_sexp(
    src,
    path=file_path,
    language=parse_lang_opt(sub),
  )
  io_print_raw(sexp)
}

///|
fn run_bench_suite_subcommand(sub : @argparse.Matches) -> Unit {
  let summary = @moongraft.evaluate_corpus()
  if flag_on(sub, "json") {
    let j : Json = ToJson::to_json(summary)
    io_print_raw(j.stringify(indent=2) + "\n")
  } else {
    io_print_raw(@report.render_suite_markdown(summary))
  }
  if !summary.all_assertions_passed {
    @env.exit(1)
  }
}

///|
fn run_analyze_renames_subcommand(sub : @argparse.Matches) -> Unit {
  let base_path = first_val(sub, "base").unwrap_or("")
  let left_path = first_val(sub, "left").unwrap_or("")
  let right_path = first_val(sub, "right").unwrap_or("")

  let base_src = match io_read_file(base_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let left_src = match io_read_file(left_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }
  let right_src = match io_read_file(right_path) {
    Ok(s) => s
    Err(e) => {
      io_eprintln("moongraft: " + e)
      @env.exit(2)
    }
  }

  let logical_path = first_val(sub, "path").unwrap_or(left_path)
  let analysis = @moongraft.analyze_renames(
    base_src,
    left_src,
    right_src,
    path=logical_path,
    language=parse_lang_opt(sub),
  )

  if flag_on(sub, "json") {
    let j : Json = ToJson::to_json(analysis)
    io_print_raw(j.stringify(indent=2) + "\n")
  } else {
    if analysis.renames.is_empty() {
      io_print_raw("No declaration renames detected across branches.\n")
    } else {
      io_print_raw("Detected declaration renames:\n")
      for r in analysis.renames {
        io_print_raw(
          "  - [" +
          r.branch +
          "] " +
          r.syntax_kind +
          " `" +
          r.old_identifier +
          "` -> `" +
          r.new_identifier +
          "` (" +
          r.similarity_pct.to_string() +
          "% body Dice similarity)\n",
        )
      }
    }
    if !analysis.hazards.is_empty() {
      io_print_raw("\nSemantic stale-reference hazards:\n")
      for h in analysis.hazards {
        io_print_raw("  ! " + h.suggestion + "\n")
      }
    }
  }

  if flag_on(sub, "fail_on_hazard") && !analysis.hazards.is_empty() {
    @env.exit(1)
  }
}
