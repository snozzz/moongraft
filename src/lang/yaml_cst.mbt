///|
/// Line record pre-parsed for indentation-sensitive lossless YAML CST construction.
priv struct YamlLine {
  raw : String
  indent : Int32
  trimmed : String
  is_blank_or_comment : Bool
}

///|
fn split_yaml_lines(source : String) -> Array[YamlLine] {
  let out : Array[YamlLine] = []
  let sc = Scanner::new(source)
  while !sc.is_eof() {
    let raw = sc.consume_to_eol(include_newline=true)
    let mut indent = 0
    for ch in raw {
      if ch == ' ' {
        indent += 1
      } else if ch == '\t' {
        indent += 2
      } else {
        break
      }
    }
    let trimmed = raw.trim().to_owned()
    let is_blank_or_comment = trimmed.is_empty() ||
      trimmed.has_prefix("#") ||
      trimmed == "---" ||
      trimmed == "..."
    out.push({ raw, indent, trimmed, is_blank_or_comment, })
  }
  out
}

///|
/// Lossless indentation-aware YAML CST parser supporting nested block mappings
/// (`CommutativeByKey`), sequences (`- name: ...` / `- id: ...` keyed items!),
/// block scalars (`|`, `>`), and preserved `#` comments.
pub fn parse_yaml_cst(source : String) -> @cst.CstNode {
  let ids = IdGen::new()
  if source.is_empty() {
    return @cst.CstNode::leaf(id=ids.alloc(), @cst.SourceFile, "")
  }
  let lines = split_yaml_lines(source)
  let (block_node, next_idx) = parse_yaml_block(lines, 0, -1, ids)
  let children : Array[@cst.CstNode] = [block_node]
  if next_idx < lines.length() {
    let rem_buf = StringBuilder()
    for i = next_idx; i < lines.length(); i = i + 1 {
      rem_buf.write_string(lines[i].raw)
    }
    children.push(
      @cst.CstNode::leaf(id=ids.alloc(), @cst.RawLine, rem_buf.to_string()),
    )
  }
  let root = @cst.CstNode::interior(
    id=ids.alloc(),
    @cst.SourceFile,
    children,
    span=@cst.ByteSpan::new(0, source.length()),
  )
  let (reindexed, _) = @cst.reindex_tree(root)
  reindexed
}

///|
fn parse_yaml_block(
  lines : Array[YamlLine],
  start_idx : Int32,
  parent_indent : Int32,
  ids : IdGen,
) -> (@cst.CstNode, Int32) {
  let n = lines.length()
  let mut probe = start_idx
  while probe < n && lines[probe].is_blank_or_comment {
    probe += 1
  }
  if probe >= n || lines[probe].indent <= parent_indent {
    let triv : Array[@cst.Trivia] = []
    for i = start_idx; i < probe; i = i + 1 {
      let kind = if lines[i].trimmed.has_prefix("#") {
        @cst.LineComment
      } else {
        @cst.Whitespace
      }
      triv.push(@cst.Trivia::new(kind, lines[i].raw))
    }
    return (
      @cst.CstNode::leaf(id=ids.alloc(), @cst.RawLine, "", leading_trivia=triv),
      probe,
    )
  }

  let block_indent = lines[probe].indent
  let is_seq = lines[probe].trimmed == "-" ||
    lines[probe].trimmed.has_prefix("- ")
  if is_seq {
    parse_yaml_sequence(lines, start_idx, block_indent, ids)
  } else {
    parse_yaml_mapping(lines, start_idx, block_indent, ids)
  }
}

///|
fn extract_yaml_key(trimmed : String) -> (String, String)? {
  // Match `key:` or `key: value` outside quotes
  let mut in_quote : Char? = None
  let mut idx = 0
  for ch in trimmed {
    match in_quote {
      Some(q) => if ch == q { in_quote = None }
      None =>
        if ch == '"' || ch == '\'' {
          in_quote = Some(ch)
        } else if ch == ':' {
          let after = idx + 1
          if after == trimmed.length() ||
            trimmed[after:after + 1].to_owned() == " " {
            let k = trimmed[:idx].trim().to_owned()
            let v = trimmed[after:].trim().to_owned()
            if !k.is_empty() {
              return Some((k, v))
            }
          }
        }
    }
    idx += ch.utf16_len()
  }
  None
}

