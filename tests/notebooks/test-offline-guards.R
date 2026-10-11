# Run in a clean disposable R session because traces intentionally persist.
source("tests/notebooks/helpers.R")
install_offline_guards()
expect_blocked <- function(expression) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  notebook_assert(inherits(error, "error") &&
                    grepl("forbids network access and external commands", conditionMessage(error), fixed = TRUE),
                  "offline guard did not block the attempted external call")
}
expect_blocked(base::url("https://example.invalid"))
expect_blocked(utils::download.file("https://example.invalid", tempfile()))
expect_blocked(base::socketConnection(host = "127.0.0.1", port = 9L))
expect_blocked(base::system2("true"))
if (requireNamespace("httr", quietly = TRUE)) {
  expect_blocked(httr::GET("https://example.invalid"))
  expect_blocked(httr::POST("https://example.invalid"))
}
if (requireNamespace("curl", quietly = TRUE)) {
  expect_blocked(curl::curl_fetch_memory("https://example.invalid"))
}
cat("PASS offline guards reject HTTP, downloads, sockets and external commands\n")
