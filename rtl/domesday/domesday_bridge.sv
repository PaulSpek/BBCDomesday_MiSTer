// Domesday integration boundary.
//
// Phase 1 owns virtual disk slot 3 and records LaserDisc mount metadata. It
// intentionally performs no SD reads yet, keeping the proven BBC Master path
// unchanged while establishing stable ports for the DLV streamer/player.

module domesday_bridge
(
	input             clk,
	input             img_mounted,
	input      [63:0] img_size,

	output reg        disc_present = 1'b0,
	output reg [63:0] disc_size    = 64'd0,

	output     [31:0] sd_lba,
	output      [5:0] sd_blk_cnt,
	output            sd_rd,
	output            sd_wr,
	input             sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,
	output      [7:0] sd_buff_din
);

always @(posedge clk) begin
	if (img_mounted) begin
		disc_present <= |img_size;
		disc_size    <= img_size;
	end
end

// Reserved for the Picmatic DLV streamer. Keeping the slot idle makes this
// phase safe to enable on hardware before decoder and player integration.
assign sd_lba      = 32'd0;
assign sd_blk_cnt  = 6'd0;
assign sd_rd       = 1'b0;
assign sd_wr       = 1'b0;
assign sd_buff_din = 8'd0;

// Keep interface inputs explicit so the intended ownership is documented.
wire _unused = &{1'b0, sd_ack, sd_buff_addr, sd_buff_dout, sd_buff_wr};

endmodule
