// Mounted-media boundary for an AIV/Domesday LV-ROM volume.
//
// The VFS data image deliberately has its own MiSTer virtual-disk slot.  It
// is not a floppy (.ssd/.dsd), and is not the DDV cache: later RTL exposes it
// as the read-only LUN behind the Acorn AIV SCSI host adapter at &FC40-&FC43.

module domesday_vfs_media
(
	input             clk,
	input             img_mounted,
	input      [63:0] img_size,
	output reg        present = 1'b0,
	output reg        valid = 1'b0,
	output reg [63:0] size = 64'd0,
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

localparam [2:0] ST_EMPTY = 3'd0;
localparam [2:0] ST_WAIT = 3'd1;
localparam [2:0] ST_REQUEST = 3'd2;
localparam [2:0] ST_RECEIVE = 3'd3;
localparam [2:0] ST_READY = 3'd4;

reg [2:0] state = ST_EMPTY;
reg saw_boot_sector = 1'b0;

assign sd_blk_cnt = 6'd0;
assign sd_wr = 1'b0;
assign sd_buff_din = 8'd0;

always @(posedge clk) begin
	if (img_mounted) begin
		present <= |img_size;
		valid <= 1'b0;
		size <= img_size;
		sd_lba <= 32'd0;
		sd_rd <= 1'b0;
		saw_boot_sector <= 1'b0;
		state <= (|img_size) ? ST_WAIT : ST_EMPTY;
	end else begin
		case (state)
		ST_EMPTY: sd_rd <= 1'b0;
		ST_WAIT: begin
			sd_rd <= 1'b0;
			if (!sd_ack) state <= ST_REQUEST;
		end
		ST_REQUEST: begin
			sd_lba <= 32'd0;
			sd_rd <= 1'b1;
			if (sd_ack) begin
				sd_rd <= 1'b0;
				state <= ST_RECEIVE;
			end
		end
		ST_RECEIVE: begin
			sd_rd <= 1'b0;
			if (sd_buff_wr) saw_boot_sector <= 1'b1;
			if (!sd_ack) begin
				// LV-ROM has no universal magic: its ADFS-era boot sector is
				// software-defined. A complete returned sector and a non-empty
				// mounted image are the safe boundary check at this layer.
				valid <= (saw_boot_sector || sd_buff_wr) && present;
				state <= ST_READY;
			end
		end
		ST_READY: sd_rd <= 1'b0;
		default: state <= ST_EMPTY;
		endcase
	end
end
endmodule
