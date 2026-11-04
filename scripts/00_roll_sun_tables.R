# Date the topographic sun tables to the current season.
#
# data/suntime holds sun windows for one season (Nov 1 - Apr 30). They depend on
# terrain and solar geometry, so they repeat almost exactly each year. The model
# joins them by calendar date and silently runs without topographic sun if the
# dates do not match, so every build shifts them to the running season.
# Only the runner's checkout is changed; the result is not committed.
#
# Usage: Rscript scripts/00_roll_sun_tables.R [dir]

suppressPackageStartupMessages(library(readr))

args <- commandArgs(trailingOnly = TRUE)
dir_sun <- if (length(args) >= 1) args[1] else "data/suntime"

today <- as.Date(format(Sys.time(), tz = "Europe/Vienna"))
month_now <- as.integer(format(today, "%m"))
season_year <- as.integer(format(today, "%Y")) - (month_now < 10)

shift_year <- function(x, delta) {
  has_value <- !is.na(x) & nzchar(x)
  x[has_value] <- paste0(
    as.integer(substr(x[has_value], 1, 4)) + delta,
    substr(x[has_value], 5, nchar(x[has_value]))
  )
  x
}

is_leap <- function(y) (y %% 4 == 0 & y %% 100 != 0) | y %% 400 == 0

files <- list.files(dir_sun, pattern = "^sun_uid_.*\\.csv$", full.names = TRUE)
if (length(files) == 0) stop("No sun tables found in ", dir_sun)

n_shifted <- 0L
for (f in files) {
  sun <- read_csv(f, col_types = cols(.default = "c"), na = character(), progress = FALSE)
  if (nrow(sun) == 0) next

  source_year <- as.integer(substr(min(sun$date), 1, 4))
  delta <- season_year - source_year
  if (delta == 0L) next

  time_cols <- intersect(c("sunrise_topo", "sunset_topo"), names(sun))
  for (col in c("date", time_cols)) sun[[col]] <- shift_year(sun[[col]], delta)

  # The source season has no Feb 29: reuse Feb 28 when the target year has one.
  feb28 <- which(substr(sun$date, 6, 10) == "02-28")
  if (length(feb28) == 1 && is_leap(as.integer(substr(sun$date[feb28], 1, 4)))) {
    leap_row <- sun[feb28, ]
    for (col in c("date", time_cols)) leap_row[[col]] <- sub("-02-28", "-02-29", leap_row[[col]], fixed = TRUE)
    sun <- rbind(sun[seq_len(feb28), ], leap_row, sun[(feb28 + 1):nrow(sun), ])
  }

  write_csv(sun, f, na = "")
  n_shifted <- n_shifted + 1L
}

message("Sun tables dated to season ", season_year, "/", season_year + 1L, ": ",
        n_shifted, " of ", length(files), " shifted")
