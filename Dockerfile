ARG BASE_IMAGE=debian:12
FROM ${BASE_IMAGE}

ARG R_VERSION=4.6.0
ARG CAPSULE_NAME=chatgpt-r-capsule
ARG BASE_LABEL=debian12

ENV DEBIAN_FRONTEND=noninteractive
ENV PREFIX=/opt/${CAPSULE_NAME}

RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    gfortran \
    wget \
    ca-certificates \
    xz-utils \
    file \
    libreadline-dev \
    libbz2-dev \
    liblzma-dev \
    zlib1g-dev \
    libpcre2-dev \
    libcurl4-openssl-dev \
    libssl-dev \
    libicu-dev \
    libpng-dev \
    libjpeg-dev \
    libtiff-dev \
    libcairo2-dev \
    libxt-dev \
    libblas-dev \
    liblapack-dev \
  && rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/build

RUN major="${R_VERSION%%.*}" && \
    wget -q "https://cran.r-project.org/src/base/R-${major}/R-${R_VERSION}.tar.xz" && \
    tar xf "R-${R_VERSION}.tar.xz" && \
    cd "R-${R_VERSION}" && \
    ./configure \
      --prefix="${PREFIX}/R" \
      --enable-R-shlib \
      --with-blas \
      --with-lapack \
      --with-x=no && \
    make -j"$(nproc)" && \
    make install

RUN mkdir -p "${PREFIX}/site-library" "${PREFIX}/lib"

RUN cat > "${PREFIX}/Rscript-capsule" <<'EOF' && chmod +x "${PREFIX}/Rscript-capsule"
#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"

export R_HOME="$DIR/R/lib/R"
export R_LIBS_USER="$DIR/site-library"
export LD_LIBRARY_PATH="$DIR/lib:$DIR/R/lib:$DIR/R/lib/R/lib:${LD_LIBRARY_PATH:-}"

mkdir -p "$R_LIBS_USER"

exec "$DIR/R/bin/Rscript" "$@"
EOF

COPY packages.txt /tmp/build/packages.txt
COPY scripts/install-capsule-packages.R /tmp/build/install-capsule-packages.R

RUN "${PREFIX}/Rscript-capsule" /tmp/build/install-capsule-packages.R /tmp/build/packages.txt

RUN find "${PREFIX}" -type f \( -name "*.so" -o -perm -111 \) -print0 | \
      xargs -0 -r ldd 2>/dev/null | \
      awk '/=> \// {print $3} /^\// {print $1}' | \
      sort -u | \
      grep -Ev '/(ld-linux|libc\.so|libm\.so|libpthread\.so|libdl\.so|librt\.so|libresolv\.so|libnsl\.so|libutil\.so)\.' | \
      xargs -r -I{} cp -L "{}" "${PREFIX}/lib/" || true

RUN "${PREFIX}/Rscript-capsule" -e 'cat("hello world\n")'

RUN mkdir -p /out && \
    cd /opt && \
    tar -czf "/out/${CAPSULE_NAME}-${R_VERSION}-${BASE_LABEL}-x86_64.tar.gz" "${CAPSULE_NAME}"