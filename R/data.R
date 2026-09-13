# Shared data access and validation for the Danish electricity price reports.

fetch_elspot_prices <- function(price_area = c("DK1", "DK2"), limit = 10000,
                                start = "now-P2D", end = "now+P2D",
                                require_future = TRUE) {
  price_area <- match.arg(price_area)
  endpoint <- "https://api.energidataservice.dk/dataset/DayAheadPrices"

  response <- httr::RETRY(
    "GET",
    endpoint,
    query = list(
      offset = 0,
      filter = jsonlite::toJSON(list(PriceArea = list(price_area)), auto_unbox = TRUE),
      start = start,
      end = end,
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
  if (require_future && !any(result$HourDK >= Sys.time())) stop("DayAheadPrices contains no future prices")
  result
}

cheapest_three_hour_window <- function(prices, from = -Inf, until = Inf) {
  prices <- prices |>
    dplyr::filter(.data$HourDK >= from, .data$HourDK < until) |>
    dplyr::arrange(.data$HourDK)
  if (nrow(prices) < 3) stop("Fewer than three price hours available for window calculation")

  candidates <- lapply(seq_len(nrow(prices) - 2), function(i) {
    window <- prices[i:(i + 2), , drop = FALSE]
    if (any(diff(as.numeric(window$HourDK)) != 3600)) return(NULL)
    data.frame(
      start = window$HourDK[1],
      end = window$HourDK[3] + 3600,
      average = mean(window$SpotPriceDKK, na.rm = TRUE),
      total = sum(window$SpotPriceDKK, na.rm = TRUE)
    )
  }) |>
    Filter(Negate(is.null), x = _)
  if (!length(candidates)) stop("No contiguous three-hour windows available")
  windows <- do.call(rbind, candidates)
  windows[which.min(windows$average), , drop = FALSE]
}
