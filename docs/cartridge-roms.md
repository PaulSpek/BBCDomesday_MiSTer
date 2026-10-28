# Sideways ROM loading

Open **Sideways ROMs** in the OSD, then choose **Load ROM slot 0** or **1**.
Both entries work in **Model B** and **Master** modes.
Files must be plain, exactly 16,384-byte `.rom` images, with no container
header. File indices 5 and 6 select slots 0 and 1 respectively.

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
| 2 | Empty | Not loadable |
| 3 | Model B DFS / Master MMFS, following Filesystem setting | Not loadable |

The two-image store uses 26 M10Ks instead of the former four-image store's
52. This allows writable sideways-RAM bank 7 to be present again alongside
banks 4–6. Master VFS in slot 8 and all other built-in ROMs are unchanged.
Master private RAM can still mask the first 4 KiB of a selected sideways ROM
when MOS enables that mapping.

The OSD no longer has a Domesday status-LED toggle. The user LED continues
to indicate ROM downloads and existing disk activity.

## Verification

Run `core/tools/test_rom_slots.ps1` from the project parent with ModelSim
installed (or pass `-ModelSim` with its installation directory).

`sim/tb_sideways_rom_slot.sv` verifies the legacy packed single-slot loader.
`sim/tb_sideways_rom_bank.sv` loads distinct patterns into slots 0 and 1 and
checks every byte through the production ROM-data mux in both models. It also
checks slot 2 remains empty, slot 3 retains its built-in fallback, removed file
indices are rejected, and invalid/oversized uploads are rejected. The packed
two-slot store occupies 26 M10Ks.

On hardware, use an appropriate service ROM in each slot and inspect the ROM
list/its command after the automatic reset. Repeat with the other model.
Reload the RBF and check that the built-in defaults are restored. Validate
full-core fit and timing as well as this simulation before deployment.
