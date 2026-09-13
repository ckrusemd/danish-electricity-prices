source("R/data.R")

app_token <- Sys.getenv("PUSHOVER_APP_TOKEN")
user_key <- Sys.getenv("PUSHOVER_USER_KEY")

if (!nzchar(app_token) || !nzchar(user_key)) {
  message("Pushover secrets are not configured; skipping notification.")
  quit(save = "no", status = 0)
}

today <- as.Date(lubridate::with_tz(Sys.time(), "Europe/Copenhagen"))
now <- lubridate::with_tz(Sys.time(), "Europe/Copenhagen")
next_day <- now + lubridate::hours(24)

format_window <- function(window) {
  paste0(
    format(window$start, "%H:%M", tz = "Europe/Copenhagen"), "-",
    format(window$end, "%H:%M", tz = "Europe/Copenhagen"), " (",
    scales::number(window$average, accuracy = 0.01), " DKK/kWh)"
  )
}

format_comparison <- function(price_area, label) {
  upcoming <- fetch_elspot_prices(price_area, limit = 10000) |>
    dplyr::filter(.data$HourDK >= now, .data$HourDK < next_day)
  recent <- fetch_elspot_prices(price_area, limit = 20000, start = "now-P6M", end = "now+P2D", require_future = FALSE) |>
    dplyr::filter(.data$HourDK < now)
  if (nrow(upcoming) < 3 || nrow(recent) < 3) stop("Not enough prices for ", label, " three-hour comparison")

  upcoming_window <- cheapest_three_hour_window(upcoming)
  historical_window <- cheapest_three_hour_window(recent)
  difference <- upcoming_window$average - historical_window$average
  comparison <- if (difference <= 0) "at or below" else "above"

  paste0(
    label, " cheapest next 3h: ", format_window(upcoming_window),
    "; 6-month low: ", format_window(historical_window),
    " (", scales::number(abs(difference), accuracy = 0.01), " DKK/kWh ", comparison, " historical low)"
  )
}

format_zone <- function(price_area, label) {
  prices <- fetch_elspot_prices(price_area, limit = 10000) |>
    dplyr::filter(as.Date(HourDK, tz = "Europe/Copenhagen") == today) |>
    dplyr::arrange(SpotPriceDKK)

  if (!nrow(prices)) stop("No prices returned for ", price_area, " today")

  cheapest <- utils::head(prices, 3)
  hours <- paste(
    format(cheapest$HourDK, "%H:%M", tz = "Europe/Copenhagen"),
    scales::number(cheapest$SpotPriceDKK, accuracy = 0.01),
    sep = " @ "
  )

  paste0(
    label, ": avg ", scales::number(mean(prices$SpotPriceDKK), accuracy = 0.01),
    " DKK/kWh; cheapest ", paste(hours, collapse = ", ")
  )
}

notification_body <- paste(
  "Today's projected spot prices (DKK/kWh)",
  format(today, "%d %b %Y"),
  "\n",
  format_zone("DK1", "West"),
  "\n", format_zone("DK2", "East"),
  "\n\nCheapest contiguous 3-hour windows",
  "\n", format_comparison("DK1", "West"),
  "\n", format_comparison("DK2", "East")
)

response <- httr::POST(
  "https://api.pushover.net/1/messages.json",
  body = list(token = app_token, user = user_key, message = notification_body,
              title = "Danish electricity prices"),
  encode = "form",
  httr::timeout(30)
)
httr::stop_for_status(response)
message("Pushover notification sent successfully.")
