// Space-efficient 256 KiB built-in BBC ROM store.
//
// Single-port M10K mode supports 256 x 40 bits. Five bytes per word need
// 205 blocks. The CPU is held in reset during uploads, so reads and writes
// share one address port. Separate read/write addresses force dual-port mode
// and lose the 40-bit geometry. Upload strobes may have arbitrary gaps.
module packed_bbc_rom
(
    input             clk,
    input      [17:0] read_addr,
    output     [7:0]  read_data,
    input             write_enable,
    input      [17:0] write_addr,
    input      [7:0]  write_data
);
    localparam integer WORDS = 52429; // ceil(256 KiB / 5)

`ifdef DOMESDAY_BEHAVIORAL_ROM
    (* ramstyle = "M10K, no_rw_check", ram_init_file = "roms/rom_packed.mif" *)
    reg [39:0] memory [0:WORDS-1];
`endif

    wire [15:0] read_group = read_addr / 18'd5;
    wire  [2:0] read_lane  = read_addr % 18'd5;
`ifndef DOMESDAY_BEHAVIORAL_ROM
    wire [39:0] read_word;
`else
    reg  [39:0] read_word = 40'd0;
`endif
    reg   [2:0] read_lane_q = 3'd0;

    reg  [31:0] upload_prefix = 32'd0;
    wire [15:0] write_group = write_addr / 18'd5;
    wire [2:0] write_lane = write_addr % 18'd5;
    wire tail = write_addr == 18'd262143;
    wire commit_word = write_enable && (write_lane == 3'd4 || tail);
    wire [15:0] memory_address = commit_word ? write_group : read_group;
    wire [39:0] memory_data = tail ? {8'd0, write_data, upload_prefix[23:0]} :
                                                   {write_data, upload_prefix};

    assign read_data = read_word[{read_lane_q, 3'b000} +: 8];

`ifndef DOMESDAY_BEHAVIORAL_ROM
    // Quartus 17 keeps inferred arrays in DUAL_PORT even with a shared
    // address. Force the physical mode so the 40-bit M10K geometry is used.
    altsyncram memory (
        .clock0(clk), .address_a(memory_address), .data_a(memory_data),
        .wren_a(commit_word), .q_a(read_word), .rden_a(1'b1),
        .clocken0(1'b1), .clocken2(1'b1), .aclr0(1'b0),
        .addressstall_a(1'b0), .byteena_a(1'b1),
        .clock1(1'b0), .clocken1(1'b1), .clocken3(1'b1), .aclr1(1'b0),
        .wren_b(1'b0), .rden_b(1'b0), .data_b(1'b0), .address_b(1'b0),
        .addressstall_b(1'b0), .byteena_b(1'b1), .q_b(), .eccstatus()
    );
    defparam memory.operation_mode = "SINGLE_PORT",
        memory.width_a = 40, memory.widthad_a = 16, memory.numwords_a = WORDS,
        memory.outdata_reg_a = "UNREGISTERED",
        memory.ram_block_type = "M10K",
        memory.intended_device_family = "Cyclone V",
        memory.init_file = "roms/rom_packed.mif",
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
        if (write_enable && write_lane < 3'd4)
            upload_prefix[{write_lane, 3'b000} +: 8] <= write_data;
    end
endmodule
