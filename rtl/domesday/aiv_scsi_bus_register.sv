// Snapshot the completed BBC CPU cycle on its 48 MHz bus clock. The engine
// consumes this tuple once at the following ce_48 edge in the 96 MHz domain.
// Reading the adapter still observes the byte preceding its acknowledgement.
module aiv_scsi_bus_register (
    input clk, reset,
    input cs, strobe, rnw,
    input [1:0] addr,
    input [7:0] din,
    output reg cs_q = 0, strobe_q = 0, rnw_q = 1,
    output reg [1:0] addr_q = 0,
    output reg [7:0] din_q = 0
);
    always @(posedge clk) begin
        if (reset) begin
            cs_q <= 0;
            strobe_q <= 0;
            rnw_q <= 1;
            addr_q <= 0;
            din_q <= 0;
        end else begin
            cs_q <= cs;
            strobe_q <= strobe;
            rnw_q <= rnw;
            addr_q <= addr;
            din_q <= din;
        end
    end
endmodule
