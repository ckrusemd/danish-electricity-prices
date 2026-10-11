# Offline, deterministic series anchored to absolute UTC instants, not RNG state.
fixture_reference_time <- function() utc_time("2026-10-11T10:00:00Z")

fixture_quarter_prices <- function(start, end, price_area = c("DK1", "DK2")) {
  time <- utc_time(seq(as.numeric(start), as.numeric(end) - 900, by = 900))
  local <- dk_time(time)
  hour <- as.integer(format(local, "%H", tz = electricity_timezone)) +
    as.integer(format(local, "%M", tz = electricity_timezone)) / 60
  days <- as.numeric(time) / 86400
  # Evening peak, midday solar dip, multi-day wind spells, occasional negatives.
  shape <- 0.55 + 0.18 * cos(2 * pi * (hour - 19) / 24) -
    0.25 * exp(-((hour - 13) / 2.8)^2) + 0.22 * sin(days * 2 * pi / 7.3) +
    0.14 * cos(days * 2 * pi / 3.9) + 0.06 * sin(days * 2 * pi / 0.29)
  wind <- -0.45 * pmax(0, sin(days * 2 * pi / 17))^8
  result <- do.call(rbind, lapply(price_area, function(zone) {
    spot <- round(shape + wind + if (zone == "DK2") 0.075 + 0.04 * sin(days) else 0, 6)
    data.frame(TimeUTC = time, TimeDK = local, PriceArea = zone,
               SpotPriceDKK = spot, SpotPriceEUR = round(spot / 7.46, 6))
  }))
  result <- result[order(result$PriceArea, result$TimeUTC), , drop = FALSE]
  rownames(result) <- NULL
  validate_quarter_prices(result)
  result
}

fixture_weather <- function(start, end) {
  time <- utc_time(seq(as.numeric(start), as.numeric(end) - 3600, by = 3600))
  hour <- as.integer(format(time, "%H", tz = electricity_timezone))
  days <- as.numeric(time) / 86400
  day_of_year <- as.integer(format(time, "%j", tz = electricity_timezone))
  temperature <- 9 + 9 * sin(2 * pi * (day_of_year - 105) / 365.25) +
    2.6 * cos(2 * pi * (hour - 15) / 24) + 2.8 * sin(days * 2 * pi / 8.7)
  humidity <- pmax(30, pmin(100, 76 - 9 * cos(2 * pi * (hour - 15) / 24) +
    7 * cos(days * 2 * pi / 4.7)))
  data.frame(TimeUTC = time, HourDK = dk_time(time),
             TemperatureC = round(temperature, 2), Humidity = round(humidity, 1))
}
