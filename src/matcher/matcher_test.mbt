///|
test "gumtree matches moved and modified MoonBit functions accurately" {
  let old_mbt =
    #|///|
    #|pub fn alpha() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|pub fn beta(x : Int) -> Int {
    #|  let y = x + 1
    #|  y * 2
    #|}
    #|
  let new_mbt =
    #|///|
    #|pub fn beta(x : Int) -> Int {
    #|  let y = x + 10
    #|  y * 2
    #|}
    #|
    #|///|
    #|pub fn alpha() -> Int {
    #|  1
    #|}
    #|
    #|///|
    #|pub fn gamma() -> Bool {
    #|  true
    #|}
    #|
  // Build CSTs directly via `@cst` or test matcher invariants
  let a1 = @cst.CstNode::leaf(
    id=1,
    @cst.FnDecl,
    "pub fn alpha() -> Int { 1 }\n",
    signature=Some("fn:alpha"),
    span=@cst.ByteSpan::new(0, 28),
  )
  let b1 = @cst.CstNode::leaf(
    id=2,
    @cst.FnDecl,
    "pub fn beta(x : Int) -> Int { x + 1 }\n",
    signature=Some("fn:beta"),
    span=@cst.ByteSpan::new(29, 67),
  )
  let root1 = @cst.CstNode::interior(
    id=0,
    @cst.SourceFile,
    [a1, b1],
    ordering=@cst.CommutativeBlocks,
  )

  let b2 = @cst.CstNode::leaf(
    id=1,
    @cst.FnDecl,
    "pub fn beta(x : Int) -> Int { x + 10 }\n",
    signature=Some("fn:beta"),
    span=@cst.ByteSpan::new(0, 39),
  )
  let a2 = @cst.CstNode::leaf(
    id=2,
    @cst.FnDecl,
    "pub fn alpha() -> Int { 1 }\n",
    signature=Some("fn:alpha"),
    span=@cst.ByteSpan::new(40, 68),
  )
  let g2 = @cst.CstNode::leaf(
    id=3,
    @cst.FnDecl,
    "pub fn gamma() -> Bool { true }\n",
    signature=Some("fn:gamma"),
    span=@cst.ByteSpan::new(69, 100),
  )
  let root2 = @cst.CstNode::interior(
    id=0,
    @cst.SourceFile,
    [b2, a2, g2],
    ordering=@cst.CommutativeBlocks,
  )

  let edits = @matcher.summarize_structural_diff(old_mbt, root1, new_mbt, root2)
  assert_true(
    edits
    .iter()
    .any(fn(e) {
      e.kind == @matcher.MovedAndModified && e.signature == Some("fn:beta")
    }),
  )
  assert_true(
    edits
    .iter()
    .any(fn(e) {
      e.kind == @matcher.Inserted && e.signature == Some("fn:gamma")
    }),
  )
}
