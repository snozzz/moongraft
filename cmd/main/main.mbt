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

  @argparse.Command(
    "moongraft",
    version="0.1.0",
    about="MoonGraft: Syntax-aware 3-way CST merge engine & multi-agent Git merge driver",
    subcommand_required=true,
    arg_required_else_help=true,
    subcommands=[
      merge_cmd, solve_cmd, diff_cmd, inspect_cmd, bench_cmd, setup_cmd,
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

