suppressPackageStartupMessages({
  library(readr)
  library(dplyr)
})

assign_path <- "data/AWS/icefalls_nearest_station.csv"
if (!file.exists(assign_path)) stop("Missing: ", assign_path)

assign <- read_csv(assign_path, show_col_types = FALSE)

if (!("uid" %in% names(assign))) stop("Column 'uid' is missing in ", assign_path)

uids <- sort(unique(assign$uid))
uids <- uids[is.finite(uids)]
assign_uids <- uids

if (length(uids) == 0) stop("No UIDs found.")

strict_plots <- tolower(Sys.getenv("STRICT_PLOTS", "false")) %in% c("1", "true", "yes", "y")
rscript_bin <- Sys.getenv("RSCRIPT_BIN", "Rscript")

# Optional: limit build to a specific UID list (for faster testing)
# Usage:
#   Rscript scripts/00_build_plots_all.R --uids=12,34,56
#   or set environment variable UID_LIMIT="12,34,56"
uid_arg <- grep("^--uids=", commandArgs(trailingOnly = TRUE), value = TRUE)
uid_raw <- if (length(uid_arg) > 0) sub("^--uids=", "", uid_arg[1]) else Sys.getenv("UID_LIMIT", "")
if (nzchar(uid_raw)) {
  uid_list <- suppressWarnings(as.integer(trimws(unlist(strsplit(uid_raw, "[,;\\s]+")))))
  uid_list <- sort(unique(uid_list[is.finite(uid_list)]))
  if (length(uid_list) == 0) stop("UID_LIMIT/--uids contains no valid UIDs.")
  missing_assign <- setdiff(uid_list, assign_uids)
  if (length(missing_assign) > 0) {
    message("UIDs not in station assignment table; diagram_uid.R will use fallback: ", paste(missing_assign, collapse = ", "))
  }
  uids <- uid_list
  message("UID filter active: ", paste(uids, collapse = ", "))
}

dir.create("site/plots", recursive = TRUE, showWarnings = FALSE)

# Caches from earlier seasons are no longer needed.
season_today <- Sys.Date()
season_tag <- sprintf(
  "%d1001",
  as.integer(format(season_today, "%Y")) - (as.integer(format(season_today, "%m")) < 10)
)
cache_files <- list.files(c("data/_cache_weather", "data/_cache_model"), full.names = TRUE)
unlink(cache_files[!grepl(season_tag, basename(cache_files), fixed = TRUE)])

run_rscript_checked <- function(script, args = character()) {
  status <- system2(rscript_bin, c(script, args), stdout = "", stderr = "")
  exit_code <- attr(status, "status")
  if (is.null(exit_code)) exit_code <- status
  if (length(exit_code) == 0 || is.na(exit_code)) exit_code <- 0
  if (!identical(as.integer(exit_code), 0L)) {
    stop("Rscript failed with exit code ", exit_code, ": ", script)
  }
  invisible(TRUE)
}

# 0) Build inversion once (cache)
inv_script <- "scripts/00_build_inversion_cache.R"
if (!file.exists(inv_script)) stop("Missing inversion script: ", inv_script)

inv_ok <- TRUE
tryCatch({
  run_rscript_checked(inv_script)
}, error = function(e) {
  inv_ok <<- FALSE
  warning(
    "Inversion cache build failed; continuing with per-UID fallback if possible: ",
    e$message,
    call. = FALSE
  )
})

if (!inv_ok && strict_plots) {
  stop("Inversion cache build failed and STRICT_PLOTS is enabled.")
}

# Plot script path
plot_script <- "scripts/diagram_uid.R"
if (!file.exists(plot_script)) stop("Missing chart script: ", plot_script)

# Bundled INCA download; routes missing afterwards request their own series.
tryCatch(
  run_rscript_checked("scripts/00_fetch_inca_points.R"),
  error = function(e) message("Bundled INCA download failed, using single requests: ", e$message)
)

build_uid <- function(u) {
  message("Build Plot UID: ", u)
  tryCatch({
    # New process per UID (more robust than source()).
    run_rscript_checked(plot_script, as.character(u))
    TRUE
  }, error = function(e) {
    message("UID ", u, " failed: ", e$message)
    FALSE
  })
}

# mclapply cannot fork on Windows, where builds run one after another.
n_cores <- if (.Platform$OS.type == "windows") 1L else max(1L, parallel::detectCores())
build_uids <- function(x) {
  res <- parallel::mclapply(x, build_uid, mc.cores = n_cores, mc.preschedule = FALSE)
  x[!vapply(res, isTRUE, logical(1))]
}

# One route per station first: routes then find their station data in the cache,
# so no two processes download the same station.
station_key <- paste(assign$source, assign$station_id)[match(uids, assign$uid)]
first_at_station <- !duplicated(station_key) | is.na(station_key)
message("Building ", length(uids), " routes on ", n_cores, " cores")
failed <- sort(c(build_uids(uids[first_at_station]), build_uids(uids[!first_at_station])))

if (length(failed) > 0) {
  built <- length(uids) - length(failed)
  fail_msg <- paste0(
    "Plots failed for ",
    length(failed),
    " of ",
    length(uids),
    " UIDs: ",
    paste(failed, collapse = ", ")
  )
  writeLines(as.character(failed), "site/plots_failed_uids.txt", useBytes = TRUE)

  if (strict_plots || built == 0) {
    stop(fail_msg)
  }

  warning(fail_msg, call. = FALSE)
  message("Continuing because at least one plot was built. Failed UID list written to site/plots_failed_uids.txt")
}

message("\nPlots built: ", length(uids) - length(failed), " / ", length(uids))
