#!/bin/bash
# Step 3: Bootstrap Debian rootfs
# Produces: $(OUTPUT_DIR)/rootfs.tar.gz
set -euo pipefail
cd "$(dirname "$0")/.."
source config/board.mk

ROOTFS="${BUILD_DIR}/rootfs"
ROOTFS_TAR="${OUTPUT_DIR}/rootfs.tar.gz"

echo "=== Step 3: Debian $(DEBIAN_VER) Rootfs ==="

# --- Bootstrap ---
if [ ! -f "${ROOTFS}/.bootstrap-done" ]; then
    echo "Bootstrapping Debian (stage 1)..."
    sudo rm -rf "${ROOTFS}"
    sudo debootstrap --arch=armhf --foreign \
        "${DEBIAN_VER}" "${ROOTFS}" "${DEBIAN_MIRROR}"
    sudo touch "${ROOTFS}/.bootstrap-done"
fi

if [ ! -f "${ROOTFS}/.second-stage-done" ]; then
    echo "Running debootstrap stage 2 (via qemu, 20-40 min)..."
    sudo cp /usr/bin/qemu-arm-static "${ROOTFS}/usr/bin/"
    sudo chroot "${ROOTFS}" /debootstrap/debootstrap --second-stage
    sudo rm -f "${ROOTFS}/usr/bin/qemu-arm-static"
    sudo touch "${ROOTFS}/.second-stage-done"
fi

# --- Configure ---
echo "Configuring rootfs..."

# APT sources
sudo tee "${ROOTFS}/etc/apt/sources.list" > /dev/null <<EOF
deb ${DEBIAN_MIRROR} ${DEBIAN_VER} main contrib non-free non-free-firmware
EOF

# Hostname
echo "z7nano" | sudo tee "${ROOTFS}/etc/hostname" > /dev/null

# Hosts
printf "127.0.0.1\tlocalhost\n127.0.1.1\tz7nano\n" | \
    sudo tee "${ROOTFS}/etc/hosts" > /dev/null

# fstab
sudo tee "${ROOTFS}/etc/fstab" > /dev/null <<EOF
/dev/mmcblk0p2  /      ext4  errors=remount-ro  0 1
/dev/mmcblk0p1  /boot  vfat  defaults            0 2
EOF

# Network: match both eth0 (legacy) and end0 (predictable naming)
sudo mkdir -p "${ROOTFS}/etc/systemd/network"
sudo tee "${ROOTFS}/etc/systemd/network/10-eth.network" > /dev/null <<EOF
[Match]
Name=eth0
Name=end0

[Network]
DHCP=yes
EOF

# DNS
printf "nameserver 8.8.8.8\nnameserver 223.5.5.5\n" | \
    sudo tee "${ROOTFS}/etc/resolv.conf" > /dev/null

# Install packages in chroot
echo "Installing packages (via qemu)..."
sudo cp /usr/bin/qemu-arm-static "${ROOTFS}/usr/bin/"
sudo chroot "${ROOTFS}" /bin/bash -c '
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y openssh-server iproute2 nano sudo python3
    echo "root:root" | chpasswd
    systemctl enable ssh systemd-networkd
' 2>&1 | tail -3
sudo rm -f "${ROOTFS}/usr/bin/qemu-arm-static"

# Permit root SSH login via password (dev board default)
sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' \
    "${ROOTFS}/etc/ssh/sshd_config"

# --- Install kernel modules ---
if [ -d "${OUTPUT_DIR}/modules/lib/modules" ]; then
    KVER=$(ls "${OUTPUT_DIR}/modules/lib/modules/" | head -1)
    echo "Installing kernel modules (${KVER})..."
    sudo mkdir -p "${ROOTFS}/lib/modules"
    sudo cp -a "${OUTPUT_DIR}/modules/lib/modules/${KVER}" \
        "${ROOTFS}/lib/modules/"
    sudo rm -f "${ROOTFS}/lib/modules/${KVER}/build" \
                  "${ROOTFS}/lib/modules/${KVER}/source"
fi

# --- Package ---
echo "Packaging rootfs..."
sudo tar czf "${ROOTFS_TAR}" -C "${ROOTFS}" .
sudo chown "$(id -u):$(id -g)" "${ROOTFS_TAR}"

SIZE=$(stat -c%s "${ROOTFS_TAR}")
echo "Rootfs packaged: ${ROOTFS_TAR} ($(( SIZE / 1024 / 1024 )) MB)"
echo "Next: make bootbin"
