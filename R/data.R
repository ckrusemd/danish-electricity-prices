# Shared data access and validation for the Danish electricity price reports.

fetch_elspot_prices <- function(price_area = c("DK1", "DK2"), limit = 10000) {
  price_area <- match.arg(price_area)
  endpoint <- "https://api.energidataservice.dk/dataset/DayAheadPrices"

  response <- httr::RETRY(
    "GET",
    endpoint,
    query = list(
      offset = 0,
      filter = jsonlite::toJSON(list(PriceArea = list(price_area)), auto_unbox = TRUE),
      start = "now-P2D",
      end = "now+P2D",
      sort = "TimeUTC DESC",
      timezone = "dk",
      limit = limit
    ),
    times = 3,
    pause_base = 1,
    timeout(30)
  )
  httr::stop_for_status(response)

  payload <- jsonlite::fromJSON(httr::content(response, as = "text", encoding = "UTF-8"))
  records <- payload$records
  required <- c("TimeDK", "TimeUTC", "PriceArea", "DayAheadPriceDKK", "DayAheadPriceEUR")

  if (!is.data.frame(records) || !all(required %in% names(records))) {
    stop("DayAheadPrices response is missing required columns: ",
         paste(setdiff(required, names(records)), collapse = ", "))
  }
  if (!nrow(records)) stop("DayAheadPrices returned no records for ", price_area)

  result <- records |>
    dplyr::filter(.data$PriceArea == price_area) |>
    dplyr::mutate(
      TimeDK = lubridate::ymd_hms(.data$TimeDK, tz = "Europe/Copenhagen"),
      SpotPriceDKK = .data$DayAheadPriceDKK / 1000,
      SpotPriceEUR = .data$DayAheadPriceEUR / 1000,
      HourDK = lubridate::floor_date(.data$TimeDK, "hour")
    ) |>
    dplyr::group_by(.data$HourDK, .data$PriceArea) |>
    dplyr::summarise(
      SpotPriceDKK = mean(.data$SpotPriceDKK, na.rm = TRUE),
      SpotPriceEUR = mean(.data$SpotPriceEUR, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::arrange(.data$HourDK)

  if (any(is.na(result$HourDK))) stop("DayAheadPrices contains invalid timestamps")
  if (!any(result$HourDK >= Sys.time())) stop("DayAheadPrices contains no future prices")
  result
}
