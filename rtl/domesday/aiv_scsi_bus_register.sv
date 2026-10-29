// Snapshot the completed BBC CPU cycle using the 96 MHz parent clock and
// its 48 MHz enable. Capture before the delayed gated BBC clock advances
// the CPU; the engine consumes this tuple at the following enabled edge.
// Reading the adapter still observes the byte preceding its acknowledgement.
module aiv_scsi_bus_register (
    input clk, reset, enable,
    input cs, strobe, rnw,
    input [1:0] addr,
    input [7:0] din,
    output reg cs_q = 0, strobe_q = 0, fire_q = 0, rnw_q = 1,
    output reg [1:0] addr_q = 0,
    output reg [7:0] din_q = 0
);
    always @(posedge clk) begin
        if (reset) begin
            cs_q <= 0;
            strobe_q <= 0;
            fire_q <= 0;
            rnw_q <= 1;
            addr_q <= 0;
            din_q <= 0;
        end else if (enable) begin
            cs_q <= cs;
            strobe_q <= strobe;
            // Present the newly captured tuple to the adapter on the next
            // parent-clock edge.  This avoids feeding the negedge-generated
            // 48 MHz enable through the adapter's command/data logic while
            // retaining one acknowledgement for each completed BBC cycle.
            fire_q <= strobe;
            rnw_q <= rnw;
            addr_q <= addr;
            din_q <= din;
        end else begin
            fire_q <= 0;
        end
    end
endmodule
