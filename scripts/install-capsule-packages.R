args <- commandArgs(trailingOnly = TRUE)
file <- if (length(args)) args[[1]] else "packages.txt"

lines <- readLines(file, warn = FALSE)
lines <- trimws(lines)
lines <- lines[nzchar(lines) & !startsWith(lines, "#")]

cran <- sub("^cran::", "", lines[startsWith(lines, "cran::")])
bioc <- sub("^bioc::", "", lines[startsWith(lines, "bioc::")])

bad <- lines[!startsWith(lines, "cran::") & !startsWith(lines, "bioc::")]
if (length(bad)) {
  stop("Unsupported package spec(s): ", paste(bad, collapse = ", "))
}

ncpus <- max(1L, parallel::detectCores(logical = TRUE))

if (length(cran)) {
  install.packages(unique(cran), repos = "https://cloud.r-project.org", Ncpus = ncpus)
}

if (length(bioc)) {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager", repos = "https://cloud.r-project.org")
  }
  BiocManager::install(unique(bioc), ask = FALSE, update = FALSE, Ncpus = ncpus)
}