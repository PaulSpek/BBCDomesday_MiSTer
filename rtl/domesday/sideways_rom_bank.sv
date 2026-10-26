// Four shared OSD ROM images, available in slots 0..3 in either BBC model.
//
// All slots share one M10K-backed store. Each 16 KiB image occupies 4096
// 32-bit words, keeping slot
// uploads independent while using every bit of the physical RAM blocks.
module sideways_rom_bank (
    input clk,
    input [1:0] read_slot,
    input [13:0] read_addr,
    output [7:0] read_data,
    output valid,
    input download,
    input [7:0] file_index,
    input write_enable,
    input [24:0] write_addr,
    input [7:0] write_data,
    output loading
);
    localparam integer WORDS_PER_SLOT = 4096;
    localparam integer TOTAL_WORDS = 4 * WORDS_PER_SLOT;

    (* ramstyle = "M10K, no_rw_check", ram_init_file = "roms/cartridge_roms_packed.mif" *)
    reg [31:0] memory [0:TOTAL_WORDS-1];

    reg [3:0] valid_slots = 4'b0010; // diagnostic ROM powers up in slot 1
    wire selected = file_index >= 8'd5 && file_index <= 8'd8;
    wire [1:0] load_slot = file_index[1:0] - 2'd1;
    assign loading = download && selected;
    assign valid = valid_slots[read_slot];

    wire [11:0] read_local_group = read_addr[13:2];
    wire  [1:0] read_lane = read_addr[1:0];
    wire [13:0] read_group = read_slot * WORDS_PER_SLOT + read_local_group;
    reg  [31:0] read_word = 32'd0;
    reg   [1:0] read_lane_q = 2'd0;
    assign read_data = read_word[{read_lane_q, 3'b000} +: 8];

    reg        was_loading = 1'b0;
    reg [1:0]  active_slot = 2'd0;
    reg [14:0] expected_addr = 15'd0;
    reg        bad_transfer = 1'b0;
    reg [31:0] upload_prefix = 32'd0;
    reg [13:0] write_group = 14'd0;
    reg  [1:0] write_lane = 2'd0;

    always @(posedge clk) begin
        read_word <= memory[read_group];
        read_lane_q <= read_lane;
        was_loading <= loading;

        if (loading && !was_loading) begin
            active_slot <= load_slot;
            valid_slots[load_slot] <= 1'b0;
            expected_addr <= 15'd0;
            bad_transfer <= 1'b0;
            upload_prefix <= 32'd0;
            write_group <= load_slot * WORDS_PER_SLOT;
            write_lane <= 2'd0;
        end

        if (loading && write_enable) begin
            if ((was_loading && load_slot != active_slot) || write_addr >= 25'd16384 ||
                write_addr != (was_loading ? {10'd0, expected_addr} : 25'd0)) begin
                bad_transfer <= 1'b1;
            end else begin
                if (!was_loading || write_addr == 25'd0) begin
                    upload_prefix[7:0] <= write_data;
                    write_lane <= 2'd1;
                end else if (write_addr == 25'd16383) begin
                    memory[write_group] <= {write_data, upload_prefix[23:0]};
                    write_lane <= 2'd0;
                end else if (write_lane == 2'd3) begin
                    memory[write_group] <= {write_data, upload_prefix[23:0]};
                    write_group <= write_group + 1'b1;
                    write_lane <= 2'd0;
                end else begin
                    upload_prefix[{write_lane, 3'b000} +: 8] <= write_data;
                    write_lane <= write_lane + 1'b1;
                end
                expected_addr <= (was_loading ? expected_addr : 15'd0) + 1'b1;
            end
        end

        if (!loading && was_loading)
            valid_slots[active_slot] <= !bad_transfer && expected_addr == 15'd16384;
    end
endmodule

// Built-in ROM routing, plus model-independent overlays in cartridge 0..3.
// Slot 4 here denotes the MOS physical ROM bank, not sideways RAM slot 4.
module sideways_rom_mux (
    input master,
    input [3:0] slot,
    input dfs, mmfs,
    input [7:0] builtin_data, cartridge_data,
    input cartridge_valid,
    output reg [7:0] data
);
    always @* begin
        data = 8'h00;
        case ({master, slot})
            5'b0_0000, 5'b0_0001, 5'b0_0010,
            5'b1_0000, 5'b1_0001, 5'b1_0010:
                data = cartridge_valid ? cartridge_data : 8'h00;
            5'b0_0011: data = cartridge_valid ? cartridge_data : (dfs ? builtin_data : 8'h00);
            5'b1_0011: data = cartridge_valid ? cartridge_data : (mmfs ? builtin_data : 8'h00);
            5'b0_1000: data = mmfs ? builtin_data : 8'h00;
            5'b1_1001: data = dfs ? builtin_data : 8'h00;
            5'b0_0100, 5'b0_1110, 5'b0_1111,
            5'b1_0100, 5'b1_1000, 5'b1_1010, 5'b1_1011,
            5'b1_1100, 5'b1_1101, 5'b1_1110, 5'b1_1111:
                data = builtin_data;
            default: data = 8'h00;
        endcase
    end
endmodule
