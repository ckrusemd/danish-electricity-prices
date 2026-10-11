# One UTC request for the 30 completed local days, using archived forecasts.
weather_config <- list(location_name = "Kgs. Lyngby", lat = 55.771979, lon = 12.494786,
                       timezone = "Europe/Copenhagen")
weather_provider <- "Open-Meteo Historical Forecast API (archived model forecasts)"
weather_endpoint <- "https://historical-forecast-api.open-meteo.com/v1/forecast"

empty_weather <- function() {
  data.frame(TimeUTC = utc_time(numeric()), HourDK = dk_time(numeric()),
             TemperatureC = numeric(), Humidity = numeric())
}

validate_weather <- function(data) {
  assert_columns(data, c("TimeUTC", "HourDK", "TemperatureC", "Humidity"), "weather")
  assert_time(data$TimeUTC, "UTC", "Weather TimeUTC", 3600)
  assert_time(data$HourDK, electricity_timezone, "Weather HourDK", 3600)
  if (!identical(as.numeric(data$TimeUTC), as.numeric(data$HourDK)) ||
      anyDuplicated(data$TimeUTC) || is.unsorted(data$TimeUTC) ||
      !is.numeric(data$TemperatureC) || !is.numeric(data$Humidity) ||
      any(!is.na(data$TemperatureC) & !is.finite(data$TemperatureC)) ||
      any(!is.na(data$Humidity) & (!is.finite(data$Humidity) | data$Humidity < 0 | data$Humidity > 100))) {
    stop("Invalid weather timestamps or values", call. = FALSE)
  }
  invisible(data)
}

fetch_historical_weather_open_meteo <- function(start = local_day(Sys.time()) - 30L,
                                                end = local_day(Sys.time()) - 1L,
                                                config = weather_config,
                                                get_json = api_get_json) {
  start_utc <- day_start(start)
  end_utc <- day_start(as.Date(end) + 1L)
  if (start_utc >= end_utc) stop("Historical weather period is empty", call. = FALSE)
  payload <- get_json(weather_endpoint, list(latitude = config$lat, longitude = config$lon,
    start_date = format(start_utc, "%Y-%m-%d", tz = "UTC"),
    end_date = format(end_utc - 1, "%Y-%m-%d", tz = "UTC"),
    hourly = "temperature_2m,relative_humidity_2m", timezone = "UTC"))
  hourly <- payload$hourly
  if (!is.list(hourly) || !all(c("time", "temperature_2m", "relative_humidity_2m") %in% names(hourly)) ||
      !length(hourly$time) || length(hourly$temperature_2m) != length(hourly$time) ||
      length(hourly$relative_humidity_2m) != length(hourly$time) ||
      (!is.null(payload$utc_offset_seconds) && payload$utc_offset_seconds != 0)) {
    stop("Open-Meteo returned invalid UTC hourly weather", call. = FALSE)
  }
  time <- utc_time(paste0(hourly$time, ":00"))
  result <- data.frame(TimeUTC = time, HourDK = dk_time(time),
                       TemperatureC = as.numeric(hourly$temperature_2m),
                       Humidity = as.numeric(hourly$relative_humidity_2m))
  validate_weather(result)
  result <- result[result$TimeUTC >= start_utc & result$TimeUTC < end_utc, , drop = FALSE]
  rownames(result) <- NULL
  result
}

# Compatibility name, now keyless; no OpenWeather secret or shifted-time fallback.
fetch_historical_weather <- function(...) fetch_historical_weather_open_meteo(...)

load_historical_weather <- function(start, end, cache_dir, config = weather_config,
                                    fetch = fetch_historical_weather_open_meteo) {
  key <- paste("utc-hourly", config$lat, config$lon, as.Date(start), as.Date(end), sep = "-")
  path <- file.path(cache_dir, paste0("v1-weather-", key, ".rds"))
  cached <- read_input_cache(path, weather_provider, key)
  valid <- !is.null(cached) && tryCatch({
    validate_weather(cached$data)
    expected <- seq(as.numeric(day_start(start)), as.numeric(day_start(as.Date(end) + 1L)) - 3600, by = 3600)
    identical(as.numeric(cached$data$TimeUTC), expected) &&
      all(is.finite(cached$data$TemperatureC)) && all(is.finite(cached$data$Humidity))
  }, error = function(e) FALSE)
  if (valid) return(cached$data)
  data <- fetch(start, end, config = config)
  validate_weather(data)
  write_input_cache(path, weather_provider, key, data, day_start(start), day_start(as.Date(end) + 1L))
  data
}

weather_coverage <- function(weather, prices, start, end, status = "available", error = NULL) {
  expected <- seq(as.numeric(start), as.numeric(end) - 3600, by = 3600)
  valid <- if (is.null(weather)) numeric() else as.numeric(weather$TimeUTC[
    is.finite(weather$TemperatureC) & is.finite(weather$Humidity)])
  valid <- intersect(valid, expected)
  matched <- lapply(c("DK1", "DK2"), function(zone) {
    hours <- as.numeric(prices$HourUTC[prices$PriceArea == zone & prices$HourUTC >= start & prices$HourUTC < end])
    length(intersect(hours, valid))
  })
  names(matched) <- c("DK1", "DK2")
  list(status = status, start = iso_utc(start), end = iso_utc(end), expected = length(expected),
       observed = length(valid), missing = length(setdiff(expected, valid)),
       complete = identical(valid, expected), matched_hours = matched, error = error,
       join = "Exact UTC hour; no offsets, interpolation or nearest-hour matching")
}

pareto_frontier <- function(data, temperature_col = "TemperatureC", price_col = "ConsumerPriceDKK") {
  data <- data[is.finite(data[[temperature_col]]) & is.finite(data[[price_col]]), , drop = FALSE]
  if (!nrow(data)) return(data)
  dominated <- vapply(seq_len(nrow(data)), function(i) {
    any(data[[temperature_col]] >= data[[temperature_col]][i] & data[[price_col]] <= data[[price_col]][i] &
      (data[[temperature_col]] > data[[temperature_col]][i] | data[[price_col]] < data[[price_col]][i]))
  }, logical(1))
  data <- data[!dominated, , drop = FALSE]
  data[order(data[[temperature_col]]), , drop = FALSE]
}
