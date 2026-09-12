source("R/data.R")

app_token <- Sys.getenv("PUSHOVER_APP_TOKEN")
user_key <- Sys.getenv("PUSHOVER_USER_KEY")

if (!nzchar(app_token) || !nzchar(user_key)) {
  message("Pushover secrets are not configured; skipping notification.")
  quit(save = "no", status = 0)
}

today <- as.Date(lubridate::with_tz(Sys.time(), "Europe/Copenhagen"))

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
  "\n",
  format_zone("DK2", "East")
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
