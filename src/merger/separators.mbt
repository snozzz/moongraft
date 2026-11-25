///|
/// Reassemble a delimiter-wrapped commutative container (`ObjectNode` in JSON / TOML inline
/// tables, or `ImportGroup` in `moon.pkg`!) with exact comma separator normalization so
/// parallel appends NEVER suffer missing-comma or stray-comma syntax errors!
pub fn reassemble_delimited_entries(
  open_delim : @cst.CstNode,
  entries : Array[@cst.CstNode],
  close_delim : @cst.CstNode,
  container_kind : @cst.SyntaxKind,
  ordering : @cst.ChildOrdering,
  signature : String?,
  leading_trivia : Array[@cst.Trivia],
  trailing_trivia : Array[@cst.Trivia],
  had_trailing_comma : Bool,
  default_entry_indent : String,
  multiline : Bool,
  events : Array[ResolutionEvent],
) -> @cst.CstNode {
  let children : Array[@cst.CstNode] = [open_delim]
  let n = entries.length()
  let mut synthesized_comma = false

  for i = 0; i < n; i = i + 1 {
    let mut entry = entries[i]
    // Ensure clean leading trivia for newly woven entries
    if multiline {
      let lead_str = @cst.render_trivia(entry.leading_trivia)
      if i == 0 {
        let open_str = @cst.render_trivia(open_delim.trailing_trivia)
        if !open_str.contains("\n") && !lead_str.contains("\n") {
          let new_lead : Array[@cst.Trivia] = [
            @cst.Trivia::newline(),
            @cst.Trivia::spaces(default_entry_indent),
          ]
          for t in entry.leading_trivia {
            if t.has_comment() {
              new_lead.push(t)
            }
          }
          entry = entry.with_trivia(leading_trivia=new_lead)
        }
      } else if !lead_str.contains("\n") &&
        !@cst.render_trivia(children[children.length() - 1].trailing_trivia).contains(
          "\n",
        ) {
        let new_lead : Array[@cst.Trivia] = [
          @cst.Trivia::spaces(default_entry_indent),
        ]
        for t in entry.leading_trivia {
          if t.kind != @cst.Whitespace {
            new_lead.push(t)
          }
        }
        entry = entry.with_trivia(leading_trivia=new_lead)
      }
    } else if i > 0 && entry.leading_trivia.is_empty() {
      entry = entry.with_trivia(leading_trivia=[@cst.Trivia::spaces(" ")])
    }

    // If an entry is a ConflictBlock, its markers must end with `\n`; don't append `,` inside marker!
    let is_last = i == n - 1
    let need_comma = (!is_last || had_trailing_comma) &&
      entry.kind != @cst.ConflictBlock
    if need_comma {
      // Strip trailing newline from `entry` so `,` sits right after the value on the same line,
      // then move `entry`'s trailing comment/newline onto `,`!
      let entry_trail = entry.trailing_trivia
      entry = entry.with_trivia(trailing_trivia=[])
      children.push(entry)
      let comma_trail = if !entry_trail.is_empty() {
        entry_trail
      } else if multiline {
        [@cst.Trivia::newline()]
      } else {
        []
      }
      children.push(
        @cst.CstNode::leaf(
          id=0,
          @cst.Punctuation,
          ",",
          trailing_trivia=comma_trail,
        ),
      )
      if !is_last {
        synthesized_comma = true
      }
    } else {
      children.push(entry)
    }
  }

  // Ensure closing `}` has newline before it when multiline and last child didn't end with `\n`
  let mut final_close = close_delim
  if multiline && n > 0 {
    let close_lead = @cst.render_trivia(final_close.leading_trivia)
    let prev_trail = @cst.render_trivia(
      children[children.length() - 1].trailing_trivia,
    )
    if !close_lead.contains("\n") && !prev_trail.contains("\n") {
      let updated_lead : Array[@cst.Trivia] = [@cst.Trivia::newline()]
      for t in final_close.leading_trivia {
        updated_lead.push(t)
      }
      final_close = final_close.with_trivia(leading_trivia=updated_lead)
    }
  }
  children.push(final_close)

  if synthesized_comma && n >= 2 {
    events.push({
      kind: CommaSeparatorSynthesized,
      target: signature.unwrap_or(container_kind.label()),
      detail: "Normalized comma separators across woven commutative entries",
    })
  }

  @cst.CstNode::interior(
    id=0,
    container_kind,
    children,
    ordering~,
    signature~,
    leading_trivia~,
    trailing_trivia~,
  )
}

///|
/// Ensure MoonBit `///|` top-level declaration blocks maintain clean `///|` block separators
/// when new declarations from both branches are woven together.
pub fn normalize_moonbit_block_separators(
  blocks : Array[@cst.CstNode],
  uses_block_sep : Bool,
) -> Array[@cst.CstNode] {
  if !uses_block_sep || blocks.is_empty() {
    return blocks
  }
  let out : Array[@cst.CstNode] = Array(capacity=blocks.length())
  for i = 0; i < blocks.length(); i = i + 1 {
    let blk = blocks[i]
    if blk.kind == @cst.ConflictBlock {
      out.push(blk)
      continue
    }
    let has_sep = blk.leading_trivia
      .iter()
      .any(fn(t) { t.kind == @cst.BlockSeparator })
    if i == 0 &&
      blk.leading_trivia.length() >= 2 &&
      blk.leading_trivia[0].kind == @cst.Newline &&
      blk.leading_trivia[1].kind == @cst.BlockSeparator {
      let trimmed_lead : Array[@cst.Trivia] = []
      for k = 1; k < blk.leading_trivia.length(); k = k + 1 {
        trimmed_lead.push(blk.leading_trivia[k])
      }
      out.push(blk.with_trivia(leading_trivia=trimmed_lead))
    } else if i > 0 && !has_sep {
      let prev_txt = out[out.length() - 1].unparse()
      let prefix_nl = if prev_txt.has_suffix("\n\n") {
        ""
      } else if prev_txt.has_suffix("\n") {
        "\n"
      } else {
        "\n\n"
      }
      let new_lead : Array[@cst.Trivia] = []
      if !prefix_nl.is_empty() {
        new_lead.push(@cst.Trivia::newline(text=prefix_nl))
      }
      new_lead.push(@cst.Trivia::block_sep())
      for t in blk.leading_trivia {
        // Skip redundant leading blank lines before synthesized `///|`
        if t.kind != @cst.Newline || !new_lead.is_empty() {
          if t.has_comment() || t.kind == @cst.Whitespace {
            new_lead.push(t)
          }
        }
      }
      out.push(blk.with_trivia(leading_trivia=new_lead))
    } else {
      out.push(blk)
    }
  }
  out
}

///|
/// Build a `ConflictBlock` CST leaf from Base, Left, and Right text snippets.
pub fn make_conflict_node(
  base_text : String,
  left_text : String,
  right_text : String,
  options : MergeOptions,
  leading_trivia~ : Array[@cst.Trivia] = [],
) -> (@cst.CstNode, Int32) {
  let b_lines = @diff3.split_lines_lossless(base_text)
  let l_lines = @diff3.split_lines_lossless(left_text)
  let r_lines = @diff3.split_lines_lossless(right_text)
  let (rendered, count) = @diff3.render_hunks(
    [@diff3.Conflict(base=b_lines, left=l_lines, right=r_lines)],
    options.style,
    options.labels,
  )
  (
    @cst.CstNode::leaf(
      id=0,
      @cst.ConflictBlock,
      rendered,
      leading_trivia~,
      has_error=true,
    ),
    count,
  )
}
