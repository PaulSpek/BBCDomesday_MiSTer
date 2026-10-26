# SCSI Master CPU timing regression

Run from the project parent:

```powershell
& '.\core\tools\test_scsi_cpu.ps1'
```

This assembles the unchanged v1.5 diagnostic ROM and runs it on the production
`rtl/AlanD/R65Cx2.vhd` Master CPU with the 48 MHz clock-enable/cycle-stretch
equations copied from `bbc_micro_core.vhd` and `vidproc.vhd`. The adapter runs
at twice that clock rate, matching the 96 MHz top-level integration. RAM is
ideal, media data is an address-dependent byte pattern, IRQ/NMI are inactive,
and MOS character output is replaced with RTS stubs. This is a CPU/peripheral
boundary test; it does not boot a full MOS/VFS system or test MiSTer SD latency.

`LEGACY_STROBE=1` reproduces the hardware report:

```text
CDB index=0 byte=CA CPUwrites=22
CDB index=1 byte=CA CPUwrites=22
CDB index=2 byte=00 CPUwrites=23
CDB index=3 byte=00 CPUwrites=23
CDB index=4 byte=00 CPUwrites=24
CDB index=5 byte=00 CPUwrites=24
REPRODUCED legacy: STEP=01 X=03 FC41=22
```

The same stretched CPU write remains present across two 1 MHz peripheral
enable events. REQ has recovered by the second event, so the target accepts
the byte again. The immediate adjacent 96 MHz edge is normally masked by
the existing REQ gap; merely reducing the width of the old 1 MHz strobe
would not establish one transaction per CPU access.

The fix derives `aiv_scsi_strobe` from `cpu_clken` and qualifies it with
`ce_48` in `BBCMicro.sv`, so the adapter consumes a byte on the CPU's actual
bus-cycle completion. CPU reads sample the current byte before it advances.
The regression checks four initial video-divider phases (0, 1, 7, 15), both
256-byte F-code payloads, all seven reply bytes, the READ6 checksum and total
CPU/target writes. Expected fixed result:

```text
F-CODE ?P: PASS
STEP/END EXP TX/RX: 07/03 00 0100/0100
VALID S/M REPLY: 03 00/00 50 60 41 41 40 40 0D
DONE CPUwrites=290 accepted=290
PASS tb_aiv_scsi_cpu
```

The old integration also shifts the CAPACITY data as sampled by this CPU.
The fixed path returns `00 00 24 00 00 00 01 00` for this model's media size,
including the correct 256-byte block-size field. A ROM reporting CAPACITY
PASS alone only confirms transaction completion, not each returned byte.

The runner checks explicit success markers because ModelSim can return exit
code zero after `$fatal`. Generated `sim/cpu-case-*.log` files preserve traces;
the byte image and simulator artifacts are ignored by Git. numeric_std
startup warnings are suppressed for the CPU's uninitialized reset registers.
Hardware must still confirm the full sequence after loading the new RBF.
