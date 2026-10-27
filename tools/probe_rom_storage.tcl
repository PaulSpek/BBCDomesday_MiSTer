# Run on STUDEER from the repository root:
# quartus_sh -t tools/probe_rom_storage.tcl
# No files/settings in the main BBCMicro project are modified.
package require ::quartus::project
package require ::quartus::flow
set repo [pwd]
file mkdir .remote-build/rom-probe
project_new .remote-build/rom-probe/rom_storage_probe -overwrite
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE 5CSEBA6U23I7
set_global_assignment -name TOP_LEVEL_ENTITY rom_storage_probe
set_global_assignment -name NUM_PARALLEL_PROCESSORS 1
set_global_assignment -name SEARCH_PATH $repo
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo rtl/domesday/packed_rom_address.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo rtl/domesday/packed_bbc_rom.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo rtl/domesday/sideways_rom_bank.sv]
set_global_assignment -name SYSTEMVERILOG_FILE [file join $repo sim/rom_storage_probe.sv]
set_global_assignment -name PROJECT_OUTPUT_DIRECTORY output_files
execute_module -tool map
execute_module -tool fit
project_close
