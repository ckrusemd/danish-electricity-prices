#!/usr/bin/env Rscript
args <- commandArgs(trailingOnly = TRUE)
stopifnot(all(args %in% "--image"))
lock <- jsonlite::fromJSON("renv.lock", simplifyVector = FALSE)
stopifnot(identical(as.character(getRversion()), lock$R$Version))
for (record in lock$Packages) {
  name <- record$Package
  if (!requireNamespace(name, quietly = TRUE)) stop("Cannot load locked package: ", name)
  actual <- as.character(utils::packageVersion(name))
  if (utils::packageVersion(name) != package_version(record$Version)) stop(name, ": expected ", record$Version, ", found ", actual)
}
pins <- readLines("renvinfra/versions.env")
version <- sub("^QUARTO_VERSION=", "", grep("^QUARTO_VERSION=", pins, value = TRUE))
stopifnot(identical(system2("quarto", "--version", stdout = TRUE), version))
manifest <- "/opt/electricity/environment.sha256"
if ("--image" %in% args && !file.exists(manifest)) stop("Image has no verified environment fingerprint; rebuild with build-container")
if (file.exists(manifest)) {
  actual <- system2("bash", "scripts/environment-fingerprint.sh", stdout = TRUE)
  stopifnot(identical(readLines(manifest), actual))
}
cat("Verified R", as.character(getRversion()), "Quarto", version,
    "and", length(lock$Packages), "locked packages\n")
