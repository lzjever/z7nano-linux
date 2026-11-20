# z7nano-linux — Mainline Linux for MicroPhase Z7-Nano
# Usage: make [target] — see docs/BUILD.md for details

include config/board.mk

.PHONY: all deps uboot kernel rootfs bootbin sd release image clean distclean help

all: deps uboot kernel rootfs bootbin
	@echo "=== Build complete ==="
	@echo "Artifacts in $(OUTPUT_DIR)/"
	@ls -la $(OUTPUT_DIR)/ 2>/dev/null || echo "(output dir empty)"

help:
	@echo "z7nano-linux — Mainline Linux for MicroPhase Z7-Nano"
	@echo ""
	@echo "Targets:"
	@echo "  all       Build everything (deps + uboot + kernel + rootfs + bootbin)"
	@echo "  deps      Install build dependencies (requires sudo)"
	@echo "  uboot     Clone + patch + build U-Boot $(UBOOT_VER)"
	@echo "  kernel    Clone + configure + build Linux $(KERNEL_VER)"
	@echo "  rootfs    Bootstrap Debian $(DEBIAN_VER) rootfs"
	@echo "  bootbin   Package BOOT.BIN (FSBL + U-Boot)"
	@echo "  sd        Interactive SD card setup (requires DEV=/dev/sdX)"
	@echo "  image     Create bootable SD image (.img file)"
	@echo "  release   Package release artifacts (.img + components)"
	@echo "  clean     Remove build outputs (keep downloads)"
	@echo "  distclean Remove everything including downloads"
	@echo ""
	@echo "Variables (override via environment or config/local.mk):"
	@echo "  DEV=/dev/sdX    SD card device for 'make sd'"
	@echo "  JOBS=$(nproc)   Parallel build jobs"

# ============================================================
# Step 0: Dependencies
# ============================================================
deps:
	@./scripts/00-deps.sh

# ============================================================
# Step 1: U-Boot
# ============================================================
$(UBOOT_DIR)/.built:
	@./scripts/01-uboot.sh

uboot: $(UBOOT_DIR)/.built
	@echo "=== U-Boot built ==="

# ============================================================
# Step 2: Linux Kernel
# ============================================================
$(KERNEL_DIR)/.built:
	@./scripts/02-kernel.sh

kernel: $(KERNEL_DIR)/.built
	@echo "=== Kernel built ==="

# ============================================================
# Step 3: Debian Rootfs
# ============================================================
$(ROOTFS_DIR)/.built:
	@./scripts/03-rootfs.sh

rootfs: $(ROOTFS_DIR)/.built
	@echo "=== Rootfs built ==="

# ============================================================
# Step 4: BOOT.BIN
# ============================================================
$(OUTPUT_DIR)/BOOT.BIN: $(UBOOT_DIR)/.built
	@./scripts/04-bootbin.sh

bootbin: $(OUTPUT_DIR)/BOOT.BIN
	@echo "=== BOOT.BIN packaged ==="

# ============================================================
# SD Card (interactive)
# ============================================================
sd:
	@if [ -z "$(DEV)" ]; then echo "Usage: make sd DEV=/dev/sdX"; exit 1; fi
	@./scripts/05-sdcard.sh $(DEV)

# ============================================================
# SD Image (.img)
# ============================================================
image: all
	@./scripts/06-release.sh image

# ============================================================
# Release packaging
# ============================================================
release: all
	@./scripts/06-release.sh release

# ============================================================
# Cleanup
# ============================================================
clean:
	rm -rf $(BUILD_DIR)/u-boot $(BUILD_DIR)/linux-* $(BUILD_DIR)/rootfs $(BUILD_DIR)/output
	@echo "Build outputs cleaned"

distclean:
	rm -rf $(BUILD_DIR)
	@echo "Everything cleaned"
