# jcore-cpu CI toolchain image.
#
# Provides the heavy toolchains needed by the Step 6/7/8 portion of
# decode/gen-go/regression.sh:
#   - sh2-elf-gcc 14.2.0 (+ binutils 2.43.1) -- bare-metal SH-2 cross
#   - GHDL 6.0.0 (libghdl exported, needed by ghdl-yosys-plugin)
#   - yosys 0.44
#   - ghdl-yosys-plugin @ 07a30ed (newer commits break against GHDL 6.0.0
#     because they call get_sname_index, which is not in GHDL 6.0.0)
#   - CUDD + OpenSTA 2.7.0 (built from source) + Nangate45 Liberty file
#   - Go (latest from golang.org so the regenerate step works without
#     pulling distro Go)
#
# Build:  docker build -t jcore-cpu-ci -f .github/ci/Dockerfile .
# Publish: see .github/workflows/build-ci-image.yml
#
# Image size: ~2.5-3.0 GB. Build time cold: ~30-60 minutes (GHDL + GCC).

ARG UBUNTU_VERSION=24.04
FROM ubuntu:${UBUNTU_VERSION}

ENV DEBIAN_FRONTEND=noninteractive
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8

# Pinned versions. Bumping these is intentional: change the value, push to
# master, the build-ci-image workflow rebuilds and replaces :latest.
ARG GHDL_VERSION=v6.0.0
ARG YOSYS_VERSION=yosys-0.44
ARG GHDL_YOSYS_PLUGIN_COMMIT=07a30ed
ARG BINUTILS_VERSION=2.43.1
ARG SH2_GCC_VERSION=14.2.0
ARG GO_VERSION=1.26.2
# OpenSTA is not packaged for Ubuntu; built from source below. OpenSTA requires
# CUDD, also built from source (ivmai/cudd, the upstream OpenSTA dependency).
# CUDD_COMMIT is ivmai/cudd HEAD (no tagged release covers the needed sources).
#
# We use the The-OpenROAD-Project/OpenSTA fork (not parallaxsw): the parallaxsw
# HEAD (v3.1.0) crashes with "Error: stoi" on set_input_delay over the bracketed
# escaped port names yosys emits for the flattened decoder (\op[code][0] etc).
# The OpenROAD fork parses them fine. OPENSTA_COMMIT is LibreLane's vetted pin
# (librelane/nix/opensta.nix, dated 2026-02-14), which reports STA version 2.7.0.
ARG OPENSTA_REPO=https://github.com/The-OpenROAD-Project/OpenSTA.git
ARG OPENSTA_COMMIT=857316ff001b2a8dbbdc5996944d08a6d38c87ab
ARG CUDD_COMMIT=f54f533303640afd5dbe47a05ebeabb3066f2a25
ARG NANGATE_URL=https://raw.githubusercontent.com/The-OpenROAD-Project/OpenSTA/master/examples/nangate45_slow.lib.gz

# ---------------------------------------------------------------------------
# 1) System packages. One apt-get to minimize layer count.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        gnat \
        gcc \
        g++ \
        make \
        cmake \
        gawk \
        bash \
        ca-certificates \
        curl \
        wget \
        git \
        xz-utils \
        unzip \
        pkg-config \
        flex \
        libfl-dev \
        bison \
        texinfo \
        clang \
        autoconf \
        automake \
        libtool \
        tcl-dev \
        tcl \
        swig \
        python3 \
        python3-dev \
        zlib1g-dev \
        libreadline-dev \
        libffi-dev \
        libgmp-dev \
        libmpfr-dev \
        libmpc-dev \
        libisl-dev \
        libboost-system-dev \
        libboost-python-dev \
        libboost-filesystem-dev \
        libeigen3-dev \
        ghdl-mcode \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# 2) Go toolchain (Go 1.26+ from upstream — distro Go in 24.04 lags).
# ---------------------------------------------------------------------------
RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
        amd64) goarch=amd64 ;; \
        arm64) goarch=arm64 ;; \
        *) echo "unsupported arch $arch" >&2; exit 1 ;; \
    esac; \
    curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
        "https://go.dev/dl/go${GO_VERSION}.linux-${goarch}.tar.gz" \
        -o /tmp/go.tgz; \
    tar -C /usr/local -xzf /tmp/go.tgz; \
    rm /tmp/go.tgz
# Include /usr/local/sbin:/usr/sbin:/sbin — ldconfig (run by the GHDL and
# CUDD build steps below) lives in /sbin, which a bare ENV PATH drops.
ENV PATH=/usr/local/go/bin:/usr/local/bin:/usr/local/sbin:/usr/sbin:/sbin:/usr/bin:/bin

# ---------------------------------------------------------------------------
# 3) sh2-elf-gcc cross compiler.
#     Recipe verbatim from decode/gen-go/docs/sh2-elf-build.md.
#     Installs to /usr/local so PATH already finds it.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /tmp/sh2-build && cd /tmp/sh2-build; \
    wget -q https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VERSION}.tar.xz; \
    tar xf binutils-${BINUTILS_VERSION}.tar.xz; \
    mkdir build-binutils && cd build-binutils; \
    ../binutils-${BINUTILS_VERSION}/configure \
        --target=sh2-elf \
        --prefix=/usr/local \
        --disable-nls \
        --disable-werror \
        --disable-doc; \
    make -j"$(nproc)"; \
    make install; \
    cd /tmp/sh2-build; \
    wget -q https://ftp.gnu.org/gnu/gcc/gcc-${SH2_GCC_VERSION}/gcc-${SH2_GCC_VERSION}.tar.xz; \
    tar xf gcc-${SH2_GCC_VERSION}.tar.xz; \
    mkdir build-gcc && cd build-gcc; \
    ../gcc-${SH2_GCC_VERSION}/configure \
        --target=sh2-elf \
        --prefix=/usr/local \
        --enable-languages=c \
        --without-headers \
        --disable-nls \
        --disable-shared \
        --disable-threads \
        --disable-libssp \
        --disable-libquadmath \
        --disable-libstdcxx \
        --disable-doc \
        --with-cpu=m2; \
    make all-gcc -j"$(nproc)"; \
    make install-gcc; \
    make all-target-libgcc -j"$(nproc)"; \
    make install-target-libgcc; \
    cd / && rm -rf /tmp/sh2-build

# ---------------------------------------------------------------------------
# 4) GHDL 6.0.0 built from source with libghdl exported (required by
#     ghdl-yosys-plugin). The apt 'ghdl' on Ubuntu 24.04 ships an older
#     release without the libghdl-dev exports the plugin needs.
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch ${GHDL_VERSION} https://github.com/ghdl/ghdl.git /tmp/ghdl; \
    cd /tmp/ghdl; \
    ./configure --prefix=/usr/local --enable-libghdl --enable-synth; \
    make -j"$(nproc)"; \
    make install; \
    cd / && rm -rf /tmp/ghdl; \
    ldconfig

# ---------------------------------------------------------------------------
# 5) yosys 0.44.
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone --depth 1 --branch ${YOSYS_VERSION} https://github.com/YosysHQ/yosys.git /tmp/yosys; \
    cd /tmp/yosys; \
    # abc is a git submodule, NOT vendored in the tag. A shallow clone leaves
    # it uninitialized, and yosys 0.44's Makefile aborts at its check-git-abc
    # guard ("Initialize the submodule ..."). Fetch it explicitly before make.
    git submodule update --init; \
    make -j"$(nproc)" PREFIX=/usr/local; \
    make install PREFIX=/usr/local; \
    cd / && rm -rf /tmp/yosys

# ---------------------------------------------------------------------------
# 6) ghdl-yosys-plugin (pinned commit; newer HEAD uses get_sname_index
#     which is not in GHDL 6.0.0).
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone https://github.com/ghdl/ghdl-yosys-plugin.git /tmp/ghdl-yosys-plugin; \
    cd /tmp/ghdl-yosys-plugin; \
    git checkout ${GHDL_YOSYS_PLUGIN_COMMIT}; \
    make GHDL=/usr/local/bin/ghdl YOSYS_CONFIG=/usr/local/bin/yosys-config; \
    make install GHDL=/usr/local/bin/ghdl YOSYS_CONFIG=/usr/local/bin/yosys-config; \
    cd / && rm -rf /tmp/ghdl-yosys-plugin; \
    # Smoke-test the plugin loads cleanly.
    yosys -m ghdl -p 'help ghdl' >/dev/null

# ---------------------------------------------------------------------------
# 7) CUDD (BDD package) — a required dependency of OpenSTA. No apt package
#     exists; built from the ivmai/cudd upstream that OpenSTA documents.
#     autoreconf is needed because the git tree ships no configure script
#     (autoconf/automake/libtool installed in step 1).
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone https://github.com/ivmai/cudd.git /tmp/cudd; \
    cd /tmp/cudd; \
    git checkout ${CUDD_COMMIT}; \
    autoreconf -i; \
    ./configure --enable-shared --prefix=/usr/local; \
    make -j"$(nproc)"; \
    make install; \
    cd / && rm -rf /tmp/cudd; \
    ldconfig

# ---------------------------------------------------------------------------
# 8) OpenSTA (static timing) built from source. There is no apt package for
#     OpenSTA on Ubuntu; the build deps (cmake, tcl-dev, swig, bison, flex +
#     libfl-dev for FlexLexer.h, eigen3, zlib) are installed in step 1 and
#     CUDD in step 7. Installs `sta` to /usr/local/bin.
# ---------------------------------------------------------------------------
RUN set -eux; \
    git clone "${OPENSTA_REPO}" /tmp/OpenSTA; \
    cd /tmp/OpenSTA; \
    git checkout ${OPENSTA_COMMIT}; \
    mkdir build && cd build; \
    cmake -DCMAKE_BUILD_TYPE=Release ..; \
    make -j"$(nproc)"; \
    make install; \
    cd / && rm -rf /tmp/OpenSTA; \
    sta -version

# ---------------------------------------------------------------------------
# 9) Nangate45 Liberty file for openSTA. Placed at a stable absolute path
#     surfaced via NANGATE_LIB in full-regression.yml.
# ---------------------------------------------------------------------------
RUN set -eux; \
    mkdir -p /opt/nangate45; \
    curl -fsSL "${NANGATE_URL}" | gunzip > /opt/nangate45/nangate45.lib; \
    test -s /opt/nangate45/nangate45.lib

ENV NANGATE_LIB=/opt/nangate45/nangate45.lib

# ---------------------------------------------------------------------------
# Final smoke test: confirm all entry points are on PATH.
# ---------------------------------------------------------------------------
RUN set -eux; \
    go version; \
    ghdl --version | head -1; \
    yosys -V | head -1; \
    yosys -m ghdl -p 'help ghdl' >/dev/null; \
    sh2-elf-gcc --version | head -1; \
    sta -version 2>&1 | head -1 || true; \
    test -f "$NANGATE_LIB"

CMD ["/bin/bash"]
