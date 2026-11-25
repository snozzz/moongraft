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

