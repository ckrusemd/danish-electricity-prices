# Shared time, HTTP and versioned raw-input cache utilities. No package attach.
electricity_timezone <- "Europe/Copenhagen"
electricity_cache_version <- 1L

utc_time <- function(x) {
  if (inherits(x, "POSIXt") || is.numeric(x)) {
    return(as.POSIXct(as.numeric(x), origin = "1970-01-01", tz = "UTC"))
  }
  as.POSIXct(x, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC")
}

dk_time <- function(x) {
  as.POSIXct(as.numeric(x), origin = "1970-01-01", tz = electricity_timezone)
}

local_day <- function(x) as.Date(format(x, "%Y-%m-%d", tz = electricity_timezone))

day_start <- function(day) {
  utc_time(as.POSIXct(paste(as.Date(day), "00:00:00"), tz = electricity_timezone))
}

iso_utc <- function(x) format(x, "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

six_months_before <- function(day) {
  # Calendar months, clamping the day for short target months.
  month <- as.Date(format(as.Date(day), "%Y-%m-01"))
  target <- seq(month, by = "-1 month", length.out = 7L)[7L]
  following <- seq(target, by = "1 month", length.out = 2L)[2L]
  target + min(as.integer(format(as.Date(day), "%d")) - 1L,
               as.integer(following - target) - 1L)
}

assert_columns <- function(data, columns, label) {
  if (!is.data.frame(data) || !all(columns %in% names(data))) {
    stop(label, " must be a data.frame with columns: ", paste(columns, collapse = ", "),
         call. = FALSE)
  }
}

assert_time <- function(x, timezone, label, step = NULL) {
  if (!inherits(x, "POSIXct") || !identical(attr(x, "tzone"), timezone) ||
      any(!is.finite(as.numeric(x))) ||
      (!is.null(step) && any(as.numeric(x) %% step != 0))) {
    stop(label, " must contain valid ", timezone, " POSIXct timestamps", call. = FALSE)
  }
}

api_get_json <- function(url, query = list(), attempts = 3L, timeout = 25,
                         pause_cap = 2, request = NULL, sleep = Sys.sleep) {
  # Only idempotent GETs; timeout and retry count are bounded. No secret headers.
  if (length(attempts) != 1L || !is.finite(attempts) || attempts != as.integer(attempts) || attempts < 1 || attempts > 3 ||
      length(timeout) != 1L || !is.finite(timeout) || timeout <= 0 || timeout > 30 ||
      length(pause_cap) != 1L || !is.finite(pause_cap) || pause_cap < 0 || pause_cap > 3) {
    stop("Invalid bounded GET retry settings", call. = FALSE)
  }
  if (is.null(request)) {
    if (!requireNamespace("httr", quietly = TRUE) || !requireNamespace("jsonlite", quietly = TRUE)) {
      stop("Live API access requires the locked httr and jsonlite packages", call. = FALSE)
    }
    request <- function(url, query, timeout) {
      response <- httr::GET(url, query = query, httr::timeout(timeout))
      list(status = httr::status_code(response),
           body = httr::content(response, as = "text", encoding = "UTF-8"))
    }
  }
  for (attempt in seq_len(as.integer(attempts))) {
    response <- tryCatch(request(url, query, timeout), error = identity)
    transport_error <- inherits(response, "error")
    if (!transport_error) {
      status <- response$status
      if (length(status) != 1L || !is.finite(status)) stop("Invalid HTTP response status")
      if (status >= 200L && status < 300L) {
        if (!is.null(response$payload)) return(response$payload)
        return(jsonlite::fromJSON(response$body))
      }
      retryable <- status %in% c(408L, 429L, 500L, 502L, 503L, 504L)
      if (!retryable) stop("API GET failed with HTTP ", status, call. = FALSE)
    }
    if (attempt == attempts) {
      stop(if (transport_error) "API GET transport failed after bounded retries" else
        paste("API GET failed after bounded retries; HTTP", status), call. = FALSE)
    }
    sleep(min(pause_cap, 2^(attempt - 1L)))
  }
}

read_input_cache <- function(path, provider, key) {
  if (!file.exists(path)) return(NULL)
  cached <- tryCatch(readRDS(path), error = function(e) NULL)
  if (!is.list(cached) || !identical(cached$cache_version, electricity_cache_version) ||
      !identical(cached$provider, provider) || !identical(cached$key, key)) return(NULL)
  cached
}

write_rds_atomic <- function(object, path) {
  directory <- dirname(path)
  if (!dir.exists(directory)) dir.create(directory, recursive = TRUE, showWarnings = FALSE)
  temporary <- tempfile("electricity-", tmpdir = directory)
  on.exit(unlink(temporary), add = TRUE)
  saveRDS(object, temporary, version = 3)
  if (!file.rename(temporary, path)) stop("Could not write RDS: ", path, call. = FALSE)
  invisible(path)
}

write_input_cache <- function(path, provider, key, data, start, end) {
  write_rds_atomic(list(cache_version = electricity_cache_version, provider = provider,
                       key = key, start = utc_time(start), end = utc_time(end), data = data), path)
}
