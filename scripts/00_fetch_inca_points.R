# Download the INCA point series of all routes in bundled requests.
#
# GeoSphere allows 240 requests per hour, so one request per route makes the build
# wait for hours. The same endpoint accepts several points per request and returns
# the same values. diagram_uid.R finds the result in the weather cache; a route that
# is missing here is simply requested on its own there.

suppressPackageStartupMessages({
  library(httr2)
  library(dplyr)
  library(lubridate)
  library(readr)
})
source("scripts/weather_cache.R")

BATCH_SIZE <- 80L # about 2.3 kB of URL; 303 points are rejected as too long
INCA_URL <- "https://dataset.api.hub.geosphere.at/v1/timeseries/historical/inca-v1-1h-1km"
TZ_LOCAL <- "Europe/Vienna"

end_date <- wx_end_date()
start_date <- as.Date(sprintf(
  "%d-10-01",
  as.integer(format(end_date, "%Y")) - (as.integer(format(end_date, "%m")) < 10)
))

fetch_points <- function(points, from, to) {
  req <- request(INCA_URL) |>
    req_url_query(
      parameters = "UU,VV,GL",
      start = sprintf("%sT00:00", from),
      end = sprintf("%sT23:00", to),
      output_format = "csv"
    ) |>
    req_url_query(lat_lon = paste0(points$lat, ",", points$lon), .multi = "explode") |>
    req_user_agent("icefall-model/1.0 (R httr2)") |>
    req_retry(max_tries = 5)

  rows <- read_csv(I(resp_body_string(req_perform(req))), show_col_types = FALSE, progress = FALSE)
  # Rows come point by point in request order; lat/lon only name the grid cell.
  n_times <- nrow(rows) / nrow(points)
  if (n_times < 1 || n_times != round(n_times)) {
    stop("Unexpected row count: ", nrow(rows), " for ", nrow(points), " points")
  }

  names(rows)[startsWith(names(rows), "UU")] <- "UU"
  names(rows)[startsWith(names(rows), "VV")] <- "VV"
  names(rows)[startsWith(names(rows), "GL")] <- "GL"
  rows$point <- rep(seq_len(nrow(points)), each = n_times)

  # Same result as parse_inca_timeseries_csv_file in diagram_uid.R, which loses the
  # 00:00 UTC rows (as.character() drops the time at midnight, the parser then gives NA).
  series <- rows |>
    filter(!(hour(time) == 0 & minute(time) == 0)) |>
    mutate(time = with_tz(as.POSIXct(time, tz = "UTC"), TZ_LOCAL)) |>
    select(point, time, UU, VV, GL)
  lapply(split(series, series$point), function(x) select(x, -point))
}

routes <- read_csv("data/AWS/icefalls_nearest_station.csv", show_col_types = FALSE, progress = FALSE) |>
  transmute(uid, lat = ice_lat, lon = ice_lon) |>
  distinct(uid, .keep_all = TRUE) |>
  filter(is.finite(lat), is.finite(lon))

uid_limit <- Sys.getenv("UID_LIMIT", "")
if (nzchar(uid_limit)) {
  routes <- filter(routes, uid %in% as.integer(strsplit(uid_limit, "[,;[:space:]]+")[[1]]))
}

tag <- wx_cache_tag()
routes$cache_file <- vapply(routes$uid, inca_cache_file, character(1), start_date = start_date)
cached <- lapply(routes$cache_file, wx_read)
names(cached) <- routes$cache_file
routes$done <- vapply(cached, function(x) !is.null(x) && identical(x$tag, tag), logical(1))
routes$fetch_from <- as.Date(vapply(
  cached,
  function(x) as.numeric(wx_fetch_from(x, start_date, end_date)),
  numeric(1)
))

n_requests <- 0L
for (group in split(filter(routes, !done), ~fetch_from)) {
  if (nrow(group) == 0) next
  from <- group$fetch_from[[1]]
  points <- distinct(group, lat, lon)
  batches <- split(points, ceiling(seq_len(nrow(points)) / BATCH_SIZE))

  for (batch in batches) {
    series <- fetch_points(batch, from, end_date)
    n_requests <- n_requests + 1L
    for (i in seq_len(nrow(batch))) {
      at_point <- filter(group, lat == batch$lat[[i]], lon == batch$lon[[i]])
      for (f in at_point$cache_file) {
        wx_store(f, cached[[f]], series[[i]], from, start_date, end_date, "time")
      }
    }
  }
}

message("INCA points: ", sum(!routes$done), " routes in ", n_requests, " requests")
