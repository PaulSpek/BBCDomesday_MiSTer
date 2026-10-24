// Domesday PVF mounted-media boundary.
//
// Owns MiSTer virtual disk slot 3, reads sector zero after a mount event and
// validates the fixed 64-byte PVF1 header used by Pi1MHz. Video records are
// deliberately not streamed yet; this stage proves that real PVF media can be
// selected and read through the stock MiSTer hps_io block interface.

module domesday_bridge
(
	input             clk,
	input             img_mounted,
	input      [63:0] img_size,

	output reg        disc_present = 1'b0,
	output reg [63:0] disc_size    = 64'd0,
	output reg        pvf_valid    = 1'b0,
	output reg        pvf_error    = 1'b0,
	output reg [31:0] pvf_width    = 32'd0,
	output reg [31:0] pvf_height   = 32'd0,
	output reg [31:0] pvf_frames   = 32'd0,
	output reg [31:0] pvf_fps_num  = 32'd0,
	output reg [31:0] pvf_fps_den  = 32'd0,
	output reg [31:0] pvf_audio_hz = 32'd0,

	output reg [31:0] sd_lba       = 32'd0,
	output      [5:0] sd_blk_cnt,
	output reg        sd_rd        = 1'b0,
	output            sd_wr,
	input             sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input             sd_buff_wr,
	output      [7:0] sd_buff_din
);

localparam [2:0] ST_NO_MEDIA = 3'd0;
localparam [2:0] ST_WAIT_BUS = 3'd1;
localparam [2:0] ST_READ_REQ = 3'd2;
localparam [2:0] ST_READ_DATA = 3'd3;
localparam [2:0] ST_VALIDATE = 3'd4;
localparam [2:0] ST_READY = 3'd5;

localparam [31:0] PVF_MAGIC = 32'h31465650; // little-endian "PVF1"
localparam [31:0] PVF_VERSION = 32'd1;

reg [2:0] state = ST_NO_MEDIA;
reg [31:0] header_words [0:15];
integer i;

wire [3:0] header_word = sd_buff_addr[5:2];
wire [31:0] expected_data_offset = 32'd64 + (header_words[6] << 2);
wire header_sane =
	header_words[0] == PVF_MAGIC &&
	header_words[1] == PVF_VERSION &&
	header_words[2] != 32'd0 &&
	header_words[3] != 32'd0 &&
	header_words[4] != 32'd0 &&
	header_words[5] != 32'd0 &&
	header_words[6] != 32'd0 &&
	header_words[10] == 32'd64 &&
	header_words[11] == expected_data_offset &&
	header_words[11] < disc_size &&
	header_words[12] != 32'd0;

assign sd_blk_cnt  = 6'd0; // one 512-byte sector
assign sd_wr       = 1'b0;
assign sd_buff_din = 8'd0;

always @(posedge clk) begin
	// MiSTer pulses img_mounted both when mounting and unmounting. A zero size
	// means no media. A fresh mount always invalidates the previous header.
	if (img_mounted) begin
		disc_present <= |img_size;
		disc_size    <= img_size;
		pvf_valid    <= 1'b0;
		pvf_error    <= 1'b0;
		pvf_width    <= 32'd0;
		pvf_height   <= 32'd0;
		pvf_frames   <= 32'd0;
		pvf_fps_num  <= 32'd0;
		pvf_fps_den  <= 32'd0;
		pvf_audio_hz <= 32'd0;
		sd_rd        <= 1'b0;
		sd_lba       <= 32'd0;
		for (i = 0; i < 16; i = i + 1) header_words[i] <= 32'd0;
		state <= (|img_size) ? ST_WAIT_BUS : ST_NO_MEDIA;
	end else begin
		case (state)
		ST_NO_MEDIA: begin
			sd_rd <= 1'b0;
		end

		// Do not mistake the tail of an earlier slot transaction for our header.
		ST_WAIT_BUS: begin
			sd_rd <= 1'b0;
			if (!sd_ack) state <= ST_READ_REQ;
		end

		ST_READ_REQ: begin
			sd_lba <= 32'd0;
			sd_rd  <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				state <= ST_READ_DATA;
			end
		end

		ST_READ_DATA: begin
			sd_rd <= 1'b0;
			if (sd_buff_wr && sd_buff_addr < 9'd64) begin
				case (sd_buff_addr[1:0])
				2'd0: header_words[header_word][7:0]   <= sd_buff_dout;
				2'd1: header_words[header_word][15:8]  <= sd_buff_dout;
				2'd2: header_words[header_word][23:16] <= sd_buff_dout;
				2'd3: header_words[header_word][31:24] <= sd_buff_dout;
				endcase
			end
			if (!sd_ack) state <= ST_VALIDATE;
		end

		ST_VALIDATE: begin
			pvf_valid    <= header_sane;
			pvf_error    <= !header_sane;
			pvf_width    <= header_words[2];
			pvf_height   <= header_words[3];
			pvf_fps_num  <= header_words[4];
			pvf_fps_den  <= header_words[5];
			pvf_frames   <= header_words[6];
			pvf_audio_hz <= header_words[7];
			state         <= ST_READY;
		end

		ST_READY: begin
			sd_rd <= 1'b0;
		end

		default: state <= ST_NO_MEDIA;
		endcase
	end
end

endmodule
