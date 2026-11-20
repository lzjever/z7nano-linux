#!/bin/bash
# Step 1: Clone, patch, and build U-Boot
# Produces: $(OUTPUT_DIR)/u-boot-dtb.bin
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

UBOOT_BIN="${OUTPUT_DIR}/u-boot-dtb.bin"
UBOOT_TAR="u-boot-$(date +%Y%m%d).tar"

echo "=== Step 1: U-Boot $(UBOOT_VER) ==="

# --- Clone ---
if [ ! -d "${UBOOT_DIR}" ]; then
    echo "Cloning U-Boot (shallow)..."
    mkdir -p "$(dirname ${UBOOT_DIR})"
    git clone --depth 1 --branch "${UBOOT_VER}" \
        https://github.com/u-boot/u-boot.git "${UBOOT_DIR}"
fi

cd "${UBOOT_DIR}"

# --- Apply patches ---
echo "Applying board patches..."
for patch in ../../patches/uboot/*.patch; do
    [ -f "$patch" ] || continue
    patch -p1 --forward < "$patch" 2>/dev/null && echo "  Applied: $(basename $patch)" \
        || echo "  Already applied: $(basename $patch)"
done

# --- Build ---
echo "Building U-Boot (JOBS=${JOBS:-$(nproc)})..."
make O="../../$(OUTPUT_DIR)/uboot-build" \
     CROSS_COMPILE="${CROSS_COMPILE}" \
     xilinx_zynq_virt_defconfig
make O="../../$(OUTPUT_DIR)/uboot-build" \
     CROSS_COMPILE="${CROSS_COMPILE}" \
     DEVICE_TREE=zynq-z7-nano \
     -j"${JOBS:-$(nproc)}"

# --- Copy output ---
cp "${OUTPUT_DIR}/uboot-build/u-boot-dtb.bin" "${UBOOT_BIN}"

# --- Verify ---
SIZE=$(stat -c%s "${UBOOT_BIN}")
if [ "$SIZE" -lt 500000 ]; then
    echo "ERROR: U-Boot binary too small (${SIZE} bytes)"
    exit 1
fi

# Verify device tree is embedded
if ! strings "${UBOOT_BIN}" | grep -q "Z7-Nano"; then
    echo "ERROR: Board device tree not embedded in U-Boot"
    exit 1
fi

touch .built
echo "U-Boot built: ${UBOOT_BIN} (${SIZE} bytes)"
echo "Next: make kernel"
