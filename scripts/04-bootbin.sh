#!/bin/bash
# Step 4: Package BOOT.BIN (FSBL + U-Boot)
# Produces: $(OUTPUT_DIR)/BOOT.BIN
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

FSBL="assets/zynq_fsbl.elf"
UBOOT_BIN="${OUTPUT_DIR}/u-boot-dtb.bin"
BOOTBIN="${OUTPUT_DIR}/BOOT.BIN"
BOOTGEN="tools/make-bootbin.py"

echo "=== Step 4: BOOT.BIN ==="

# --- Verify inputs ---
[ -f "${FSBL}" ] || {
    echo "ERROR: FSBL not found at ${FSBL}"
    echo "  Place the vendor FSBL (zynq_fsbl.elf) in assets/"
    echo "  Source: vendor's Linux demo package (04_Linux_Demo)"
    exit 1
}

[ -f "${UBOOT_BIN}" ] || {
    echo "ERROR: U-Boot not found. Run 'make uboot' first."
    exit 1
}

[ -f "${BOOTGEN}" ] || {
    echo "ERROR: make-bootbin.py not found at ${BOOTGEN}"
    exit 1
}

# --- Package ---
echo "Packaging BOOT.BIN..."
python3 "${BOOTGEN}" \
    --template "${FSBL}" \
    --uboot "${UBOOT_BIN}" \
    --text-base "${UBOOT_TEXT_BASE}" \
    -o "${BOOTBIN}"

# --- Verify ---
SIZE=$(stat -c%s "${BOOTBIN}")
[ "$SIZE" -gt 1000000 ] || {
    echo "ERROR: BOOT.BIN too small (${SIZE} bytes)"
    exit 1
}

# Verify magic bytes at offset 0x20
MAGIC=$(xxd -s 0x20 -l 4 "${BOOTBIN}" | awk '{print $2}')
[ "$MAGIC" = "6655" ] || {
    echo "ERROR: BOOT.BIN missing Zynq magic at 0x20 (got ${MAGIC})"
    exit 1
}

echo "BOOT.BIN packaged: ${BOOTBIN} (${SIZE} bytes)"
echo ""
echo "=== Build complete ==="
echo "Artifacts:"
ls -la "${OUTPUT_DIR}"/{BOOT.BIN,zImage,zynq-z7-nano.dtb,rootfs.tar.gz} 2>/dev/null
echo ""
echo "Next: make sd DEV=/dev/sdX  (to create bootable SD card)"
echo "  or: make image             (to create .img file)"
