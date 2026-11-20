# board.mk — All tunables for MicroPhase Z7-Nano R20 (XC7Z020)
# Override any variable via environment or config/local.mk

# SoC
PART        := xc7z020clg400-2
SOC         := zynq-7000

# Versions
UBOOT_VER   := v2026.01
KERNEL_VER  := v6.18
DEBIAN_VER  := trixie

# Mirrors (adjust for your region)
KERNEL_URL  := https://mirrors.tuna.tsinghua.edu.cn/kernel/v6.x
DEBIAN_MIRROR := https://mirrors.tuna.tsinghua.edu.cn/debian

# DDR size (bytes) — affects device tree memory node
DDR_SIZE    := 0x20000000  # 512 MB

# Console UART
UART_BASE   := 0xE0000000  # UART0
UART_BAUD   := 115200

# Ethernet PHY
PHY_ADDR    := 1
PHY_RESET_MIO := 46

# Boot partition size (sectors, 512B each)
BOOT_SIZE_SECTORS := 1048576  # 512 MB

# Cross compiler prefix
CROSS_COMPILE := arm-linux-gnueabihf-

# Build directories (relative to repo root)
BUILD_DIR   := build
DL_DIR      := $(BUILD_DIR)/downloads
UBOOT_DIR   := $(BUILD_DIR)/u-boot
KERNEL_DIR  := $(BUILD_DIR)/linux-$(KERNEL_VER:v%=)
ROOTFS_DIR  := $(BUILD_DIR)/rootfs
OUTPUT_DIR  := $(BUILD_DIR)/output

# U-Boot text base (match xilinx_zynq_virt_defconfig)
UBOOT_TEXT_BASE := 0x04000000

# Include local overrides if present
-include config/local.mk
