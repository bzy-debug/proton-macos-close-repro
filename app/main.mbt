///|
async fn main {
  @proton.html(
    "Proton Close Repro",
    "<h1>Proton close lifecycle</h1><p>Close this window using its red close button.</p>",
    width=640,
    height=360,
  )
  .load_config()
  .run_or_abort()
}
