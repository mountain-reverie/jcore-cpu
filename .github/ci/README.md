# jcore-cpu CI toolchain image

This directory holds the Dockerfile for the heavy-toolchain image used
by `.github/workflows/full-regression.yml`. The image is published to
`ghcr.io/<owner>/jcore-cpu-ci:latest`.

## What's in the image

| Tool | Version | Purpose |
|------|---------|---------|
| Ubuntu base | 24.04 | Modern apt deps (boost, eigen, tcl, etc.) |
| Go | 1.26.2 | `go test ./...`, `make -C decode generate` |
| GHDL | 6.0.0 (built from source, `--enable-libghdl --enable-synth`) | Step 3, 4, 5, 7 |
| yosys | 0.44 | Step 7 synthesis |
| ghdl-yosys-plugin | commit `07a30ed` (pinned) | Bridges GHDL into yosys for Step 7 |
| sh2-elf-gcc | 14.2.0 (binutils 2.43.1) | Step 6 cross-compile of sim/tests |
| openSTA | apt (`opensta`) | Step 8 static timing analysis |
| Nangate45 Liberty | upstream OpenSTA examples, `nangate45_slow.lib.gz` | Step 8 cell library, installed at `/opt/nangate45/nangate45.lib` |
| SKY130 Liberty (tt 025C 1v80) | open_pdks build `bdc9412b` (via `ciel`) | ASIC cheap-tier timing, installed at `/opt/sky130/sky130_fd_sc_hd__tt_025C_1v80.lib`; env `SKY130_LIB` |
| IHP SG13G2 Liberty (typ 1p20V 25C) | IHP-Open-PDK tag `v1.0` | ASIC cheap-tier timing, installed at `/opt/ihp-sg13g2/sg13g2_stdcell_typ_1p20V_25C.lib`; env `IHP_SG13G2_LIB` |

The image size is roughly 2.5–3.0 GB. Cold build time on a 4-core
ubuntu-24.04 runner is 30–60 minutes (sh2-elf-gcc and GHDL dominate).

## Why pinned versions

- **GHDL 6.0.0**: Ubuntu 24.04 ships an older GHDL whose `libghdl` does
  not export the symbols `ghdl-yosys-plugin` needs.
- **ghdl-yosys-plugin @ `07a30ed`**: Commits past this point introduce
  calls to `get_sname_index`, which does not exist in GHDL 6.0.0. Bump
  the plugin commit and GHDL version together.
- **yosys 0.44**: Most recent release known to work with the pinned
  plugin commit.
- **sh2-elf-gcc 14.2.0 / binutils 2.43.1**: Recipe verbatim from
  `decode/gen-go/docs/sh2-elf-build.md` — kept in lockstep with that
  file. Bumping the toolchain version should be coordinated with a
  separate validation pass on the test ROM binaries.

## Rebuilding the image

The image rebuilds automatically when `.github/ci/Dockerfile` or
`.github/workflows/build-ci-image.yml` lands on `master` / `main`. You
can also rebuild on demand:

1. Open the Actions tab on GitHub.
2. Choose the **build-ci-image** workflow.
3. Click **Run workflow** and select the branch.

The workflow pushes two tags:

- `:latest` — overwritten each build; consumed by `full-regression.yml`.
- `:sha-<short>` — immutable, for rollback. To pin a specific image,
  temporarily edit `full-regression.yml`'s `container.image:` field.

## Bumping a tool version

1. Edit the matching `ARG` line in `Dockerfile`.
2. Commit and push to `master` (or open a PR — the rebuild runs on PR
   merge, not on every PR push).
3. Wait for `build-ci-image` to publish a new `:latest`.
4. Re-run `full-regression` and confirm Step 7 / 8 still pass — these
   are the most version-sensitive steps.

## Local reproduction

```bash
# From repository root:
docker build -t jcore-cpu-ci -f .github/ci/Dockerfile .

# Drop into a shell with all tools:
docker run --rm -it -v "$PWD:/work" -w /work jcore-cpu-ci

# Inside the container:
TOOLS_DIR=/work/../jcore-soc/tools bash decode/gen-go/regression.sh
```

(You'll need to mount or clone `jcore-soc` next to `jcore-cpu` for
`TOOLS_DIR` to resolve.)
