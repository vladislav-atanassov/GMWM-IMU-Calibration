# Helpers for main.R experiments, the R counterparts of the MATLAB helpers in this folder.
# run.py sources this file before main.R and passes everything through EXP_* variables.

# A path in the repository, e.g. exp_path("external/simts")
exp_path <- function(relative) file.path(Sys.getenv("EXP_ROOT"), relative)

# The running experiment's config.json, as a list. Lists of strings come back as character vectors
exp_config <- function() jsonlite::fromJSON(Sys.getenv("EXP_CONFIG"))

# The running experiment's data: the window of its dataset that run.py decoded once into
# data/cache/, the same samples for every language. Returns a list with
#   dataset   name in data/README.md
#   window_s  the window kept, "from-to" in seconds since the log's first sample
#   fs        nominal sample rate [Hz]
#   t0        time of the first sample [s] since the log's first sample
#   gyro      N x 3 angular rate [dps], axes x y z
#   accel     N x 3 acceleration [g]
#   lost      blocks lost within the window; gyro and accel run straight across the gaps
exp_data <- function() {
  h <- jsonlite::fromJSON(Sys.getenv("EXP_DATA"))
  n <- length(h$columns)
  raw <- readBin(file.path(dirname(Sys.getenv("EXP_DATA")), h$samples_file), "integer",
                 n = h$samples * n + 1, size = 2, signed = TRUE, endian = "little")
  if (length(raw) != h$samples * n) stop("The cached samples do not match their header")
  raw <- matrix(raw, ncol = n, byrow = TRUE) # one sample per row
  list(dataset = h$dataset, window_s = h$window_s, fs = h$fs, t0 = h$t0_s,
       gyro = raw[, 1:3] * h$gyro_scale, accel = raw[, 4:6] * h$accel_scale, lost = h$lost_blocks)
}

# Loads the R package in a submodule, e.g. exp_package(exp_path("external/simts")), after
# checking that the installed copy was built from the submodule's checked-out commit. run.py
# builds and installs it when it was not
exp_package <- function(path) {
  package <- read.dcf(file.path(path, "DESCRIPTION"), fields = "Package")[1, 1]
  commit <- system2("git", c("-C", shQuote(path), "rev-parse", "HEAD"), stdout = TRUE)
  installed <- tryCatch(packageDescription(package)$RemoteSha, error = function(e) NULL)
  if (!identical(installed, commit)) {
    stop(sprintf("The installed %s was not built from %s at %s; run this experiment with run.py, which builds it",
                 package, path, substr(commit, 1, 7)))
  }
  suppressPackageStartupMessages(library(package, character.only = TRUE))
  cat(sprintf("%s %s, built from %s\n", package, packageVersion(package), substr(commit, 1, 7)))
}

# Writes data frame df to the run's outputs as file (params.csv, wv.csv or fit.csv). run.py
# then checks its columns and units against experiments/README.md. NA is written as an
# empty field, numbers with 10 significant digits as in exp_write.m
exp_write <- function(file, df) {
  cells <- lapply(df, function(col) {
    if (is.numeric(col)) {
      s <- trimws(formatC(col, digits = 10, format = "g"))
      s[is.na(col)] <- ""
    } else {
      s <- as.character(col)
      quote <- grepl("[,\"\n]", s) # CSV: quote the field, doubling its quotes
      s[quote] <- paste0("\"", gsub("\"", "\"\"", s[quote]), "\"")
    }
    s
  })
  lines <- c(paste(names(df), collapse = ","), do.call(paste, c(cells, sep = ",")))
  con <- file(file.path(Sys.getenv("EXP_OUT"), file), "wb") # LF line ends, as exp_write.m
  on.exit(close(con))
  writeLines(lines, con)
}

# Draws a figure with draw() and saves it to the run's outputs as name.png
exp_figure <- function(name, draw, width = 15, height = 5.2) {
  png(file.path(Sys.getenv("EXP_OUT"), paste0(name, ".png")), width = width, height = height,
      units = "in", res = 150)
  on.exit(dev.off())
  draw()
}
