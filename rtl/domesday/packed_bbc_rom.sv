// Space-efficient 256 KiB built-in BBC ROM store.
//
// Cyclone-V M10Ks store 1024 bytes when inferred as an 8-bit memory, wasting
// two of every ten bits.  Five bytes per 40-bit word use the complete block
// and reduce this image from 256 to 205 M10Ks.  Downloads arrive in ascending
// byte order, so writes can be collected without a read/modify/write port.
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
    reg  [15:0] write_group = 16'd0;
    reg   [2:0] write_lane = 3'd0;
    reg         was_writing = 1'b0;

    assign read_data = read_word[{read_lane_q, 3'b000} +: 8];

    always @(posedge clk) begin
        read_word <= memory[read_group];
        read_lane_q <= read_lane;
        was_writing <= write_enable;

        if (write_enable && !was_writing) begin
            write_group <= 16'd0;
            write_lane <= 3'd0;
            upload_prefix <= 32'd0;
        end

        if (write_enable) begin
            // The MiSTer framework transfers the complete core ROM image in
            // ascending order.  Restart cleanly if a new transfer begins.
            if (!was_writing || write_addr == 18'd0) begin
                upload_prefix[7:0] <= write_data;
                write_group <= 16'd0;
                write_lane <= 3'd1;
            end else if (write_addr == 18'd262143) begin
                memory[write_group] <= {8'd0, write_data, upload_prefix[23:0]};
                write_lane <= 3'd0;
            end else if (write_lane == 3'd4) begin
                memory[write_group] <= {write_data, upload_prefix};
                write_group <= write_group + 1'b1;
                write_lane <= 3'd0;
            end else begin
                upload_prefix[{write_lane, 3'b000} +: 8] <= write_data;
                write_lane <= write_lane + 1'b1;
            end
        end
    end
endmodule
