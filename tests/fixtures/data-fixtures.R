# Small raw API responses derived deterministically from the production fixture.
raw_price_fixture <- function(start, end, zone = "DK1") {
  quarters <- fixture_quarter_prices(start, end, zone)
  data.frame(TimeUTC = format(quarters$TimeUTC, "%Y-%m-%dT%H:%M:%S", tz = "UTC"),
    # Deliberately misleading local strings prove UTC is the canonical source.
    TimeDK = rep("1900-01-01T00:00:00", nrow(quarters)), PriceArea = quarters$PriceArea,
    DayAheadPriceDKK = quarters$SpotPriceDKK * 1000,
    DayAheadPriceEUR = quarters$SpotPriceEUR * 1000)
}

expect_error <- function(expression, pattern = NULL) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  check(inherits(error, "error"), "expected an error")
  if (!is.null(pattern)) check(grepl(pattern, conditionMessage(error)), paste("error pattern", pattern))
  invisible(error)
}
