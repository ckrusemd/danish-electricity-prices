# Negative cases ensure malformed or stale notebooks cannot silently pass CI.
source("tests/notebooks/helpers.R")
east <- read_notebook("EAST.ipynb")$notebook
west <- read_notebook("WEST.ipynb")$notebook
check_notebook_pair(east, west)
expect_failure <- function(expression, pattern) {
  error <- tryCatch({ force(expression); NULL }, error = identity)
  notebook_assert(inherits(error, "error") && grepl(pattern, conditionMessage(error)),
                  paste("Expected rejection:", pattern))
}
code_index <- which(vapply(east$cells, function(cell) cell$cell_type == "code", logical(1)))[1L]
broken <- east
broken$cells[[code_index]]$source <- list("stray invalid R here")
expect_failure(validate_notebook(broken), "invalid R")
broken <- east
broken$cells[[code_index]]$outputs <- list(list(output_type = "stream", text = "old prices"))
expect_failure(validate_notebook(broken), "clear outputs")
broken <- east
broken$cells[[code_index]]$execution_count <- 1L
expect_failure(validate_notebook(broken), "execution count")
broken <- east
broken$cells[[code_index]]$metadata$execution <- list(timestamp = "old")
expect_failure(validate_notebook(broken), "metadata")
broken <- east
broken$cells[[code_index]]$source <- list("\n")
expect_failure(validate_notebook(broken), "empty cell")
broken <- east
broken$metadata$kernelspec$name <- "local-private-kernel"
expect_failure(validate_notebook(broken), "standard ir kernel")
broken <- east
broken$cells[[code_index]]$source <- c(broken$cells[[code_index]]$source, list("httr::GET('example')\n"))
expect_failure(validate_notebook(broken), "external calls")
broken <- east
broken$cells[[code_index]]$source <- c(broken$cells[[code_index]]$source, list("mean(prices)\n"))
expect_failure(validate_notebook(broken), "calculations")
broken <- west
broken$cells[[code_index]]$source <- lapply(broken$cells[[code_index]]$source, function(text) sub("DK1", "DK2", text))
expect_failure(check_notebook_pair(east, broken), "WEST must select DK1")
cat("PASS notebook checker rejects invalid code, stale outputs, local kernels, duplicated calculations and wrong zones\n")
