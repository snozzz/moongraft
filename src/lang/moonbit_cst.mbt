///|
/// Lossless CST parser for MoonBit source & interface files (`.mbt`, `.mbti`).
/// Exploits MoonBit's native `///|` block-independent architecture (`CommutativeBlocks`),
/// parses top-level declarations (`fn`, `test`, `struct`, `enum`, `suberror`, `trait`,
/// `impl`, `type`, `const`, `let`) with semantic signatures, AND recursively decomposes:
/// - `struct` bodies into `CommutativeByKey` `FieldDecl` entries!
/// - `enum` / `suberror` bodies into `CommutativeByKey` `VariantDecl` entries!
/// - `fn` / `test` / `impl` bodies into statement-level `Block` children!
pub fn parse_moonbit_cst(source : String) -> @cst.CstNode {
  let sc = Scanner::new(source)
  let ids = IdGen::new()
  let decls : Array[@cst.CstNode] = []
  let mut anon_counter = 0

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia(recognize_moonbit_sep=true)
    if sc.is_eof() {
      let root = @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.SourceFile,
        decls,
        ordering=@cst.CommutativeBlocks,
        trailing_trivia=triv,
        span=@cst.ByteSpan::new(0, source.length()),
      )
      let (reindexed, _) = @cst.reindex_tree(root)
      return reindexed
    }

    let decl_start = sc.pos
    // Consume leading `#attribute(...)` lines as part of declaration header
    while sc.peek() == Some('#') && !sc.starts_with("#|") {
      sc.advance()
      let _ = sc.scan_ident(allow_hyphen=true)
      if sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      }
      let _ = sc.collect_c_like_trivia(recognize_moonbit_sep=false)
    }

    // Consume visibility / async / extern modifiers to inspect primary keyword
    let kw_probe = sc.pos
    let mut primary_kw = sc.scan_ident()
    while primary_kw == "pub" ||
          primary_kw == "priv" ||
          primary_kw == "async" ||
          primary_kw == "readonly" ||
          primary_kw == "extern" {
      let _ = sc.consume_spaces()
      if sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      } else if sc.peek() == Some('"') {
        let _ = sc.scan_quoted_string()
      }
      let _ = sc.collect_c_like_trivia(recognize_moonbit_sep=false)
      primary_kw = sc.scan_ident()
    }

    match primary_kw {
      "fn" =>
        decls.push(
          parse_mbt_fn_or_impl(sc, ids, triv, decl_start, @cst.FnDecl, "fn"),
        )
      "test" => {
        let (node, next_anon) = parse_mbt_test_decl(
          sc, ids, triv, decl_start, anon_counter,
        )
        anon_counter = next_anon
        decls.push(node)
      }
      "struct" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.StructDecl,
            "struct",
            @cst.FieldDecl,
          ),
        )
      "enum" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.EnumDecl,
            "enum",
            @cst.VariantDecl,
          ),
        )
      "suberror" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.SuberrorDecl,
            "suberror",
            @cst.VariantDecl,
          ),
        )
      "trait" =>
        decls.push(
          parse_mbt_record_or_adt(
            sc,
            ids,
            triv,
            decl_start,
            @cst.TraitDecl,
            "trait",
            @cst.FieldDecl,
          ),
        )
      "impl" =>
        decls.push(
          parse_mbt_fn_or_impl(sc, ids, triv, decl_start, @cst.ImplDecl, "impl"),
        )
      "let" | "const" | "type" | "typealias" | "fnalias" => {
        let kind = match primary_kw {
          "const" => @cst.ConstDecl
          "let" => @cst.LetDecl
          _ => @cst.TypeDecl
        }
        decls.push(
          parse_mbt_simple_decl(sc, ids, triv, decl_start, kind, primary_kw),
        )
      }
      _ => {
        sc.pos = kw_probe
        let line = sc.consume_to_eol(include_newline=true)
        let prefix = sc.slice_chars(decl_start, kw_probe)
        decls.push(
          @cst.CstNode::leaf(
            id=ids.alloc(),
            @cst.Stmt,
            prefix + line,
            leading_trivia=triv,
          ),
        )
      }
    }
  }

  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    decls,
    ordering=@cst.CommutativeBlocks,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
/// Scan a MoonBit declaration name (`foo` or `Type::method` or `[T] Type::method`).
fn scan_mbt_qualified_name(sc : Scanner) -> String {
  let _ = sc.collect_c_like_trivia()
  if sc.peek() == Some('[') {
    let _ = sc.skip_balanced_group()
    let _ = sc.collect_c_like_trivia()
  }
  let first = sc.scan_ident()
  if first.is_empty() {
    return ""
  }
  if sc.starts_with("::") {
    sc.advance(count=2)
    let second = sc.scan_ident()
    if !second.is_empty() {
      return first + "::" + second
    }
  }
  first
}

///|
/// Scan up to the body `{` of a MoonBit `fn` or `impl` (skipping `(params)` and `-> RetType`
/// where `{` inside `where { ... }` is distinguished from body `{` if followed by another `{`).
fn advance_to_decl_open_brace(sc : Scanner) -> Bool {
  while !sc.is_eof() {
    if sc.starts_with("///|") {
      return false
    }
    match sc.peek() {
      Some('(') | Some('[') => {
        let _ = sc.skip_balanced_group()
      }
      Some('"') | Some('\'') => {
        let _ = sc.scan_quoted_string()
      }
      Some('/') =>
        if sc.starts_with("//") {
          let _ = sc.consume_to_eol(include_newline=true)
        } else {
          sc.advance()
        }
      Some('=') => {
        // Extern `fn ... = "..."` or `#| ...` body without `{`
        let saved = sc.pos
        sc.advance()
        let _ = sc.collect_c_like_trivia()
        if sc.peek() == Some('"') || sc.starts_with("#|") {
          sc.pos = saved
          return false
        }
      }
      Some('{') => return true
      Some('\n') => {
        // In `.mbti` interface files, `pub fn foo(...) -> Int\n` has no `{` body!
        let saved_nl = sc.pos
        let _ = sc.collect_c_like_trivia()
        if sc.is_eof() ||
          sc.starts_with("pub ") ||
          sc.starts_with("priv ") ||
          sc.starts_with("fn ") ||
          sc.starts_with("type ") ||
          sc.starts_with("struct ") ||
          sc.starts_with("enum ") ||
          sc.starts_with("impl ") ||
          sc.starts_with("#") ||
          sc.starts_with("///|") {
          sc.pos = saved_nl
          return false
        }
      }
      _ => sc.advance()
    }
  }
  false
}

///|
/// Parse a brace-delimited statement block `{ stmt1; stmt2; ... }` into `Block`
/// with individual line/balanced-block `Stmt` children so disjoint edits inside
/// the SAME function body merge cleanly!
pub fn parse_brace_statement_block(
  sc : Scanner,
  ids : IdGen,
  allow_hash_comment~ : Bool = false,
) -> @cst.CstNode {
  let b_start = sc.byte_offset()
  sc.advance() // '{'
  let open_trail = sc.collect_trailing_line_trivia(
    allow_slash_comment=true,
    allow_hash_comment~,
  )
  let children : Array[@cst.CstNode] = [
    @cst.CstNode::leaf(
      id=ids.alloc(),
      @cst.Punctuation,
      "{",
      trailing_trivia=open_trail,
    ),
  ]
  let mut has_err = false

  while !sc.is_eof() {
    let triv = sc.collect_c_like_trivia(allow_hash_comment~)
    if sc.peek() == Some('}') {
      sc.advance()
      let close_trail = sc.collect_trailing_line_trivia(
        allow_slash_comment=true,
        allow_hash_comment~,
      )
      children.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.Punctuation,
          "}",
          leading_trivia=triv,
          trailing_trivia=close_trail,
        ),
      )
      return @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.Block,
        children,
        ordering=@cst.Sequential,
        span=@cst.ByteSpan::new(b_start, sc.byte_offset()),
        has_error=has_err,
      )
    }

    // Scan one logical statement (respecting nested `{...}`, `(...)`, `[...]`, strings)
    let stmt_start = sc.pos
    while !sc.is_eof() {
      match sc.peek() {
        Some('\n') | Some('\r') | Some('}') => break
        Some('{') | Some('(') | Some('[') => {
          let ok = sc.skip_balanced_group(allow_hash_comment~)
          if !ok {
            has_err = true
          }
        }
        Some('"') | Some('\'') => {
          let (_, _, ok) = sc.scan_quoted_string(allow_multiline=true)
          if !ok {
            has_err = true
          }
        }
        Some('/') => if sc.starts_with("//") { break } else { sc.advance() }
        Some('#') =>
          if sc.starts_with("#|") {
            let _ = sc.consume_to_eol(include_newline=false)
          } else if allow_hash_comment {
            break
          } else {
            sc.advance()
          }
        _ => sc.advance()
      }
    }
    let mut stmt_end = sc.pos
    while stmt_end > stmt_start &&
          (sc.chars[stmt_end - 1] == ' ' || sc.chars[stmt_end - 1] == '\t') {
      stmt_end -= 1
    }
    sc.pos = stmt_end
    let raw_stmt = sc.slice_chars(stmt_start, sc.pos)
    let stmt_trail = sc.collect_trailing_line_trivia(
      allow_slash_comment=true,
      allow_hash_comment~,
    )
    children.push(
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.Stmt,
        raw_stmt,
        leading_trivia=triv,
        trailing_trivia=stmt_trail,
      ),
    )
  }

  @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.Block,
    children,
    ordering=@cst.Sequential,
    span=@cst.ByteSpan::new(b_start, sc.byte_offset()),
    has_error=true,
  )
}

///|
fn parse_mbt_fn_or_impl(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  decl_start : Int32,
  kind : @cst.SyntaxKind,
  prefix_tag : String,
) -> @cst.CstNode {
  let name = if kind == @cst.FnDecl {
    scan_mbt_qualified_name(sc)
  } else {
    let impl_hdr_start = sc.pos
    let _ = advance_to_decl_open_brace(sc)
    let raw_hdr = sc.slice_chars(impl_hdr_start, sc.pos).trim().to_owned()
    sc.pos = impl_hdr_start
    raw_hdr.replace_all(old=" ", new="")
  }
  let has_brace = advance_to_decl_open_brace(sc)
  if has_brace && sc.peek() == Some('{') {
    let sig_raw = sc.slice_chars(decl_start, sc.pos)
    let header_leaf = @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, sig_raw)
    let body_block = parse_brace_statement_block(sc, ids)
    let sig = if !name.is_empty() {
      Some(prefix_tag + ":" + name)
    } else {
      None
    }
    @cst.CstNode::interior(
      id=ids.alloc(),
      kind,
      [header_leaf, body_block],
      signature=sig,
      leading_trivia=leading,
      span=@cst.ByteSpan::new(sc.offsets[decl_start], sc.byte_offset()),
      has_error=body_block.has_error,
    )
  } else {
    // Extern `#|` body or `.mbti` signature without `{ ... }`
    while !sc.is_eof() && !sc.starts_with("///|") {
      let line_s = sc.pos
      let _ = sc.consume_to_eol(include_newline=true)
      let l_txt = sc.slice_chars(line_s, sc.pos).trim().to_owned()
      let _ = sc.consume_spaces()
      if !sc.starts_with("#|") && !l_txt.has_suffix("=") {
        break
      }
    }
    let raw = sc.slice_chars(decl_start, sc.pos)
    let sig = if !name.is_empty() {
      Some(prefix_tag + ":" + name)
    } else {
      None
    }
    @cst.CstNode::leaf(
      id=ids.alloc(),
      kind,
      raw,
      signature=sig,
      leading_trivia=leading,
      span=@cst.ByteSpan::new(sc.offsets[decl_start], sc.byte_offset()),
    )
  }
}

///|
fn parse_mbt_test_decl(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  decl_start : Int32,
  anon_idx : Int32,
) -> (@cst.CstNode, Int32) {
  let _ = sc.consume_spaces()
  let mut next_anon = anon_idx
  let sig = if sc.peek() == Some('"') {
    let (_, test_name, _) = sc.scan_quoted_string()
    "test:" + test_name
  } else {
    let s = "anon:test#" + next_anon.to_string()
    next_anon += 1
    s
  }
  let has_brace = advance_to_decl_open_brace(sc)
  if has_brace && sc.peek() == Some('{') {
    let hdr = sc.slice_chars(decl_start, sc.pos)
    let hdr_leaf = @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, hdr)
    let body = parse_brace_statement_block(sc, ids)
    (
      @cst.CstNode::interior(
        id=ids.alloc(),
        @cst.TestDecl,
        [hdr_leaf, body],
        signature=Some(sig),
        leading_trivia=leading,
        span=@cst.ByteSpan::new(sc.offsets[decl_start], sc.byte_offset()),
        has_error=body.has_error,
      ),
      next_anon,
    )
  } else {
    let _ = sc.consume_to_eol(include_newline=true)
    let raw = sc.slice_chars(decl_start, sc.pos)
    (
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.TestDecl,
        raw,
        signature=Some(sig),
        leading_trivia=leading,
      ),
      next_anon,
    )
  }
}

///|
fn parse_mbt_record_or_adt(
  sc : Scanner,
  ids : IdGen,
  leading : Array[@cst.Trivia],
  decl_start : Int32,
  kind : @cst.SyntaxKind,
  prefix_tag : String,
  member_kind : @cst.SyntaxKind,
) -> @cst.CstNode {
  let name = scan_mbt_qualified_name(sc)
  let has_brace = advance_to_decl_open_brace(sc)
  if has_brace && sc.peek() == Some('{') {
    let hdr = sc.slice_chars(decl_start, sc.pos)
    let hdr_leaf = @cst.CstNode::leaf(id=ids.alloc(), @cst.Keyword, hdr)
    let members_block = parse_mbt_member_block(sc, ids, member_kind)
    // Optional trailing `derive(...)` on same line if legacy style exists
    let after_pos = sc.pos
    let _ = sc.consume_spaces()
    if sc.starts_with("derive") {
      sc.advance(count=6)
      if sc.peek() == Some('(') {
        let _ = sc.skip_balanced_group()
      }
      let trail = sc.collect_trailing_line_trivia(allow_slash_comment=true)
      let derive_leaf = @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.Attribute,
        sc.slice_chars(after_pos, sc.pos - @cst.render_trivia(trail).length()),
        trailing_trivia=trail,
      )
      return @cst.CstNode::interior(
        id=ids.alloc(),
        kind,
        [hdr_leaf, members_block, derive_leaf],
        signature=if !name.is_empty() {
          Some(prefix_tag + ":" + name)
        } else {
          None
        },
        leading_trivia=leading,
        has_error=members_block.has_error,
      )
    } else {
      sc.pos = after_pos
    }
    @cst.CstNode::interior(
      id=ids.alloc(),
      kind,
      [hdr_leaf, members_block],
      signature=if !name.is_empty() {
        Some(prefix_tag + ":" + name)
      } else {
        None
      },
      leading_trivia=leading,
      span=@cst.ByteSpan::new(sc.offsets[decl_start], sc.byte_offset()),
      has_error=members_block.has_error,
    )
  } else {
    let _ = sc.consume_to_eol(include_newline=true)
    let raw = sc.slice_chars(decl_start, sc.pos)
    @cst.CstNode::leaf(
      id=ids.alloc(),
      kind,
      raw,
      signature=if !name.is_empty() {
        Some(prefix_tag + ":" + name)
      } else {
        None
      },
      leading_trivia=leading,
    )
  }
}

