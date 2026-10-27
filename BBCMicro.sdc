derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
set_multicycle_path -to {emu|BBCMicro|*} -setup 2
set_multicycle_path -to {emu|BBCMicro|*} -hold 1

# These boundary registers use the same 48 MHz clock as the BBC. Like the
# BBC registers above, they capture once per TWO 96 MHz parent cycles. Keep
# the exception restricted to that bank; the SCSI engine remains at 96 MHz.
set_multicycle_path -to {emu|scsi_bus|*} -setup 2
set_multicycle_path -to {emu|scsi_bus|*} -hold 1

set_multicycle_path -to {emu|mixer|*} -setup 2
set_multicycle_path -to {emu|mixer|*} -hold 1
