# Explicit 2026 Radius C / Andel FlexEnergi scenario applied to both spot zones.
# All per-kWh rates below are ore unless the column name says DKK.
consumer_price_scenario <- function() {
  list(id = "radius-c-andel-flexenergi-2026", year = 2026L,
       label = "Radius C / Andel FlexEnergi 2026",
       description = "Illustrative Radius/Andel household scenario in both zones; DK1 is not a local grid quote.",
       currency = "DKK/kWh", vat = 1.25, supplier_markup_incl_vat_ore = 14.63,
       electricity_tax_ex_vat_ore = 0.80, system_tariff_ex_vat_ore = 7.20,
       grid_tariff_ex_vat_ore = 4.30, fixed_subscriptions_included = FALSE,
       outside_rate_year = "2026 rates retained as an illustrative scenario")
}

andel_flexenergi_spottillaeg_oere <- function() 14.63

radius_tariff_incl_vat <- function(time) {
  summer <- as.integer(format(time, "%m", tz = "Europe/Copenhagen")) %in% 4:9
  hour <- as.integer(format(time, "%H", tz = "Europe/Copenhagen"))
  ifelse(hour < 6, ifelse(summer, 13.27, 12.20),
    ifelse(hour >= 17 & hour < 21, ifelse(summer, 51.76, 109.85),
           ifelse(summer, 19.91, 36.61)))
}

apply_consumer_price_components <- function(data, spot_col = "SpotPriceDKK") {
  if (!is.data.frame(data) || !all(c("HourDK", spot_col) %in% names(data)) ||
      !is.numeric(data[[spot_col]]) || any(!is.finite(data[[spot_col]]))) {
    stop("Consumer pricing requires valid hourly spot prices", call. = FALSE)
  }
  data$RadiusNettarifInclMoms <- radius_tariff_incl_vat(data$HourDK)
  data$transport <- data$RadiusNettarifInclMoms / 1.25
  data$elafgift <- rep(0.80, nrow(data))
  data$EnerginetTarif <- rep(7.20 + 4.30, nrow(data))
  data$AndelPristillaeg <- rep(andel_flexenergi_spottillaeg_oere(), nrow(data))
  data$SpotPriceDKK_Total <- 1.25 * (data[[spot_col]] + data$transport / 100 +
    data$elafgift / 100 + data$EnerginetTarif / 100) + data$AndelPristillaeg / 100
  data$SpotPriceDKK_Total_SansAfgift <- 1.25 * (data[[spot_col]] + data$transport / 100 +
    data$EnerginetTarif / 100) + data$AndelPristillaeg / 100
  # Spot is already DKK/kWh: dividing by 100 again was a unit error.
  data$SpotPriceDKK_Total_SansAfgiftTransport <- 1.25 * data[[spot_col]]
  data
}
