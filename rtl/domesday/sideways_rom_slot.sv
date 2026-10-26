// Master sideways ROM slot with a 16 KiB MiSTer OSD file-loader input.
// A short, oversized or out-of-order transfer makes the slot invisible to MOS.
module sideways_rom_slot #(
    parameter [7:0] FILE_INDEX = 8'd5,
    parameter INIT_FILE = "roms/empty_sideways.mif",
    parameter DEFAULT_VALID = 1'b0
)(
    input clk,
    input [13:0] read_addr,
    output [7:0] read_data,
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
    // Pack byte pairs into a single write. A 16K x 8 array needs 512 separate
    // MLAB banks per slot; 8K x 16 needs 256. Avoid byte write enables here:
    // they can split the memory back into two narrow, inefficient arrays.
    (* ramstyle = "MLAB, no_rw_check", ram_init_file = INIT_FILE *) reg [15:0] memory [0:8191];
    reg [7:0] even_byte;
    reg [15:0] read_word;
    reg read_lane;
    reg was_loading = 1'b0;
    reg [14:0] expected_addr = 15'd0;
    reg bad_transfer = 1'b0;
    assign loading = download && file_index == FILE_INDEX;
    assign read_data = read_lane ? read_word[15:8] : read_word[7:0];

    always @(posedge clk) begin
        read_word <= memory[read_addr[13:1]];
        read_lane <= read_addr[0];
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
                if (write_addr[0])
                    memory[write_addr[13:1]] <= {write_data, even_byte};
                else
                    even_byte <= write_data;
                expected_addr <= (was_loading ? expected_addr : 15'd0) + 1'b1;
            end
        end
        if (!loading && was_loading)
            valid <= !bad_transfer && expected_addr == 15'd16384;
    end
endmodule
