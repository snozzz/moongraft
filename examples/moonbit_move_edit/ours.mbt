///|
pub fn compute_checksum(seed : Int, step : Int) -> Int {
  let acc = seed + step
  acc * 31
}

///|
pub fn parse_header(line : String) -> String {
  line.trim().to_owned()
}

///|
pub fn format_digest(v : Int) -> String {
  "digest:" + v.to_string()
}
