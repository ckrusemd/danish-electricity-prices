source("scripts/notification-content.R")
source("scripts/notification-delivery.R")
assert_error <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  stopifnot(inherits(error, "error"), grepl(pattern, conditionMessage(error)))
}

fixture <- function(day = "2026-10-11") {
  start <- as.POSIXct(paste(day, "00:00:00"), tz = "Europe/Copenhagen")
  end <- as.POSIXct(paste(as.Date(day) + 1L, "00:00:00"), tz = "Europe/Copenhagen")
  utc <- seq(start, end - 900, by = 900)
  attr(utc, "tzone") <- "UTC"
  local <- utc
  attr(local, "tzone") <- "Europe/Copenhagen"
  quarter <- data.frame(TimeUTC = utc, TimeDK = local, PriceArea = "DK2", SpotPriceDKK = sin(seq_along(utc)/10) / 3)
  profile <- expand.grid(minute = c(0L, 15L, 30L, 45L), hour = 0:23)
  profile$q25 <- -0.1
  profile$median <- 0.1
  profile$q75 <- 0.4
  summary <- list(quarter_today = quarter,
    period_averages = data.frame(label = c("00-06", "06-09", "09-17", "17-21", "21-24"), average = c(-0.1, 0.2, 0.3, 0.4, 0.5)),
    upcoming_window = data.frame(start = start + 5*3600, end = start + 8*3600, average = 0.1, total = 0.3),
    historical_window = data.frame(start = start - 100*86400, end = start - 100*86400 + 10800, average = -0.2, total = -0.6),
    history_profile = profile)
  coverage <- list(upcoming = list(complete = TRUE), history = list(complete = TRUE))
  list(schema_version = 1L, date = day, summaries = list(DK1 = summary, DK2 = summary),
       meta = list(coverage = list(prices = list(DK1 = coverage, DK2 = coverage))))
}
snapshot <- fixture()
body <- notification_body(snapshot)
stopifnot(!grepl("DK1|West|;", body), grepl("East Denmark (DK2)", body, fixed = TRUE),
          grepl("00-06: -0.10\n06-09: 0.20", body, fixed = TRUE))
# DK1 must never affect the notification or attachment.
snapshot$summaries$DK1 <- NULL
snapshot$meta$coverage$prices$DK1 <- NULL
stopifnot(identical(body, notification_body(snapshot)))
stopifnot(nchar(body) <= 1024L, grepl("0.30 DKK/kWh above", body, fixed = TRUE),
          all(vapply(c("00-06", "06-09", "09-17", "17-21", "21-24", "6-month low"), grepl, logical(1), x = body, fixed = TRUE)))
snapshot$summaries$DK2$upcoming_window <- snapshot$summaries$DK2$upcoming_window[FALSE, ]
stopifnot(grepl("Unavailable", notification_body(snapshot)))
snapshot <- fixture()
snapshot$meta$coverage$prices$DK2$upcoming$complete <- FALSE
snapshot$meta$coverage$prices$DK2$history$complete <- FALSE
stopifnot(grepl("Best published 3 hours (provisional)", notification_body(snapshot), fixed = TRUE),
          grepl("Incomplete history", notification_body(snapshot), fixed = TRUE),
          grepl("11/10", notification_body(snapshot), fixed = TRUE))
partial <- fixture()
partial$summaries$DK2$period_averages$average[1] <- NA_real_
stopifnot(grepl("00-06: Unavailable", notification_body(partial), fixed = TRUE))
for (day in c("2026-03-29", "2026-10-25", "2026-10-11")) {
  snapshot <- fixture(day)
  expected <- c("2026-03-29" = 92L, "2026-10-25" = 100L, "2026-10-11" = 96L)[[day]]
  stopifnot(nrow(snapshot$summaries$DK2$quarter_today) == expected,
            all(diff(as.numeric(snapshot$summaries$DK2$quarter_today$TimeUTC)) == 900))
  snapshot$summaries$DK1 <- NULL
  graph <- notification_graph(snapshot)
  stopifnot(file.info(graph)$size > 1000, file.info(graph)$size <= 5 * 1024^2)
  unlink(graph)
}

graph <- tempfile(fileext = ".png")
writeBin(as.raw(1:10), graph)
events <- character()
post <- function() { events <<- c(events, "POST"); list(http_status = 200L, payload = list(status = 1L, request = "confirmed")) }
journal <- function(command) { events <<- c(events, command) }
save <- function(receipt) { events <<- c(events, "save"); stopifnot(receipt$date == "2026-10-11") }
send <- function(post_fn = post, journal_fn = journal, daily = TRUE, message = "fixture")
  notification_deliver(message, graph, "2026-10-11", "123-1", daily, post_fn, journal_fn, save)
send()
stopifnot(identical(events, c("pending", "POST", "save", "accepted")))
events <- character()
send(daily = FALSE)
stopifnot(identical(events, c("POST", "save")))
events <- character()
assert_error(send(journal_fn = function(x) stop("failed state write")), "failed state write")
stopifnot(length(events) == 0L)
events <- character()
assert_error(send(post_fn = function() { events <<- c(events, "POST"); stop("lost HTTP response") }), "uncertain")
stopifnot(identical(events, c("pending", "POST")))
events <- character()
assert_error(send(post_fn = function() { events <<- c(events, "POST"); list(http_status = 400L, payload = list(status = 0L)) }), "explicitly rejected")
stopifnot(identical(events, c("pending", "POST", "rejected")))
events <- character()
assert_error(send(journal_fn = function(x) { journal(x); if (x == "accepted") stop("record failed") }), "record failed")
stopifnot(identical(events, c("pending", "POST", "save", "accepted")))
events <- character()
assert_error(send(message = paste(rep("x", 1025), collapse = "")), "1024")
stopifnot(length(events) == 0L)
unlink(graph)
cat("Notification text, DST graphs, single POST policy, rejection, receipt ordering, and manual-force tests passed\n")
