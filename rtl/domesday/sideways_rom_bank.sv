// Two shared OSD ROM images, available in slots 0 and 1 in either BBC model.
//
// Both slots share a single-port M10K store. Each image occupies 3277 40-bit
// words. Slots 2 and 3 retain their normal empty/built-in routing and consume
// no upload storage. Reads share the upload port while the CPU is in reset.
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
    localparam integer WORDS_PER_SLOT = 3277;
    localparam integer TOTAL_WORDS = 2 * WORDS_PER_SLOT;

`ifdef DOMESDAY_BEHAVIORAL_ROM
    (* ramstyle = "M10K, no_rw_check", ram_init_file = "roms/cartridge_roms_packed.mif" *)
    reg [39:0] memory [0:TOTAL_WORDS-1];
`endif

    reg [1:0] valid_slots = 2'b10; // diagnostic ROM powers up in slot 1
    wire selected = file_index >= 8'd5 && file_index <= 8'd6;
    wire load_slot = file_index[0] - 1'b1;
    assign loading = download && selected;
    assign valid = !read_slot[1] && valid_slots[read_slot[0]];

    wire [11:0] read_local_group;
    wire  [2:0] read_lane;
    packed_rom_address #(.WIDTH(14)) read_address (
        .clk(clk), .address(read_addr), .word_address(read_local_group), .byte_lane(read_lane)
    );
    reg [12:0] slot_base_q = 0, slot_base_qq = 0;
    always @(posedge clk) begin
        case (read_slot)
            0: slot_base_q <= 0;
            1: slot_base_q <= WORDS_PER_SLOT;
            default: slot_base_q <= 0;
        endcase
        slot_base_qq <= slot_base_q;
    end
    wire [12:0] read_group = slot_base_qq + read_local_group;
`ifndef DOMESDAY_BEHAVIORAL_ROM
    wire [39:0] read_word;
`else
    reg  [39:0] read_word = 40'd0;
`endif
    reg   [2:0] read_lane_q = 3'd0;
    assign read_data = read_word[{read_lane_q, 3'b000} +: 8];

    reg        was_loading = 1'b0;
    reg        active_slot = 1'b0;
    reg [14:0] expected_addr = 15'd0;
    reg        bad_transfer = 1'b0;
    reg [31:0] upload_prefix = 32'd0;
    reg [12:0] write_group = 13'd0;
    reg  [2:0] write_lane = 3'd0;
    wire valid_byte = loading && write_enable &&
        !(was_loading && load_slot != active_slot) && write_addr < 25'd16384 &&
        write_addr == (was_loading ? {10'd0, expected_addr} : 25'd0);
    wire tail = write_addr == 25'd16383;
    wire commit_word = valid_byte && was_loading && write_addr != 0 &&
        (tail || write_lane == 3'd4);
    wire [13:0] memory_address = commit_word ? write_group : read_group;
    wire [39:0] memory_data = tail ? {8'd0, write_data, upload_prefix[23:0]} :
                                                   {write_data, upload_prefix};

`ifndef DOMESDAY_BEHAVIORAL_ROM
    altsyncram memory (
        .clock0(clk), .address_a(memory_address), .data_a(memory_data),
        .wren_a(commit_word), .q_a(read_word), .rden_a(1'b1),
        .clocken0(1'b1), .clocken2(1'b1), .aclr0(1'b0),
        .addressstall_a(1'b0), .byteena_a(1'b1),
        .clock1(), .clocken1(1'b1), .clocken3(1'b1), .aclr1(1'b0),
        .wren_b(1'b0), .rden_b(1'b0), .data_b(1'b0), .address_b(1'b0),
        .addressstall_b(1'b0), .byteena_b(1'b1), .q_b(), .eccstatus()
    );
    defparam memory.operation_mode = "SINGLE_PORT",
        memory.width_a = 40, memory.widthad_a = 14, memory.numwords_a = TOTAL_WORDS,
        memory.outdata_reg_a = "UNREGISTERED",
        memory.ram_block_type = "M10K",
        memory.maximum_depth = 256,
        memory.intended_device_family = "Cyclone V",
        memory.init_file = "roms/cartridge_roms_packed.mif",
        memory.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
        memory.width_byteena_a = 1,
        memory.lpm_type = "altsyncram";
`else
    always @(posedge clk) begin
        read_word <= memory[memory_address];
        if (commit_word) memory[memory_address] <= memory_data;
    end
`endif
    always @(posedge clk) begin
        read_lane_q <= read_lane;
        was_loading <= loading;

        if (loading && !was_loading) begin
            active_slot <= load_slot;
            valid_slots[load_slot] <= 1'b0;
            expected_addr <= 15'd0;
            bad_transfer <= 1'b0;
            upload_prefix <= 32'd0;
            write_group <= load_slot * WORDS_PER_SLOT;
            write_lane <= 3'd0;
        end

        if (loading && write_enable) begin
            if ((was_loading && load_slot != active_slot) || write_addr >= 25'd16384 ||
                write_addr != (was_loading ? {10'd0, expected_addr} : 25'd0)) begin
                bad_transfer <= 1'b1;
            end else begin
                if (!was_loading || write_addr == 25'd0) begin
                    upload_prefix[7:0] <= write_data;
                    write_lane <= 3'd1;
                end else if (write_addr == 25'd16383) begin
                    write_lane <= 3'd0;
                end else if (write_lane == 3'd4) begin
                    write_group <= write_group + 1'b1;
                    write_lane <= 3'd0;
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
