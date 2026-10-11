#!/usr/bin/env Rscript
# Offline regression suite. Run: Rscript --vanilla tests/data/test-data.R
source("R/project.R")
source("tests/fixtures/data-fixtures.R")
checks <- 0L
check <- function(condition, label) {
  if (!isTRUE(condition)) stop("FAIL: ", label, call. = FALSE)
  checks <<- checks + 1L
  invisible(TRUE)
}
same <- function(actual, expected, label) check(isTRUE(all.equal(actual, expected)), label)
scratch <- tempfile("electricity-data-tests-")
dir.create(scratch)

# The fixture path is completely offline, deterministic, and does not change RNG.
original_get <- api_get_json
api_get_json <- function(...) stop("fixture attempted network")
set.seed(21L)
rng <- .Random.seed
now <- fixture_reference_time()
snapshot <- prepare_analysis(now, fixture = TRUE, cache_dir = file.path(scratch, "unused"))
again <- prepare_analysis(now, fixture = TRUE, cache_dir = file.path(scratch, "unused"))
check(identical(snapshot, again), "fixed as-of snapshot is deterministic")
check(identical(snapshot, prepare_analysis(now + 0.5, fixture = TRUE)), "subsecond generation uses consistent ISO precision")
check(identical(rng, .Random.seed), "fixture preserves RNG state")
check(!dir.exists(file.path(scratch, "unused")), "fixture does not write caches")
api_get_json <- original_get
check(identical(snapshot$schema_version, 1L), "schema v1 integer")
check(identical(snapshot$generated_at, "2026-10-11T10:00:00Z"), "stable fixture as-of")
check(identical(snapshot$date, "2026-10-11"), "Copenhagen date")
check(nrow(snapshot$quarter_prices) == 35520L && nrow(snapshot$hourly_prices) == 8880L, "six months plus two current days")
check(any(snapshot$quarter_prices$SpotPriceDKK < 0), "realistic negative spot quarters")
check(length(unique(snapshot$quarter_prices$SpotPriceDKK)) > 1000L, "fixture has varied quarter prices")
check(nrow(snapshot$weather) == 720L && nrow(snapshot$heatmap) > 100L, "month weather and heatmap")
check(all(snapshot$heatmap$HourBand %in% 7:23), "heatmap target hours")
check(all(snapshot$heatmap$TemperatureBand %% 1 == 0), "one-degree heatmap bands")
check(identical(snapshot$meta$calculations$heatmap$low, "#062b5c") &&
      identical(snapshot$meta$calculations$heatmap$high, "#ffffff"), "heatmap consumer palette")
check(identical(names(snapshot$summaries), c("DK1", "DK2")), "named zone summaries")
for (zone in names(snapshot$summaries)) {
  summary <- snapshot$summaries[[zone]]
  check(nrow(summary$today) == 24L && nrow(summary$quarter_today) == 96L, paste(zone, "today rows"))
  check(nrow(summary$history_profile) == 96L, paste(zone, "96 quarter-slot overlay"))
  check(all(is.finite(as.matrix(summary$history_profile[c("q25", "median", "q75")]))), paste(zone, "complete overlay"))
  check(all(summary$history_profile$q25 <= summary$history_profile$median &
    summary$history_profile$median <= summary$history_profile$q75), paste(zone, "quantile ordering"))
  check(snapshot$meta$coverage$prices[[zone]]$overlay$expected == 2880L, paste(zone, "30 completed days"))
  check(snapshot$meta$coverage$prices[[zone]]$upcoming$complete, paste(zone, "complete upcoming fixture"))
  check(as.numeric(summary$upcoming_window$end - summary$upcoming_window$start, units = "secs") == 10800,
    paste(zone, "elapsed three-hour window"))
  same(summary$upcoming_window$total, summary$upcoming_window$average * 3, paste(zone, "window total"))
  check(as.numeric(summary$historical_window$end) <= as.numeric(now), paste(zone, "historical no future prices"))
}

# DST: complete Copenhagen days have 92, 96 or 100 UTC quarters, never merged.
for (case in list(c("2026-03-29", 92L, 23L), c("2026-07-01", 96L, 24L), c("2026-10-25", 100L, 25L))) {
  day <- as.Date(case[1L])
  quarters <- fixture_quarter_prices(day_start(day), day_start(day + 1L), "DK2")
  hourly <- derive_hourly_prices(quarters)
  check(nrow(quarters) == as.integer(case[2L]), paste(day, "quarter count"))
  check(nrow(hourly) == as.integer(case[3L]), paste(day, "hour count"))
  check(all(diff(as.numeric(hourly$HourUTC)) == 3600), paste(day, "UTC continuity"))
  check(quarter_day_coverage(quarters)$complete, paste(day, "complete day"))
  if (day == as.Date("2026-10-25")) {
    check(sum(format(hourly$HourDK, "%H", tz = electricity_timezone) == "02") == 2L, "both autumn 02 hours retained")
    check(length(unique(format(hourly$HourDK, "%z", tz = electricity_timezone))) == 2L, "autumn offsets distinct")
  }
}
same(six_months_before(as.Date("2026-08-31")), as.Date("2026-02-28"), "calendar-month clamp")
same(local_day(utc_time("2026-10-10T23:30:00Z")), as.Date("2026-10-11"), "local day across UTC midnight")

start <- day_start("2026-10-25")
end <- day_start("2026-10-26")
small <- fixture_quarter_prices(start, end, "DK1")
missing <- small[-3L, , drop = FALSE]
check(nrow(derive_hourly_prices(missing)) == 24L, "incomplete hour not averaged")
check(!price_range_coverage(missing, start, end)$complete, "missing quarter coverage explicit")
check(price_range_coverage(missing, start, end)$missing == 1L, "missing quarter count")
bad <- small[c(seq_len(nrow(small)), 1L), , drop = FALSE]
expect_error(validate_quarter_prices(bad), "Duplicate")
bad <- small; bad$TimeUTC[1L] <- bad$TimeUTC[1L] + 1
expect_error(validate_quarter_prices(bad), "timestamps")
bad <- small; bad$TimeDK[1L] <- bad$TimeDK[1L] + 900
expect_error(validate_quarter_prices(bad), "alignment")
bad <- small; bad$SpotPriceDKK[1L] <- NA_real_
expect_error(validate_quarter_prices(bad), "values")
bad <- small; bad$SpotPriceDKK[1L] <- Inf
expect_error(validate_quarter_prices(bad), "values")
bad <- small; bad$PriceArea[1L] <- "DE"
expect_error(validate_quarter_prices(bad), "zone")
expect_error(validate_quarter_prices(small[nrow(small):1L, ]), "sorted")
bad <- small; attr(bad$TimeUTC, "tzone") <- "Europe/Copenhagen"
expect_error(validate_quarter_prices(bad), "UTC")

# Consumer unit regression and tariff bands use Copenhagen independently of host TZ.
tariff_times <- dk_time(utc_time(c("2026-01-01T04:00:00Z", "2026-01-01T05:00:00Z",
  "2026-01-01T16:00:00Z", "2026-01-01T20:00:00Z", "2026-07-01T03:00:00Z",
  "2026-07-01T04:00:00Z", "2026-07-01T15:00:00Z", "2026-07-01T19:00:00Z")))
same(radius_tariff_incl_vat(tariff_times), c(12.20, 36.61, 109.85, 36.61, 13.27, 19.91, 51.76, 19.91), "tariff hour/season boundaries")
consumer <- apply_consumer_price_components(data.frame(HourDK = tariff_times, SpotPriceDKK = rep(1, 8L)))
same(consumer$SpotPriceDKK_Total_SansAfgiftTransport, rep(1.25, 8L), "spot has no extra /100")
same(consumer$SpotPriceDKK_Total - consumer$SpotPriceDKK_Total_SansAfgift, rep(0.01, 8L), "tax DKK and VAT")
same(consumer$SpotPriceDKK_Total[1L], 1.25 + 0.122 + 1.25 * 0.123 + 0.1463, "independent total units")

# Windows require three contiguous elapsed full hours and reject cross-zone mixes.
hours <- derive_hourly_prices(small)
hours$SpotPriceDKK <- seq_len(nrow(hours))
window <- cheapest_three_hour_window(hours)
same(as.numeric(window$start), as.numeric(hours$HourUTC[1L]), "earliest tie/minimum")
check(nrow(cheapest_three_hour_window(hours[1:2, ])) == 0L, "short horizon zero-row window")
check(nrow(cheapest_three_hour_window(hours[c(1L, 3L, 5L), ])) == 0L, "gap cannot form window")
check(nrow(cheapest_three_hour_window(hours[1:3, ], until = hours$HourUTC[3L] + 1800)) == 0L, "window cannot end past boundary")
expect_error(cheapest_three_hour_window(snapshot$hourly_prices), "single price zone")

# Pagination fetches each raw range/page once. No separate hourly request.
raw <- raw_price_fixture(start, start + 10800, "DK1")
queries <- list()
get_prices <- function(url, query) {
  queries[[length(queries) + 1L]] <<- query
  index <- seq.int(query$offset + 1L, min(query$offset + query$limit, nrow(raw)))
  list(records = raw[index, , drop = FALSE], total = nrow(raw))
}
fetched <- fetch_quarter_hour_prices("DK1", limit = 5L, start = start, end = start + 10800,
  require_future = FALSE, get_json = get_prices)
check(length(queries) == 3L, "one GET per pagination page")
same(vapply(queries, `[[`, integer(1), "offset"), c(0L, 5L, 10L), "page offsets")
check(all(vapply(queries, function(q) identical(q$timezone, "utc"), logical(1))), "API timezone UTC")
same(fetched$TimeUTC, utc_time(raw$TimeUTC), "raw UTC preserved")
same(fetched$TimeDK, dk_time(utc_time(raw$TimeUTC)), "display time derived from UTC, ignoring misleading local strings")
same(fetched$SpotPriceDKK, raw$DayAheadPriceDKK / 1000, "MWh conversion once")
queries <- list()
invisible(fetch_elspot_prices("DK1", limit = 5L, start = start, end = start + 10800,
  require_future = FALSE, get_json = get_prices))
check(length(queries) == 3L, "hourly wrapper derives from same raw pages")
expect_error(fetch_quarter_hour_prices("DK1", limit = 5L, require_future = FALSE,
  get_json = get_prices, max_pages = 1L), "page count")
expect_error(normalise_price_records(transform(raw, PriceArea = "DK2"), "DK1"), "zone")

# Bounded retry behavior, with no real network or waits.
calls <- 0L; pauses <- numeric()
retry_request <- function(url, query, timeout) {
  calls <<- calls + 1L
  list(status = c(503L, 429L, 200L)[calls], payload = list(ok = TRUE))
}
same(api_get_json("https://example.invalid", request = retry_request,
  sleep = function(x) pauses <<- c(pauses, x)), list(ok = TRUE), "retry result")
check(calls == 3L, "bounded three attempts")
same(pauses, c(1, 2), "bounded backoff")
calls <- 0L
expect_error(api_get_json("https://example.invalid", request = function(...) {
  calls <<- calls + 1L; list(status = 401L)
}, sleep = function(...) stop("must not wait")), "401")
check(calls == 1L, "auth/client errors not retried")
calls <- 0L
expect_error(api_get_json("https://example.invalid", request = function(...) {
  calls <<- calls + 1L; stop("transport")
}, sleep = function(...) NULL), "bounded retries")
check(calls == 3L, "transport failures bounded")
expect_error(api_get_json("https://example.invalid", attempts = 4L), "settings")
expect_error(api_get_json("https://example.invalid", attempts = 2.5), "settings")

# Historical cache is versioned; only newly completed days fetch on rollover.
calls <- list()
fetch_history <- function(price_area, start, end, ...) {
  calls[[length(calls) + 1L]] <<- list(start = start, end = end)
  fixture_quarter_prices(start, end, price_area)
}
cache_dir <- file.path(scratch, "cache")
cache_start <- day_start("2026-10-01"); cache_end <- day_start("2026-10-03")
first <- load_historical_prices("DK1", cache_start, cache_end, cache_dir, fetch_history)
second <- load_historical_prices("DK1", cache_start, cache_end, cache_dir, fetch_history)
check(length(calls) == 1L, "cached history fetched once")
same(first, second, "historical cache data unchanged")
invisible(load_historical_prices("DK1", cache_start + 86400, cache_end + 86400, cache_dir, fetch_history))
check(length(calls) == 2L, "rollover fetches only tail")
same(calls[[2L]], list(start = cache_end, end = cache_end + 86400), "nonoverlapping incremental range")
cache_file <- file.path(cache_dir, "v1-prices-DK1.rds")
cached <- readRDS(cache_file); cached$cache_version <- 0L; saveRDS(cached, cache_file)
invisible(load_historical_prices("DK1", cache_start, cache_end, cache_dir, fetch_history))
check(length(calls) == 3L, "invalid cache version refetched")
expect_error(load_historical_prices("DK2", cache_start, cache_end, cache_dir,
  function(price_area, start, end, ...) fixture_quarter_prices(start, end, price_area)[-1L, ]), "Incomplete historical")

# One weather request in UTC; joins exactly and never shift timestamps.
weather_queries <- list()
get_weather <- function(url, query) {
  weather_queries[[length(weather_queries) + 1L]] <<- list(url = url, query = query)
  time <- utc_time(seq(as.numeric(utc_time(paste0(query$start_date, "T00:00:00"))),
    as.numeric(utc_time(paste0(query$end_date, "T23:00:00"))), by = 3600))
  list(utc_offset_seconds = 0L, hourly = list(time = format(time, "%Y-%m-%dT%H:%M", tz = "UTC"),
    temperature_2m = rep(10.5, length(time)), relative_humidity_2m = rep(80, length(time))))
}
weather <- fetch_historical_weather_open_meteo("2026-10-01", "2026-10-30", get_json = get_weather)
check(length(weather_queries) == 1L, "single month weather GET")
check(identical(weather_queries[[1L]]$query$timezone, "UTC"), "weather query UTC")
check(identical(weather_queries[[1L]]$url, weather_endpoint), "historical forecast endpoint")
check(nrow(weather) == 721L, "DST month weather elapsed hours")
small_hours <- apply_consumer_price_components(derive_hourly_prices(small))
matched_weather <- fixture_weather(start, end)
matched_weather$TemperatureC <- rep(10.5, nrow(matched_weather))
heatmap <- build_heatmap(small_hours, matched_weather, start, end)
check(sum(heatmap$Observations) == 17L, "exact target-hour joins")
for (hour in 7:23) same(heatmap$ConsumerPriceDKK[heatmap$HourBand == hour],
  small_hours$SpotPriceDKK_Total[as.integer(format(small_hours$HourDK, "%H", tz = electricity_timezone)) == hour], paste("consumer heatmap hour", hour))
shifted <- matched_weather
shifted$TimeUTC <- shifted$TimeUTC + 7 * 86400
shifted$HourDK <- dk_time(shifted$TimeUTC)
check(nrow(build_heatmap(small_hours, shifted, start, end)) == 0L, "no offset rescue of unmatched weather")
weather_calls <- 0L
weather_fetch <- function(start, end, config) {
  weather_calls <<- weather_calls + 1L
  fixture_weather(day_start(start), day_start(as.Date(end) + 1L))
}
invisible(load_historical_weather("2026-10-01", "2026-10-30", cache_dir, fetch = weather_fetch))
invisible(load_historical_weather("2026-10-01", "2026-10-30", cache_dir, fetch = weather_fetch))
check(weather_calls == 1L, "weather raw input cached")

# Serialization validates fields, calculations, coverage and UTC joins on read.
path <- file.path(scratch, "snapshot.rds")
write_rds_atomic(snapshot, path)
check(identical(read_analysis(path), snapshot), "RDS round trip")
for (field in c("schema_version", "date", "hourly", "summary", "coverage", "weather", "scenario")) {
  bad <- snapshot
  if (field == "schema_version") bad$schema_version <- 2L
  if (field == "date") bad$date <- "2026-10-10"
  if (field == "hourly") bad$hourly_prices$SpotPriceDKK[1L] <- 50
  if (field == "summary") bad$summaries$DK1$upcoming_window$average <- 50
  if (field == "coverage") bad$meta$coverage$prices$DK1$upcoming$complete <- FALSE
  if (field == "weather") bad$meta$coverage$weather$observed <- 1L
  if (field == "scenario") bad$meta$scenario$vat <- 1
  write_rds_atomic(bad, file.path(scratch, "bad.rds"))
  expect_error(read_analysis(file.path(scratch, "bad.rds")))
}
without <- prepare_analysis(now, fixture = TRUE, include_weather = FALSE)
check(is.null(without$weather) && nrow(without$heatmap) == 0L, "without weather snapshot")
check(identical(without$meta$coverage$weather$status, "skipped"), "without weather explicitly skipped")
Sys.setenv(ELECTRICITY_DATA_FILE = path, ELECTRICITY_FIXTURE = "true")
check(identical(load_or_prepare_analysis(FALSE), snapshot), "consumer uses configured RDS, preserving its weather")
Sys.setenv(ELECTRICITY_DATA_FILE = file.path(scratch, "not-found.rds"))
expect_error(load_or_prepare_analysis(), "does not exist")
Sys.unsetenv("ELECTRICITY_DATA_FILE")
check(identical(load_or_prepare_analysis(FALSE), without), "environment fixture uses deterministic as-of")
Sys.unsetenv("ELECTRICITY_FIXTURE")

# Partial upcoming publication is valid and explicitly provisional, not fabricated.
original_fetch <- fetch_quarter_hour_prices
original_history <- load_historical_prices
fetch_quarter_hour_prices <- function(price_area, start, end, ...) {
  fixture_quarter_prices(start, start + 3600, price_area)
}
load_historical_prices <- function(price_area, start, end, ...) fixture_quarter_prices(start, end, price_area)
partial <- prepare_analysis(now, fixture = FALSE, include_weather = FALSE, cache_dir = cache_dir)
check(!partial$meta$coverage$prices$DK1$upcoming$complete, "unpublished next hours incomplete")
check(partial$meta$coverage$prices$DK1$upcoming$observed == 0L, "no invented future prices")
check(nrow(partial$summaries$DK1$upcoming_window) == 0L, "unavailable upcoming window zero rows")
check(partial$meta$coverage$prices$DK1$upcoming$window_provisional, "provisional window flag")
fetch_quarter_hour_prices <- original_fetch
load_historical_prices <- original_history

# The complete preparation boundary always refreshes current inputs, but caches history.
prepare_calls <- list()
fetch_quarter_hour_prices <- function(price_area, start, end, ...) {
  prepare_calls[[length(prepare_calls) + 1L]] <<- list(zone = price_area, start = start, end = end)
  fixture_quarter_prices(start, end, price_area)
}
prepare_cache <- file.path(scratch, "prepare-cache")
invisible(prepare_analysis(now, include_weather = FALSE, cache_dir = prepare_cache))
check(length(prepare_calls) == 4L, "first preparation one history and one current range per zone")
prepare_calls <- list()
invisible(prepare_analysis(now + 3600, include_weather = FALSE, cache_dir = prepare_cache))
check(length(prepare_calls) == 2L, "repeat preparation only two fresh current queries")
check(all(vapply(prepare_calls, function(x) identical(x$start, day_start(snapshot$date)), logical(1))), "fresh query starts today, avoiding history overlap")
fetch_quarter_hour_prices <- original_fetch

# Project sourcing also resolves paths outside the project working directory.
root <- getwd()
setwd(scratch)
isolated <- new.env(parent = globalenv())
source(file.path(root, "R", "project.R"), local = isolated)
setwd(root)
check(exists("prepare_analysis", envir = isolated, inherits = FALSE), "project module loading from other working directory")

# CI CLI uses a stable as-of independent of wall clock and reproduces the RDS bytes.
cli_paths <- file.path(scratch, c("cli-1.rds", "cli-2.rds"))
for (cli_path in cli_paths) {
  result <- system2(Sys.which("Rscript"), c("--vanilla", shQuote(file.path(root, "scripts", "prepare-data.R")),
    "--fixture", "--without-weather", "--output", shQuote(cli_path)), stdout = TRUE, stderr = TRUE)
  check(is.null(attr(result, "status")), "fixture CLI succeeds")
}
check(identical(unname(tools::md5sum(cli_paths[1L])), unname(tools::md5sum(cli_paths[2L]))), "fixture CLI byte deterministic")
check(identical(read_analysis(cli_paths[1L]), without), "fixture CLI snapshot contract")
cat("PASS: ", checks, " shared data assertions; offline, DST, units, cache, retries, schema and UTC joins\n", sep = "")
unlink(scratch, recursive = TRUE)
