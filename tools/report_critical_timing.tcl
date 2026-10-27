# Read-only timing diagnostics for the latest completed BBCMicro fit.
# Run from the repository root: quartus_sta -t tools/report_critical_timing.tcl
package require ::quartus::project
package require ::quartus::sta
project_open BBCMicro
create_timing_netlist
read_sdc
update_timing_netlist
file mkdir .remote-build
report_timing -setup -npaths 12 -nworst 2 -detail full_path \
    -file .remote-build/critical-setup.rpt
report_clock_fmax_summary -file .remote-build/critical-fmax.rpt
delete_timing_netlist
project_close
