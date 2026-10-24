site_tests <- function() {
  pages <- c("index.qmd", "east-denmark.qmd", "heatpump.qmd", "price-components.qmd")
  stopifnot(all(file.exists(pages)))
  config <- readLines("_quarto.yml", warn = FALSE)
  rendered <- trimws(sub("^- ", "", trimws(config[grepl("^    - .*\\.qmd$", config)])))
  stopifnot(identical(rendered, pages),
            any(grepl("output-dir: _site", config, fixed = TRUE)),
            any(grepl("execute-dir: project", config, fixed = TRUE)),
            any(grepl("freeze: false", config, fixed = TRUE)),
            any(grepl("cache: false", config, fixed = TRUE)))
  for (page in pages) {
    text <- paste(readLines(page, warn = FALSE), collapse = "\n")
    stopifnot(grepl('source("R/project.R")', text, fixed = TRUE),
              grepl("site_read_snapshot()", text, fixed = TRUE),
              !grepl("fetch_|prepare_analysis\\(|load_or_prepare_analysis\\(", text))
  }
  source("scripts/site-helpers.R", local = environment())
  source("scripts/site-redirects.R", local = environment())
  source("R/plots.R", local = environment())
  stopifnot(identical(names(formals(plot_daily_prices)), c("snapshot", "zone")),
            site_escape('<x & "y">') == '&lt;x &amp; &quot;y&quot;&gt;')
  original_path <- Sys.getenv("ELECTRICITY_DATA_FILE", unset = NA_character_)
  on.exit(if (is.na(original_path)) Sys.unsetenv("ELECTRICITY_DATA_FILE") else
    Sys.setenv(ELECTRICITY_DATA_FILE = original_path), add = TRUE)
  Sys.unsetenv("ELECTRICITY_DATA_FILE")
  missing_snapshot <- tryCatch(site_read_snapshot(), error = identity)
  stopifnot(inherits(missing_snapshot, "error"),
            grepl("prepare-data.R --fixture", conditionMessage(missing_snapshot), fixed = TRUE))
  if (!is.na(original_path)) Sys.setenv(ELECTRICITY_DATA_FILE = original_path)
  empty <- list(summaries = list(DK1 = list(upcoming_window = data.frame())))
  stopifnot(grepl("No complete", site_window_hero(empty, "DK1"), fixed = TRUE))
  meta <- list(date = "2026-10-11", generated_at = "2026-10-11T05:00:00Z",
               quarter_prices = data.frame(),
               meta = list(provider = list(prices = "Fixture <source>", weather = NULL),
                           scenario = "Radius / Andel", coverage = list(prices = list(DK1 = list(today = "partial")))))
  output <- paste(capture.output(site_metadata(meta)), collapse = "\n")
  stopifnot(grepl("Fixture &lt;source&gt;", output, fixed = TRUE),
            grepl("partial", output, fixed = TRUE))
  if (requireNamespace("knitr", quietly = TRUE)) {
    table <- paste(capture.output(site_table(data.frame(HourBand = 7L, Observations = 12L,
      ConsumerPriceDKK = 1.234), "test counts")), collapse = "\n")
    stopifnot(!grepl("7.000|12.000", table), grepl("1.234", table, fixed = TRUE))
  }
  redirect_dir <- tempfile("site-redirect-test-")
  dir.create(redirect_dir)
  on.exit(unlink(redirect_dir, recursive = TRUE), add = TRUE)
  for (target in unique(unname(site_redirect_routes()))) writeLines("test page", file.path(redirect_dir, target))
  routes <- site_write_redirects(redirect_dir)
  for (alias in names(routes)) {
    html <- paste(readLines(file.path(redirect_dir, alias), warn = FALSE), collapse = "\n")
    stopifnot(grepl(paste0('href="', routes[[alias]], '"'), html, fixed = TRUE),
              grepl("location.search+hash", html, fixed = TRUE))
  }
  if (requireNamespace("ggplot2", quietly = TRUE)) site_plot_tests()
  else message("Plot builds unavailable: ggplot2 is not installed in the active library.")
  invisible(TRUE)
}

site_plot_tests <- function() {
  source("R/plots.R", local = environment())
  utc <- as.POSIXct(c("2026-10-25 00:00:00", "2026-10-25 01:00:00"), tz = "UTC")
  quarter <- data.frame(TimeUTC = utc, TimeDK = as.POSIXct(as.numeric(utc), origin = "1970-01-01", tz = "Europe/Copenhagen"),
                        PriceArea = "DK1", SpotPriceDKK = c(-0.4, 0.7))
  hourly <- data.frame(HourUTC = utc, HourDK = quarter$TimeDK, PriceArea = "DK1",
                       SpotPriceDKK = c(-0.4, 0.7), SpotPriceDKK_Total = c(0.1, 1.3))
  snapshot <- list(date = "2026-10-25", quarter_prices = quarter, hourly_prices = hourly,
    heatmap = data.frame(PriceArea = "DK1", TemperatureBand = c(4L, 5L), HourBand = c(7L, 23L),
                        ConsumerPriceDKK = c(-0.2, 1.2), Observations = c(1L, 9L)),
    summaries = list(DK1 = list(quarter_today = quarter,
      history_profile = data.frame(hour = 2L, minute = 0L, q25 = -0.1, median = 0.2, q75 = 0.4))))
  daily <- ggplot2::ggplot_build(plot_daily_prices(snapshot, "DK1"))
  stopifnot(daily$layout$panel_params[[1]]$y.range[1] < -0.4,
            all(daily$data[[2]]$ymin == -0.1), nrow(daily$data[[4]]) == 2L,
            diff(daily$data[[4]]$x) == 3600)
  hourly_plot <- ggplot2::ggplot_build(plot_hourly_overview(snapshot, "DK1"))
  stopifnot(hourly_plot$layout$panel_params[[1]]$y.range[1] < -0.4)
  heat <- plot_heatmap(snapshot, "DK1")
  scale <- heat$scales$get_scales("fill")
  stopifnot(identical(tolower(scale$palette(c(0, 1))), c("#062b5c", "#ffffff")))
  ggplot2::ggplot_build(heat)
  mixed <- snapshot
  east <- snapshot$heatmap
  east$PriceArea <- "DK2"
  mixed$heatmap <- rbind(snapshot$heatmap, east)
  mixed$summaries$DK2 <- mixed$summaries$DK1
  stopifnot(all(plot_heatmap(mixed)$data$PriceArea == "DK2"))
  snapshot$summaries$DK1$quarter_today <- quarter[FALSE, ]
  snapshot$heatmap <- snapshot$heatmap[FALSE, ]
  ggplot2::ggplot_build(plot_daily_prices(snapshot, "DK1"))
  ggplot2::ggplot_build(plot_heatmap(snapshot))
  invisible(TRUE)
}

site_rendered_tests <- function(output_dir) {
  pages <- c("index.html", "east-denmark.html", "heatpump.html", "price-components.html")
  stopifnot(all(file.exists(file.path(output_dir, pages))))
  for (page in pages) {
    html <- paste(readLines(file.path(output_dir, page), warn = FALSE), collapse = "\n")
    stopifnot(grepl("quarto", html, fixed = TRUE),
              grepl("Snapshot date:", html, fixed = TRUE),
              !grepl("Error in |Execution halted", html))
    links <- regmatches(html, gregexpr('(?:href|src)="[^"#]+"', html, perl = TRUE))[[1]]
    links <- sub('^[^=]+="', "", sub('"$', "", links))
    links <- unique(sub("[?#].*$", "", links))
    links <- links[!grepl("^(https?:|mailto:|data:|javascript:|/)", links)]
    for (link in links) stopifnot(file.exists(file.path(output_dir, URLdecode(link))))
  }
  source("scripts/site-redirects.R", local = environment())
  stopifnot(all(file.exists(file.path(output_dir, names(site_redirect_routes())))))
  invisible(TRUE)
}
