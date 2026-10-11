#!/usr/bin/env Rscript
# Offline only: Rscript --vanilla tests/data/test-api-retry.R
source("R/utils.R")
checks <- 0L
check <- function(condition, label) {
  if (!isTRUE(condition)) stop("FAIL: ", label, call. = FALSE)
  checks <<- checks + 1L
}
same <- function(actual, expected, label) check(isTRUE(all.equal(actual, expected)), label)
now <- utc_time("2026-10-11T10:00:00Z")
clock <- function() now

run_requests <- function(responses, ...) {
  calls <- 0L
  pauses <- numeric()
  result <- tryCatch(api_get_json("https://offline.invalid", ...,
    request = function(url, query, timeout) {
      calls <<- calls + 1L
      if (calls > length(responses)) stop("Unexpected extra request")
      responses[[calls]]
    }, sleep = function(seconds) pauses <<- c(pauses, seconds), clock = clock), error = identity)
  list(result = result, calls = calls, pauses = pauses)
}
ok <- list(status = 200L, payload = list(ok = TRUE))
rate_limit <- function(value) list(status = 429L, retry_after = value,
  body = "SECRET-BODY-DO-NOT-LOG")

# Long delays, including a far-future server clock, fail on the first response.
for (value in c("60", "3600", strrep("9", 400L),
                "Sun, 11 Oct 2026 10:00:03 GMT", "Sun, 11 Oct 2099 10:00:00 GMT")) {
  test <- run_requests(list(rate_limit(value), ok))
  check(inherits(test$result, "error"), "long Retry-After fails")
  check(grepl("rate limit.*429.*Retry-After.*short pause cap", conditionMessage(test$result)), "informative rate limit error")
  check(!grepl("SECRET|2099", conditionMessage(test$result)), "no response body or raw header logs")
  check(test$calls == 1L && length(test$pauses) == 0L, "long delay makes one GET and zero sleeps")
}
test <- run_requests(list(rate_limit("60")), attempts = 1L)
check(grepl("Retry-After", conditionMessage(test$result)), "long-delay explanation even on last attempt")
check(test$calls == 1L && length(test$pauses) == 0L, "single-attempt long delay never sleeps")

# Valid short delays respect the server minimum and the configured short cap.
test <- run_requests(list(rate_limit("2"), ok))
same(test$result, list(ok = TRUE), "short-delay success")
same(test$pauses, 2, "Retry-After within cap is honored")
check(test$calls == 2L, "one short-delay retry")
test <- run_requests(list(rate_limit("1"), rate_limit("2"), ok))
same(test$pauses, c(1, 2), "short delays remain bounded across attempts")
check(test$calls == 3L, "retry attempt cap retained")
test <- run_requests(list(rate_limit("3"), ok), pause_cap = 3)
same(test$pauses, 3, "custom short cap accepted at boundary")
test <- run_requests(list(rate_limit("1"), ok), pause_cap = 0)
check(inherits(test$result, "error") && test$calls == 1L && !length(test$pauses), "zero cap rejects positive delay")
test <- run_requests(list(rate_limit("0"), ok), pause_cap = 0)
same(test$pauses, 0, "zero delay allowed with zero cap")
test <- run_requests(list(rate_limit("2"), rate_limit("2"), rate_limit("2")))
check(inherits(test$result, "error") && test$calls == 3L, "persistent short rate limit stops at attempt cap")
same(test$pauses, c(2, 2), "final attempt never sleeps")

# HTTP dates parse in UTC without changing locale, waiting for clocks, or polling.
same(parse_retry_after("Sun, 11 Oct 2026 10:00:02 GMT", now), 2, "HTTP date future delay")
same(parse_retry_after("Sun, 11 Oct 2026 09:59:59 GMT", now), 0, "HTTP date past delay clamps to zero")
same(parse_retry_after("Sun, 11 Oct 2026 10:00:00 GMT", now), 0, "HTTP date current time")
test <- run_requests(list(rate_limit("Sun, 11 Oct 2026 10:00:02 GMT"), ok))
same(test$pauses, 2, "HTTP date retry respects acceptable delay")
same(test$result, list(ok = TRUE), "HTTP date retry success")
test <- run_requests(list(rate_limit("Sun, 11 Oct 2026 09:00:00 GMT"), ok))
same(test$pauses, 1, "past date retains ordinary backoff")
same(parse_retry_after(" 2 ", now), 2, "header whitespace trimmed")
same(parse_retry_after(2L, now), 2, "numeric injected header compatible")

# Absent/malformed headers retain the existing short retry behavior.
malformed <- list(NULL, "", "bad-date", "-1", "1.5", "Inf", "NaN", NA_character_,
  c("1", "2"), list("1"), "Sun, 31 Feb 2026 10:00:00 GMT", "Sun, 11 Oct 2026 25:00:00 GMT")
for (value in malformed) {
  check(is.na(parse_retry_after(value, now)), "malformed header rejected")
  test <- run_requests(list(rate_limit(value), ok))
  same(test$result, list(ok = TRUE), "malformed header uses ordinary retry")
  same(test$pauses, 1, "malformed header cannot cause long sleep")
}
test <- run_requests(list(list(status = 503L), list(status = 429L), ok))
same(test$result, list(ok = TRUE), "existing injected responses without headers still work")
same(test$pauses, c(1, 2), "existing backoff preserved")
test <- run_requests(list(list(status = 403L, retry_after = "60")))
check(inherits(test$result, "error") && grepl("403", conditionMessage(test$result)), "403 remains terminal")
check(test$calls == 1L && !length(test$pauses), "403 never sleeps or retries")
test <- run_requests(list(list(status = 503L, retry_after = "60"), ok))
same(test$pauses, 1, "Retry-After handling scoped to HTTP 429")
cat("PASS: ", checks, " offline API retry assertions; no network or real sleeps\n", sep = "")
