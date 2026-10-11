# Presentation only: all prices, historical profiles and heatmap cells come
# from the validated shared analysis snapshot. No data retrieval here.
if (!exists("plot_theme", mode = "function")) source("R/plot-theme.R")

plot_zone <- function(snapshot, zone) {
  if (length(zone) != 1L || !zone %in% c("DK1", "DK2")) {
    stop("zone must be DK1 or DK2.", call. = FALSE)
  }
  snapshot$summaries[[zone]]
}

plot_empty <- function(title, message) {
  ggplot2::ggplot() +
    ggplot2::annotate("text", x = 0, y = 0, label = message,
                      colour = "#a9bbb9", size = 4) +
    ggplot2::labs(title = title, x = NULL, y = NULL) +
    plot_theme() +
    ggplot2::theme(axis.text = ggplot2::element_blank(),
                   panel.grid = ggplot2::element_blank())
}

plot_daily_prices <- function(snapshot, zone) {
  summary <- plot_zone(snapshot, zone)
  prices <- summary$quarter_today
  title <- paste(zone, "· today's quarter-hour spot prices")
  if (!nrow(prices)) return(plot_empty(title, "No quarter-hour prices available for this date."))
  prices <- prices[order(prices$TimeUTC), , drop = FALSE]
  profile <- summary$history_profile
  # Map the precomputed clock-hour profile to each UTC instant. On the autumn
  # clock change, both occurrences receive the same clock-time reference.
  key <- paste(format(prices$TimeUTC, "%H", tz = "Europe/Copenhagen"),
               format(prices$TimeUTC, "%M", tz = "Europe/Copenhagen"))
  reference <- profile[match(key, paste(sprintf("%02d", profile$hour),
                                       sprintf("%02d", profile$minute))), , drop = FALSE]
  reference$TimeUTC <- prices$TimeUTC
  start <- as.POSIXct(as.numeric(as.POSIXct(snapshot$date, tz = "Europe/Copenhagen")), origin = "1970-01-01", tz = "UTC")
  end <- as.POSIXct(as.numeric(as.POSIXct(as.character(as.Date(snapshot$date) + 1), tz = "Europe/Copenhagen")), origin = "1970-01-01", tz = "UTC")
  p <- ggplot2::ggplot(prices, ggplot2::aes(x = TimeUTC)) +
    ggplot2::geom_hline(yintercept = 0, colour = "#78908d", linewidth = 0.45)
  if (nrow(profile)) {
    p <- p +
      ggplot2::geom_ribbon(data = reference,
                           ggplot2::aes(ymin = q25, ymax = q75, fill = "Historical Q25–Q75"),
                           alpha = 0.22, na.rm = TRUE) +
      ggplot2::geom_line(data = reference,
                         ggplot2::aes(y = median, colour = "Historical median"),
                         linewidth = 0.7, linetype = "dashed", na.rm = TRUE)
  }
  p + ggplot2::geom_segment(
    ggplot2::aes(xend = TimeUTC + 15 * 60, y = SpotPriceDKK,
                 yend = SpotPriceDKK, colour = "Today's spot price"), linewidth = 1.1) +
    ggplot2::scale_x_datetime(timezone = "Europe/Copenhagen", date_breaks = "4 hours",
                              date_labels = "%H:%M", limits = c(start, end),
                              expand = ggplot2::expansion(mult = c(0, 0.01))) +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = 0.08)) +
    ggplot2::scale_colour_manual(values = c("Today's spot price" = "#42e0c0",
                                            "Historical median" = "#ffc857"), name = NULL) +
    ggplot2::scale_fill_manual(values = c("Historical Q25–Q75" = "#7eb8ff"), name = NULL) +
    ggplot2::labs(title = title, subtitle = paste(snapshot$date, "· wholesale, before VAT and consumer charges"),
                   x = "Copenhagen time", y = "DKK/kWh",
                   caption = "Reference: 30 completed days · median and middle 50% at the same local clock time.") +
    plot_theme()
}

plot_hourly_overview <- function(snapshot, zone) {
  plot_zone(snapshot, zone)
  prices <- snapshot$hourly_prices
  start <- as.POSIXct(as.character(as.Date(snapshot$date) - 7), tz = "Europe/Copenhagen")
  prices <- prices[prices$PriceArea == zone & as.numeric(prices$HourUTC) >= as.numeric(start), , drop = FALSE]
  prices <- prices[order(prices$HourUTC), , drop = FALSE]
  if (!nrow(prices)) return(plot_empty(paste(zone, "· hourly overview"), "No hourly prices available."))
  p <- ggplot2::ggplot(prices, ggplot2::aes(x = HourUTC)) +
    ggplot2::geom_hline(yintercept = 0, colour = "#78908d", linewidth = 0.45) +
    ggplot2::geom_segment(ggplot2::aes(xend = HourUTC + 3600, y = SpotPriceDKK,
                                      yend = SpotPriceDKK, colour = "Wholesale spot"), linewidth = 0.65)
  colours <- c("Wholesale spot" = "#42e0c0")
  if (zone == "DK2") {
    p <- p + ggplot2::geom_segment(
      ggplot2::aes(xend = HourUTC + 3600, y = SpotPriceDKK_Total, yend = SpotPriceDKK_Total,
                   colour = "Radius / Andel scenario (incl. VAT)"), linewidth = 0.75)
    colours <- c(colours, "Radius / Andel scenario (incl. VAT)" = "#ffc857")
  }
  p + ggplot2::geom_vline(xintercept = as.POSIXct(as.numeric(as.POSIXct(snapshot$date, tz = "Europe/Copenhagen")), origin = "1970-01-01", tz = "UTC"),
                          colour = "#7eb8ff", linetype = "dotted") +
    ggplot2::scale_x_datetime(timezone = "Europe/Copenhagen", date_breaks = "2 days", date_labels = "%d %b") +
    ggplot2::scale_y_continuous(expand = ggplot2::expansion(mult = 0.08)) +
    ggplot2::scale_colour_manual(values = colours, name = NULL) +
    ggplot2::labs(title = paste(zone, "· recent and published hourly prices"),
                   x = "Copenhagen date", y = "DKK/kWh",
                   caption = "Dotted line: start of snapshot date. Published future prices are not a forecast.") +
    plot_theme()
}

plot_heatmap <- function(snapshot, zone = NULL) {
  cells <- snapshot$heatmap
  if (!is.null(zone)) {
    plot_zone(snapshot, zone)
    cells <- cells[cells$PriceArea == zone, , drop = FALSE]
  }
  if (!nrow(cells)) return(plot_empty("Temperature and electricity price", "Weather / price heatmap unavailable in this snapshot."))
  ggplot2::ggplot(cells, ggplot2::aes(x = TemperatureBand, y = HourBand, fill = ConsumerPriceDKK)) +
    ggplot2::geom_tile(colour = "#173238", linewidth = 0.2) +
    ggplot2::facet_wrap(~ PriceArea, ncol = 1) +
    ggplot2::scale_fill_gradient(low = "#062b5c", high = "#ffffff",
                                 na.value = "#173238", name = "DKK/kWh") +
    ggplot2::scale_y_continuous(breaks = 7:23, limits = c(6.5, 23.5), expand = c(0, 0)) +
    ggplot2::scale_x_continuous(expand = ggplot2::expansion(add = 0.5)) +
    ggplot2::labs(title = "Temperature and hourly consumer-price scenario",
                   subtitle = "Radius / Andel charges applied to each zone's spot prices",
                   x = "Outdoor temperature band (°C)", y = "Copenhagen clock hour",
                   caption = "Dark blue = lowest mean price; white = highest. Missing cells have no observations.") +
    plot_theme()
}
