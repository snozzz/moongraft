///|
pub fn parse_header(line : String) -> String {
  line.trim().to_owned()
}

///|
pub fn compute_checksum(seed : Int, step : Int) -> Int {
  let acc = seed + step * 2
  acc * 31
}

///|
pub fn verify_digest(v : Int) -> Bool {
  v >= 0
}
