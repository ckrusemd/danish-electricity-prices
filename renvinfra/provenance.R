args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) == 2L)
source("R/project.R")
snapshot <- read_analysis(args[1L])
mode <- Sys.getenv("BUILD_MODE", "local")
provenance <- list(
  schema_version = 1L,
  source_revision = Sys.getenv("GITHUB_SHA", "local"),
  workflow_run = Sys.getenv("GITHUB_RUN_ID", "local"),
  image = Sys.getenv("IMAGE", "local"),
  environment_hash = Sys.getenv("ENVIRONMENT_HASH", system2("bash", "scripts/environment-fingerprint.sh", stdout = TRUE)),
  build_mode = mode,
  counters = list(cold_builds = as.integer(mode == "cold"), warm_reuses = as.integer(mode == "warm"),
                  snapshot_preparations = 1L),
  timings = list(build_seconds = as.numeric(Sys.getenv("BUILD_SECONDS", NA_character_)),
                 prepare_seconds = as.numeric(Sys.getenv("PREPARE_SECONDS", NA_character_)),
                 render_seconds = as.numeric(Sys.getenv("RENDER_SECONDS", NA_character_))),
  data = list(schema_version = snapshot$schema_version, generated_at = snapshot$generated_at,
              date = snapshot$date, sha256 = unname(digest::digest(file = args[1L], algo = "sha256")),
              quarters = nrow(snapshot$quarter_prices), hours = nrow(snapshot$hourly_prices),
              weather_observations = if (is.null(snapshot$weather)) 0L else nrow(snapshot$weather),
              coverage = snapshot$meta$coverage, provider = snapshot$meta$provider,
              scenario = snapshot$meta$scenario))
jsonlite::write_json(provenance, args[2L], auto_unbox = TRUE, pretty = TRUE, null = "null", POSIXt = "ISO8601")
