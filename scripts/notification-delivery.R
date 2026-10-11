# Injected transport/journal functions keep delivery policy testable offline.
notification_deliver <- function(body, graph, date, attempt, record_daily,
                                 post, journal, save_receipt) {
  if (nchar(body, type = "chars") > 1024L) stop("Notification exceeds 1024 characters", call. = FALSE)
  if (is.na(file.info(graph)$size) || file.info(graph)$size > 5 * 1024^2)
    stop("Attachment exceeds 5 MiB", call. = FALSE)
  if (record_daily) journal("pending")
  response <- tryCatch(post(), error = function(e)
    stop("Pushover response uncertain; review pending attempt, do not resend", call. = FALSE))
  if (!is.list(response) || !is.numeric(response$http_status) || length(response$http_status) != 1L)
    stop("Pushover acceptance is ambiguous; do not resend", call. = FALSE)
  code <- response$http_status
  receipt <- response$payload
  if (code >= 400L && code < 500L && is.list(receipt) && identical(receipt$status, 0L)) {
    if (record_daily) journal("rejected")
    stop("Pushover explicitly rejected delivery; fix configuration before a later invocation", call. = FALSE)
  }
  if (code != 200L || !is.list(receipt) || !identical(receipt$status, 1L) ||
      !is.character(receipt$request) || length(receipt$request) != 1L ||
      nchar(receipt$request) > 300L || !grepl("^[A-Za-z0-9_-]+$", receipt$request))
    stop("Pushover acceptance is ambiguous; review pending attempt, do not resend", call. = FALSE)
  result <- list(status = 1L, request = receipt$request, date = date, slot = "morning",
                 attempt = if (nzchar(attempt)) attempt else "manual", record_daily = record_daily)
  save_receipt(result)
  if (record_daily) journal("accepted")
  invisible(result)
}
