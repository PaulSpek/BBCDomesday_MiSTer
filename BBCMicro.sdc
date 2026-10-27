derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
set_multicycle_path -to {emu|BBCMicro|*} -setup 2
set_multicycle_path -to {emu|BBCMicro|*} -hold 1

# These parent-clock boundary registers capture only when ce_48 is high.
# Like the BBC registers above, they capture once per TWO parent cycles. Keep
# the exception restricted to that bank; the SCSI engine remains at 96 MHz.
set_multicycle_path -to {emu|scsi_bus|*} -setup 2
set_multicycle_path -to {emu|scsi_bus|*} -hold 1

set_multicycle_path -to {emu|mixer|*} -setup 2
set_multicycle_path -to {emu|mixer|*} -hold 1
