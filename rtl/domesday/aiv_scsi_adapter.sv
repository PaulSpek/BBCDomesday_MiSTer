// Read-only Acorn AIV / Pi1MHz-compatible SCSI target at BBC FRED &FC40-43.
//
// The target implements the small command set required to discover and read a
// VFS/LV-ROM LUN.  SCSI blocks are 256 bytes; the media cache below operates
// on MiSTer's native 512-byte sectors.
module aiv_scsi_adapter
(
	input             clk,
	input             reset,
	input             cs,
	input             strobe,
	input             rnw,
	input       [1:0] addr,
	input       [7:0] din,
	output reg  [7:0] dout,
	input             media_present,
	input      [63:0] media_size,
	output            media_read,
	output      [31:0] media_lba,
	input             media_ready,
	output      [8:0] media_addr,
	input       [7:0] media_data
);
localparam [7:0] ST_CND = 8'h80;
localparam [7:0] ST_INO = 8'h40;
localparam [7:0] ST_REQ = 8'h20;
localparam [7:0] ST_BSY = 8'h02;
localparam [7:0] ST_MSG = 8'h01;

localparam [3:0] PH_BUSFREE   = 4'd0;
localparam [3:0] PH_COMMAND   = 4'd1;
localparam [3:0] PH_DATA      = 4'd2;
localparam [3:0] PH_READ_WAIT = 4'd3;
localparam [3:0] PH_READ      = 4'd4;
localparam [3:0] PH_STATUS    = 4'd5;
localparam [3:0] PH_MESSAGE   = 4'd6;
localparam [3:0] PH_DATAOUT   = 4'd7;

reg [3:0] phase = PH_BUSFREE;
reg [7:0] data_reg = 8'h00;
reg [7:0] cdb [0:9];
reg [3:0] cdb_count = 4'd0;
reg [3:0] cdb_length = 4'd6;
reg [8:0] data_count = 9'd0;
reg [8:0] data_length = 9'd0;
reg [8:0] blocks_left = 9'd0;
reg [31:0] current_block = 32'd0;
reg [8:0] block_base = 9'd0;
reg [7:0] scsi_status = 8'h00;
reg irq_enable = 1'b0;
reg [7:0] host_id = 8'h00;
reg [7:0] fcode_tx0 = 8'h00;
reg [7:0] fcode_tx1 = 8'h00;
reg [7:0] fcode_tx2 = 8'h00;
reg [2:0] fcode_reply = 3'd0;
reg req_asserted = 1'b0;
reg [5:0] req_gap = 6'd0;

// LV-ROM is exposed using the 256-byte logical blocks expected by VFS,
// whereas MiSTer's block API and the cache use 512-byte sectors.
wire [31:0] scsi_block_count = media_size[39:8];
wire [31:0] scsi_last_block = scsi_block_count ? scsi_block_count - 1'b1 : 32'd0;

function automatic [7:0] inquiry_byte(input [5:0] index);
	begin
		case (index)
			 0: inquiry_byte = 8'h00; // direct-access block device
			 1: inquiry_byte = 8'h80; // removable
			 2: inquiry_byte = 8'h01;
			 3: inquiry_byte = 8'h02;
			 4: inquiry_byte = 8'd31;
			 8: inquiry_byte = "M";  9: inquiry_byte = "i";
			10: inquiry_byte = "S"; 11: inquiry_byte = "T";
			12: inquiry_byte = "e"; 13: inquiry_byte = "r";
			14: inquiry_byte = " "; 15: inquiry_byte = " ";
			16: inquiry_byte = "D"; 17: inquiry_byte = "o";
			18: inquiry_byte = "m"; 19: inquiry_byte = "e";
			20: inquiry_byte = "s"; 21: inquiry_byte = "d";
			22: inquiry_byte = "a"; 23: inquiry_byte = "y";
			24: inquiry_byte = " "; 25: inquiry_byte = "V";
			26: inquiry_byte = "F"; 27: inquiry_byte = "S";
			28: inquiry_byte = " "; 29: inquiry_byte = " ";
			30: inquiry_byte = " "; 31: inquiry_byte = " ";
			32: inquiry_byte = "0"; 33: inquiry_byte = ".";
			34: inquiry_byte = "1"; 35: inquiry_byte = " ";
			default: inquiry_byte = 8'h00;
		endcase
	end
endfunction

// VP415/LV-DOS F-code replies are always a 256-byte block.  These are the
// discovery replies VFS requires before it starts reading the LV-ROM.  They
// match Pi1MHz: ?P says that a CAV, frame-locked disc is loaded and VPX says
// that the player is in the hard-keyed overlay mode.  Other commands get the
// VP415 empty reply (CR followed by padding) until the video back-end exists.
function automatic [7:0] fcode_byte(input [8:0] index);
	begin
		fcode_byte = 8'h00;
		case (fcode_reply)
			3'd1: case (index) // ?P: player status
				0: fcode_byte = "P";
				1: fcode_byte = 8'h60; // '@' + disc loaded
				2: fcode_byte = 8'h41; // '@' + CAV / no chapters
				3: fcode_byte = 8'h41; // '@' + frame lock / replay off
				4: fcode_byte = 8'h40; // transmission delay, remote and RC off
				5: fcode_byte = 8'h40; // both audio channels and teletext off
				6: fcode_byte = 8'h0d;
				default: fcode_byte = 8'h00;
			endcase
			3'd2: case (index) // VPX: video-overlay-mode query
				0: fcode_byte = "V";
				1: fcode_byte = "P";
				2: fcode_byte = "3";
				3: fcode_byte = 8'h0d;
				default: fcode_byte = 8'h00;
			endcase
			3'd3: begin // ,1: player loaded and standing by
				fcode_byte = (index == 0) ? "S" : ((index == 1) ? 8'h0d : 8'h00);
			end
			default: fcode_byte = (index == 0) ? 8'h0d : 8'h00;
		endcase
	end
endfunction

function automatic [7:0] sense_byte(input [4:0] index);
	begin
		case (index)
			0: sense_byte = 8'h70;
			2: sense_byte = media_present ? 8'h00 : 8'h02; // not ready
			7: sense_byte = 8'd10;
			default: sense_byte = 8'h00;
		endcase
	end
endfunction

// Replies for control commands which precede normal VFS reads.  VFS needs a
// real capacity reply to derive its LV-ROM geometry; MODE SENSE needs at
// least a legal four-byte header.  The LV-ROM is deliberately read-only.
function automatic [7:0] control_byte(input [7:0] opcode, input [5:0] index);
	begin
		control_byte = 8'h00;
		case (opcode)
			8'h25: case (index) // READ CAPACITY(10): last LBA, 256-byte block size
				0: control_byte = scsi_last_block[31:24];
				1: control_byte = scsi_last_block[23:16];
				2: control_byte = scsi_last_block[15:8];
				3: control_byte = scsi_last_block[7:0];
				6: control_byte = 8'h01;
				default: control_byte = 8'h00;
			endcase
			8'h1a: case (index) // MODE SENSE(6), no block descriptor/pages
				0: control_byte = 8'h03;
				default: control_byte = 8'h00;
			endcase
			default: control_byte = 8'h00;
		endcase
	end
endfunction

always @* begin
	case (addr)
		2'd0: dout = data_reg;
		2'd1: begin
			dout = 8'h00;
			if (phase != PH_BUSFREE) dout = ST_BSY;
			if (req_asserted) dout = dout | ST_REQ;
			if (phase == PH_COMMAND || phase == PH_STATUS || phase == PH_MESSAGE)
				dout = dout | ST_CND;
			if (phase == PH_DATA || phase == PH_READ || phase == PH_STATUS || phase == PH_MESSAGE)
				dout = dout | ST_INO;
			if (phase == PH_MESSAGE) dout = dout | ST_MSG;
		end
		default: dout = 8'hFF;
	endcase
end

assign media_read = (phase == PH_READ_WAIT);
assign media_lba = current_block >> 1;
assign media_addr = (phase == PH_READ_WAIT) ? (current_block[0] ? 9'd256 : 9'd0) :
	(phase == PH_READ && strobe && rnw && addr == 2'd0 && data_count == 9'd255 && !current_block[0]) ? 9'd256 :
	(phase == PH_READ && strobe && rnw && addr == 2'd0 && data_count != 9'd255) ? block_base + data_count + 1'b1 :
	block_base + data_count;

always @(posedge clk) begin
	if (reset || !media_present) begin
		phase <= PH_BUSFREE;
		data_reg <= 8'h00;
		cdb_count <= 4'd0;
		irq_enable <= 1'b0;
		host_id <= 8'h00;
		fcode_tx0 <= 8'h00;
		fcode_tx1 <= 8'h00;
		fcode_tx2 <= 8'h00;
		fcode_reply <= 3'd0;
		req_asserted <= 1'b0;
		req_gap <= 6'd0;
	end else begin
		// The AIV host acknowledges every byte at FC40.  The real Pi1MHz
		// interface drops REQ in that access and only raises it again when the
		// next byte is ready.  VFS polls for that edge; holding REQ high makes
		// it wait indefinitely after the first byte of a command.
		if (!req_asserted && phase != PH_BUSFREE && phase != PH_READ_WAIT) begin
			if (req_gap == 0) req_asserted <= 1'b1;
			else req_gap <= req_gap - 1'b1;
		end

		if (strobe && !rnw && addr == 2'd2) begin
			// FC42: host asserts SELECT and presents its initiator ID.  VFS uses
			// ID 16; preserving it is needed to distinguish its group-6 F-code
			// protocol from the ordinary READ(6) command with the same opcode.
			host_id <= din;
			phase <= PH_COMMAND;
			cdb_count <= 4'd0;
			scsi_status <= 8'h00;
			req_asserted <= 1'b1;
			req_gap <= 6'd0;
		end
		if (strobe && !rnw && addr == 2'd3) irq_enable <= din[0];

		if (strobe && !rnw && addr == 2'd0 && phase == PH_COMMAND && req_asserted) begin
			cdb[cdb_count] <= din;
			if (cdb_count == 0) begin
				// SCSI group 1 commands are always ten-byte CDBs.  In
				// particular, READ CAPACITY(10) is 0x25 as well as READ(10)
				// being 0x28; decoding only the latter prematurely entered
				// data-in after six command bytes.
				cdb_length <= (din[7:5] == 3'b001) ? 4'd10 : 4'd6;
				cdb_count <= 4'd1;
			end else if (cdb_count + 1'b1 == cdb_length) begin
				cdb_count <= 4'd0;
				case (cdb[0])
				8'h00: begin // TEST UNIT READY
					scsi_status <= 8'h00;
					data_reg <= 8'h00;
					phase <= PH_STATUS;
				end
				8'h03: begin // REQUEST SENSE
					data_count <= 9'd0;
					data_length <= (cdb[4] < 18) ? cdb[4] : 9'd18;
					data_reg <= sense_byte(0);
					phase <= (cdb[4] == 0) ? PH_STATUS : PH_DATA;
				end
				8'h12: begin // INQUIRY
					data_count <= 9'd0;
					data_length <= (cdb[4] < 36) ? cdb[4] : 9'd36;
					data_reg <= inquiry_byte(0);
					phase <= (cdb[4] == 0) ? PH_STATUS : PH_DATA;
				end
				8'h1a: begin // MODE SENSE(6)
					data_count <= 9'd0;
					data_length <= (cdb[4] < 4) ? cdb[4] : 9'd4;
					data_reg <= control_byte(8'h1a, 0);
					phase <= (cdb[4] == 0) ? PH_STATUS : PH_DATA;
				end
				8'h1b: begin // START/STOP UNIT: mounted LV-ROM is always ready
					scsi_status <= 8'h00;
					data_reg <= 8'h00;
					phase <= PH_STATUS;
				end
				8'h25: begin // READ CAPACITY(10)
					data_count <= 9'd0;
					data_length <= 9'd8;
					data_reg <= control_byte(8'h25, 0);
					phase <= PH_DATA;
				end
				8'h08: begin // READ(6), 256-byte SCSI blocks
					current_block <= {11'd0, cdb[1][4:0], cdb[2], cdb[3]};
					blocks_left <= (cdb[4] == 0) ? 9'd256 : {1'b0, cdb[4]};
					phase <= PH_READ_WAIT;
				end
				8'h28: begin // READ(10), 256-byte SCSI blocks
					current_block <= {cdb[2], cdb[3], cdb[4], cdb[5]};
					blocks_left <= ({cdb[7], cdb[8]} == 0) ? 9'd1 :
						(cdb[7] == 0 ? {1'b0, cdb[8]} : 9'd256);
					phase <= PH_READ_WAIT;
				end
				8'hca: begin // WRITE F-Code (group 6 / opcode 0x0a)
					// LV-DOS sends a CR-terminated F-code, null padded to one
					// 256-byte block.  Consume the whole block before status.
					if (host_id == 8'h10) begin
						data_count <= 9'd0;
						data_length <= 9'd256;
						phase <= PH_DATAOUT;
					end else begin
						scsi_status <= 8'h02;
						data_reg <= 8'h02;
						phase <= PH_STATUS;
					end
				end
				8'hc8: begin // READ F-Code (group 6 / opcode 0x08)
					if (host_id == 8'h10) begin
						data_count <= 9'd0;
						data_length <= 9'd256;
						data_reg <= fcode_byte(0);
						phase <= PH_DATA;
					end else begin
						scsi_status <= 8'h02;
						data_reg <= 8'h02;
						phase <= PH_STATUS;
					end
				end
				default: begin
					scsi_status <= 8'h02; // CHECK CONDITION
					data_reg <= 8'h02;
					phase <= PH_STATUS;
				end
				endcase
			end else begin
				cdb_count <= cdb_count + 1'b1;
			end
		end

		// Data-out is the missing half of the LV-DOS F-code protocol.  There
		// is no video command back-end yet, but accepting the exact 256-byte
		// transaction prevents VFS initialisation from wedging at its first
		// player probe.  A later decoder consumes this stream here.
		if (strobe && !rnw && addr == 2'd0 && phase == PH_DATAOUT && req_asserted) begin
			if (data_count == 0) fcode_tx0 <= din;
			if (data_count == 1) fcode_tx1 <= din;
			if (data_count == 2) fcode_tx2 <= din;
			if (data_count == 9'd255) begin
				if (fcode_tx0 == "?" && fcode_tx1 == "P")
					fcode_reply <= 3'd1;
				else if (fcode_tx0 == "V" && fcode_tx1 == "P" && fcode_tx2 == "X")
					fcode_reply <= 3'd2;
				else if (fcode_tx0 == "," && fcode_tx1 == "1")
					fcode_reply <= 3'd3;
				else
					fcode_reply <= 3'd0;
				scsi_status <= 8'h00;
				data_reg <= 8'h00;
				phase <= PH_STATUS;
			end else begin
				data_count <= data_count + 1'b1;
			end
		end

		if (phase == PH_READ_WAIT && media_ready) begin
			block_base <= current_block[0] ? 9'd256 : 9'd0;
			data_count <= 9'd0;
			data_reg <= media_data;
			phase <= PH_READ;
			req_asserted <= 1'b1;
			req_gap <= 6'd0;
		end

		// FC40 is ACK for both directions. Leave REQ inactive long enough for
		// the 2 MHz host to observe it before presenting the following byte.
		if (strobe && addr == 2'd0 && req_asserted) begin
			req_asserted <= 1'b0;
			req_gap <= 6'd32;
		end

		// A FC40 read is the host acknowledge for target-to-host phases.
		if (strobe && rnw && addr == 2'd0 && req_asserted) begin
			case (phase)
			PH_DATA: begin
				if (data_count + 1'b1 >= data_length) begin
					data_reg <= scsi_status;
					phase <= PH_STATUS;
				end else begin
					data_count <= data_count + 1'b1;
					if (cdb[0] == 8'h12) data_reg <= inquiry_byte(data_count + 1'b1);
					else if (cdb[0] == 8'h03) data_reg <= sense_byte(data_count + 1'b1);
					else if (cdb[0] == 8'hc8) data_reg <= fcode_byte(data_count + 1'b1);
					else data_reg <= control_byte(cdb[0], data_count + 1'b1);
				end
			end
			PH_READ: begin
				if (data_count == 9'd255) begin
					if (blocks_left == 9'd1) begin
						data_reg <= scsi_status;
						phase <= PH_STATUS;
					end else if (!current_block[0]) begin
						current_block <= current_block + 1'b1;
						blocks_left <= blocks_left - 1'b1;
						block_base <= 9'd256;
						data_count <= 9'd0;
						data_reg <= media_data;
					end else begin
						current_block <= current_block + 1'b1;
						blocks_left <= blocks_left - 1'b1;
						phase <= PH_READ_WAIT;
					end
				end else begin
					data_count <= data_count + 1'b1;
					data_reg <= media_data;
				end
			end
			PH_STATUS: begin
				data_reg <= 8'h00;
				phase <= PH_MESSAGE;
			end
			PH_MESSAGE: phase <= PH_BUSFREE;
			default: ;
			endcase
		end
	end
end
endmodule
