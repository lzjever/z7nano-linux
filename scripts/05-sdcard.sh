#!/bin/bash
# Step 5: Interactive SD card partition + format + install
# Usage: ./scripts/05-sdcard.sh /dev/sdX
# SAFETY: Only operates on removable devices
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

DEV="${1:?Usage: $0 /dev/sdX}"

# ============================================================
# Safety checks — refuse to operate on non-removable devices
# ============================================================
[ -b "$DEV" ] || { echo "ERROR: $DEV is not a block device"; exit 1; }
echo "$DEV" | grep -q "nvme" && { echo "ERROR: Refusing NVMe device"; exit 1; }
RM=$(lsblk -no RM "$DEV" | head -1 | tr -d ' ')
[ "$RM" = "1" ] || {
    echo "ERROR: $DEV is not marked as removable (safety check)"
    echo "  If you are sure this is correct, remove this check manually."
    exit 1
}

MODEL=$(lsblk -no MODEL "$DEV" | head -1)
SIZE=$(lsblk -no SIZE "$DEV" | head -1)
echo "Target: $DEV ($MODEL, $SIZE)"
echo ""
echo "WARNING: This will ERASE ALL DATA on $DEV"
# Preflight: verify all artifacts exist before touching the card
echo "Checking artifacts..."
for f in "${OUTPUT_DIR}/BOOT.BIN" "${OUTPUT_DIR}/zImage" "${OUTPUT_DIR}/zynq-z7-nano.dtb" "${OUTPUT_DIR}/rootfs.tar.gz"; do
    [ -f "$f" ] || { echo "ERROR: Missing $f"; echo "  Run 'make all' first."; exit 1; }
done
echo "All artifacts present."

read -p "Type 'yes' to continue: " CONFIRM
[ "$CONFIRM" = "yes" ] || { echo "Aborted."; exit 1; }

# Unmount any existing partitions
sudo umount "${DEV}"* 2>/dev/null || true

# ============================================================
# Partition
# ============================================================
echo "Partitioning..."
sudo sfdisk --wipe always "$DEV" <<EOF
label: dos
start=8192, size=${BOOT_SIZE_SECTORS}, type=c
start=$((8192 + BOOT_SIZE_SECTORS)), type=83
EOF
sudo partprobe "$DEV" || true
sleep 2

P1="${DEV}1"
P2="${DEV}2"

# ============================================================
# Format
# ============================================================
echo "Formatting boot partition (FAT32)..."
sudo mkfs.vfat -F 32 -n ZNANOBOOT "$P1"
echo "Formatting root partition (ext4)..."
sudo mkfs.ext4 -q -L rootfs "$P2"

# ============================================================
# Populate boot partition
# ============================================================
echo "Populating boot partition..."
sudo mkdir -p /mnt/z7nano-boot /mnt/z7nano-root
sudo mount "$P1" /mnt/z7nano-boot
sudo mount "$P2" /mnt/z7nano-root

sudo cp "${OUTPUT_DIR}/BOOT.BIN" /mnt/z7nano-boot/
sudo cp "${OUTPUT_DIR}/zImage" /mnt/z7nano-boot/
sudo cp "${OUTPUT_DIR}/zynq-z7-nano.dtb" /mnt/z7nano-boot/

sudo mkdir -p /mnt/z7nano-boot/extlinux
sudo tee /mnt/z7nano-boot/extlinux/extlinux.conf > /dev/null <<EOF
label Debian $(DEBIAN_VER) (mainline $(KERNEL_VER)) — Z7-Nano
    kernel /zImage
    fdt /zynq-z7-nano.dtb
    append root=/dev/mmcblk0p2 rootwait rw console=ttyPS0,${UART_BAUD}
EOF

# ============================================================
# Populate root partition
# ============================================================
echo "Populating root partition (this takes a few minutes)..."
sudo tar xzf "${OUTPUT_DIR}/rootfs.tar.gz" -C /mnt/z7nano-root

# ============================================================
# Sync and unmount
# ============================================================
echo "Syncing..."
sync
sudo umount /mnt/z7nano-boot /mnt/z7nano-root
rmdir /mnt/z7nano-boot /mnt/z7nano-root 2>/dev/null || true

echo ""
echo "=== SD card created successfully ==="
echo "Insert into board's SD slot, set jumper to SD boot, power on."
echo "Login: root/root  (serial console 115200 8N1)"
