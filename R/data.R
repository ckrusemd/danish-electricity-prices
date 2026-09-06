# Shared data access and validation for the Danish electricity price reports.

fetch_elspot_prices <- function(price_area = c("DK1", "DK2"), limit = 10000) {
  price_area <- match.arg(price_area)
  endpoint <- "https://api.energidataservice.dk/dataset/Elspotprices"

  response <- httr::RETRY(
    "GET",
    endpoint,
    query = list(
      offset = 0,
      filter = jsonlite::toJSON(list(PriceArea = list(price_area)), auto_unbox = TRUE),
      sort = "HourUTC DESC",
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
  required <- c("HourDK", "HourUTC", "PriceArea", "SpotPriceDKK", "SpotPriceEUR")

  if (!is.data.frame(records) || !all(required %in% names(records))) {
    stop("Elspotprices response is missing required columns: ",
         paste(setdiff(required, names(records)), collapse = ", "))
  }
  if (!nrow(records)) stop("Elspotprices returned no records for ", price_area)

  result <- records |>
    dplyr::filter(.data$PriceArea == price_area) |>
    dplyr::mutate(
      HourDK = lubridate::ymd_hms(.data$HourDK, tz = "Europe/Copenhagen"),
      SpotPriceDKK = .data$SpotPriceDKK / 1000,
      SpotPriceEUR = .data$SpotPriceEUR / 1000
    ) |>
    dplyr::arrange(.data$HourDK)

  if (any(is.na(result$HourDK))) stop("Elspotprices contains invalid timestamps")
  if (!any(result$HourDK >= Sys.time())) stop("Elspotprices contains no future prices")
  result
}
