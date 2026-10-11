# Shared assertions for the notebook checker and its regression tests.
notebook_assert <- function(ok, message) {
  if (!isTRUE(ok)) stop(message, call. = FALSE)
}

validate_notebook <- function(notebook, label = "notebook") {
  fail <- function(ok, message) notebook_assert(ok, paste0(label, ": ", message))
  fail(identical(notebook$nbformat, 4L), "expected notebook format 4")
  fail(identical(notebook$metadata$kernelspec$name, "ir") &&
         identical(notebook$metadata$kernelspec$language, "R"),
       "use the portable standard ir kernel")
  fail(identical(notebook$metadata$language_info$name, "R"), "expected R language metadata")
  fail(length(notebook$cells) >= 6L && length(notebook$cells) <= 10L,
       "expected 6–10 meaningful cells")
  ids <- vapply(notebook$cells, function(cell) cell$id %||% "", character(1))
  fail(all(nzchar(ids)) && !anyDuplicated(ids), "cell ids must be nonempty and unique")
  codes <- list()
  for (i in seq_along(notebook$cells)) {
    cell <- notebook$cells[[i]]
    fail(cell$cell_type %in% c("markdown", "code"), paste("unexpected cell type at", i))
    fail(is.character(unlist(cell$source)) || length(cell$source) == 0L,
         paste("invalid source at cell", i))
    text <- paste0(unlist(cell$source), collapse = "")
    fail(nzchar(trimws(text)), paste("empty cell", i))
    fail(!any(c("execution", "ExecuteTime", "collapsed", "vscode") %in% names(cell$metadata)),
         paste("remove execution/editor metadata at cell", i))
    if (cell$cell_type != "code") next
    fail("execution_count" %in% names(cell) && is.null(cell$execution_count),
         paste("execution count must be null at cell", i))
    fail("outputs" %in% names(cell) && length(cell$outputs) == 0L,
         paste("clear outputs at cell", i))
    expression <- tryCatch(parse(text = text, keep.source = TRUE),
      error = function(e) stop(label, ": invalid R in cell ", i, ": ", conditionMessage(e), call. = FALSE))
    fail(length(expression) > 0L, paste("empty R expression at cell", i))
    tokens <- utils::getParseData(expression)
    calls <- tokens$text[tokens$token == "SYMBOL_FUNCTION_CALL"]
    fail(!any(grepl("^(fetch_|send_|notify|pushover|apply_consumer)|^(GET|POST|RETRY|download.file|url|readRDS|prepare_analysis|mean|quantile|aggregate|install.packages|p_load|system|system2)$", calls)),
         paste("use shared snapshot calculations; external calls or calculations found at cell", i))
    fail(!grepl("https?://|API_|TARIFF_|EXCHANGE_RATE", text),
         paste("embedded API or tariff configuration at cell", i))
    codes[[length(codes) + 1L]] <- list(index = i, text = text, expression = expression)
  }
  fail(length(codes) > 0L, "no R code cells")
  all_code <- paste(vapply(codes, `[[`, character(1), "text"), collapse = "\n")
  fail(grepl('source("R/project.R")', all_code, fixed = TRUE) &&
         grepl('source("R/plots.R")', all_code, fixed = TRUE), "source shared project and plotting modules")
  fail(length(gregexpr("load_or_prepare_analysis\\(", all_code)[[1]]) == 1L &&
         grepl("load_or_prepare_analysis(include_weather = FALSE)", all_code, fixed = TRUE),
       "load one snapshot without weather")
  fail(grepl("plot_daily_prices(snapshot, zone)", all_code, fixed = TRUE), "use the shared daily chart")
  codes
}

`%||%` <- function(x, fallback) if (is.null(x)) fallback else x

read_notebook <- function(path) {
  notebook <- jsonlite::fromJSON(path, simplifyVector = FALSE)
  list(notebook = notebook, codes = validate_notebook(notebook, basename(path)))
}

check_notebook_pair <- function(east, west) {
  normalize <- function(notebook) {
    vapply(notebook$cells, function(cell) {
      text <- paste0(unlist(cell$source), collapse = "")
      text <- gsub("DK[12]", "ZONE", text)
      sub("# (East|West) Denmark", "# REGION Denmark", text)
    }, character(1))
  }
  notebook_assert(identical(normalize(east), normalize(west)),
                  "EAST and WEST must differ only by their zone and region")
  notebook_assert(grepl('zone <- "DK2"', paste(normalize_zone_code(east), collapse = "\n"), fixed = TRUE) &&
                    grepl('zone <- "DK1"', paste(normalize_zone_code(west), collapse = "\n"), fixed = TRUE),
                  "EAST must select DK2 and WEST must select DK1")
}

normalize_zone_code <- function(notebook) {
  vapply(Filter(function(cell) cell$cell_type == "code", notebook$cells),
         function(cell) paste0(unlist(cell$source), collapse = ""), character(1))
}

# These guards live only in disposable worker processes. Fail loudly if a
# fixture execution accidentally attempts HTTP, a socket or an external sender.
install_offline_guards <- function() {
  block <- quote(stop("Notebook check forbids network access and external commands", call. = FALSE))
  guard_namespace <- function(package, functions) {
    namespace <- asNamespace(package)
    for (name in functions) {
      if (exists(name, envir = namespace, inherits = FALSE)) {
        suppressMessages(trace(name, tracer = block, print = FALSE, where = namespace))
      }
    }
  }
  guard_namespace("base", c("url", "socketConnection", "socketAccept", "serverSocket", "system", "system2"))
  guard_namespace("utils", c("download.file", "install.packages"))
  packages <- list(httr = c("GET", "POST", "PUT", "DELETE", "PATCH", "RETRY"),
                   httr2 = c("req_perform", "req_perform_parallel"),
                   curl = c("curl", "curl_fetch_memory", "curl_fetch_disk", "curl_fetch_stream", "curl_download"),
                   pushoverr = c("pushover", "pushover_normal", "pushover_quiet", "pushover_emergency"))
  for (package in names(packages)) local({
    pkg <- package
    functions <- packages[[pkg]]
    if (pkg %in% loadedNamespaces()) guard_namespace(pkg, functions)
    setHook(packageEvent(pkg, "onLoad"), function(...) guard_namespace(pkg, functions), action = "append")
  })
  invisible(NULL)
}

check_notebook_result <- function(environment, zone) {
  snapshot <- environment$snapshot
  summary <- environment$zone_summary
  notebook_assert(identical(environment$zone, zone), "wrong zone after Run All")
  notebook_assert(identical(snapshot$schema_version, 1L), "unexpected snapshot schema")
  notebook_assert(all(c("provider", "scenario", "coverage") %in% names(snapshot$meta)),
                  "snapshot must expose provider, scenario and coverage")
  notebook_assert(identical(summary, snapshot$summaries[[zone]]), "summary must come directly from snapshot")
  for (name in c("today", "quarter_today", "period_averages", "upcoming_window", "historical_window", "history_profile")) {
    notebook_assert(is.data.frame(summary[[name]]), paste("invalid summary table:", name))
  }
  notebook_assert(all(c("hour", "minute", "q25", "median", "q75") %in% names(summary$history_profile)),
                  "profile must contain precomputed clock-time quantiles")
  notebook_assert(all(summary$today$PriceArea == zone) && all(summary$quarter_today$PriceArea == zone),
                  "today tables contain another zone")
  invisible(TRUE)
}
