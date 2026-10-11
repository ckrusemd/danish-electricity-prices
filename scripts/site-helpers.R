# HTML formatting helpers; do not fetch or recalculate analysis data.
site_read_snapshot <- function() {
  path <- Sys.getenv("ELECTRICITY_DATA_FILE")
  if (!nzchar(path) || !file.exists(path)) {
    stop("Set ELECTRICITY_DATA_FILE to a prepared snapshot RDS before rendering. ",
         "For offline validation: Rscript scripts/prepare-data.R --fixture --output .cache/site-fixture.rds",
         call. = FALSE)
  }
  read_analysis(path)
}

site_escape <- function(x) {
  x <- gsub("&", "&amp;", as.character(x), fixed = TRUE)
  x <- gsub("<", "&lt;", x, fixed = TRUE)
  x <- gsub(">", "&gt;", x, fixed = TRUE)
  gsub('"', "&quot;", x, fixed = TRUE)
}

site_time <- function(x) format(x, "%d %b %H:%M %Z", tz = "Europe/Copenhagen")
site_number <- function(x) ifelse(is.finite(x), sprintf("%.3f", x), "Unavailable")

site_meta_lines <- function(value, prefix = "") {
  if (is.null(value) || !length(value)) return(character())
  if (is.list(value) || is.data.frame(value)) {
    keys <- names(value)
    if (is.null(keys)) keys <- seq_along(value)
    return(unlist(lapply(seq_along(value), function(i) {
      site_meta_lines(value[[i]], paste0(prefix, if (nzchar(prefix)) " · " else "", keys[i]))
    }), use.names = FALSE))
  }
  text <- if (inherits(value, "POSIXt")) site_time(value) else as.character(value)
  paste0(prefix, if (nzchar(prefix)) ": " else "", paste(text, collapse = ", "))
}

site_table <- function(data, caption, empty = "No observations available in this snapshot.") {
  if (is.null(data) || !nrow(data)) {
    cat('<p class="publication-note">', site_escape(empty), '</p>\n', sep = "")
    return(invisible(NULL))
  }
  for (name in names(data)) {
    if (inherits(data[[name]], "POSIXt")) data[[name]] <- site_time(data[[name]])
    else if (is.numeric(data[[name]])) {
      if (grepl("Observations|HourBand|TemperatureBand|Count|bands|hour$|minute$", name)) {
        data[[name]] <- ifelse(is.finite(data[[name]]), as.character(data[[name]]), "Unavailable")
      } else data[[name]] <- site_number(data[[name]])
    }
  }
  cat('<div class="table-scroll" role="region" tabindex="0" aria-label="',
      site_escape(caption), '">', sep = "")
  cat(as.character(knitr::kable(data, format = "html", escape = TRUE, caption = caption,
                                row.names = FALSE)), "</div>\n", sep = "")
}

site_metadata <- function(snapshot, zone = NULL) {
  prices <- snapshot$quarter_prices
  if (!is.null(zone)) prices <- prices[prices$PriceArea == zone, , drop = FALSE]
  cat('<div class="snapshot-meta"><p><strong>Snapshot date:</strong> ',
      site_escape(snapshot$date), ' · <strong>Generated:</strong> ',
      site_escape(snapshot$generated_at), ' (UTC)</p>', sep = "")
  if (isTRUE(snapshot$meta$fixture)) {
    cat('<p class="fixture-label"><strong>Demonstration snapshot:</strong> synthetic fixture data; use for validation only.</p>')
  }
  if (nrow(prices)) {
    cat('<p><strong>Available market coverage:</strong> ', site_escape(site_time(min(prices$TimeUTC))),
        ' – ', site_escape(site_time(max(prices$TimeUTC) + 900)), '</p>', sep = "")
  }
  coverage <- snapshot$meta$coverage
  zones <- if (is.null(zone)) c("DK1", "DK2") else zone
  for (area in zones) {
    zone_coverage <- coverage$prices[[area]]
    for (period in intersect(c("today", "overlay", "history", "upcoming"), names(zone_coverage))) {
      item <- zone_coverage[[period]]
      if (!is.list(item)) next
      label <- switch(period, today = "Today", overlay = "30 completed days", history = "Six-month history", upcoming = "Upcoming")
      status <- if (isTRUE(item$complete)) "Complete" else "Incomplete"
      counts <- if (!is.null(item$observed) && !is.null(item$expected))
        paste0(" · ", item$observed, "/", item$expected, " quarter-hours") else ""
      cat('<p><strong>', site_escape(paste(area, label)), ':</strong> ', status, site_escape(counts), '</p>', sep = "")
    }
    # The per-day diagnostic frame is intentionally omitted from the metadata
    # panel; the aggregate completeness and counts above are the useful view.
    coverage$prices[[area]]$days <- NULL
  }
  if (!is.null(zone)) coverage$prices <- coverage$prices[zone]
  if (is.null(zone) && is.list(coverage$weather)) {
    weather <- coverage$weather
    counts <- if (!is.null(weather$observed) && !is.null(weather$expected))
      paste0(" · ", weather$observed, "/", weather$expected, " hours · ", weather$missing, " missing") else ""
    cat('<p><strong>Weather coverage:</strong> ',
        site_escape(if (isTRUE(weather$complete)) "Complete" else "Incomplete / unavailable"),
        site_escape(counts), '</p>', sep = "")
  }
  metadata <- list(provider = snapshot$meta$provider, scenario = snapshot$meta$scenario,
                   history = snapshot$meta$history, coverage = coverage)
  for (key in names(metadata)) {
    labels <- site_meta_lines(metadata[[key]])
    if (length(labels)) {
      cat('<details><summary>', site_escape(tools::toTitleCase(key)),
          '</summary><ul><li>', paste(site_escape(labels), collapse = "</li><li>"), '</li></ul></details>', sep = "")
    }
  }
  cat('</div>\n')
}

site_window_hero <- function(snapshot, zone) {
  window <- snapshot$summaries[[zone]]$upcoming_window
  if (is.null(window) || !nrow(window)) {
    return("No complete upcoming window is available. Check the published price table before scheduling use.")
  }
  provisional <- snapshot$meta$coverage$prices[[zone]]$upcoming$window_provisional
  paste0(if (isTRUE(provisional)) "Provisional best published wholesale window: " else "Best available wholesale window: ",
         site_time(window$start[1]), " – ", site_time(window$end[1]), ". Average ",
         site_number(window$average[1]), " DKK/kWh before consumer charges.",
         if (isTRUE(provisional)) " Upcoming coverage is incomplete; later published prices may change this choice." else "")
}

site_windows <- function(data, caption) {
  if (!is.null(data) && nrow(data)) {
    data <- data[, c("start", "end", "average", "total"), drop = FALSE]
    names(data) <- c("Start (Copenhagen)", "End (Copenhagen)", "Wholesale average (DKK/kWh)",
                     "Wholesale cost for 1 kW throughout (DKK)")
  }
  site_table(data, caption, "No complete contiguous window is available for this period.")
}

site_today <- function(snapshot, zone) {
  data <- snapshot$summaries[[zone]]$today
  cols <- c("HourUTC", "SpotPriceDKK")
  labels <- c("Hour (Copenhagen)", "Wholesale spot (DKK/kWh)")
  if (zone == "DK2") {
    cols <- c(cols, "SpotPriceDKK_Total")
    labels <- c(labels, "Radius / Andel incl. VAT (DKK/kWh)")
  }
  data <- data[, cols, drop = FALSE]
  names(data) <- labels
  site_table(data, paste(zone, "· today's hourly prices"))
}
