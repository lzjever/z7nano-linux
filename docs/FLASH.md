# Flashing and First Boot

This document describes how to bring up the MicroPhase Z7-Nano R20 board with either
the pre-built SD image or artifacts produced by a local build, and how to perform the
initial system configuration, including FPGA loading. A serial terminal at 115200
baud, 8N1, no flow control, is required for all interaction with the board.

## Flashing the Pre-Built SD Image

### Step 1: Download the image

Download the latest release from the GitHub Releases page of this repository. The
release contains an SD card image and its checksum:

| File | Description |
|---|---|
| `z7nano-sd.img.xz` | Compressed bootable SD image |
| `z7nano-sd.img.xz.sha256` | SHA256 checksum of the image |

```bash
wget https://github.com/lzjever/z7nano-linux/releases/latest/download/z7nano-sd.img.xz
wget https://github.com/lzjever/z7nano-linux/releases/latest/download/z7nano-sd.img.xz.sha256
```

### Step 2: Verify the checksum

```bash
sha256sum -c z7nano-sd.img.xz.sha256
```

The output must report `OK`. A failed verification means a corrupted or truncated
download; re-download before proceeding.

### Step 3: Write the image to the SD card

The write target is the whole device, not a partition. Writing to the wrong device
destroys all data on it.

```bash
# Identify the SD card device (confirm by capacity and model)
lsblk -o NAME,SIZE,MODEL,TRAN

# Unmount any partitions the desktop environment may have mounted automatically
umount /dev/sdX? 2>/dev/null || true

# Write the image (replace /dev/sdX with the device identified above)
xzcat z7nano-sd.img.xz | sudo dd of=/dev/sdX bs=4M conv=fsync status=progress
sync
```

Safety notes:

- Double-check the `of=` device against `lsblk` output before pressing Enter. Writing
  to the system disk instead of the SD card renders that disk unbootable.
- The command erases the entire target card.
- Use `/dev/sdX`, not `/dev/sdX1`; the image contains its own partition table.
- An 8 GB or larger card is required.

### Step 4: First boot

1. Insert the card into the Z7-Nano SD slot.
2. Set the boot-mode jumper to the SD position (see
   [TROUBLESHOOTING.md](TROUBLESHOOTING.md) if the board does not attempt to boot).
3. Connect the serial console and open a terminal:

   ```bash
   # Adjust the device name to your USB-UART adapter
   picocom -b 115200 /dev/ttyUSB0
   ```

4. Apply power.

Expected sequence on the console:

| Time after power-on | Console activity |
|---|---|
| 0 to 10 s | Nothing. The FSBL is silent by design. |
| ~10 s | U-Boot banner and boot messages |
| 10 to 30 s | Linux kernel boot log |
| ~30 s | Debian login prompt |

Log in as `root` with password `root`, then change the password immediately:

```bash
passwd
```

## Manual SD Card Setup

As an alternative to flashing the full image, a card can be partitioned and populated
directly with artifacts from a local build (`build/output/`). The project automates
this with `make sd DEV=/dev/sdX`; the equivalent manual procedure follows.

### Partition layout

| Partition | Type | Size | Contents |
|---|---|---|---|
| 1 | FAT32 (LBA), bootable | 512 MB | `BOOT.BIN`, `boot.scr`, `zImage`, `zynq-z7nano.dtb` |
| 2 | ext4 | Remaining capacity | Debian root filesystem |

### Creating the partitions

```bash
# Replace /dev/sdX with the actual device; this erases the card
sudo sfdisk /dev/sdX <<'EOF'
label: dos
start=2048, size=1048576, type=c, bootable
type=83
EOF

sudo mkfs.vfat -F 32 -n BOOT /dev/sdX1
sudo mkfs.ext4 -L rootfs /dev/sdX2
```

The 512 MB boot partition size matches `BOOT_SIZE_SECTORS` in `config/board.mk`.

### Populating the partitions

```bash
sudo mkdir -p /mnt/z7boot /mnt/z7root
sudo mount /dev/sdX1 /mnt/z7boot
sudo mount /dev/sdX2 /mnt/z7root

# Boot partition
sudo cp build/output/BOOT.BIN /mnt/z7boot/
sudo cp build/output/boot.scr /mnt/z7boot/
sudo cp build/output/zImage /mnt/z7boot/
sudo cp build/output/zynq-z7nano.dtb /mnt/z7boot/

# Root filesystem
sudo tar -xzf build/output/rootfs.tar.gz -C /mnt/z7root

sync
sudo umount /mnt/z7boot /mnt/z7root
```

## First Boot Configuration

### Login

The default account is `root` with password `root`. Change it before connecting the
board to any shared network:

```bash
passwd
```

### Network setup

The Ethernet interface is named `end0` on this kernel (not `eth0`; see
[TROUBLESHOOTING.md](TROUBLESHOOTING.md) for background and renaming options). Obtain
an address with DHCP using systemd-networkd:

```bash
cat > /etc/systemd/network/10-dhcp.network <<'EOF'
[Match]
Name=end0

[Network]
DHCP=yes
EOF

systemctl enable --now systemd-networkd
systemctl enable --now systemd-resolved
ip addr show end0
```

For a static address, replace the `[Network]` section with explicit addresses:

```ini
[Network]
Address=192.168.1.50/24
Gateway=192.168.1.1
DNS=192.168.1.1
```

To install an SSH server:

```bash
apt update
apt install openssh-server
```

### FPGA loading

The Linux stack does not program the PL by default. The supported workflow is to load
the bitstream over JTAG from the host and then bring up the PL clocks and interfaces
from Linux with register writes.

#### Step 1: Program the bitstream over JTAG

From the host, using openFPGALoader:

```bash
openFPGALoader -f path/to/design.bit
```

Or, with Vivado Hardware Manager: open the target, select the XC7Z020 device, and
program it with the bitstream file.

#### Step 2: Enable FCLK0 and the PS-PL interface from Linux

The bitstream loaded over JTAG does not reconfigure the PL clocks, resets, or level
shifters; Linux must do it. The `devmem` utility from busybox provides the register
access:

```bash
apt install -y busybox

devmem() { busybox devmem "$@"; }

devmem 0xF8000004 32 0x0000DF0D   # SLCR_UNLOCK: allow SLCR writes
devmem 0xF8000240 32 0x00000000   # FPGA_RST_CTRL: deassert all PL resets
devmem 0xF8000170 32 0x0010000A   # FPGA0_CLK_CTRL: FCLK0 = IO PLL / 10 = 100 MHz
devmem 0xF8000180 32 0x00000001   # FPGA0_THR_CNT: start the FCLK0 counter
devmem 0xF8000900 32 0x0000000F   # LVL_SHFTR_EN: enable all PS-PL level shifters
devmem 0xF8000000 32 0x0000767B   # SLCR_LOCK: re-lock SLCR
```

Register summary (SLCR base 0xF8000000; see the Zynq-7000 TRM, UG585, for field
layouts):

| Address | Register | Value | Purpose |
|---|---|---|---|
| `0xF8000004` | `SLCR_UNLOCK` | `0xDF0D` | Unlock SLCR for writing |
| `0xF8000240` | `FPGA_RST_CTRL` | `0x0` | Deassert PL external resets |
| `0xF8000170` | `FPGA0_CLK_CTRL` | `0x0010000A` | FCLK0 source and divisor (100 MHz) |
| `0xF8000180` | `FPGA0_THR_CNT` | `0x1` | Start the FCLK0 threshold counter |
| `0xF8000900` | `LVL_SHFTR_EN` | `0xF` | Enable all four level shifters |
| `0xF8000000` | `SLCR_LOCK` | `0x767B` | Re-lock SLCR |

Adjust the divisor in `FPGA0_CLK_CTRL` for a different FCLK0 frequency; the IO PLL
runs at 1000 MHz, so the written value gives 1000/divisor MHz.

If the PL design hangs or returns bus errors, review the AXI protocol notes in
[TROUBLESHOOTING.md](TROUBLESHOOTING.md).
