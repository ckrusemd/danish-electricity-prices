#!/usr/bin/env Rscript
# Run from the project root. No HTTP requests or preparation occurs here.
source("tests/site/test-site.R")
site_tests()
args <- commandArgs(trailingOnly = TRUE)
if ("--rendered" %in% args) site_rendered_tests("_site")
cat("Site checks passed", if ("--rendered" %in% args) " (including rendered HTML)" else " (source and presentation)", ".\n", sep = "")
