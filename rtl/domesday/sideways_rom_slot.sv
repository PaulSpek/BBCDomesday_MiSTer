// Model B / Master sideways ROM slot with a 16 KiB OSD file-loader input.
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
    // Four 8K x 16 slots would need 1024 MLABs, above the device limit.
    // Five bytes per 40-bit word fully use two 20-bit MLAB lanes: each slot
    // needs 206 MLABs, four need 824. No byte enables (they split the RAM).
    // The final word has four bytes plus a zero padding byte.
    (* ramstyle = "MLAB, no_rw_check", ram_init_file = INIT_FILE *) reg [39:0] memory [0:3276];
    reg [31:0] upload_prefix;
    reg [39:0] read_word;
    reg [2:0] read_lane;
    wire [11:0] read_group = read_addr / 14'd5;
    wire [2:0] read_offset = read_addr % 14'd5;
    wire [11:0] write_group = write_addr[13:0] / 14'd5;
    wire [2:0] write_offset = write_addr[13:0] % 14'd5;
    reg was_loading = 1'b0;
    reg [14:0] expected_addr = 15'd0;
    reg bad_transfer = 1'b0;
    assign loading = download && file_index == FILE_INDEX;
    assign read_data = read_word[read_lane * 8 +: 8];

    always @(posedge clk) begin
        read_word <= memory[read_group];
        read_lane <= read_offset;
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
                if (write_addr == 25'd16383)
                    memory[write_group] <= {8'd0, write_data, upload_prefix[23:0]};
                else if (write_offset == 3'd4)
                    memory[write_group] <= {write_data, upload_prefix};
                else
                    upload_prefix[write_offset * 8 +: 8] <= write_data;
                expected_addr <= (was_loading ? expected_addr : 15'd0) + 1'b1;
            end
        end
        if (!loading && was_loading)
            valid <= !bad_transfer && expected_addr == 15'd16384;
    end
endmodule
