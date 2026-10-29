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
	output reg        ddv_valid    = 1'b0,
	output reg        ddv_error    = 1'b0,
	// Metadata for DDV frame zero. This is deliberately a small, verified
	// fetch before the JPEG/PCM DMA stage is introduced.
	output reg        ddv_index_valid = 1'b0,
	output reg        ddv_index_error = 1'b0,
	output reg [63:0] ddv_frame_offset = 64'd0,
	output reg [31:0] ddv_frame_length = 32'd0,
	output reg [31:0] ddv_frame_number = 32'd0,
	output reg [31:0] pvf_width    = 32'd0,
	output reg [31:0] pvf_height   = 32'd0,
	output reg [31:0] pvf_frames   = 32'd0,
	output reg [31:0] pvf_fps_num  = 32'd0,
	output reg [31:0] pvf_fps_den  = 32'd0,
	output reg [31:0] pvf_audio_hz = 32'd0,

	// Baseline-JPEG byte stream from DDV frame zero.  The downstream decoder
	// supplies backpressure, so the SD sector cache never has to hold a whole
	// compressed frame.
	output reg  [7:0] jpeg_byte    = 8'd0,
	output reg        jpeg_valid   = 1'b0,
	input             jpeg_ready,
	output reg        jpeg_last    = 1'b0,
	output            jpeg_reset,
	// Random-access request from the VP415 player.  Valid remains asserted
	// until ack; a picture number is converted to this zero-based DDV index
	// by the player, not guessed by the media layer.
	input             frame_request,
	input      [31:0] frame_request_index,
	output reg        frame_request_ack = 1'b0,
	output reg        jpeg_streaming = 1'b0,
	output reg        jpeg_stream_done = 1'b0,
	output reg        jpeg_stream_error = 1'b0,

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

localparam [4:0] ST_NO_MEDIA = 5'd0;
localparam [4:0] ST_WAIT_BUS = 5'd1;
localparam [4:0] ST_READ_REQ = 5'd2;
localparam [4:0] ST_READ_DATA = 5'd3;
localparam [4:0] ST_VALIDATE = 5'd4;
localparam [4:0] ST_INDEX_WAIT = 5'd5;
localparam [4:0] ST_INDEX_REQ = 5'd6;
localparam [4:0] ST_INDEX_DATA = 5'd7;
localparam [4:0] ST_INDEX_VALIDATE = 5'd8;
localparam [4:0] ST_READY = 5'd9;
localparam [4:0] ST_FRAME_WAIT = 5'd10;
localparam [4:0] ST_FRAME_REQ = 5'd11;
localparam [4:0] ST_FRAME_DATA = 5'd12;
localparam [4:0] ST_STREAM_PRIME = 5'd13;
localparam [4:0] ST_STREAM_BYTE = 5'd14;

localparam [31:0] PVF_MAGIC = 32'h31465650; // little-endian "PVF1"
localparam [31:0] PVF_VERSION = 32'd1;
localparam [31:0] DDV_MAGIC = 32'h31564444; // little-endian "DDV1"
localparam [31:0] DDV_VERSION = 32'd1;

reg [4:0] state = ST_NO_MEDIA;
reg [31:0] header_words [0:127];
reg [31:0] index_words [0:3];
(* ramstyle = "MLAB, no_rw_check" *) reg [7:0] frame_sector [0:511];
reg [31:0] frame_lba = 32'd0;
reg  [8:0] frame_skip = 9'd0;
reg        frame_first = 1'b0;
reg  [8:0] stream_pos = 9'd0;
reg [31:0] bytes_remaining = 32'd0;
reg [31:0] requested_frame = 32'd0;
reg        decoder_reset = 1'b1;
integer i;

assign jpeg_reset = decoder_reset;

wire [6:0] header_word = sd_buff_addr[8:2];
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

// DDV1 is the high-quality, JPEG/PCM playback cache made by
// tools/pvf/pvf_to_ddv.py. Its 64-bit index fields intentionally exceed the
// 4 GiB limit of arcade DLV files.  This bridge validates the media boundary;
// JPEG and PCM streaming are the next RTL stage.
wire [63:0] ddv_index_offset = {header_words[10], header_words[9]};
wire [63:0] ddv_index_size   = {header_words[12], header_words[11]};
wire [63:0] ddv_video_offset = {header_words[14], header_words[13]};
wire [63:0] ddv_video_size   = {header_words[16], header_words[15]};
wire [63:0] ddv_audio_offset = {header_words[18], header_words[17]};
wire [63:0] ddv_audio_size   = {header_words[20], header_words[19]};
wire [63:0] ddv_expected_index_size = ({32'd0, header_words[6]} << 4);
wire ddv_header_sane =
	header_words[0] == DDV_MAGIC &&
	header_words[1] == DDV_VERSION &&
	header_words[2] != 32'd0 &&
	header_words[3] != 32'd0 &&
	header_words[4] != 32'd0 &&
	header_words[5] != 32'd0 &&
	header_words[6] != 32'd0 &&
	header_words[7] == 32'd48000 &&
	header_words[8] == 32'd2 &&
	ddv_index_offset == 64'd512 &&
	ddv_index_size == ddv_expected_index_size &&
	ddv_video_offset >= (ddv_index_offset + ddv_index_size) &&
	ddv_video_size != 64'd0 &&
	ddv_audio_offset >= (ddv_video_offset + ddv_video_size) &&
	ddv_audio_size != 64'd0 &&
	header_words[22] == 32'd1920 &&
	header_words[23] == 32'd3 &&
	ddv_audio_offset < disc_size;

// DDV index entries are { u64 video_offset_relative, u32 jpeg_bytes,
// u32 reserved }. The cache starts its index at a sector boundary, so index
// entry zero can be fetched atomically using the stock one-sector hps_io API.
wire [63:0] ddv_index_entry_address = ddv_index_offset + ({32'd0, requested_frame} << 4);
wire  [8:0] ddv_index_entry_base = ddv_index_entry_address[8:0];
wire  [8:0] ddv_index_local_addr = sd_buff_addr - ddv_index_entry_base;
wire [63:0] ddv_index_frame_offset = {index_words[1], index_words[0]};
wire [31:0] ddv_index_frame_length = index_words[2];
wire [63:0] ddv_index_frame_absolute = ddv_video_offset + ddv_index_frame_offset;
wire ddv_index_sane =
	requested_frame < header_words[6] &&
	ddv_index_frame_length != 32'd0 &&
	ddv_index_frame_offset < ddv_video_size &&
	{32'd0, ddv_index_frame_length} <= (ddv_video_size - ddv_index_frame_offset) &&
	ddv_index_frame_absolute < disc_size &&
	{32'd0, ddv_index_frame_length} <= (disc_size - ddv_index_frame_absolute);

assign sd_blk_cnt  = 6'd0; // one 512-byte sector
assign sd_wr       = 1'b0;
assign sd_buff_din = 8'd0;

always @(posedge clk) begin
	frame_request_ack <= 1'b0;
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
		ddv_valid    <= 1'b0;
		ddv_error    <= 1'b0;
		ddv_index_valid <= 1'b0;
		ddv_index_error <= 1'b0;
		ddv_frame_offset <= 64'd0;
		ddv_frame_length <= 32'd0;
		ddv_frame_number <= 32'd0;
		jpeg_byte <= 8'd0;
		jpeg_valid <= 1'b0;
		jpeg_last <= 1'b0;
		jpeg_streaming <= 1'b0;
		jpeg_stream_done <= 1'b0;
		jpeg_stream_error <= 1'b0;
		decoder_reset <= 1'b1;
		frame_lba <= 32'd0;
		frame_skip <= 9'd0;
		frame_first <= 1'b0;
		stream_pos <= 9'd0;
		bytes_remaining <= 32'd0;
		requested_frame <= 32'd0;
		for (i = 0; i < 128; i = i + 1) header_words[i] <= 32'd0;
		for (i = 0; i < 4; i = i + 1) index_words[i] <= 32'd0;
		state <= (|img_size) ? ST_WAIT_BUS : ST_NO_MEDIA;
	end else begin
		case (state)
		ST_NO_MEDIA: begin
			sd_rd <= 1'b0;
			jpeg_valid <= 1'b0;
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
			if (sd_buff_wr) begin
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
			ddv_valid    <= ddv_header_sane;
			ddv_error    <= !ddv_header_sane;
			pvf_width    <= header_words[2];
			pvf_height   <= header_words[3];
			pvf_fps_num  <= header_words[4];
			pvf_fps_den  <= header_words[5];
			pvf_frames   <= header_words[6];
			pvf_audio_hz <= header_words[7];
			// Fetch index entry zero as soon as a DDV header has been accepted.
			// It verifies byte-address translation and the 64-bit index layout
			// without committing the upcoming JPEG DMA/decode pipeline.
			requested_frame <= 32'd0;
			state         <= ddv_header_sane ? ST_INDEX_WAIT : ST_READY;
		end

		ST_INDEX_WAIT: begin
			sd_rd <= 1'b0;
			if (!sd_ack) state <= ST_INDEX_REQ;
		end

		ST_INDEX_REQ: begin
			// Header validation pins this to 512, but retain the expression so
			// later readers can select arbitrary 16-byte entries.
			sd_lba <= ddv_index_entry_address[40:9];
			sd_rd <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				state <= ST_INDEX_DATA;
			end
		end

		ST_INDEX_DATA: begin
			sd_rd <= 1'b0;
			if (sd_buff_wr && sd_buff_addr >= ddv_index_entry_base &&
			    {1'b0, sd_buff_addr} < ({1'b0, ddv_index_entry_base} + 10'd16)) begin
				case (ddv_index_local_addr[3:2])
					2'd0: index_words[0][{ddv_index_local_addr[1:0], 3'b000} +: 8] <= sd_buff_dout;
					2'd1: index_words[1][{ddv_index_local_addr[1:0], 3'b000} +: 8] <= sd_buff_dout;
					2'd2: index_words[2][{ddv_index_local_addr[1:0], 3'b000} +: 8] <= sd_buff_dout;
					2'd3: index_words[3][{ddv_index_local_addr[1:0], 3'b000} +: 8] <= sd_buff_dout;
				endcase
			end
			if (!sd_ack) state <= ST_INDEX_VALIDATE;
		end

		ST_INDEX_VALIDATE: begin
			ddv_index_valid <= ddv_index_sane;
			ddv_index_error <= !ddv_index_sane;
			ddv_frame_offset <= ddv_index_frame_absolute;
			ddv_frame_length <= ddv_index_frame_length;
			ddv_frame_number <= requested_frame;
			if (ddv_index_sane) begin
				frame_lba <= ddv_index_frame_absolute[40:9];
				frame_skip <= ddv_index_frame_absolute[8:0];
				frame_first <= 1'b1;
				bytes_remaining <= ddv_index_frame_length;
				jpeg_streaming <= 1'b1;
				state <= ST_FRAME_WAIT;
			end else begin
				jpeg_stream_error <= 1'b1;
				state <= ST_READY;
			end
		end

		ST_FRAME_WAIT: begin
			sd_rd <= 1'b0;
			jpeg_valid <= 1'b0;
			if (!sd_ack) state <= ST_FRAME_REQ;
		end

		ST_FRAME_REQ: begin
			sd_lba <= frame_lba;
			sd_rd <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				state <= ST_FRAME_DATA;
			end
		end

		ST_FRAME_DATA: begin
			sd_rd <= 1'b0;
			if (sd_buff_wr)
				frame_sector[sd_buff_addr] <= sd_buff_dout;
			if (!sd_ack) begin
				stream_pos <= frame_first ? frame_skip : 9'd0;
				decoder_reset <= 1'b0;
				state <= ST_STREAM_PRIME;
			end
		end

		ST_STREAM_PRIME: begin
			jpeg_valid <= 1'b0;
			jpeg_last <= 1'b0;
			jpeg_byte <= frame_sector[stream_pos];
			state <= ST_STREAM_BYTE;
		end

		ST_STREAM_BYTE: begin
			jpeg_valid <= 1'b1;
			jpeg_last <= (bytes_remaining == 32'd1);
			if (jpeg_valid && jpeg_ready) begin
				jpeg_valid <= 1'b0;
				if (bytes_remaining == 32'd1) begin
					bytes_remaining <= 32'd0;
					jpeg_last <= 1'b0;
					jpeg_streaming <= 1'b0;
					jpeg_stream_done <= 1'b1;
					state <= ST_READY;
				end else begin
					bytes_remaining <= bytes_remaining - 1'b1;
					if (stream_pos == 9'd511) begin
						frame_lba <= frame_lba + 1'b1;
						frame_first <= 1'b0;
						state <= ST_FRAME_WAIT;
					end else begin
						stream_pos <= stream_pos + 1'b1;
						state <= ST_STREAM_PRIME;
					end
				end
			end
		end

		ST_READY: begin
			sd_rd <= 1'b0;
			jpeg_valid <= 1'b0;
			if (frame_request && ddv_valid && pvf_frames != 32'd0) begin
				requested_frame <= (frame_request_index < pvf_frames) ?
				                   frame_request_index : pvf_frames - 1'b1;
				frame_request_ack <= 1'b1;
				ddv_index_valid <= 1'b0;
				ddv_index_error <= 1'b0;
				jpeg_stream_done <= 1'b0;
				jpeg_stream_error <= 1'b0;
				decoder_reset <= 1'b1;
				state <= ST_INDEX_WAIT;
			end
		end

		default: state <= ST_NO_MEDIA;
		endcase
	end
end

endmodule
