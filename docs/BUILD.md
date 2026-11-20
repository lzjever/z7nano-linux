# Building the System

This document describes how to build the complete boot stack for the MicroPhase
Z7-Nano R20 board from source: U-Boot 2026.01, Linux kernel 6.18, a Debian 13
(trixie) root filesystem, and the BOOT.BIN boot image. Each build stage is exposed
as a separate make target so the stages can be run and inspected individually, or the
whole stack can be built with a single command.

No Xilinx/AMD tools are required. The FSBL binary used for BOOT.BIN packaging is
included in the repository under `assets/`.

## Prerequisites

| Requirement | Detail |
|---|---|
| Operating system | Ubuntu 22.04 LTS or newer (x86-64) |
| Free disk space | 40 GB minimum |
| Memory | 4 GB minimum; 8 GB or more recommended for parallel kernel builds |
| Internet access | Sources are fetched from U-Boot, kernel.org, and Debian mirrors |
| Privileges | `sudo` access for `make deps` (package installation) |
| Time | 45 to 120 minutes for `make all`, depending on CPU and network |

The build downloads all upstream sources into `build/downloads/` and never installs
anything outside the host packages listed by `make deps`.

## Build Artifacts

All finished artifacts are placed in `build/output/`:

| File | Description |
|---|---|
| `BOOT.BIN` | Zynq boot image: FSBL + U-Boot, written to the SD boot partition |
| `boot.scr` | U-Boot boot script that loads the kernel and device tree |
| `zImage` | Linux kernel image |
| `zynq-z7nano.dtb` | Compiled device tree for the Z7-Nano R20 |
| `rootfs.tar.gz` | Debian 13 root filesystem tarball |
| `z7nano-sd.img` | Complete bootable SD image (produced by `make image`) |

## Step 1: Install Dependencies — `make deps`

Installs the ARM hard-float cross-compiler and every host package the later stages
need, including the device tree compiler, kernel build tooling, `mkimage`,
`debootstrap`, and `qemu-user-static` for the ARM chroot. The script is idempotent and
safe to run repeatedly.

```bash
make deps
```

- What it does: runs `scripts/00-deps.sh`, which calls `apt-get install` with
  `sudo` for approximately 20 packages, then verifies that the cross-compiler works.
- What it produces: a functional host build environment; no project artifacts.
- Expected duration: 2 to 5 minutes, dominated by package downloads.

Verify the toolchain afterwards:

```bash
arm-linux-gnueabihf-gcc --version
```

## Step 2: Build U-Boot — `make uboot`

Fetches the U-Boot v2026.01 source, applies the board patches from `patches/uboot/`,
configures the tree with the Zynq `xilinx_zynq_virt_defconfig` base configuration plus
board-specific settings, and builds U-Boot and its tools.

```bash
make uboot
```

- What it does: runs `scripts/01-uboot.sh`; the source is cloned into
  `build/u-boot/` and built with `arm-linux-gnueabihf-`.
- What it produces: the U-Boot ELF in `build/u-boot/`, consumed later by
  `make bootbin`, and `mkimage`-format artifacts.
- Expected duration: 5 to 15 minutes on a modern 8-core machine.

The step is stamp-tracked (`build/u-boot/.built`); re-running `make uboot` without
changes is a no-op. Delete the stamp file or run `make clean` to force a rebuild.

## Step 3: Build the Linux Kernel — `make kernel`

Downloads the Linux v6.18 source from the mirror configured in
`config/board.mk`, applies the board patches from `patches/kernel/` (which add the
Z7-Nano device tree source), applies a multi_v7 configuration suitable for Zynq-7000,
and builds the kernel image and device tree blobs.

```bash
make kernel
```

- What it does: runs `scripts/02-kernel.sh`; the source is unpacked into
  `build/linux-6.18/` and built with `make -j$(nproc)`.
- What it produces: `zImage` and `zynq-z7nano.dtb`, copied to `build/output/`.
- Expected duration: 15 to 45 minutes depending on core count; the first build is
  slower than incremental rebuilds.

To modify the kernel configuration interactively:

```bash
cd build/linux-6.18
make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- menuconfig
cd ../..
rm build/linux-6.18/.built
make kernel
```

## Step 4: Bootstrap the Debian Rootfs — `make rootfs`

Creates a Debian 13 (trixie) armhf root filesystem with `debootstrap`, executed under
`qemu-user-static` so that ARM binaries can run on the x86-64 host. The stage installs
core packages (systemd, networking, a package manager, and shell tools), sets the
default console, and packs the result as a tarball.

```bash
make rootfs
```

- What it does: runs `scripts/03-rootfs.sh`; the filesystem is assembled in
  `build/rootfs/` inside a chroot, then archived.
- What it produces: `build/output/rootfs.tar.gz`.
- Expected duration: 10 to 30 minutes, dominated by package downloads from the
  configured Debian mirror.

## Step 5: Package BOOT.BIN — `make bootbin`

Packages the FSBL binary from `assets/` together with the U-Boot ELF built in
Step 2 into `BOOT.BIN`, the image the Zynq boot ROM loads from the SD card.

```bash
make bootbin
```

- What it does: runs `scripts/04-bootbin.sh`; no compilation is involved, only
  image assembly.
- What it produces: `build/output/BOOT.BIN`.
- Expected duration: a few seconds.

## One-Shot Build — `make all`

Runs every stage in order: dependencies, U-Boot, kernel, rootfs, and BOOT.BIN.

```bash
make all
```

- Expected duration: 45 to 120 minutes.

Afterwards, write the artifacts to a card with `make sd DEV=/dev/sdX` (see
[FLASH.md](FLASH.md)) or generate a distributable image with `make image`.

## Additional Targets

| Target | Purpose |
|---|---|
| `make sd DEV=/dev/sdX` | Partition an SD card and populate it with the build artifacts (interactive, destructive) |
| `make image` | Run `make all`, then create `build/output/z7nano-sd.img` |
| `make release` | Run `make all`, then package the image and component artifacts for a release |
| `make clean` | Remove build outputs, keeping downloaded sources |
| `make distclean` | Remove the entire `build/` tree, including downloads |
| `make help` | List all targets and variables |

## Configuration

All tunables live in `config/board.mk` and can be overridden either by environment
variables on the make command line or by a `config/local.mk` file, which is included
automatically if present.

| Variable | Default | Description |
|---|---|---|
| `UBOOT_VER` | `v2026.01` | U-Boot tag to build |
| `KERNEL_VER` | `v6.18` | Linux version to build |
| `DEBIAN_VER` | `trixie` | Debian release for the root filesystem |
| `KERNEL_URL` | Tsinghua kernel mirror | Base URL for kernel tarballs |
| `DEBIAN_MIRROR` | Tsinghua Debian mirror | Mirror used by debootstrap and apt |
| `CROSS_COMPILE` | `arm-linux-gnueabihf-` | Cross-compiler prefix |
| `PART` | `xc7z020clg400-2` | Zynq part on the board |
| `DDR_SIZE` | `0x20000000` | DDR size in bytes; feeds the device tree memory node |
| `UART_BASE` / `UART_BAUD` | `0xE0000000` / `115200` | Console UART and baud rate |
| `PHY_ADDR` / `PHY_RESET_MIO` | `1` / `46` | Ethernet PHY address and reset pin |
| `BOOT_SIZE_SECTORS` | `1048576` | Boot partition size in 512-byte sectors (512 MB) |
| `UBOOT_TEXT_BASE` | `0x04000000` | U-Boot link address; must match the defconfig |
| `BUILD_DIR` | `build` | Root of the generated build tree |

## Customization

### Changing the kernel version

Override `KERNEL_VER` and point `KERNEL_URL` at the matching directory:

```bash
make kernel KERNEL_VER=v6.19 KERNEL_URL=https://cdn.kernel.org/pub/linux/kernel/v6.x
```

Board patches are written against v6.18; when moving to a significantly newer tree,
review `patches/kernel/` for rejects and update the device tree as needed.

### Changing the Debian release

```bash
make rootfs DEBIAN_VER=bookworm
```

Any Debian suite or snapshot name accepted by debootstrap can be used.

### Using a different mirror

The defaults use the Tsinghua University mirrors, which are fast within China.
International users may prefer the canonical sources:

```bash
# As a config/local.mk file:
cat > config/local.mk <<'EOF'
KERNEL_URL   := https://cdn.kernel.org/pub/linux/kernel/v6.x
DEBIAN_MIRROR := https://deb.debian.org/debian
EOF
```

All subsequent builds pick up the overrides automatically. Changing mirrors mid-build
is safe; downloaded tarballs are keyed by version, not by mirror.
