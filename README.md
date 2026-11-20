# Mainline Linux for MicroPhase Z7-Nano

This project provides a complete, reproducible build system that produces a bootable
mainline Linux platform for the MicroPhase Z7-Nano R20 development board, based on the
Xilinx Zynq-7000 XC7Z020 SoC. The stack is assembled entirely from mainline components:
U-Boot 2026.01, Linux kernel 6.18, and Debian 13 (trixie). No Xilinx/AMD Vivado
installation is required to build the software stack; the FSBL binary needed for
BOOT.BIN packaging is included in the repository. The build can be driven one step at a
time or as a single command, and pre-built SD card images are published for users who
only need a working system.

## Features

| Feature | Detail |
|---|---|
| Mainline U-Boot | v2026.01 with a minimal board patch set |
| Mainline Linux kernel | v6.18 with a Z7-Nano device tree |
| Debian userland | Debian 13 (trixie), armhf, bootstrapped with debootstrap |
| Pre-built images | Ready-to-flash SD card images on the GitHub Releases page |
| Flexible build | Step-by-step make targets or one-shot `make all` |
| Single-point configuration | All versions, mirrors, and board parameters in `config/board.mk` |
| No vendor tools required | FSBL shipped pre-built; packaging uses open tooling |

## Quick Start

Two paths are supported. Choose one.

### Path A: Flash the pre-built image

```bash
# 1. Download the latest release image and its checksum
wget https://github.com/lzjever/z7nano-linux/releases/latest/download/z7nano-sd.img.xz
wget https://github.com/lzjever/z7nano-linux/releases/latest/download/z7nano-sd.img.xz.sha256

# 2. Verify the download
sha256sum -c z7nano-sd.img.xz.sha256

# 3. Write it to an SD card (replace /dev/sdX with your actual device)
xzcat z7nano-sd.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
```

Insert the card, set the board boot-mode jumper to SD boot, connect a serial terminal
at 115200 8N1, and apply power. The login prompt appears in roughly 30 seconds;
log in as `root` with password `root`.

See [docs/FLASH.md](docs/FLASH.md) for full instructions, safety notes, and first-boot
configuration.

### Path B: Build from source

```bash
git clone https://github.com/lzjever/z7nano-linux.git
cd z7nano-linux

make deps        # Install the cross-toolchain and build packages (uses sudo)
make all         # Build U-Boot, kernel, Debian rootfs, and BOOT.BIN

# Either write the artifacts to an SD card directly
make sd DEV=/dev/sdX

# Or produce a flashable image file
make image       # Creates build/output/z7nano-sd.img
```

See [docs/BUILD.md](docs/BUILD.md) for the step-by-step guide, expected build times,
and configuration options.

## Hardware Requirements

| Item | Requirement |
|---|---|
| Development board | MicroPhase Z7-Nano R20 (Xilinx Zynq XC7Z020-2CLG400, 512 MB DDR) |
| Boot media | microSD card, 8 GB minimum, class 10 recommended |
| Host computer (build) | x86-64 running Ubuntu 22.04 or newer, 40 GB free disk |
| Host computer (use) | Any system with a serial terminal application |
| Serial console | 115200 baud, 8N1, no flow control; on-board USB-UART bridge or external 3.3 V adapter |
| Power supply | DC supply as specified in the Z7-Nano board documentation |
| Optional | Vivado Hardware Manager or openFPGALoader for FPGA bitstream loading |

## Repository Structure

```text
z7nano-linux/
├── Makefile               # Entry point for all build targets
├── config/
│   ├── board.mk           # All tunables: versions, mirrors, board parameters
│   └── local.mk           # Optional local overrides (not committed)
├── scripts/
│   ├── 00-deps.sh         # Install host build dependencies
│   ├── 01-uboot.sh        # Clone, patch, and build U-Boot
│   ├── 02-kernel.sh       # Download, patch, configure, and build Linux
│   ├── 03-rootfs.sh       # Bootstrap the Debian root filesystem
│   ├── 04-bootbin.sh      # Package BOOT.BIN (FSBL + U-Boot)
│   ├── 05-sdcard.sh       # Partition and populate an SD card
│   └── 06-release.sh      # Build the SD image and package release artifacts
├── patches/
│   ├── uboot/             # Patches applied to the U-Boot source tree
│   └── kernel/            # Patches applied to the Linux source tree
├── assets/                # Vendor-derived FSBL and board files
├── tools/                 # Helper utilities used by the build
├── docs/
│   ├── BUILD.md           # Step-by-step build guide
│   ├── FLASH.md           # Flashing and first-boot procedures
│   └── TROUBLESHOOTING.md # Known issues and solutions
└── build/                 # Generated during the build (not committed)
```

## Documentation

- [docs/BUILD.md](docs/BUILD.md) — Prerequisites, step-by-step build guide, configuration reference, and customization.
- [docs/FLASH.md](docs/FLASH.md) — Flashing the pre-built image, manual SD card setup, and first-boot configuration including FPGA loading.
- [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) — Known issues with causes and solutions.

## License

This project is released under the MIT License. The generated artifacts are covered by
the licenses of their respective upstream projects (U-Boot: GPL-2.0+; Linux: GPL-2.0;
Debian packages: their individual licenses).

## Acknowledgments

- MicroPhase, for the Z7-Nano hardware documentation and the vendor package from which
  the FSBL is derived.
- The codex review pass, which provided an independent audit of the build scripts and
  documentation.
