// Philips VP415-compatible command/state engine used by the AIV SCSI target.
//
// LV-DOS transports every command in a 256-byte, zero-padded SCSI block.  The
// useful command is CR terminated and small, so keeping sixteen bytes in
// registers avoids consuming another scarce Cyclone-V RAM block while still
// covering every command used by Pi1MHz's player implementation.
module vp415_player
(
	input             clk,
	input             reset,
	input             media_present,
	input      [31:0] frame_count,

	input             command_write,
	input       [8:0] command_index,
	input       [7:0] command_data,
	input             command_commit,
	input       [8:0] reply_index,
	output reg  [7:0] reply_data,

	output reg        frame_request = 1'b0,
	output reg [31:0] frame_index = 32'd0,
	input             frame_request_ack,
	input             frame_presented,

	output reg  [2:0] vp_mode = 3'd3,
	output reg        video_enabled = 1'b1,
	output reg        audio_1_enabled = 1'b0,
	output reg        audio_2_enabled = 1'b0,
	output reg        playing = 1'b0,
	output reg        reverse = 1'b0,
	output reg [31:0] current_picture = 32'd1
);

localparam [3:0] REPLY_EMPTY = 4'd0;
localparam [3:0] REPLY_STATUS = 4'd1;
localparam [3:0] REPLY_VPX = 4'd2;
localparam [3:0] REPLY_STANDBY = 4'd3;
localparam [3:0] REPLY_TITLE = 4'd4;
localparam [3:0] REPLY_VOLUME = 4'd5;
localparam [3:0] REPLY_DESCRIPTION = 4'd6;
localparam [3:0] REPLY_ABSENT = 4'd7;
localparam [3:0] REPLY_PICTURE = 4'd8;
localparam [3:0] REPLY_ACK0 = 4'd9;
localparam [3:0] REPLY_ACK1 = 4'd10;
localparam [3:0] REPLY_ACK2 = 4'd11;
localparam [3:0] REPLY_ACK3 = 4'd12;

reg [7:0] command [0:15];
reg [3:0] reply_kind = REPLY_EMPTY;
reg [31:0] requested_picture = 32'd1;
// Picture requests pass through two short registered stages before they reach
// the media bridge.  Keeping operand calculation, range limiting and the
// zero-based frame-index conversion in separate clocks avoids a long 96-MHz
// current_picture -> frame_index carry/comparator path.
reg [31:0] picture_candidate = 32'd1;
reg picture_candidate_valid = 1'b0;
reg [31:0] bounded_picture = 32'd1;
reg bounded_picture_valid = 1'b0;
reg awaiting_present = 1'b0;
reg stop_ack_pending = 1'b0;
reg [19:0] current_picture_bcd = 20'h00001;
reg [36:0] bcd_shift = 37'd0;
reg [4:0] bcd_steps = 5'd0;
reg bcd_busy = 1'b0;
// Numeric operands are accumulated one received byte at a time.  LV-DOS
// leaves dozens of 96-MHz clocks between FC40 transfers, so this turns the
// former six-stage commit-time multiply chain into one shift/add per byte.
reg [31:0] parsed_number = 32'd0;
reg [3:0] parsed_digits = 4'd0;
reg [7:0] parsed_action = 8'h00;
integer i;

// A serial double-dabble conversion keeps decimal query formatting out of
// the 96-MHz combinational path.  Seventeen clocks cover the five-digit CAV
// picture range and are negligible beside one BBC/SCSI handshake.
reg [36:0] bcd_adjusted;
integer b;
always @* begin
	bcd_adjusted = bcd_shift;
	for (b = 17; b < 37; b = b + 4)
		if (bcd_shift[b +: 4] >= 5) bcd_adjusted[b +: 4] = bcd_shift[b +: 4] + 3;
end
wire [36:0] bcd_next = bcd_adjusted << 1;

// Reply storage is represented by state rather than a 256-byte RAM.  Reads
// are therefore stable snapshots until the next complete WRITE F-Code.
always @* begin
	reply_data = 8'h00;
	case (reply_kind)
		REPLY_STATUS: case (reply_index)
			0: reply_data = "P";
			1: reply_data = 8'h40 | (media_present ? 8'h20 : 8'h00) |
			                ((frame_request | awaiting_present) ? 8'h01 : 8'h00);
			2: reply_data = 8'h41; // CAV, no chapters
			3: reply_data = 8'h41; // frame locked, replay disabled
			4: reply_data = 8'h40;
			5: reply_data = 8'h40 | (audio_2_enabled ? 8'h20 : 8'h00) |
			                (audio_1_enabled ? 8'h10 : 8'h00);
			6: reply_data = 8'h0d;
			default: reply_data = 8'h00;
		endcase
		REPLY_VPX: case (reply_index)
			0: reply_data = "V"; 1: reply_data = "P";
			2: reply_data = "0" + vp_mode; 3: reply_data = 8'h0d;
			default: reply_data = 8'h00;
		endcase
		REPLY_STANDBY: begin
			if (reply_index == 0) reply_data = "S";
			else if (reply_index == 1) reply_data = 8'h0d;
		end
		REPLY_TITLE: case (reply_index)
			0: reply_data = "T"; 1: reply_data = "M"; 2: reply_data = "i";
			3: reply_data = "S"; 4: reply_data = "T"; 5: reply_data = "e";
			6: reply_data = "r"; 7: reply_data = " "; 8: reply_data = "L";
			9: reply_data = "a"; 10: reply_data = "s"; 11: reply_data = "e";
			12: reply_data = "r"; 13: reply_data = "D"; 14: reply_data = "i";
			15: reply_data = "s"; 16: reply_data = "c"; 17: reply_data = 8'h0d;
			default: reply_data = 8'h00;
		endcase
		REPLY_VOLUME: case (reply_index)
			0: reply_data = "V"; 1: reply_data = "0"; 2: reply_data = 8'h0d;
			default: reply_data = 8'h00;
		endcase
		REPLY_DESCRIPTION: case (reply_index)
			0: reply_data = "Y"; 1: reply_data = "M"; 2: reply_data = "o";
			3: reply_data = "u"; 4: reply_data = "n"; 5: reply_data = "t";
			6: reply_data = "e"; 7: reply_data = "d"; 8: reply_data = " ";
			9: reply_data = "D"; 10: reply_data = "D"; 11: reply_data = "V";
			12: reply_data = "/"; 13: reply_data = "P"; 14: reply_data = "V";
			15: reply_data = "F"; 16: reply_data = " "; 17: reply_data = "m";
			18: reply_data = "e"; 19: reply_data = "d"; 20: reply_data = "i";
			21: reply_data = "a"; 22: reply_data = 8'h0d;
			default: reply_data = 8'h00;
		endcase
		REPLY_ABSENT: begin
			if (reply_index == 0) reply_data = "X";
			else if (reply_index == 1) reply_data = 8'h0d;
		end
		REPLY_PICTURE: begin
			if (!media_present) begin
				if (reply_index == 0) reply_data = "X";
				else if (reply_index == 1) reply_data = 8'h0d;
			end else if (reply_index == 0) reply_data = "F";
			else if (reply_index >= 1 && reply_index <= 5)
				case (reply_index)
					1: reply_data = "0" + current_picture_bcd[19:16];
					2: reply_data = "0" + current_picture_bcd[15:12];
					3: reply_data = "0" + current_picture_bcd[11:8];
					4: reply_data = "0" + current_picture_bcd[7:4];
					default: reply_data = "0" + current_picture_bcd[3:0];
				endcase
			else if (reply_index == 6) reply_data = 8'h0d;
		end
		REPLY_ACK0, REPLY_ACK1, REPLY_ACK2, REPLY_ACK3: begin
			if (reply_index == 0) reply_data = "A";
			else if (reply_index == 1) reply_data = "0" + (reply_kind - REPLY_ACK0);
			else if (reply_index == 2) reply_data = 8'h0d;
		end
		default: reply_data = (reply_index == 0) ? 8'h0d : 8'h00;
	endcase
end

task automatic queue_picture(input [31:0] picture);
	begin
		picture_candidate <= picture;
		picture_candidate_valid <= media_present;
	end
endtask

always @(posedge clk) begin
	if (reset) begin
		for (i = 0; i < 16; i = i + 1) command[i] <= 8'h00;
		reply_kind <= REPLY_EMPTY;
		frame_request <= 1'b0;
		frame_index <= 32'd0;
		requested_picture <= 32'd1;
		picture_candidate <= 32'd1;
		picture_candidate_valid <= 1'b0;
		bounded_picture <= 32'd1;
		bounded_picture_valid <= 1'b0;
		awaiting_present <= 1'b0;
		stop_ack_pending <= 1'b0;
		vp_mode <= 3'd3;
		video_enabled <= 1'b1;
		audio_1_enabled <= 1'b0;
		audio_2_enabled <= 1'b0;
		playing <= 1'b0;
		reverse <= 1'b0;
		current_picture <= 32'd1;
		current_picture_bcd <= 20'h00001;
		bcd_shift <= 37'd0;
		bcd_steps <= 5'd0;
		bcd_busy <= 1'b0;
		parsed_number <= 32'd0;
		parsed_digits <= 4'd0;
		parsed_action <= 8'h00;
	end else begin
		if (bcd_busy) begin
			bcd_shift <= bcd_next;
			if (bcd_steps == 5'd16) begin
				current_picture_bcd <= bcd_next[36:17];
				bcd_busy <= 1'b0;
			end else bcd_steps <= bcd_steps + 1'b1;
		end
		if (!media_present) begin
			frame_request <= 1'b0;
			picture_candidate_valid <= 1'b0;
			bounded_picture_valid <= 1'b0;
			awaiting_present <= 1'b0;
			playing <= 1'b0;
			current_picture <= 32'd1;
		end else begin
			// Stage 2: convert the bounded one-based picture number into the
			// bridge's zero-based frame index.  Back-pressure preserves a queued
			// request until the bridge has acknowledged the preceding request.
			if (bounded_picture_valid && !frame_request) begin
				requested_picture <= bounded_picture;
				frame_index <= bounded_picture - 1'b1;
				frame_request <= 1'b1;
				bounded_picture_valid <= 1'b0;
			end

			// Stage 1: clamp the requested picture to the mounted media.  This
			// may refill stage 2 in the same clock in which it is consumed.
			if (picture_candidate_valid &&
			    (!bounded_picture_valid || !frame_request)) begin
				if (picture_candidate < 1)
					bounded_picture <= 32'd1;
				else if (frame_count != 0 && picture_candidate > frame_count)
					bounded_picture <= frame_count;
				else
					bounded_picture <= picture_candidate;
				bounded_picture_valid <= 1'b1;
				picture_candidate_valid <= 1'b0;
			end
		end

		if (command_write && command_index < 16) begin
			command[command_index[3:0]] <= command_data;
			if (command_index == 0) begin
				parsed_number <= 32'd0;
				parsed_digits <= 4'd0;
				parsed_action <= 8'h00;
			end else if ((command[0] == "F" || command[0] == "+" ||
			              command[0] == "-" || command[0] == "S") &&
			             parsed_action == 0) begin
				if (command_data >= "0" && command_data <= "9") begin
					parsed_number <= (parsed_number << 3) + (parsed_number << 1) +
					                 command_data - "0";
					parsed_digits <= parsed_digits + 1'b1;
				end else if (command_data != 8'h0d && command_data != 8'h00) begin
					parsed_action <= command_data;
				end
			end
		end

		if (frame_request && frame_request_ack) begin
			frame_request <= 1'b0;
			awaiting_present <= 1'b1;
		end

		if (frame_presented && awaiting_present) begin
			current_picture <= requested_picture;
			bcd_shift <= {20'd0, requested_picture[16:0]};
			bcd_steps <= 5'd0;
			bcd_busy <= 1'b1;
			awaiting_present <= 1'b0;
			if (stop_ack_pending) begin
				reply_kind <= REPLY_ACK2;
				stop_ack_pending <= 1'b0;
			end
			if (playing) begin
				if (reverse) begin
					if (requested_picture > 1) queue_picture(requested_picture - 1'b1);
					else playing <= 1'b0;
				end else begin
					if (frame_count == 0 || requested_picture < frame_count)
						queue_picture(requested_picture + 1'b1);
					else playing <= 1'b0;
				end
			end
		end

		if (command_commit) begin
			reply_kind <= REPLY_EMPTY;
			// Queries and menu extension commands.
			if (command[0] == "?" && command[1] == "P") reply_kind <= REPLY_STATUS;
			else if (command[0] == "?" && command[1] == "F") reply_kind <= REPLY_PICTURE;
			else if (command[0] == "V" && command[1] == "P" && command[2] == "X") reply_kind <= REPLY_VPX;
			else if (command[0] == "," && command[1] == "1") reply_kind <= REPLY_STANDBY;
			else if (command[0] == "?" && (command[1] == "T" || command[1] == "V" || command[1] == "Y")) begin
				if (media_present && command[2] == "1" && command[3] == 8'h0d)
					reply_kind <= (command[1] == "T") ? REPLY_TITLE :
					              (command[1] == "V") ? REPLY_VOLUME : REPLY_DESCRIPTION;
				else reply_kind <= REPLY_ABSENT;
			end
			// Player state and transport commands mirrored from Pi1MHz fcode.c.
			else if (command[0] == "V" && command[1] == "P" &&
			         command[2] >= "1" && command[2] <= "5")
				vp_mode <= command[2] - "0";
			else if (command[0] == "E" && (command[1] == "0" || command[1] == "1"))
				video_enabled <= (command[1] == "1");
			else if (command[0] == "A" && (command[1] == "0" || command[1] == "1")) begin
				audio_1_enabled <= (command[1] == "1");
				if (command[1] == "1") reply_kind <= REPLY_ACK0;
			end else if (command[0] == "B" && (command[1] == "0" || command[1] == "1")) begin
				audio_2_enabled <= (command[1] == "1");
				if (command[1] == "1") reply_kind <= REPLY_ACK0;
			end else if (command[0] == "*" || command[0] == "/") begin
				playing <= 1'b0;
				if (command[0] == "/") begin
					audio_1_enabled <= 1'b0;
					audio_2_enabled <= 1'b0;
				end
			end else if (command[0] == "N" || command[0] == "O" ||
			             command[0] == "U" || command[0] == "V" ||
			             command[0] == "W" || command[0] == "Z") begin
				playing <= 1'b1;
				reverse <= (command[0] == "O" || command[0] == "V" || command[0] == "Z");
				if (!frame_request && !awaiting_present)
					queue_picture((command[0] == "O" || command[0] == "V" || command[0] == "Z") ?
					                ((current_picture > 1) ? current_picture - 1'b1 : 32'd1) :
					                current_picture + 1'b1);
			end else if (command[0] == "L") begin
				playing <= 1'b0;
				queue_picture(current_picture + 1'b1);
			end else if (command[0] == "M") begin
				playing <= 1'b0;
				queue_picture((current_picture > 1) ? current_picture - 1'b1 : 32'd1);
			end else if (command[0] == "+" || command[0] == "-") begin
				if (parsed_digits != 0 && parsed_number != 0) begin
					playing <= 1'b0;
					if (command[0] == "+") queue_picture(current_picture + parsed_number);
					else queue_picture((current_picture > parsed_number) ?
					                     current_picture - parsed_number : 32'd1);
				end
			end else if (command[0] == "F") begin
				if (parsed_digits != 0) begin
					queue_picture(parsed_number);
					case (parsed_action)
						"I": reply_kind <= REPLY_ACK3;
						"S": begin playing <= 1'b0; stop_ack_pending <= 1'b1; end
						"N": begin playing <= 1'b1; reverse <= 1'b0; reply_kind <= REPLY_ACK1; end
						"R", "Q": begin playing <= 1'b0; reply_kind <= REPLY_ACK0; end
						default: begin playing <= 1'b0; reply_kind <= REPLY_ACK0; end
					endcase
				end
			end
		end
	end
end

endmodule
