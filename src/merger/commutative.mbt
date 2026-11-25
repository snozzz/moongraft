///|
/// Decompose a container's children into `(optional_open_punct,optional_header, semantic_items, optional_close_punct, had_trailing_comma)`.
priv struct ContainerParts {
  open_punct : @cst.CstNode?
  header_node : @cst.CstNode?
  items : Array[@cst.CstNode]
  close_punct : @cst.CstNode?
  had_trailing_comma : Bool
}

///|
fn split_container_parts(node : @cst.CstNode) -> ContainerParts {
  let cs = node.children
  let n = cs.length()
  if n == 0 {
    return {
      open_punct: None,
      header_node: None,
      items: [],
      close_punct: None,
      had_trailing_comma: false,
    }
  }

  let mut start = 0
  let mut end = n
  let mut open_punct : @cst.CstNode? = None
  let mut header_node : @cst.CstNode? = None
  let mut close_punct : @cst.CstNode? = None

  // Check `{` / `[` or `import {` (`Keyword` on `ImportGroup`!)
  if (
      node.kind == @cst.ObjectNode ||
      node.kind == @cst.ArrayNode ||
      node.kind == @cst.Block
    ) &&
    cs[0].kind == @cst.Punctuation &&
    (cs[0].text == "{" || cs[0].text == "[") {
    open_punct = Some(cs[0])
    start = 1
  } else if node.kind == @cst.ImportGroup && cs[0].kind == @cst.Keyword {
    open_punct = Some(cs[0])
    start = 1
  } else if (
      node.kind == @cst.TableSection ||
      node.kind == @cst.ArrayOfTablesSection ||
      node.kind == @cst.ClassDecl
    ) &&
    cs[0].kind == @cst.Keyword {
    header_node = Some(cs[0])
    start = 1
  }

  if end > start &&
    cs[end - 1].kind == @cst.Punctuation &&
    (
      cs[end - 1].text == "}" ||
      cs[end - 1].text == "]" ||
      cs[end - 1].text.has_prefix("}")
    ) {
    close_punct = Some(cs[end - 1])
    end -= 1
  }

  let items : Array[@cst.CstNode] = []
  let mut last_non_close_was_comma = false
  for i = start; i < end; i = i + 1 {
    if cs[i].kind == @cst.Punctuation && cs[i].text == "," {
      // Preserve any inline comment on `,` by attaching it to the preceding item's trailing trivia!
      if !items.is_empty() && !cs[i].trailing_trivia.is_empty() {
        let prev = items.pop().unwrap()
        let merged_trail = prev.trailing_trivia.copy()
        for t in cs[i].trailing_trivia {
          merged_trail.push(t)
        }
        items.push(prev.with_trivia(trailing_trivia=merged_trail))
      }
      last_non_close_was_comma = true
    } else {
      items.push(cs[i])
      last_non_close_was_comma = false
    }
  }

  {
    open_punct,
    header_node,
    items,
    close_punct,
    had_trailing_comma: last_non_close_was_comma,
  }
}

