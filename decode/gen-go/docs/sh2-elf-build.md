# Building sh2-elf-gcc from source

## Why

`testrom/Makefile` and `sim/tests/Makefile` both invoke `sh2-elf-gcc`,
`sh2-elf-ld`, `sh2-elf-ar`, `sh2-elf-ranlib`, and `sh2-elf-objcopy` to
cross-compile SH-2 test ROMs into binary `.img` files. The simulator
(`cpu_ctb`) loads `ram.img` (built from `testrom/`) as the boot ROM for
the verification run; `sim/tests/` builds `interrupts.img` and `rte.img`
used by targeted test cases. There is no distro package for the bare-metal
`sh2-elf` target; the toolchain must be built from source.

No sibling project in the J-Core monorepo (`jcore-soc`, `j2-llvm`,
`arboriginal`, `qemu`, `aasm`) contains a concrete recipe for a modern
baremetal `sh2-elf` toolchain. The arboriginal project ships a pre-built
Aboriginal Linux image that includes a very old GCC 4.2.1 / Binutils 2.x
toolchain (2016 vintage) targeting a Linux ABI — not the baremetal ELF
target needed here. The recipe below follows standard upstream
GNU toolchain practice for a baremetal cross-compiler.

## Target triplet

`sh2-elf` — confirmed from `testrom/Makefile` and `sim/tests/Makefile`
which hard-code `CC = sh2-elf-gcc` and related tools. Both Makefiles pass
`-m2` to select the SH-2 CPU variant.

## Prerequisites (Ubuntu/Debian)

```bash
sudo apt install \
  build-essential \
  libgmp-dev \
  libmpfr-dev \
  libmpc-dev \
  libisl-dev \
  texinfo \
  flex \
  bison \
  wget \
  xz-utils
```

Package name notes:
- `libgmp-dev`, `libmpfr-dev`, `libmpc-dev`, `libisl-dev` — GCC
  prerequisite math libraries (ISL is optional but avoids a download
  step if present).
- `texinfo` — required for building binutils documentation; without it,
  `make install` may fail on `makeinfo` errors (add `--disable-doc` to
  configure if you prefer to skip docs entirely).
- `flex` / `bison` — required by both binutils and GCC build systems.

On **Fedora/RHEL/CentOS**: replace `apt install` with `dnf install` and use
`gmp-devel mpfr-devel libmpc-devel isl-devel` as package names.

## Build recipe

Approximate total time: 20–35 minutes on a modern multi-core machine.  
Peak disk usage during build: ~3.5 GB (sources + build trees).  
Installed footprint: ~150 MB under `$PREFIX`.

```bash
PREFIX=$HOME/cross/sh2-elf
TARGET=sh2-elf
BINUTILS_VER=2.43.1
GCC_VER=14.2.0

mkdir -p "$PREFIX/src"
cd "$PREFIX/src"

# ── 1) Binutils ──────────────────────────────────────────────────────────────
# Provides sh2-elf-as, sh2-elf-ld, sh2-elf-objcopy, sh2-elf-ar, etc.

wget https://ftp.gnu.org/gnu/binutils/binutils-${BINUTILS_VER}.tar.xz
tar xf binutils-${BINUTILS_VER}.tar.xz

mkdir build-binutils
cd build-binutils
../binutils-${BINUTILS_VER}/configure \
    --target=$TARGET \
    --prefix=$PREFIX \
    --disable-nls \
    --disable-werror
make -j$(nproc)
make install
cd ..

# ── 2) GCC (C only, with libgcc) ─────────────────────────────────────────────
# The testrom links against libgcc only; no libc, no C++ library needed.

wget https://ftp.gnu.org/gnu/gcc/gcc-${GCC_VER}/gcc-${GCC_VER}.tar.xz
tar xf gcc-${GCC_VER}.tar.xz

# Download GCC prerequisites (gmp, mpfr, mpc, isl) into the source tree.
# If the network is unavailable, install them via apt (see Prerequisites
# above) and omit this step; configure will find them automatically.
cd gcc-${GCC_VER}
./contrib/download_prerequisites
cd ..

mkdir build-gcc
cd build-gcc
../gcc-${GCC_VER}/configure \
    --target=$TARGET \
    --prefix=$PREFIX \
    --enable-languages=c \
    --without-headers \
    --disable-nls \
    --disable-shared \
    --disable-threads \
    --disable-libssp \
    --disable-libquadmath \
    --disable-libstdcxx \
    --with-cpu=m2
make all-gcc -j$(nproc)
make install-gcc
make all-target-libgcc -j$(nproc)
make install-target-libgcc
cd ..
```

**Why `--without-headers` and the disabled libraries?**  
This is a bare-metal target with no operating system. The flags tell GCC
not to expect a C library (stdio.h etc.) and skip building runtime
components that require one. The testrom programs link only against
`libgcc.a` (for integer division helpers, etc.) which `make
all-target-libgcc` provides.

**Why `--with-cpu=m2`?**  
Selects SH-2 as the default CPU. The J-Core J2 is a J-Core extension of
SH-2; the stock GCC SH-2 code generation is correct for the base ISA
that testrom exercises.

## PATH setup

```bash
export PATH=$HOME/cross/sh2-elf/bin:$PATH
```

Add this to `~/.profile` (login shells) or `~/.bashrc` (interactive shells)
to persist across sessions. If you use `~/.zshrc`, add it there instead.

## Verification

```bash
# Confirm the compiler is reachable and shows expected version
sh2-elf-gcc --version
# Expected output starts with: sh2-elf-gcc (GCC) 14.2.0

# Minimal compile-and-link smoke test (bare-metal, no startup)
printf 'int main(void){return 0;}\n' | \
  sh2-elf-gcc -x c -nostdlib -o /tmp/test.elf -
sh2-elf-objcopy -O binary /tmp/test.elf /tmp/test.img
ls -la /tmp/test.img
# Expect a small file (a few hundred bytes to a few KB); exact size
# depends on section alignment padding.

# Confirm the testrom builds cleanly
make -C /path/to/jcore-cpu/testrom
# Expect: no errors, produces main.elf
```

## Common pitfalls

- **Wrong target triplet**: `sh-elf` (without the "2") builds for a
  generic SuperH target and will produce a compiler with a different
  multilib layout. Always use `sh2-elf` to match the Makefiles.

- **`sh2-elf-gcc` not found after build**: The `bin/` subdirectory under
  `$PREFIX` must be on `$PATH`. Verify with `which sh2-elf-gcc` after
  setting PATH as shown above.

- **`download_prerequisites` fails**: If the GCC source tree cannot reach
  the GNU FTP server, install `libgmp-dev libmpfr-dev libmpc-dev libisl-dev`
  via apt and skip the `download_prerequisites` step. The configure script
  will find the system-installed libraries automatically.

- **`makeinfo` / texinfo errors during `make install`**: Add
  `--disable-doc` to both the binutils and GCC configure lines if you
  want to skip building documentation.

- **`libgcc` build fails with "headers not found"**: This can happen if
  `--without-headers` is accidentally omitted. Re-run configure with the
  flag present, then re-run `make all-target-libgcc`.

- **newlib NOT required**: The testrom does not use a C standard library.
  Do not install newlib unless you later need printf/malloc/etc. in test
  programs; adding it is a separate build step not covered here.

- **Old GCC in arboriginal**: The Aboriginal Linux system image in
  `arboriginal/system-image-sh2eb/` contains a GCC 4.2.1 / Binutils 2.x
  toolchain targeting `sh2eb` (big-endian Linux ABI). It is not suitable
  for bare-metal ELF and is extremely old. Do not use it as a reference.

## Alternative: crosstool-NG

[crosstool-NG](https://crosstool-ng.github.io/) wraps the manual build
above in a menuconfig-style interface and handles patching, download
mirroring, and reproducible configurations. To use it for an `sh2-elf`
target:

```bash
# Install crosstool-NG
git clone https://github.com/crosstool-ng/crosstool-ng.git
cd crosstool-ng
./bootstrap && ./configure --prefix=$HOME/ct-ng && make install
export PATH=$HOME/ct-ng/bin:$PATH

# List available SH samples and pick the closest one
ct-ng list-samples | grep sh

# Configure manually (no stock sh2-elf sample exists; use sh-unknown-elf
# as a base and change the CPU to sh2 in menuconfig)
ct-ng sh-unknown-elf
ct-ng menuconfig
# Under "Target options" → "Emit assembly for CPU": set to "m2"
# Under "C-library": select "none"

ct-ng build
```

The built toolchain will appear under `$HOME/x-tools/sh-unknown-elf/` (or
whatever target name you configured). Rename or symlink the binaries to
`sh2-elf-*` names if the Makefiles do not find them automatically.

Crosstool-NG is a good fallback if the manual build proves fragile across
OS upgrades, but the manual recipe above is straightforward and has fewer
moving parts.
