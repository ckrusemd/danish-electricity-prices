# The only orchestration boundary: downstream consumers receive a frozen snapshot.
empty_price_window <- function() {
  data.frame(start = dk_time(numeric()), end = dk_time(numeric()),
             average = numeric(), total = numeric())
}

cheapest_three_hour_window <- function(prices, from = -Inf, until = Inf,
                                       price_col = "SpotPriceDKK") {
  assert_columns(prices, c("HourDK", price_col), "Window prices")
  if ("PriceArea" %in% names(prices) && length(unique(prices$PriceArea)) > 1L) {
    stop("Window calculation requires a single price zone", call. = FALSE)
  }
  time <- if ("HourUTC" %in% names(prices)) prices$HourUTC else prices$HourDK
  keep <- as.numeric(time) >= as.numeric(from) & as.numeric(time) + 3600 <= as.numeric(until)
  prices <- prices[keep, , drop = FALSE]
  time <- as.numeric(time[keep])
  order <- order(time)
  prices <- prices[order, , drop = FALSE]
  time <- time[order]
  if (nrow(prices) < 3L) return(empty_price_window())
  starts <- seq_len(nrow(prices) - 2L)
  value <- prices[[price_col]]
  valid <- diff(time)[starts] == 3600 & diff(time)[starts + 1L] == 3600 &
    is.finite(value[starts]) & is.finite(value[starts + 1L]) & is.finite(value[starts + 2L])
  starts <- starts[valid]
  if (!length(starts)) return(empty_price_window())
  totals <- value[starts] + value[starts + 1L] + value[starts + 2L]
  best <- which.min(totals)
  data.frame(start = dk_time(time[starts[best]]), end = dk_time(time[starts[best]] + 10800),
             average = totals[best] / 3, total = totals[best], row.names = NULL)
}

daily_period_averages <- function(prices) {
  bounds <- c(0L, 6L, 9L, 17L, 21L, 24L)
  labels <- c("00-06", "06-09", "09-17", "17-21", "21-24")
  hour <- as.integer(format(prices$HourDK, "%H", tz = electricity_timezone))
  averages <- vapply(seq_along(labels), function(i) {
    value <- prices$SpotPriceDKK[hour >= bounds[i] & hour < bounds[i + 1L]]
    if (length(value)) mean(value) else NA_real_
  }, numeric(1))
  data.frame(label = labels, average = averages)
}

quarter_history_profile <- function(prices, start, end) {
  prices <- prices[prices$TimeUTC >= start & prices$TimeUTC < end, , drop = FALSE]
  hour <- as.integer(format(prices$TimeDK, "%H", tz = electricity_timezone))
  minute <- as.integer(format(prices$TimeDK, "%M", tz = electricity_timezone))
  slot <- hour * 4L + minute %/% 15L
  groups <- split(prices$SpotPriceDKK, slot)
  result <- data.frame(hour = rep(0:23, each = 4L), minute = rep(c(0L, 15L, 30L, 45L), 24L),
                       q25 = NA_real_, median = NA_real_, q75 = NA_real_)
  for (key in names(groups)) {
    i <- as.integer(key) + 1L
    result[i, c("q25", "median", "q75")] <- as.list(stats::quantile(groups[[key]],
      probs = c(0.25, 0.5, 0.75), names = FALSE))
  }
  result
}

empty_heatmap <- function() {
  data.frame(PriceArea = character(), TemperatureBand = integer(), HourBand = integer(),
             ConsumerPriceDKK = numeric(), Observations = integer())
}

build_heatmap <- function(prices, weather, start, end) {
  if (is.null(weather) || !nrow(weather)) return(empty_heatmap())
  validate_weather(weather)
  prices <- prices[prices$HourUTC >= start & prices$HourUTC < end, , drop = FALSE]
  # Preserve the two physical repeated local hours; both match their exact UTC key.
  index <- match(as.numeric(prices$HourUTC), as.numeric(weather$TimeUTC))
  temperature <- weather$TemperatureC[index]
  humidity <- weather$Humidity[index]
  hour <- as.integer(format(prices$HourDK, "%H", tz = electricity_timezone))
  keep <- is.finite(temperature) & is.finite(humidity) & hour >= 7L & hour <= 23L &
    is.finite(prices$SpotPriceDKK_Total)
  if (!any(keep)) return(empty_heatmap())
  observations <- data.frame(PriceArea = prices$PriceArea[keep],
    TemperatureBand = as.integer(floor(temperature[keep])), HourBand = hour[keep],
    ConsumerPriceDKK = prices$SpotPriceDKK_Total[keep])
  groups <- split(seq_len(nrow(observations)), paste(observations$PriceArea,
    observations$TemperatureBand, observations$HourBand))
  result <- do.call(rbind, lapply(groups, function(i) {
    data.frame(PriceArea = observations$PriceArea[i[1L]],
      TemperatureBand = observations$TemperatureBand[i[1L]], HourBand = observations$HourBand[i[1L]],
      ConsumerPriceDKK = mean(observations$ConsumerPriceDKK[i]), Observations = length(i))
  }))
  result <- result[order(result$PriceArea, result$TemperatureBand, result$HourBand), , drop = FALSE]
  rownames(result) <- NULL
  result
}

prepare_analysis <- function(now = Sys.time(), fixture = FALSE, include_weather = TRUE,
                             cache_dir = ".cache/data") {
  now <- utc_time(now)
  if (length(now) != 1L || !is.finite(as.numeric(now))) stop("now must be one valid instant")
  # generated_at uses whole-second ISO precision; all interval decisions use it too.
  now <- utc_time(floor(as.numeric(now)))
  if (!is.logical(fixture) || length(fixture) != 1L || is.na(fixture) ||
      !is.logical(include_weather) || length(include_weather) != 1L || is.na(include_weather)) {
    stop("fixture and include_weather must be single logical values")
  }
  date <- local_day(now)
  today_start <- day_start(date)
  tomorrow_start <- day_start(date + 1L)
  history_start <- day_start(six_months_before(date))
  overlay_start <- day_start(date - 30L)
  current_end <- day_start(date + 2L)
  if (fixture) {
    quarters <- fixture_quarter_prices(history_start, current_end)
  } else {
    quarters <- do.call(rbind, lapply(c("DK1", "DK2"), function(zone) {
      historical <- load_historical_prices(zone, history_start, today_start, cache_dir)
      # Current and published next-day inputs always refresh, never from disk cache.
      current <- fetch_quarter_hour_prices(zone, start = today_start, end = current_end,
        require_future = FALSE, now = now)
      rbind(historical, current)
    }))
  }
  quarters <- quarters[order(quarters$PriceArea, quarters$TimeUTC), , drop = FALSE]
  rownames(quarters) <- NULL
  validate_quarter_prices(quarters)
  hourly <- apply_consumer_price_components(derive_hourly_prices(quarters))
  weather_error <- NULL
  weather <- if (!include_weather) NULL else if (fixture) fixture_weather(overlay_start, today_start) else {
    tryCatch(load_historical_weather(date - 30L, date - 1L, cache_dir), error = function(e) {
      weather_error <<- conditionMessage(e)
      warning("Historical weather unavailable: ", weather_error, call. = FALSE)
      NULL
    })
  }
  upcoming_start <- utc_time(ceiling(as.numeric(now) / 900) * 900)
  upcoming_end <- upcoming_start + 86400
  summaries <- list()
  coverage <- list()
  for (zone in c("DK1", "DK2")) {
    q <- quarters[quarters$PriceArea == zone, , drop = FALSE]
    h <- hourly[hourly$PriceArea == zone, , drop = FALSE]
    coverage[[zone]] <- list(today = price_range_coverage(q, today_start, tomorrow_start),
      history = price_range_coverage(q, history_start, today_start),
      overlay = price_range_coverage(q, overlay_start, today_start),
      upcoming = price_range_coverage(q, upcoming_start, upcoming_end),
      days = quarter_day_coverage(q, seq(six_months_before(date), date + 1L, by = "day")),
      incomplete_hours = length(unique(as.numeric(q$TimeUTC) %/% 3600)) - nrow(h))
    if (!coverage[[zone]]$history$complete) stop("Incomplete six-month historical prices for ", zone)
    today <- h[h$HourUTC >= today_start & h$HourUTC < tomorrow_start, , drop = FALSE]
    summaries[[zone]] <- list(today = today,
      quarter_today = q[q$TimeUTC >= today_start & q$TimeUTC < tomorrow_start, , drop = FALSE],
      period_averages = daily_period_averages(today),
      upcoming_window = cheapest_three_hour_window(h, from = now, until = now + 86400),
      historical_window = cheapest_three_hour_window(h, from = history_start, until = now),
      history_profile = quarter_history_profile(q, overlay_start, today_start))
    coverage[[zone]]$upcoming$window_available <- nrow(summaries[[zone]]$upcoming_window) == 1L
    coverage[[zone]]$upcoming$window_provisional <- !coverage[[zone]]$upcoming$complete
  }
  weather_status <- if (!include_weather) "skipped" else if (is.null(weather)) "unavailable" else "available"
  snapshot <- list(schema_version = 1L, generated_at = iso_utc(now), date = as.character(date),
    quarter_prices = quarters, hourly_prices = hourly, weather = weather,
    heatmap = build_heatmap(hourly, weather, overlay_start, today_start), summaries = summaries,
    meta = list(fixture = fixture, timezone = electricity_timezone, units = "DKK/kWh",
      provider = list(prices = if (fixture) "Deterministic synthetic DayAheadPrices fixture" else price_provider,
        weather = if (!include_weather) "Not requested" else if (fixture) "Deterministic synthetic hourly weather fixture" else weather_provider,
        price_endpoint = price_endpoint, weather_endpoint = weather_endpoint,
        weather_kind = "archived model forecasts; not station observations"),
      scenario = consumer_price_scenario(),
      coverage = list(prices = coverage, weather = weather_coverage(weather, hourly,
        overlay_start, today_start, weather_status, weather_error)),
      history = list(overlay_completed_days = 30L, historical_window_months = 6L,
        overlay_start = as.character(date - 30L), overlay_end = as.character(date - 1L),
        historical_start = as.character(six_months_before(date))),
      calculations = list(hourly = "Arithmetic mean of exactly four UTC quarters",
        summaries = "Spot DKK/kWh; windows are three elapsed hours, total assumes 1 kWh per hour",
        upcoming = "Only full hours starting at or after generated_at, ending within 24 elapsed hours",
        heatmap = list(hours = 7:23, temperature_band_degrees = 1L, price = "SpotPriceDKK_Total",
          low = "#062b5c", high = "#ffffff"))))
  validate_analysis(snapshot)
  snapshot
}

validate_analysis <- function(snapshot) {
  fail <- function(message) stop("Invalid analysis snapshot: ", message, call. = FALSE)
  required <- c("schema_version", "generated_at", "date", "quarter_prices", "hourly_prices",
                "weather", "heatmap", "summaries", "meta")
  if (!is.list(snapshot) || !all(required %in% names(snapshot)) ||
      !identical(snapshot$schema_version, 1L)) fail("unsupported schema or missing fields")
  if (!is.character(snapshot$generated_at) || length(snapshot$generated_at) != 1L ||
      !grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$", snapshot$generated_at)) fail("generated_at is not UTC ISO")
  now <- utc_time(snapshot$generated_at)
  if (!is.finite(as.numeric(now)) || !identical(snapshot$date, as.character(local_day(now)))) fail("date does not match Copenhagen generation date")
  quarters <- snapshot$quarter_prices
  validate_quarter_prices(quarters)
  if (!identical(sort(unique(quarters$PriceArea)), c("DK1", "DK2"))) fail("both zones are required")
  hourly <- snapshot$hourly_prices
  expected_hourly <- apply_consumer_price_components(derive_hourly_prices(quarters))
  assert_columns(hourly, names(expected_hourly), "hourly_prices")
  if (!isTRUE(all.equal(hourly[names(expected_hourly)], expected_hourly, check.attributes = TRUE))) fail("hourly prices are inconsistent with quarters or scenario")
  date <- as.Date(snapshot$date)
  start <- day_start(date - 30L)
  end <- day_start(date)
  if (!is.list(snapshot$meta) || !all(c("provider", "scenario", "coverage") %in% names(snapshot$meta)) ||
      !is.list(snapshot$meta$provider) || !all(c("prices", "weather") %in% names(snapshot$meta$provider)) ||
      !is.list(snapshot$meta$scenario) || !isTRUE(all.equal(snapshot$meta$scenario, consumer_price_scenario())) ||
      !is.list(snapshot$meta$coverage) || !all(c("prices", "weather") %in% names(snapshot$meta$coverage))) fail("missing provider/scenario/coverage metadata")
  if (!is.null(snapshot$weather)) {
    validate_weather(snapshot$weather)
    if (any(snapshot$weather$TimeUTC < start | snapshot$weather$TimeUTC >= end)) fail("weather outside completed-day interval")
  }
  expected_heatmap <- build_heatmap(hourly, snapshot$weather, start, end)
  if (!isTRUE(all.equal(snapshot$heatmap, expected_heatmap, check.attributes = TRUE))) fail("heatmap disagrees with exact UTC weather joins")
  weather_meta <- snapshot$meta$coverage$weather
  if (!is.list(weather_meta) || length(weather_meta$status) != 1L ||
      !weather_meta$status %in% c("available", "skipped", "unavailable") ||
      (identical(weather_meta$status, "available") && is.null(snapshot$weather)) ||
      (!identical(weather_meta$status, "available") && !is.null(snapshot$weather))) fail("invalid weather status")
  expected_weather_coverage <- weather_coverage(snapshot$weather, hourly, start, end,
    weather_meta$status, weather_meta$error)
  if (!isTRUE(all.equal(weather_meta, expected_weather_coverage))) fail("inconsistent weather coverage")
  if (!is.list(snapshot$summaries) || !identical(names(snapshot$summaries), c("DK1", "DK2"))) fail("summaries must be named DK1/DK2")
  for (zone in c("DK1", "DK2")) {
    summary <- snapshot$summaries[[zone]]
    if (!is.list(summary) || !all(c("today", "quarter_today", "period_averages", "upcoming_window",
      "historical_window", "history_profile") %in% names(summary))) fail(paste("missing summary fields", zone))
    h <- hourly[hourly$PriceArea == zone, , drop = FALSE]
    q <- quarters[quarters$PriceArea == zone, , drop = FALSE]
    today <- h[h$HourUTC >= end & h$HourUTC < day_start(date + 1L), , drop = FALSE]
    quarter_today <- q[q$TimeUTC >= end & q$TimeUTC < day_start(date + 1L), , drop = FALSE]
    expected <- list(today = today, quarter_today = quarter_today, period_averages = daily_period_averages(today),
      upcoming_window = cheapest_three_hour_window(h, from = now, until = now + 86400),
      historical_window = cheapest_three_hour_window(h, from = day_start(six_months_before(date)), until = now),
      history_profile = quarter_history_profile(q, start, end))
    if (!isTRUE(all.equal(summary[names(expected)], expected, check.attributes = TRUE))) fail(paste("inconsistent summary", zone))
    for (interval in c("today", "history", "overlay", "upcoming")) {
      bounds <- switch(interval,
        today = list(end, day_start(date + 1L)), history = list(day_start(six_months_before(date)), end),
        overlay = list(start, end), upcoming = list(utc_time(ceiling(as.numeric(now) / 900) * 900),
          utc_time(ceiling(as.numeric(now) / 900) * 900 + 86400)))
      calculated <- price_range_coverage(q, bounds[[1L]], bounds[[2L]])
      stored <- snapshot$meta$coverage$prices[[zone]][[interval]]
      if (!is.list(stored) || !isTRUE(all.equal(stored[names(calculated)], calculated))) fail(paste("inconsistent coverage", zone, interval))
      if (interval == "history" && !calculated$complete) fail(paste("incomplete historical quarters", zone))
    }
    stored <- snapshot$meta$coverage$prices[[zone]]
    if (!identical(stored$upcoming$window_available, nrow(summary$upcoming_window) == 1L) ||
        !identical(stored$upcoming$window_provisional, !stored$upcoming$complete) ||
        !identical(stored$incomplete_hours, length(unique(as.numeric(q$TimeUTC) %/% 3600)) - nrow(h)) ||
        !identical(stored$days, quarter_day_coverage(q, seq(six_months_before(date), date + 1L, by = "day")))) {
      fail(paste("inconsistent day/hour/window coverage", zone))
    }
  }
  invisible(snapshot)
}

read_analysis <- function(path) {
  if (length(path) != 1L || !is.character(path) || !nzchar(path) || !file.exists(path)) stop("Analysis RDS does not exist: ", path)
  snapshot <- readRDS(path)
  validate_analysis(snapshot)
  snapshot
}

load_or_prepare_analysis <- function(include_weather = FALSE) {
  path <- Sys.getenv("ELECTRICITY_DATA_FILE", unset = "")
  if (nzchar(path)) return(read_analysis(path))
  fixture <- identical(tolower(Sys.getenv("ELECTRICITY_FIXTURE", unset = "false")), "true")
  prepare_analysis(now = if (fixture) fixture_reference_time() else Sys.time(),
    fixture = fixture, include_weather = include_weather)
}
