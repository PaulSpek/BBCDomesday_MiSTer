# Cartridge ROM loading

Open **Cartridge ROMs** in the OSD, then choose **Load ROM slot 0**, **1**,
**2** or **3**. All four entries work in **Model B** and **Master** modes.
Files must be plain, exactly 16,384-byte `.rom` images, with no container
header. File indices 5, 6, 7, 8 select slots 0, 1, 2, 3 respectively.

The upload holds the BBC in reset. A complete transfer makes the selected
ROM visible to MOS; an invalid transfer hides it. Loading one slot does not
modify the others. There is no persistent storage in the FPGA: a new RBF
load restores the built-ins. CPU resets and model changes retain loaded
images; the same four ROM images are shared across the two model settings.
Choose ROM software compatible with the selected BBC model.

| Slot | Default | After valid upload |
|---|---|---|
| 0 | Empty | Selected ROM |
| 1 | SCSITEST diagnostic | Selected ROM |
| 2 | Empty | Selected ROM |
| 3 | Model B DFS / Master MMFS, following Filesystem setting | Selected ROM, independent of Filesystem setting |

Loading a cartridge into slot 3 replaces that model's built-in filing-system
ROM at that position. Other built-in slots, including Master VFS in slot 8,
are unchanged. Master private RAM can still mask the first 4 KiB of a selected
sideways ROM when MOS enables that mapping.

The OSD no longer has a Domesday status-LED toggle. The user LED continues
to indicate ROM downloads and existing disk activity.

## Verification

Run `core/tools/test_rom_slots.ps1` from the project parent with ModelSim
installed (or pass `-ModelSim` with its installation directory).

`sim/tb_sideways_rom_slot.sv` verifies the packed single-slot loader, including
replacement after an interrupted upload. `sim/tb_sideways_rom_bank.sv` loads
distinct patterns into all four slots and checks every byte through the
production ROM-data mux in both models, including slot 3 fallback, isolation,
and invalid/oversized uploads. Five bytes per 40-bit memory word reduce the
expected four-slot allocation to 824 MLABs, preserving scarce M10K blocks.

On hardware, use an appropriate service ROM in each slot and inspect the ROM
list/its command after the automatic reset. Repeat with the other model.
Reload the RBF and check that the built-in defaults are restored. Validate
full-core fit and timing as well as this simulation before deployment.
