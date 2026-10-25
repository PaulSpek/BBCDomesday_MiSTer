// Mounted-media and single-sector cache for an AIV/Domesday LV-ROM volume.
//
// MiSTer's virtual-drive API transfers 512-byte sectors. The Acorn VFS SCSI
// LUN uses 256-byte blocks, so the SCSI target selects either half of the
// cached sector. This block intentionally exposes a read-only interface.

module domesday_vfs_media
(
	input             clk,
	input             img_mounted,
	input      [63:0] img_size,
	output reg        present = 1'b0,
	output reg        valid = 1'b0,
	output reg [63:0] size = 64'd0,

	input             read_request,
	input      [31:0] read_lba,
	output reg        read_ready = 1'b0,
	input       [8:0] cache_addr,
	output      [7:0] cache_data,

	output reg [31:0] sd_lba = 32'd0,
	output      [5:0] sd_blk_cnt,
	output reg        sd_rd = 1'b0,
	output             sd_wr,
	input              sd_ack,
	input       [8:0] sd_buff_addr,
	input       [7:0] sd_buff_dout,
	input              sd_buff_wr,
	output      [7:0] sd_buff_din
);

localparam [2:0] ST_EMPTY   = 3'd0;
localparam [2:0] ST_WAIT    = 3'd1;
localparam [2:0] ST_REQUEST = 3'd2;
localparam [2:0] ST_RECEIVE = 3'd3;
localparam [2:0] ST_READY   = 3'd4;

reg [2:0] state = ST_EMPTY;
reg [31:0] requested_lba = 32'd0;
reg [31:0] cached_lba = 32'd0;
reg cached = 1'b0;
reg saw_data = 1'b0;
reg [7:0] sector_cache [0:511];

assign sd_blk_cnt = 6'd0;
assign sd_wr = 1'b0;
assign sd_buff_din = 8'd0;
assign cache_data = sector_cache[cache_addr];

always @(posedge clk) begin
	read_ready <= 1'b0;
	if (img_mounted) begin
		present <= |img_size;
		valid <= 1'b0;
		size <= img_size;
		sd_lba <= 32'd0;
		sd_rd <= 1'b0;
		requested_lba <= 32'd0;
		cached_lba <= 32'd0;
		cached <= 1'b0;
		saw_data <= 1'b0;
		state <= (|img_size) ? ST_WAIT : ST_EMPTY;
	end else begin
		case (state)
		ST_EMPTY: begin
			sd_rd <= 1'b0;
			valid <= 1'b0;
			cached <= 1'b0;
		end
		ST_WAIT: begin
			sd_rd <= 1'b0;
			if (!sd_ack) state <= ST_REQUEST;
		end
		ST_REQUEST: begin
			sd_lba <= requested_lba;
			sd_rd <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				saw_data <= 1'b0;
				state <= ST_RECEIVE;
			end
		end
		ST_RECEIVE: begin
			sd_rd <= 1'b0;
			if (sd_buff_wr) begin
				sector_cache[sd_buff_addr] <= sd_buff_dout;
				saw_data <= 1'b1;
			end
			if (!sd_ack) begin
				cached_lba <= requested_lba;
				cached <= saw_data || sd_buff_wr;
				// LV-ROM has no universal signature. Sector 0 returning data is
				// sufficient to establish mounted-media presence; later reads use
				// the same verified cache path.
				valid <= (saw_data || sd_buff_wr) && present;
				read_ready <= (saw_data || sd_buff_wr);
				state <= ST_READY;
			end
		end
		ST_READY: begin
			sd_rd <= 1'b0;
			if (read_request) begin
				if (cached && cached_lba == read_lba) begin
					read_ready <= 1'b1;
				end else begin
					requested_lba <= read_lba;
					state <= ST_WAIT;
				end
			end
		end
		default: state <= ST_EMPTY;
		endcase
	end
end
endmodule
