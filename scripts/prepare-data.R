#!/usr/bin/env Rscript
# Build one snapshot for all consumers. No notification or secret access.
arguments <- commandArgs(trailingOnly = TRUE)
fixture <- FALSE
include_weather <- TRUE
output <- NULL
i <- 1L
while (i <= length(arguments)) {
  argument <- arguments[i]
  if (identical(argument, "--fixture")) fixture <- TRUE else
  if (identical(argument, "--without-weather")) include_weather <- FALSE else
  if (identical(argument, "--output")) {
    i <- i + 1L
    if (i > length(arguments) || startsWith(arguments[i], "--")) stop("--output requires a path")
    output <- arguments[i]
  } else if (identical(argument, "--help")) {
    cat("Usage: Rscript --vanilla scripts/prepare-data.R [--fixture] [--without-weather] --output PATH\n")
    quit(status = 0L)
  } else stop("Unknown argument: ", argument)
  i <- i + 1L
}
if (is.null(output) || !nzchar(output)) stop("--output PATH is required")
script_arg <- commandArgs(trailingOnly = FALSE)
script <- sub("^--file=", "", script_arg[startsWith(script_arg, "--file=")][1L])
root <- dirname(dirname(normalizePath(script)))
output <- if (startsWith(output, "/")) output else file.path(getwd(), output)
source(file.path(root, "R", "project.R"))
snapshot <- prepare_analysis(now = if (fixture) fixture_reference_time() else Sys.time(),
  fixture = fixture, include_weather = include_weather, cache_dir = file.path(root, ".cache", "data"))
write_rds_atomic(snapshot, output)
cat("Analysis snapshot: ", normalizePath(output), "\n", sep = "")
cat("Date: ", snapshot$date, "; quarters: ", nrow(snapshot$quarter_prices),
    "; hours: ", nrow(snapshot$hourly_prices), "; weather: ",
    if (is.null(snapshot$weather)) 0L else nrow(snapshot$weather), "\n", sep = "")
for (zone in names(snapshot$summaries)) {
  coverage <- snapshot$meta$coverage$prices[[zone]]$upcoming
  cat(zone, " upcoming quarters: ", coverage$observed, "/", coverage$expected,
    if (coverage$complete) " (complete)" else " (incomplete; window is provisional)", "\n", sep = "")
}
