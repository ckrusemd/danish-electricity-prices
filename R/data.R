# Fetch raw quarters once, validate by UTC, and derive complete physical hours.
price_provider <- "Energi Data Service DayAheadPrices"
price_endpoint <- "https://api.energidataservice.dk/dataset/DayAheadPrices"

empty_quarter_prices <- function() {
  data.frame(TimeUTC = utc_time(numeric()), TimeDK = dk_time(numeric()),
             PriceArea = character(), SpotPriceDKK = numeric())
}

validate_quarter_prices <- function(data) {
  assert_columns(data, c("TimeUTC", "TimeDK", "PriceArea", "SpotPriceDKK"), "quarter_prices")
  assert_time(data$TimeUTC, "UTC", "TimeUTC", 900)
  assert_time(data$TimeDK, electricity_timezone, "TimeDK", 900)
  if (!is.character(data$PriceArea) || anyNA(data$PriceArea) ||
      any(!data$PriceArea %in% c("DK1", "DK2")) ||
      !is.numeric(data$SpotPriceDKK) || any(!is.finite(data$SpotPriceDKK)) ||
      !identical(as.numeric(data$TimeUTC), as.numeric(data$TimeDK))) {
    stop("Invalid quarter price values, zone, or UTC/local alignment", call. = FALSE)
  }
  if (anyDuplicated(data[c("PriceArea", "TimeUTC")])) stop("Duplicate UTC quarter prices", call. = FALSE)
  if (!identical(order(data$PriceArea, data$TimeUTC), seq_len(nrow(data)))) {
    stop("Quarter prices must be sorted by zone and UTC", call. = FALSE)
  }
  invisible(data)
}

normalise_price_records <- function(records, price_area) {
  assert_columns(records, c("TimeUTC", "PriceArea", "DayAheadPriceDKK"), "DayAheadPrices records")
  if (anyNA(records$PriceArea) || any(!records$PriceArea %in% price_area)) stop("DayAheadPrices returned an unexpected zone")
  # Source DKK/MWh -> DKK/kWh, exactly once. Local strings are ambiguous at DST.
  time <- utc_time(records$TimeUTC)
  result <- data.frame(TimeUTC = time, TimeDK = dk_time(time),
                       PriceArea = as.character(records$PriceArea),
                       SpotPriceDKK = records$DayAheadPriceDKK / 1000)
  if ("DayAheadPriceEUR" %in% names(records)) result$SpotPriceEUR <- records$DayAheadPriceEUR / 1000
  result <- result[order(result$PriceArea, result$TimeUTC), , drop = FALSE]
  rownames(result) <- NULL
  validate_quarter_prices(result)
  result
}

fetch_quarter_hour_prices_batched <- function(start, end, get_json = api_get_json) {
  assert_time(start, "UTC", "batch start", 900)
  assert_time(end, "UTC", "batch end", 900)
  # Two zones over six calendar months fit in one bounded request. Current
  # and newly completed historical quarters share this request, not pagination.
  limit <- 50000L
  if (length(start) != 1L || length(end) != 1L || start >= end ||
      2 * (as.numeric(end) - as.numeric(start)) / 900 > limit) {
    stop("Invalid bounded batch price range", call. = FALSE)
  }
  payload <- get_json(price_endpoint, list(
    filter = '{"PriceArea":["DK1","DK2"]}',
    start = format(start, "%Y-%m-%dT%H:%M", tz = "UTC"),
    end = format(end, "%Y-%m-%dT%H:%M", tz = "UTC"),
    sort = "TimeUTC ASC", timezone = "utc", limit = limit,
    columns = "TimeUTC,PriceArea,DayAheadPriceDKK,DayAheadPriceEUR"))
  records <- payload$records
  if (is.list(records) && !length(records)) return(empty_quarter_prices())
  assert_columns(records, c("TimeUTC", "PriceArea", "DayAheadPriceDKK"), "DayAheadPrices records")
  if (nrow(records) >= limit || (!is.null(payload$total) && payload$total > nrow(records))) {
    stop("DayAheadPrices batch response is truncated", call. = FALSE)
  }
  result <- normalise_price_records(records, c("DK1", "DK2"))
  if (any(result$TimeUTC < start | result$TimeUTC >= end)) stop("Prices exceed batch query range")
  result
}

load_price_inputs <- function(start, today, end, cache_dir,
                              fetch = fetch_quarter_hour_prices_batched) {
  key <- "utc-quarters-both"
  path <- file.path(cache_dir, "v1-prices-both.rds")
  cached <- read_input_cache(path, price_provider, key)
  valid <- !is.null(cached) && tryCatch({
    validate_quarter_prices(cached$data)
    assert_time(cached$start, "UTC", "cached start", 900)
    assert_time(cached$end, "UTC", "cached end", 900)
    length(cached$start) == 1L && length(cached$end) == 1L &&
      cached$start <= start && cached$end > start && cached$end <= today &&
      all(cached$data$TimeUTC >= cached$start & cached$data$TimeUTC < cached$end) &&
      all(vapply(c("DK1", "DK2"), function(zone) price_range_coverage(
        cached$data[cached$data$PriceArea == zone, , drop = FALSE],
        cached$start, cached$end)$complete, logical(1)))
  }, error = function(e) FALSE)
  fetch_start <- if (valid) cached$end else start
  # Exactly one GET even on a cold cache. Never reuse cached current-day prices.
  data <- fetch(start = fetch_start, end = end)
  if (valid) data <- rbind(cached$data[cached$data$TimeUTC >= start &
    cached$data$TimeUTC < fetch_start, , drop = FALSE], data)
  data <- data[order(data$PriceArea, data$TimeUTC), , drop = FALSE]
  rownames(data) <- NULL
  validate_quarter_prices(data)
  if (any(data$TimeUTC < start | data$TimeUTC >= end)) stop("Prices exceed requested input range")
  for (zone in c("DK1", "DK2")) {
    if (!price_range_coverage(data[data$PriceArea == zone, , drop = FALSE], start, today)$complete) {
      stop("Incomplete historical UTC quarter coverage for ", zone)
    }
  }
  historical <- data[data$TimeUTC < today, , drop = FALSE]
  write_input_cache(path, price_provider, key, historical, start, today)
  data
}

fetch_quarter_hour_prices <- function(price_area = c("DK1", "DK2"), limit = 10000L,
                                      start = "now-P2D", end = "now+P2D",
                                      require_future = TRUE, now = Sys.time(),
                                      get_json = api_get_json, max_pages = 100L) {
  price_area <- match.arg(price_area)
  if (length(limit) != 1L || !is.finite(limit) || limit != as.integer(limit) || limit < 1L || limit > 10000L ||
      length(max_pages) != 1L || !is.finite(max_pages) || max_pages != as.integer(max_pages) || max_pages < 1L || max_pages > 100L) {
    stop("Invalid price pagination bounds", call. = FALSE)
  }
  query_time <- function(x) if (inherits(x, "POSIXt")) format(x, "%Y-%m-%dT%H:%M", tz = "UTC") else x
  pages <- list()
  for (page in seq_len(as.integer(max_pages))) {
    payload <- get_json(price_endpoint, list(offset = (page - 1L) * as.integer(limit),
      filter = paste0('{"PriceArea":["', price_area, '"]}'),
      start = query_time(start), end = query_time(end), sort = "TimeUTC ASC",
      timezone = "utc", limit = as.integer(limit)))
    records <- payload$records
    if (is.list(records) && length(records) == 0L) break
    assert_columns(records, c("TimeUTC", "PriceArea", "DayAheadPriceDKK"), "DayAheadPrices records")
    if (!nrow(records)) break
    pages[[length(pages) + 1L]] <- records
    if (nrow(records) < limit) break
    if (page == max_pages) stop("DayAheadPrices pagination exceeded bounded page count", call. = FALSE)
  }
  if (!length(pages)) return(empty_quarter_prices())
  result <- normalise_price_records(do.call(rbind, pages), price_area)
  if (inherits(start, "POSIXt") && any(result$TimeUTC < start)) stop("Prices precede query range")
  if (inherits(end, "POSIXt") && any(result$TimeUTC >= end)) stop("Prices exceed query range")
  if (require_future && !any(result$TimeUTC >= now)) stop("No future quarter-hour prices available")
  result
}

derive_hourly_prices <- function(quarters) {
  validate_quarter_prices(quarters)
  result <- data.frame(HourUTC = utc_time(numeric()), HourDK = dk_time(numeric()),
                       PriceArea = character(), SpotPriceDKK = numeric(), QuarterObservations = integer())
  if (!nrow(quarters)) return(result)
  hour <- as.numeric(quarters$TimeUTC) %/% 3600L * 3600L
  key <- paste(quarters$PriceArea, hour)
  group <- match(key, unique(key))
  count <- tabulate(group)
  complete <- which(count == 4L)
  if (!length(complete)) return(result)
  first <- match(complete, group)
  sums <- rowsum(quarters$SpotPriceDKK, group, reorder = FALSE)[, 1L]
  result <- data.frame(HourUTC = utc_time(hour[first]), HourDK = dk_time(hour[first]),
    PriceArea = quarters$PriceArea[first],
    SpotPriceDKK = unname(sums[complete] / 4),
    QuarterObservations = rep(4L, length(complete)), row.names = NULL)
  if ("SpotPriceEUR" %in% names(quarters)) {
    result$SpotPriceEUR <- unname(rowsum(quarters$SpotPriceEUR, group, reorder = FALSE)[complete, 1L] / 4)
  }
  result <- result[order(result$PriceArea, result$HourUTC), , drop = FALSE]
  rownames(result) <- NULL
  result
}

fetch_elspot_prices <- function(...) derive_hourly_prices(fetch_quarter_hour_prices(...))

price_range_coverage <- function(quarters, start, end) {
  expected <- seq(as.numeric(start), as.numeric(end) - 900, by = 900)
  observed <- as.numeric(quarters$TimeUTC)
  observed <- observed[observed >= as.numeric(start) & observed < as.numeric(end)]
  missing <- setdiff(expected, observed)
  list(start = iso_utc(start), end = iso_utc(end), expected = length(expected),
       observed = length(observed), missing = length(missing), complete = !length(missing),
       available_until = if (length(observed)) iso_utc(utc_time(max(observed) + 900)) else NULL,
       first_missing = if (length(missing)) iso_utc(utc_time(min(missing))) else NULL)
}

quarter_day_coverage <- function(quarters, dates = unique(local_day(quarters$TimeDK))) {
  if (!length(dates)) return(data.frame(date = character(), expected = integer(), observed = integer(), complete = logical()))
  dates <- as.Date(dates)
  expected <- as.integer((as.numeric(day_start(dates + 1L)) - as.numeric(day_start(dates))) / 900)
  observed <- tabulate(match(local_day(quarters$TimeDK), dates), nbins = length(dates))
  data.frame(date = as.character(dates), expected = expected, observed = observed,
             complete = expected == observed)
}

load_historical_prices <- function(price_area, start, end, cache_dir, fetch = fetch_quarter_hour_prices) {
  key <- paste0("utc-quarters-", price_area)
  path <- file.path(cache_dir, paste0("v1-prices-", price_area, ".rds"))
  cached <- read_input_cache(path, price_provider, key)
  valid <- !is.null(cached) && tryCatch({
    validate_quarter_prices(cached$data)
    assert_time(cached$start, "UTC", "cached start", 900)
    assert_time(cached$end, "UTC", "cached end", 900)
    length(cached$start) == 1L && length(cached$end) == 1L && cached$start < cached$end &&
      all(cached$data$TimeUTC >= cached$start & cached$data$TimeUTC < cached$end) &&
      all(cached$data$PriceArea == price_area) &&
      price_range_coverage(cached$data, cached$start, cached$end)$complete
  }, error = function(e) FALSE)
  parts <- list()
  if (!valid || cached$end <= start || cached$start >= end) {
    parts[[1L]] <- fetch(price_area, start = start, end = end, require_future = FALSE)
  } else {
    parts[[1L]] <- cached$data[cached$data$TimeUTC >= start & cached$data$TimeUTC < end, , drop = FALSE]
    if (start < cached$start) parts[[length(parts) + 1L]] <- fetch(price_area,
      start = start, end = cached$start, require_future = FALSE)
    if (end > cached$end) parts[[length(parts) + 1L]] <- fetch(price_area,
      start = cached$end, end = end, require_future = FALSE)
  }
  data <- do.call(rbind, parts)
  data <- data[order(data$PriceArea, data$TimeUTC), , drop = FALSE]
  rownames(data) <- NULL
  validate_quarter_prices(data)
  if (!price_range_coverage(data, start, end)$complete) stop("Incomplete historical UTC quarter coverage for ", price_area)
  write_input_cache(path, price_provider, key, data, start, end)
  data
}
