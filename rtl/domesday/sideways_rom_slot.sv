// Master sideways ROM slot with a 16 KiB MiSTer OSD file-loader input.
// A short, oversized or out-of-order transfer makes the slot invisible to MOS.
module sideways_rom_slot #(
    parameter [7:0] FILE_INDEX = 8'd5,
    parameter INIT_FILE = "roms/empty_sideways.mif",
    parameter DEFAULT_VALID = 1'b0
)(
    input clk,
    input [13:0] read_addr,
    output reg [7:0] read_data,
    output reg valid = DEFAULT_VALID,
    input download,
    input [7:0] file_index,
    input write_enable,
    input [24:0] write_addr,
    input [7:0] write_data,
    output loading
);
    // The base BBC core already consumes most M10Ks. Use distributed MLAB
    // memory for the OSD overlays instead of another 32 M10Ks. The BBC is
    // held in reset throughout a download, so read-during-write data is unused.
    (* ramstyle = "MLAB, no_rw_check", ram_init_file = INIT_FILE *) reg [7:0] memory [0:16383];
    reg was_loading = 1'b0;
    reg [14:0] expected_addr = 15'd0;
    reg bad_transfer = 1'b0;
    assign loading = download && file_index == FILE_INDEX;

    always @(posedge clk) begin
        read_data <= memory[read_addr];
        was_loading <= loading;
        if (loading && !was_loading) begin
            valid <= 1'b0;
            expected_addr <= 15'd0;
            bad_transfer <= 1'b0;
        end
        if (loading && write_enable) begin
            if (write_addr >= 25'd16384 ||
                write_addr != (was_loading ? {10'd0, expected_addr} : 25'd0))
                bad_transfer <= 1'b1;
            else begin
                memory[write_addr[13:0]] <= write_data;
                expected_addr <= (was_loading ? expected_addr : 15'd0) + 1'b1;
            end
        end
        if (!loading && was_loading)
            valid <= !bad_transfer && expected_addr == 15'd16384;
    end
endmodule
