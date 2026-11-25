///|
fn io_read_file(path : String) -> Result[String, String] {
  Err(
    "Filesystem access requires JS/Node CLI runner (`bin/moongraft`); attempted path: " +
    path,
  )
}

///|
fn io_write_file(path : String, _content : String) -> Result[Unit, String] {
  Err(
    "Filesystem write requires JS/Node CLI runner (`bin/moongraft`); attempted path: " +
    path,
  )
}

///|
fn io_print_raw(text : String) -> Unit {
  println(text)
}

///|
fn io_eprintln(text : String) -> Unit {
  println(text)
}

///|
fn maybe_init_browser_mode() -> Bool {
  false
}
