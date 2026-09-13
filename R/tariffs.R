# 2026 consumer-price components for a private C customer in Radius' area
# with an existing Andel Energi TimeEnergi agreement. TimeEnergi is a legacy
# product; confirm its account-specific surcharge on the bill.

andel_timeenergi_spottillaeg_oere <- function() {
  configured <- Sys.getenv("ANDEL_TIMEENERGI_SPOTTILLAEG_OERE", "14.63")
  value <- suppressWarnings(as.numeric(configured))
  if (!is.finite(value) || value < 0) stop("ANDEL_TIMEENERGI_SPOTTILLAEG_OERE must be non-negative", call. = FALSE)
  value
}

radius_tariff_incl_vat <- function(time) {
  summer <- lubridate::month(time) %in% 4:9
  hour <- lubridate::hour(time)
  dplyr::case_when(
    hour < 6 ~ ifelse(summer, 13.27, 12.20),
    hour < 17 ~ ifelse(summer, 19.91, 36.61),
    hour < 21 ~ ifelse(summer, 51.76, 109.85),
    TRUE ~ ifelse(summer, 19.91, 36.61)
  )
}

apply_consumer_price_components <- function(data, spot_col = "SpotPriceDKK") {
  data |>
    dplyr::mutate(
      RadiusNettarifInclMoms = radius_tariff_incl_vat(.data$HourDK),
      # Keep transport ex VAT for compatibility with the legacy calculations.
      transport = .data$RadiusNettarifInclMoms / 1.25,
      elafgift = 0.80,
      EnerginetTarif = 7.20 + 4.30,
      AndelPristillaeg = andel_timeenergi_spottillaeg_oere(),
      SpotPriceDKK_Total = 1.25 * (.data[[spot_col]] + .data$transport / 100 +
        .data$elafgift / 100 + .data$EnerginetTarif / 100) + .data$AndelPristillaeg / 100,
      SpotPriceDKK_Total_SansAfgift = 1.25 * (.data[[spot_col]] + .data$transport / 100 +
        .data$EnerginetTarif / 100) + .data$AndelPristillaeg / 100,
      SpotPriceDKK_Total_SansAfgiftTransport = 1.25 * .data[[spot_col]] / 100
    )
}
