# Troubleshooting

This document lists the known issues encountered on the MicroPhase Z7-Nano R20 with
the mainline stack (U-Boot 2026.01, Linux 6.18, Debian 13), together with their causes
and solutions. When debugging an unexplained failure, first capture a full serial
console log at 115200 8N1 from power-on onward; most boot-time problems are visible
there.

```bash
# Host-side capture example
picocom -b 115200 --logfile boot.log /dev/ttyUSB0
```

### FIQ storm when inserting the FPGA Manager module

**Symptom.** Loading a bitstream through the kernel FPGA Manager framework, for
example with `modprobe zynq_fpga_manager` or by writing a firmware name to
`/sys/class/fpga_manager/fpga0/firmware`, floods the console with interrupt messages.
The system becomes unresponsive, the console reports RCU stalls, and a hard reset is
required.

**Cause.** A defect in the interaction between the Zynq FPGA Manager driver and PL
interrupt routing in Linux 6.18: enabling the PL configuration path releases a pending
PL-to-PS interrupt that the kernel cannot acknowledge, producing a fast interrupt
(FIQ) storm.

**Solution.** Do not load PL firmware through the FPGA Manager on this kernel. Program
the PL over JTAG from the host instead, and bring up clocks and level shifters from
Linux with register writes:

```bash
# Host side: program the bitstream over JTAG
openFPGALoader -f path/to/design.bit

# Target side: enable FCLK0, deassert resets, enable level shifters
# (full sequence in FLASH.md, "FPGA loading")
busybox devmem 0xF8000004 32 0x0000DF0D
busybox devmem 0xF8000240 32 0x00000000
busybox devmem 0xF8000170 32 0x0010000A
busybox devmem 0xF8000180 32 0x00000001
busybox devmem 0xF8000900 32 0x0000000F
busybox devmem 0xF8000000 32 0x0000767B
```

### AXI3 versus AXI4-Lite bus protocols

**Symptom.** Accessing a custom PL peripheral from Linux (through `/dev/mem`, a UIO
mapping, or a driver) hangs the CPU, returns `Bus error`, or produces a kernel log
entry such as `Unhandled fault: external abort on non-linefetch`.

**Cause.** The Zynq-7000 PS general-purpose AXI master ports (M_AXI_GP0/GP1) implement
the AXI3 protocol, not AXI4 or AXI4-Lite. AXI3 requires response ID matching and read
termination signals that AXI4-Lite does not have:

- `BID` must be driven with the value presented on `AWID`, and `RID` with the value
  presented on `ARID` (12-bit IDs on the GP ports).
- `RLAST` must be asserted on the final beat of every read response. AXI4-Lite cores,
  which are single-beat by design, typically never drive `RLAST`.

If these signals are left undriven or tied inactive, the PS interconnect waits for a
response that never completes, and the access stalls the AXI transaction indefinitely.

**Solution.** Use one of the following approaches in the PL design:

- Instantiate the Xilinx AXI Protocol Converter between the GP port and the
  AXI4-Lite peripheral.
- Add a small shim in RTL that latches `AWID`/`ARID` and returns them on `BID`/`RID`,
  and asserts `RLAST` on every read beat (valid for single-beat AXI4-Lite slaves).

Simulate the interface with an AXI3 protocol checker before committing to hardware.

### FCLK0 does not start: THR_CNT, not CLK_CTRL bit 0

**Symptom.** After configuring `FPGA0_CLK_CTRL`, FCLK0 still does not toggle; the PL
logic stays unclocked and peripherals are unreachable.

**Cause.** Bit 0 of `FPGA0_CLK_CTRL` is the least significant bit of the source
select field, not a global enable bit. After a power-on reset the FCLK threshold
counter resets to zero, and a zero counter gates the clock output regardless of the
configured source and divisor.

**Solution.** Program the threshold counter after configuring the clock control
register:

```bash
busybox devmem 0xF8000004 32 0x0000DF0D      # SLCR unlock
busybox devmem 0xF8000170 32 0x0010000A      # FCLK0 = IO PLL / 10 = 100 MHz
busybox devmem 0xF8000180 32 0x00000001      # FPGA0_THR_CNT: starts the clock
busybox devmem 0xF8000000 32 0x0000767B      # SLCR lock
```

The same requirement applies to FCLK1 through FCLK3 using their respective THR_CNT
registers at offsets 0x188, 0x190, and 0x198.

### LVL_SHFTR_EN must be set after JTAG programming

**Symptom.** A design programmed over JTAG appears loaded (DONE is high) but all
PS-to-PL accesses fail, or PL-to-PS interrupts and DDR data arrive corrupted.

**Cause.** The PL is powered and configured after JTAG programming, but the level
shifters that connect the PL domain to the PS domain remain disabled. When the FSBL
loads a bitstream as part of BOOT.BIN it enables them automatically; a JTAG
programming path never executes that step.

**Solution.** After every JTAG programming cycle, enable the level shifters from
Linux:

```bash
busybox devmem 0xF8000004 32 0x0000DF0D   # SLCR unlock
busybox devmem 0xF8000900 32 0x0000000F   # LVL_SHFTR_EN: all four shifters
busybox devmem 0xF8000000 32 0x0000767B   # SLCR lock
```

### Python os.pread cannot access registers above 0x7FFFFFFF

**Symptom.** A helper script that reads peripheral registers through
`os.pread(fd, size, offset)` on `/dev/mem` raises `OverflowError` or `OSError`
(EINVAL/EOVERFLOW) for addresses such as `0xE0000000` (UART) or `0xF8000000` (SLCR),
while lower addresses work.

**Cause.** On 32-bit Python builds (armhf userland, or a host Python compiled with a
32-bit `off_t`), the offset parameter of `os.pread` is a signed 32-bit value. Physical
addresses with bit 31 set cannot be represented, and the call fails before any
transfer happens.

**Solution.** Use the `devmem` utility for register access at high addresses. On the
Debian root filesystem it is provided by busybox:

```bash
apt install -y busybox
busybox devmem 0xF8000900       # read LVL_SHFTR_EN
busybox devmem 0xF8000900 32 0x0000000F   # write it
```

If Python access is required, prefer `mmap` over `os.pread` and map the offset into
the region base rather than passing the absolute address.

### SD card is detected but the board does not boot

**Symptom.** The card is valid (it boots on another board, or was flashed from a
verified image), but the Z7-Nano shows no boot activity at all: the serial console
stays silent and the board may fall into an idle state.

**Cause.** The boot-mode strap pins (MIO[5:3], selected by the on-board jumper) are
sampled at power-on reset. If the jumper is in the JTAG or QSPI position, the boot ROM
never reads the SD card. A warm reset after moving the jumper is not sufficient if the
strap was latched incorrectly.

**Solution.**

1. Verify the boot-mode jumper is in the SD position according to the board
   silkscreen.
2. Power the board off completely, wait a few seconds, and power it on again; the
   straps are only sampled at power-on reset.
3. Confirm the card image was written to the whole device (`/dev/sdX`), not to a
   partition, and that `BOOT.BIN` is present in the FAT32 partition.

### Serial console is silent right after power-on

**Symptom.** After power-on, the serial console shows nothing for roughly ten seconds.
The board is working normally otherwise, and U-Boot output begins after the pause.

**Cause.** Expected behavior. The FSBL executes during the first seconds after reset
and produces no console output by design; it initializes the DDR memory and loads
U-Boot silently. The first console output appears when U-Boot starts.

**Solution.** None required. Open the terminal before applying power so early U-Boot
messages are not missed, and confirm the settings are 115200 baud, 8N1, with no flow
control. If nothing appears within 30 seconds of power-on, treat it as a genuine boot
failure and check the boot-mode jumper and card contents.

### Network interface is named end0 instead of eth0

**Symptom.** Configuration written for `eth0` (for example `/etc/network/interfaces`
or firewall rules) does not apply, and `ip link` shows the Ethernet device as `end0`.

**Cause.** Newer kernels combined with systemd predictable network interface naming
assign the interface a driver-derived name. The Zynq GEM is a platform device with no
onboard, slot, or path name available, so udev falls back to the driver-based scheme
and produces `end0`.

**Solution.** Use `end0` in configurations:

```bash
ip link set end0 up
```

Alternatively, restore the traditional kernel name in either of two ways:

```bash
# Option 1: kernel command line (append to bootargs in the U-Boot environment)
net.ifnames=0

# Option 2: a systemd .link file forcing the kernel name
cat > /etc/systemd/network/10-eth0.link <<'EOF'
[Match]
Driver=macb

[Link]
NamePolicy=kernel
Name=eth0
EOF
```

Reboot after changing either setting.
