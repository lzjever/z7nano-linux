#!/bin/bash
# Step 2: Clone, configure, and build Linux kernel
# Produces: $(OUTPUT_DIR)/zImage, $(OUTPUT_DIR)/zynq-z7-nano.dtb, $(OUTPUT_DIR)/modules.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

KVER="${KERNEL_DIR##*/}"
ZIMAGE="${OUTPUT_DIR}/zImage"
DTB="${OUTPUT_DIR}/zynq-z7-nano.dtb"
MODULES_TAR="${OUTPUT_DIR}/modules.tar.gz"

echo "=== Step 2: Linux Kernel $(KERNEL_VER) ==="

# --- Download ---
KDIR="${DL_DIR}/linux"
if [ ! -f "${KDIR}/.extracted" ]; then
    TARFILE="${DL_DIR}/linux-${KERNEL_VER:v%=}.tar.xz"
    if [ ! -f "$TARFILE" ]; then
        echo "Downloading kernel ${KERNEL_VER}..."
        mkdir -p "${DL_DIR}"
        curl -L -o "$TARFILE" "${KERNEL_URL}/linux-${KERNEL_VER:v%=}.tar.xz"
    fi
    echo "Extracting..."
    mkdir -p "${KDIR}"
    tar xf "$TARFILE" -C "${DL_DIR}"
    touch "${KDIR}/.extracted"
    # Update KERNEL_DIR to actual extracted dir
    mv "${DL_DIR}/linux-${KERNEL_VER:v%=}" "${KDIR}" 2>/dev/null || true
fi

cd "${KDIR}"

# --- Apply patches ---
echo "Applying board patches..."
for patch in ../../patches/kernel/*.patch; do
    [ -f "$patch" ] || continue
    patch -p1 --forward < "$patch" 2>/dev/null && echo "  Applied: $(basename $patch)" \
        || echo "  Already applied: $(basename $patch)"
done

# --- Configure ---
echo "Configuring kernel (multi_v7_defconfig)..."
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" multi_v7_defconfig

# Enable FPGA Manager support
echo "Enabling FPGA Manager framework..."
./scripts/config -e CONFIG_FPGA
./scripts/config -e CONFIG_FPGA_MGR_ZYNQ_FPGA
./scripts/config -e CONFIG_FPGA_BRIDGE
./scripts/config -e CONFIG_FPGA_REGION
./scripts/config -e CONFIG_OF_OVERLAY
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" olddefconfig

# --- Build ---
echo "Building kernel (this takes 10-20 minutes)..."
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" \
     -j"${JOBS:-$(nproc)}" zImage dtbs modules

# --- Install modules ---
echo "Installing modules..."
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" \
     INSTALL_MOD_PATH="${OUTPUT_DIR}/modules" modules_install

# Refresh Module.symvers for out-of-tree module builds
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" modules_prepare 2>/dev/null || true
make ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" modules 2>/dev/null || true

# --- Copy outputs ---
mkdir -p "${OUTPUT_DIR}"
cp arch/arm/boot/zImage "${ZIMAGE}"
cp arch/arm/boot/dts/xilinx/zynq-z7-nano.dtb "${DTB}"
tar czf "${MODULES_TAR}" -C "${OUTPUT_DIR}/modules" .

# --- Verify ---
for f in "${ZIMAGE}" "${DTB}" "${MODULES_TAR}"; do
    [ -f "$f" ] || { echo "ERROR: Missing $f"; exit 1; }
done

SIZE=$(stat -c%s "${ZIMAGE}")
echo "Kernel built: ${ZIMAGE} (${SIZE} bytes)"
echo "DTB: ${DTB}"
echo "Modules: ${MODULES_TAR}"
echo "Next: make rootfs"
