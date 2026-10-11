#!/usr/bin/env Rscript
# Extract, parse and execute notebook code without a Jupyter installation.
arguments <- commandArgs(trailingOnly = TRUE)
script_arg <- grep("^--file=", commandArgs(), value = TRUE)
if (length(script_arg) != 1L) stop("Run with Rscript scripts/check-notebooks.R", call. = FALSE)
script <- normalizePath(sub("^--file=", "", script_arg), mustWork = TRUE)
root <- dirname(dirname(script))
setwd(root)
if (!requireNamespace("jsonlite", quietly = TRUE)) stop("Restore the locked jsonlite package first", call. = FALSE)
source("tests/notebooks/helpers.R")

if (length(arguments) && arguments[[1L]] == "--worker") {
  if (length(arguments) != 3L) stop("Invalid worker arguments", call. = FALSE)
  path <- normalizePath(arguments[[2L]], mustWork = TRUE)
  mode <- match.arg(arguments[[3L]], c("fixture", "snapshot", "unavailable"))
  checked <- read_notebook(path)
  install_offline_guards()
  Sys.setenv(ELECTRICITY_FIXTURE = "true")
  Sys.unsetenv("ELECTRICITY_DATA_FILE")
  # Match a fresh kernel's global environment: source() loads shared modules
  # there, and ggplot evaluates its data expressions there.
  if (mode != "fixture") {
    source("R/project.R")
    fixture <- prepare_analysis(now = as.POSIXct("2026-10-25 10:00:00", tz = "UTC"),
      fixture = TRUE, include_weather = FALSE, cache_dir = file.path(tempdir(), "data"))
    data_file <- file.path(tempdir(), "notebook-fixture.rds")
    saveRDS(fixture, data_file)
    Sys.setenv(ELECTRICITY_DATA_FILE = data_file)
    # A valid file must take precedence even if fixture preparation is disabled.
    Sys.setenv(ELECTRICITY_FIXTURE = "false")
  }
  grDevices::cairo_pdf(file.path(tempdir(), "notebook-plots.pdf"), width = 10, height = 6)
  for (cell in checked$codes) {
    tryCatch(eval(cell$expression, envir = globalenv()), error = function(e) {
      stop(basename(path), " [", mode, "] cell ", cell$index, ": ", conditionMessage(e), call. = FALSE)
    })
  }
  expected_zone <- if (basename(path) == "EAST.ipynb") "DK2" else "DK1"
  check_notebook_result(globalenv(), expected_zone)
  if (mode != "fixture") notebook_assert(identical(snapshot, fixture), "prepared snapshot was not reused verbatim")
  if (mode == "snapshot") {
    notebook_assert(nrow(zone_summary$today) == 25L && nrow(zone_summary$quarter_today) == 100L,
                    "autumn DST fixture must retain repeated local hours")
  }
  if (mode == "unavailable") {
    # A deliberately edited RDS would correctly fail snapshot validation.
    # Exercise empty-result presentation on an isolated copy of the summary
    # after a successful Run All using the original valid saved snapshot.
    for (table in c("upcoming_window", "historical_window", "history_profile")) {
      zone_summary[[table]] <- zone_summary[[table]][FALSE, , drop = FALSE]
    }
    output <- capture.output({
      for (cell in checked$codes) {
        if (grepl("low-windows|history-profile", checked$notebook$cells[[cell$index]]$id)) {
          eval(cell$expression, envir = globalenv())
        }
      }
    })
    notebook_assert(any(grepl("insufficient contiguous published prices", output, fixed = TRUE)) &&
      any(grepl("insufficient contiguous historical prices", output, fixed = TRUE)) &&
      any(grepl("Historical profile unavailable", output, fixed = TRUE)),
      "empty windows and profile must be explained")
  }
  invisible(grDevices::dev.off())
  cat("PASS", basename(path), mode, "Run All\n")
  quit(status = 0L)
}

parse_only <- "--parse-only" %in% arguments
paths <- arguments[arguments != "--parse-only"]
if (!length(paths)) paths <- c("EAST.ipynb", "WEST.ipynb")
paths <- vapply(paths, normalizePath, character(1), mustWork = TRUE)
checked <- lapply(paths, read_notebook)
names(checked) <- basename(paths)
if (all(c("EAST.ipynb", "WEST.ipynb") %in% names(checked))) {
  check_notebook_pair(checked$EAST.ipynb$notebook, checked$WEST.ipynb$notebook)
}
cat("PASS notebook JSON, metadata, cleared outputs, shared structure and R parsing\n")
if (parse_only) quit(status = 0L)
for (dependency in c("R/project.R", "R/plots.R")) {
  if (!file.exists(dependency)) stop("Shared implementation not yet available: ", dependency, call. = FALSE)
}
if (!requireNamespace("ggplot2", quietly = TRUE)) stop("Restore the locked ggplot2 package before execution", call. = FALSE)
for (path in paths) {
  for (mode in c("fixture", "snapshot", "unavailable")) {
    output <- system2(file.path(R.home("bin"), "Rscript"),
      c("--vanilla", shQuote(script), "--worker", shQuote(path), mode), stdout = TRUE, stderr = TRUE)
    status <- attr(output, "status") %||% 0L
    if (status != 0L) {
      cat(paste(output, collapse = "\n"), "\n")
      stop(basename(path), " failed in ", mode, " mode (status ", status, ")", call. = FALSE)
    }
    cat(tail(output, 1L), "\n")
  }
}
