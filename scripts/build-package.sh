#!/usr/bin/env bash
set -euo pipefail

: "${PKG:?PKG is required}"
: "${R_VERSION:?R_VERSION is required}"
: "${CAPSULE_NAME:?CAPSULE_NAME is required}"
: "${BASE_LABEL:?BASE_LABEL is required}"

root="/tmp/package"
lib="$root/library"
syslib="$root/lib"

rm -rf "$root"
mkdir -p "$lib" "$syslib"

cat > /tmp/install-package.R <<'EOF'
pkg <- Sys.getenv("PKG")
lib <- "/tmp/package/library"

dir.create(lib, recursive = TRUE, showWarnings = FALSE)
.libPaths(c(lib, .libPaths()))

ncpus <- max(1L, parallel::detectCores(logical = TRUE))
deps <- c("Depends", "Imports", "LinkingTo")

install_bioc_manager <- function() {
  if (!requireNamespace("BiocManager", quietly = TRUE)) {
    install.packages("BiocManager", lib = lib, repos = "https://cloud.r-project.org")
  }
  options(repos = BiocManager::repositories())
}

if (startsWith(pkg, "cran::")) {
  name <- sub("^cran::", "", pkg)
  install.packages(name, lib = lib, repos = "https://cloud.r-project.org",
                   dependencies = deps, Ncpus = ncpus)
  package_name <- name
} else if (startsWith(pkg, "bioc::")) {
  name <- sub("^bioc::", "", pkg)
  install_bioc_manager()
  BiocManager::install(name, lib = lib, ask = FALSE, update = FALSE,
                       dependencies = deps, Ncpus = ncpus)
  package_name <- name
} else if (startsWith(pkg, "local::")) {
  path <- sub("^local::", "", pkg)
  desc <- file.path(path, "DESCRIPTION")
  if (!file.exists(desc)) {
    stop("Local package path does not contain DESCRIPTION: ", path)
  }

  package_name <- read.dcf(desc, fields = "Package")[[1]]
  install_bioc_manager()
  remotes::install_local(path, lib = lib, dependencies = TRUE,
                         upgrade = "never", build_vignettes = FALSE,
                         force = TRUE)
} else {
  stop("PKG must be cran::<pkg>, bioc::<pkg>, or a local path")
}

writeLines(package_name, "/tmp/package/name.txt")
writeLines(sort(basename(list.dirs(lib, recursive = FALSE))),
           "/tmp/package/installed-packages.txt")
EOF

/opt/"$CAPSULE_NAME"/Rscript-capsule /tmp/install-package.R

pkg_name="$(cat "$root/name.txt")"
safe_name="$(echo "$pkg_name" | sed 's|[^A-Za-z0-9_.-]|-|g')"
archive="${safe_name}-package-r${R_VERSION}-${BASE_LABEL}-x86_64.tar.gz"

find "$lib" -type f -name "*.so" -print0 | \
  xargs -0 -r ldd 2>/dev/null | \
  awk '
    /=> \// { print $3 }
    $1 ~ /^\// && $1 !~ /:$/ { print $1 }
  ' | \
  sort -u | \
  grep -Ev '/(ld-linux|libc\.so|libm\.so|libpthread\.so|libdl\.so|librt\.so|libresolv\.so|libnsl\.so|libutil\.so)\.' | \
  xargs -r -I{} cp -L "{}" "$syslib/" || true

{
  echo "PKG=$PKG"
  echo "PACKAGE_NAME=$pkg_name"
  echo "R_VERSION=$R_VERSION"
  echo "CAPSULE_NAME=$CAPSULE_NAME"
  echo "BASE_LABEL=$BASE_LABEL"
  echo "BUILT_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "INSTALLED_PACKAGES:"
  cat "$root/installed-packages.txt"
} > "$root/manifest.txt"

tar -czf "/out/$archive" -C /tmp package

echo "Wrote /out/$archive"