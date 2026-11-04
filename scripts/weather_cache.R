# Weather cache shared by diagram_uid.R and 00_fetch_inca_points.R.
#
# Keeps what earlier runs downloaded and requests only the last days again. The APIs
# take UTC days, so old and new data are joined at 00:00 UTC of the first fetched day.

WX_CACHE_DIR <- "data/_cache_weather"

# Days that are downloaded again on every run, because recent values can still change.
WX_REFRESH_DAYS <- 3L

wx_end_date <- function() {
  raw <- Sys.getenv("MODEL_END_DATE", "")
  if (nzchar(raw)) as.Date(raw) else Sys.Date()
}

# Data fetched in this run is reused as is, e.g. by other routes at the same station.
wx_cache_tag <- function() paste(Sys.getenv("GITHUB_RUN_ID", "local"), format(wx_end_date()))

inca_cache_file <- function(uid, start_date) {
  file.path(WX_CACHE_DIR, sprintf("inca_uid%s_%s.rds", uid, format(as.Date(start_date), "%Y%m%d")))
}

wx_read <- function(cache_file) {
  if (!file.exists(cache_file)) return(NULL)
  tryCatch(readRDS(cache_file), error = function(e) NULL)
}

wx_fetch_from <- function(cached, start_date, end_date) {
  if (is.null(cached)) return(as.Date(start_date))
  max(as.Date(start_date), min(as.Date(end_date), cached$end_date) - WX_REFRESH_DAYS)
}

wx_store <- function(cache_file, cached, fresh, fetch_from, start_date, end_date, time_col) {
  data <- fresh
  if (fetch_from > as.Date(start_date)) {
    cutoff <- as.POSIXct(paste(fetch_from, "00:00:00"), tz = "UTC")
    data <- dplyr::bind_rows(cached$data[cached$data[[time_col]] < cutoff, ], fresh)
  }
  dir.create(dirname(cache_file), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(cache_file, ".", Sys.getpid(), ".tmp")
  saveRDS(list(tag = wx_cache_tag(), end_date = as.Date(end_date), data = data), tmp)
  file.rename(tmp, cache_file)
  data
}

incremental_fetch <- function(cache_file, start_date, end_date, fetch, time_col, whole_season = FALSE) {
  cached <- wx_read(cache_file)
  if (!is.null(cached) && identical(cached$tag, wx_cache_tag())) return(cached$data)

  fetch_from <- if (whole_season) as.Date(start_date) else wx_fetch_from(cached, start_date, end_date)
  fresh <- fetch(fetch_from, as.Date(end_date))
  wx_store(cache_file, cached, fresh, fetch_from, start_date, end_date, time_col)
}
