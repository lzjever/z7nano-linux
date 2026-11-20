#!/bin/bash
# Step 0: Install build dependencies
# Idempotent: safe to run multiple times
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

echo "=== Installing build dependencies ==="

PACKAGES=(
    gcc-arm-linux-gnueabihf    # Cross compiler (ARM hard-float)
    device-tree-compiler        # dtc: compile device trees
    bison flex bc              # Kernel/U-Boot build tools
    libssl-dev                  # Kernel crypto
    libgnutls28-dev             # Kernel module signing
    swig python3-dev            # Kernel build scripts
    libncurses-dev              # menuconfig
    u-boot-tools                # mkimage
    debootstrap                 # Debian rootfs bootstrap
    qemu-user-static            # ARM binary emulation for chroot
    libelf-dev                  # mkbootimage dependency
    p7zip-full                  # Extract vendor assets
    python3-serial              # Serial port communication
    file                        # File type detection
)

echo "Installing ${#PACKAGES[@]} packages..."
sudo apt-get update -qq
sudo apt-get install -y "${PACKAGES[@]}"

echo ""
echo "Verifying cross compiler..."
${CROSS_COMPILE}gcc --version | head -1
echo ""
echo "Dependencies installed successfully."
echo "Next: make uboot"
