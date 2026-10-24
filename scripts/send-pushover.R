#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
if (any(!args %in% c("--dry-run", "--fixture"))) stop("Usage: send-pushover.R [--dry-run] [--fixture]", call. = FALSE)
dry_run <- "--dry-run" %in% args
if ("--fixture" %in% args && !dry_run) stop("--fixture requires --dry-run", call. = FALSE)
if ("--fixture" %in% args) Sys.setenv(ELECTRICITY_FIXTURE = "true")
source("R/project.R")
source("scripts/notification-content.R")
source("scripts/notification-delivery.R")
snapshot <- load_or_prepare_analysis(include_weather = FALSE)
admitted_date <- Sys.getenv("NOTIFICATION_DATE", snapshot$date)
if (!identical(snapshot$date, admitted_date)) stop("Snapshot date differs from admitted Copenhagen date", call. = FALSE)
body <- notification_body(snapshot)
graph <- notification_graph(snapshot)
if (nchar(body, type = "chars") > 1024L) stop("Notification exceeds 1024 characters", call. = FALSE)
if (is.na(file.info(graph)$size) || file.info(graph)$size > 5 * 1024^2) stop("Attachment exceeds 5 MiB", call. = FALSE)
if (dry_run) {
  preview <- Sys.getenv("NOTIFICATION_PREVIEW_FILE", ".cache/notification-preview.png")
  dir.create(dirname(preview), recursive = TRUE, showWarnings = FALSE)
  if (!file.copy(graph, preview, overwrite = TRUE)) stop("Cannot save preview", call. = FALSE)
  unlink(graph)
  cat(body, "\nGraph: ", preview, "\n", sep = "")
  quit(status = 0L)
}
app_token <- Sys.getenv("PUSHOVER_APP_TOKEN")
user_key <- Sys.getenv("PUSHOVER_USER_KEY")
if (!nzchar(app_token) || !nzchar(user_key)) stop("Pushover secrets are not configured", call. = FALSE)
record_daily <- identical(Sys.getenv("NOTIFICATION_RECORD_DAILY", "true"), "true")
attempt <- Sys.getenv("NOTIFICATION_ATTEMPT")
if (record_daily && (!nzchar(attempt) || !nzchar(Sys.getenv("NOTIFICATION_DATE"))))
  stop("Admitted date and attempt are required", call. = FALSE)
state_command <- function(command, receipt = NULL) {
  cli_args <- c("scripts/notification-state.py", command)
  if (!is.null(receipt)) cli_args <- c(cli_args, "--receipt", shQuote(receipt))
  status <- system2("python3", cli_args)
  if (!identical(status, 0L)) stop("Notification journal update failed; no resend permitted", call. = FALSE)
}
result_path <- Sys.getenv("PUSHOVER_RESULT_FILE", "pushover-result.json")
notification_deliver(body, graph, admitted_date, attempt, record_daily,
  post = function() {
    response <- httr::POST("https://api.pushover.net/1/messages.json",
      body = list(token = app_token, user = user_key, message = body,
                  title = "East Denmark electricity · DK2", attachment = httr::upload_file(graph)),
      encode = "multipart", httr::timeout(30))
    payload <- tryCatch(jsonlite::fromJSON(httr::content(response, as = "text", encoding = "UTF-8")),
                        error = function(e) NULL)
    list(http_status = httr::status_code(response), payload = payload)
  },
  journal = function(command) state_command(command, if (command == "accepted") result_path else NULL),
  save_receipt = function(result) {
    temp_path <- paste0(result_path, ".tmp")
    jsonlite::write_json(result, temp_path, auto_unbox = TRUE)
    if (!file.rename(temp_path, result_path)) stop("Accepted receipt could not be saved; no resend permitted", call. = FALSE)
  })
unlink(graph)
message(if (record_daily) "Pushover accepted and daily delivery recorded" else "Pushover accepted; manual delivery has no daily record")
