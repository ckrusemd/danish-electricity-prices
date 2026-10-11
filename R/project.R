# Source from any working directory; deliberately do not attach packages or plots.
local({
  source_file <- tryCatch(sys.frame(1L)$ofile, error = function(e) NULL)
  root <- if (is.null(source_file)) getwd() else dirname(dirname(normalizePath(source_file)))
  target <- parent.env(environment())
  for (module in c("utils.R", "data.R", "tariffs.R", "weather.R", "fixtures.R", "analysis.R")) {
    sys.source(file.path(root, "R", module), envir = target)
  }
})
