#!/bin/bash
# Step 6: Package release artifacts (.img + components)
# Usage: ./scripts/06-release.sh [image|release]
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

MODE="${1:-release}"
VER="$(date +%Y.%m.%d)"
OUT="release"
IMG_FILE="${OUT}/z7nano-linux-${VER}.img"
COMP_FILE="${OUT}/z7nano-linux-${VER}-components.tar.gz"
IMG_SIZE_MB=1536  # 1.5 GB (512MB boot + ~700MB rootfs + padding)

mkdir -p "${OUT}"

create_image() {
    echo "=== Creating bootable SD image ==="
    echo "Size: ${IMG_SIZE_MB} MB"
    dd if=/dev/zero of="${IMG_FILE}" bs=1M count=${IMG_SIZE_MB} status=progress

    # Attach loop device
    LOOP=$(sudo losetup --find --show -P "${IMG_FILE}")
    echo "Loop device: ${LOOP}"

    trap "sudo losetup -d ${LOOP}" EXIT

    # Partition
    sudo sfdisk --wipe always "${LOOP}" <<EOF
label: dos
start=8192, size=${BOOT_SIZE_SECTORS}, type=c
start=$((8192 + BOOT_SIZE_SECTORS)), type=83
EOF
    sleep 1

    # Format
    sudo mkfs.vfat -F 32 -n ZNANOBOOT "${LOOP}p1"
    sudo mkfs.ext4 -q -L rootfs "${LOOP}p2"

    # Populate boot
    sudo mkdir -p /mnt/rel-boot /mnt/rel-root
    sudo mount "${LOOP}p1" /mnt/rel-boot
    sudo mount "${LOOP}p2" /mnt/rel-root

    sudo cp "${OUTPUT_DIR}/BOOT.BIN" /mnt/rel-boot/
    sudo cp "${OUTPUT_DIR}/zImage" /mnt/rel-boot/
    sudo cp "${OUTPUT_DIR}/zynq-z7-nano.dtb" /mnt/rel-boot/
    sudo mkdir -p /mnt/rel-boot/extlinux
    sudo tee /mnt/rel-boot/extlinux/extlinux.conf > /dev/null <<EOF
label Debian $(DEBIAN_VER) (mainline $(KERNEL_VER)) — Z7-Nano
    kernel /zImage
    fdt /zynq-z7-nano.dtb
    append root=/dev/mmcblk0p2 rootwait rw console=ttyPS0,${UART_BAUD}
EOF

    # Populate root
    echo "Populating rootfs (this takes a few minutes)..."
    sudo tar xzf "${OUTPUT_DIR}/rootfs.tar.gz" -C /mnt/rel-root

    sync
    sudo umount /mnt/rel-boot /mnt/rel-root

    echo "Image created: ${IMG_FILE} ($(stat -c%s ${IMG_FILE} | numfmt --to=iec))"
}

create_components() {
    echo "=== Creating components package ==="
    tar czf "${COMP_FILE}" \
        -C "${OUTPUT_DIR}" \
        BOOT.BIN zImage zynq-z7-nano.dtb rootfs.tar.gz

    echo "Components: ${COMP_FILE} ($(stat -c%s ${COMP_FILE} | numfmt --to=iec))"
}

create_checksums() {
    echo "Generating SHA256SUMS..."
    cd "${OUT}"
    sha256sum *.img *.tar.gz > SHA256SUMS 2>/dev/null || \
        sha256sum * > SHA256SUMS
    cd ..
    echo "Checksums written to ${OUT}/SHA256SUMS"
}

case "$MODE" in
    image)
        create_image
        create_checksums
        ;;
    release)
        create_image
        create_components
        create_checksums
        echo ""
        echo "=== Release artifacts ==="
        ls -lah "${OUT}/"
        echo ""
        echo "Upload to GitHub Releases:"
        echo "  gh release create v${VER} ${OUT}/* --title \"z7nano-linux ${VER}\""
        ;;
    *)
        echo "Usage: $0 [image|release]"
        exit 1
        ;;
esac
