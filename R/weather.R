# Historical weather access shared by the heat-pump analysis.

weather_config <- list(
  location_name = "Kgs. Lyngby",
  lat = 55.771979,
  lon = 12.494786,
  timezone = "Europe/Copenhagen"
)

require_weather_key <- function() {
  key <- Sys.getenv("OPENWEATHERMAP_APIKEY")
  if (!nzchar(trimws(key))) {
    stop("OPENWEATHERMAP_APIKEY is not configured.", call. = FALSE)
  }
  key
}

fetch_historical_weather_day <- function(date, config = weather_config,
                                         api_key = require_weather_key()) {
  day <- as.Date(date)
  timestamp <- as.numeric(as.POSIXct(day, tz = "UTC"))
  response <- httr::RETRY(
    "GET", "https://api.openweathermap.org/data/3.0/onecall/timemachine",
    query = list(lat = config$lat, lon = config$lon, dt = timestamp,
                 appid = api_key, units = "metric"),
    times = 3, pause_base = 1, httr::timeout(30)
  )
  httr::stop_for_status(response)
  payload <- jsonlite::fromJSON(
    httr::content(response, as = "text", encoding = "UTF-8"),
    simplifyVector = FALSE
  )
  if (!is.list(payload$data) || !length(payload$data)) {
    stop("OpenWeather historical response contains no hourly data for ", day,
         call. = FALSE)
  }
  rows <- lapply(payload$data, function(x) {
    data.frame(
      TimeUTC = as.POSIXct(x$dt, origin = "1970-01-01", tz = "UTC"),
      HourDK = as.POSIXct(x$dt, origin = "1970-01-01", tz = config$timezone),
      TemperatureC = as.numeric(x$temp),
      Humidity = as.numeric(x$humidity %||% NA_real_),
      stringsAsFactors = FALSE
    )
  })
  do.call(rbind, rows)
}

fetch_historical_weather <- function(start = Sys.Date() - 30,
                                     end = Sys.Date() - 1,
                                     config = weather_config,
                                     api_key = require_weather_key()) {
  dates <- seq.Date(as.Date(start), as.Date(end), by = "day")
  if (!length(dates)) stop("Historical weather period is empty.", call. = FALSE)
  result <- do.call(rbind, lapply(dates, fetch_historical_weather_day,
                                  config = config, api_key = api_key))
  result[order(result$HourDK), , drop = FALSE]
}

fetch_historical_weather_open_meteo <- function(start = Sys.Date() - 30,
                                                end = Sys.Date() - 1,
                                                config = weather_config) {
  response <- httr::GET(
    "https://archive-api.open-meteo.com/v1/archive",
    query = list(
      latitude = config$lat, longitude = config$lon,
      start_date = as.character(as.Date(start)),
      end_date = as.character(as.Date(end)),
      hourly = "temperature_2m,relative_humidity_2m",
      timezone = config$timezone
    ),
    httr::timeout(30)
  )
  httr::stop_for_status(response)
  payload <- jsonlite::fromJSON(httr::content(response, as = "text", encoding = "UTF-8"))
  if (!is.list(payload$hourly) || !length(payload$hourly$time)) {
    stop("Open-Meteo historical response contains no hourly data.", call. = FALSE)
  }
  data.frame(
    HourDK = as.POSIXct(payload$hourly$time, format = "%Y-%m-%dT%H:%M",
                        tz = config$timezone),
    TemperatureC = as.numeric(payload$hourly$temperature_2m),
    Humidity = as.numeric(payload$hourly$relative_humidity_2m),
    stringsAsFactors = FALSE
  )
}

`%||%` <- function(x, y) if (is.null(x)) y else x

pareto_frontier <- function(data, temperature_col = "TemperatureC",
                            price_col = "ConsumerPriceDKK") {
  keep <- is.finite(data[[temperature_col]]) & is.finite(data[[price_col]])
  data <- data[keep, , drop = FALSE]
  if (!nrow(data)) stop("No complete temperature/price observations.", call. = FALSE)
  dominated <- vapply(seq_len(nrow(data)), function(i) {
    any(data[[temperature_col]] >= data[[temperature_col]][i] &
          data[[price_col]] <= data[[price_col]][i] &
          (data[[temperature_col]] > data[[temperature_col]][i] |
             data[[price_col]] < data[[price_col]][i]))
  }, logical(1))
  data[!dominated, , drop = FALSE][order(data[[temperature_col]][!dominated]), , drop = FALSE]
}
