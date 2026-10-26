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

    (* ramstyle = "M10K, no_rw_check", ram_init_file = "roms/rom_packed.mif" *)
    reg [39:0] memory [0:WORDS-1];

    wire [15:0] read_group = read_addr / 18'd5;
    wire  [2:0] read_lane  = read_addr % 18'd5;
    reg  [39:0] read_word = 40'd0;
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

    always @(posedge clk) begin
        read_word <= memory[memory_address];
        read_lane_q <= read_lane;
        if (commit_word) memory[memory_address] <= memory_data;
        if (write_enable && write_lane < 3'd4)
            upload_prefix[{write_lane, 3'b000} +: 8] <= write_data;
    end
endmodule
