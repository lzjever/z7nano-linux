# Vendor Assets

## zynq_fsbl.elf

This is the First-Stage Boot Loader (FSBL) binary extracted from MicroPhase's
official Linux demo package (`04_Linux_Demo` → `1_petalinux_boot_from_sd`).

**What it does:** Initializes DDR memory, clocks, and MIO pin muxing for the
Z7-Nano R20 board before handing off to U-Boot. It is board-specific and
cannot be regenerated without Vivado and the board's hardware definition
file (.hdf).

**Licensing:** This binary is provided by MicroPhase for use with their
development boards. It is included here for convenience under the assumption
that users of this repository own a MicroPhase Z7-Nano board.

**If you need to regenerate it:**
1. Obtain the vendor's hardware handoff file (.hdf) from the demo package
2. Use Vivado's XSCT: `hsi open_hw_design system.hdf; hsi generate_app -app fsbl`
3. Replace this file with the newly generated binary

## FSBL is silent

The vendor FSBL is a release build with debug output disabled. Expect no
serial output for the first 2-3 seconds after power-on; U-Boot is the first
component that prints to the console.
