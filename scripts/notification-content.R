# Presentation only: the shared snapshot supplies summaries and profiles.
notification_body <- function(snapshot) {
  number <- function(x) {
    if (length(x) != 1L || !is.finite(x)) stop("Invalid summary price", call. = FALSE)
    sprintf("%.2f", x)
  }
  window <- function(x) {
    if (!is.data.frame(x) || !nrow(x)) return("Unavailable")
    if (nrow(x) != 1L || !all(c("start", "end", "average", "total") %in% names(x)))
      stop("Invalid shared window summary", call. = FALSE)
    paste0(format(x$start, "%d/%m %H:%M %Z", tz = "Europe/Copenhagen"), " – ",
           format(x$end, "%d/%m %H:%M %Z", tz = "Europe/Copenhagen"),
           "\nAverage: ", number(x$average), " DKK/kWh")
  }
  summary <- snapshot$summaries$DK2
  periods <- summary$period_averages
  labels <- c("00-06", "06-09", "09-17", "17-21", "21-24")
  if (!is.data.frame(periods) || !all(c("label", "average") %in% names(periods)) ||
      anyDuplicated(periods$label) || !all(labels %in% periods$label))
    stop("Missing shared period averages for DK2", call. = FALSE)
  values <- vapply(periods$average[match(labels, periods$label)], function(x) {
    if (is.na(x)) "Unavailable" else number(x)
  }, character(1))
  coverage <- snapshot$meta$coverage$prices$DK2
  upcoming_label <- if (isTRUE(coverage$upcoming$complete)) "Best 3 hours in the next 24h" else
    "Best published 3 hours (provisional)"
  history_complete <- isTRUE(coverage$history$complete)
  historical_window <- if (history_complete) summary$historical_window else
    summary$historical_window[FALSE, , drop = FALSE]
  comparison <- character()
  if (nrow(summary$upcoming_window) == 1L && nrow(historical_window) == 1L) {
    difference <- summary$upcoming_window$average - historical_window$average
    comparison <- paste0(number(abs(difference)), " DKK/kWh ",
      if (difference < 0) "below" else if (difference > 0) "above" else "equal to", " the 6-month low")
  }
  body <- paste(c(paste("East Denmark (DK2) ·", snapshot$date),
    "Wholesale spot · DKK/kWh\nBefore VAT and consumer charges · Copenhagen time",
    paste(upcoming_label, window(summary$upcoming_window), sep = "\n"),
    paste(c("Today's period averages (DKK/kWh)", paste(labels, values, sep = ": ")), collapse = "\n"),
    paste(c("6-month low (historical)", window(historical_window),
      if (!history_complete) "Incomplete history" else character(), comparison), collapse = "\n")),
    collapse = "\n\n")
  if (nchar(body, type = "chars") > 1024L) stop("Notification exceeds 1024 characters", call. = FALSE)
  body
}

notification_graph <- function(snapshot, path = tempfile(fileext = ".png")) {
  grDevices::png(path, width = 1200, height = 800, res = 150)
  on.exit(grDevices::dev.off(), add = TRUE)
  graphics::par(mar = c(4, 4, 5, 1))
  colours <- c(DK2 = "#ea580c")
  for (zone in names(colours)) {
    today <- snapshot$summaries[[zone]]$quarter_today
    profile <- snapshot$summaries[[zone]]$history_profile
    if (!is.data.frame(today) || !nrow(today) ||
        !all(c("TimeUTC", "TimeDK", "SpotPriceDKK") %in% names(today)))
      stop("Missing shared quarter-hour prices for ", zone, call. = FALSE)
    if (!is.data.frame(profile) || !all(c("hour", "minute", "q25", "median", "q75") %in% names(profile)))
      stop("Invalid shared history profile for ", zone, call. = FALSE)
    today <- today[order(today$TimeUTC), ]
    # The profile is keyed by Copenhagen display slot, not a second timeline.
    # Actual timestamps stay UTC, including repeated autumn hours.
    index <- match(paste(as.integer(format(today$TimeDK, "%H", tz = "Europe/Copenhagen")),
                        as.integer(format(today$TimeDK, "%M", tz = "Europe/Copenhagen"))),
                   paste(profile$hour, profile$minute))
    overlay <- profile[index, , drop = FALSE]
    x <- as.numeric(today$TimeUTC)
    limits <- range(c(today$SpotPriceDKK, overlay$q25, overlay$q75), finite = TRUE)
    graphics::plot(x, today$SpotPriceDKK, type = "n", xaxt = "n", ylim = limits,
                   xlab = "", ylab = "Spot price (DKK/kWh)", main = "")
    graphics::title(main = paste("East Denmark (DK2) ·", snapshot$date), line = 3.2)
    good <- is.finite(overlay$q25) & is.finite(overlay$q75)
    if (any(good)) graphics::polygon(c(x[good], rev(x[good])),
      c(overlay$q25[good], rev(overlay$q75[good])),
      col = grDevices::adjustcolor(colours[[zone]], alpha.f = 0.16), border = NA)
    graphics::lines(x, overlay$median, lty = 2, col = colours[[zone]])
    graphics::lines(x, today$SpotPriceDKK, lwd = 2, col = colours[[zone]])
    ticks <- seq(1L, nrow(today), by = 12L)
    graphics::axis(1, at = x[ticks], labels = format(today$TimeDK[ticks], "%H:%M %Z", tz = "Europe/Copenhagen"), cex.axis = 0.9)
    graphics::legend("top", inset = c(0, -0.14), xpd = NA, horiz = TRUE, c("Today", "30-day median", "Middle 50%"),
      lty = c(1, 2, 1), col = c(colours[[zone]], colours[[zone]], grDevices::adjustcolor(colours[[zone]], alpha.f = 0.3)),
      bty = "n", cex = 0.9)
  }
  path
}
