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

///|
fn parse_yaml_mapping(
  lines : Array[YamlLine],
  start_idx : Int32,
  map_indent : Int32,
  ids : IdGen,
) -> (@cst.CstNode, Int32) {
  let n = lines.length()
  let entries : Array[@cst.CstNode] = []
  let mut idx = start_idx

  while idx < n {
    let lead_triv : Array[@cst.Trivia] = []
    let saved = idx
    while idx < n && lines[idx].is_blank_or_comment {
      let kind = if lines[idx].trimmed.has_prefix("#") {
        @cst.LineComment
      } else {
        @cst.Whitespace
      }
      lead_triv.push(@cst.Trivia::new(kind, lines[idx].raw))
      idx += 1
    }
    if idx >= n || lines[idx].indent < map_indent {
      // Do not consume trailing blank/comment lines belonging to outer scope
      idx = saved
      break
    }
    if lines[idx].indent > map_indent {
      // Misaligned continuation line
      entries.push(
        @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.ErrorFragment,
          lines[idx].raw,
          leading_trivia=lead_triv,
          has_error=true,
        ),
      )
      idx += 1
      continue
    }
    if lines[idx].trimmed == "-" || lines[idx].trimmed.has_prefix("- ") {
      idx = saved
      break
    }

    match extract_yaml_key(lines[idx].trimmed) {
      Some((key, inline_val)) => {
        let header_leaf = @cst.CstNode::leaf(
          id=ids.alloc(),
          @cst.KeyValue,
          lines[idx].raw,
        )
        idx += 1
        let entry_children : Array[@cst.CstNode] = [header_leaf]
        if inline_val == "|" ||
          inline_val == "|-" ||
          inline_val == ">" ||
          inline_val == ">-" {
          // Consume multiline scalar lines with indent > map_indent
          let scalar_buf = StringBuilder()
          while idx < n {
            if lines[idx].trimmed.is_empty() || lines[idx].indent > map_indent {
              scalar_buf.write_string(lines[idx].raw)
              idx += 1
            } else {
              break
            }
          }
          let s_text = scalar_buf.to_string()
          if !s_text.is_empty() {
            entry_children.push(
              @cst.CstNode::leaf(id=ids.alloc(), @cst.StringLiteral, s_text),
            )
          }
        } else if inline_val.is_empty() || inline_val.has_prefix("#") {
          // Check if nested indented block follows
          let mut peek_i = idx
          while peek_i < n && lines[peek_i].is_blank_or_comment {
            peek_i += 1
          }
          if peek_i < n && lines[peek_i].indent > map_indent {
            let (nested, after_nested) = parse_yaml_block(
              lines, idx, map_indent, ids,
            )
            entry_children.push(nested)
            idx = after_nested
          }
        }
        entries.push(
          @cst.CstNode::interior(
            id=ids.alloc(),
            @cst.MappingEntry,
            entry_children,
            signature=Some("key:" + key),
            leading_trivia=lead_triv,
          ),
        )
      }
      None => {
        entries.push(
          @cst.CstNode::leaf(
            id=ids.alloc(),
            @cst.RawLine,
            lines[idx].raw,
            leading_trivia=lead_triv,
          ),
        )
        idx += 1
      }
    }
  }

  (
    @cst.CstNode::interior(
      id=ids.alloc(),
      @cst.MappingNode,
      entries,
      ordering=@cst.CommutativeByKey,
    ),
    idx,
  )
}

///|
fn parse_yaml_sequence(
  lines : Array[YamlLine],
  start_idx : Int32,
  seq_indent : Int32,
  ids : IdGen,
) -> (@cst.CstNode, Int32) {
  let n = lines.length()
  let items : Array[@cst.CstNode] = []
  let mut idx = start_idx

  while idx < n {
    let lead_triv : Array[@cst.Trivia] = []
    let saved = idx
    while idx < n && lines[idx].is_blank_or_comment {
      let kind = if lines[idx].trimmed.has_prefix("#") {
        @cst.LineComment
      } else {
        @cst.Whitespace
      }
      lead_triv.push(@cst.Trivia::new(kind, lines[idx].raw))
      idx += 1
    }
    if idx >= n || lines[idx].indent < seq_indent {
      idx = saved
      break
    }
    if lines[idx].indent != seq_indent ||
      !(lines[idx].trimmed == "-" || lines[idx].trimmed.has_prefix("- ")) {
      idx = saved
      break
    }

    let first_line = lines[idx]
    let after_dash = if first_line.trimmed.length() >= 2 {
      first_line.trimmed[2:].trim().to_owned()
    } else {
      ""
    }
    let mut item_sig : String? = match extract_yaml_key(after_dash) {
      Some((k, v)) =>
        if (k == "name" || k == "id" || k == "uses") && !v.is_empty() {
          Some("item:" + k + "=" + v)
        } else {
          None
        }
      None => None
    }

    let item_lines_buf = StringBuilder()
    item_lines_buf.write_string(first_line.raw)
    idx += 1
    while idx < n {
      if lines[idx].is_blank_or_comment {
        // Look ahead to see if another child line of this sequence item follows
        let mut look = idx
        while look < n && lines[look].is_blank_or_comment {
          look += 1
        }
        if look < n && lines[look].indent > seq_indent {
          item_lines_buf.write_string(lines[idx].raw)
          idx += 1
          continue
        } else {
          break
        }
      }
      if lines[idx].indent > seq_indent {
        if item_sig == None {
          match extract_yaml_key(lines[idx].trimmed) {
            Some((k, v)) =>
              if (k == "name" || k == "id") && !v.is_empty() {
                item_sig = Some("item:" + k + "=" + v)
              }
            None => ()
          }
        }
        item_lines_buf.write_string(lines[idx].raw)
        idx += 1
      } else {
        break
      }
    }

    items.push(
      @cst.CstNode::leaf(
        id=ids.alloc(),
        @cst.SequenceItem,
        item_lines_buf.to_string(),
        signature=item_sig,
        leading_trivia=lead_triv,
      ),
    )
  }

  (
    @cst.CstNode::interior(
      id=ids.alloc(),
      @cst.SequenceNode,
      items,
      ordering=@cst.Sequential,
    ),
    idx,
  )
}
