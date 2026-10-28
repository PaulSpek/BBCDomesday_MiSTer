derive_pll_clocks
derive_clock_uncertainty

# core specific constraints
set_multicycle_path -to {emu|BBCMicro|*} -setup 2
set_multicycle_path -to {emu|BBCMicro|*} -hold 1

# ext_A is launched by the delayed/gated 48 MHz BBC clock. The inferred
# 96 MHz RAM may capture it on either of the two parent-clock edges before
# the next BBC edge consumes ext_Dout. The first edge has only about 5 ns
# after clock-tree skew; the second is the functional deadline. Restrict this
# exception to the three external BBC RAM arrays and preserve the normal
# one-cycle hold relationship. ROM, SCSI and video paths are not relaxed.
set_multicycle_path -from {emu|BBCMicro|ext_A*} \
                    -to {emu|external_ram|tube_ram_rtl_0|* emu|external_ram|sideways_ram_rtl_0|* emu|external_ram|host_ram_rtl_0|*} -setup 2
set_multicycle_path -from {emu|BBCMicro|ext_A*} \
                    -to {emu|external_ram|tube_ram_rtl_0|* emu|external_ram|sideways_ram_rtl_0|* emu|external_ram|host_ram_rtl_0|*} -hold 1

# These parent-clock boundary registers capture only when ce_48 is high.
# Like the BBC registers above, they capture once per TWO parent cycles. Keep
# the exception restricted to that bank; the SCSI engine remains at 96 MHz.
set_multicycle_path -to {emu|scsi_bus|*} -setup 2
set_multicycle_path -to {emu|scsi_bus|*} -hold 1

set_multicycle_path -to {emu|mixer|*} -setup 2
set_multicycle_path -to {emu|mixer|*} -hold 1
