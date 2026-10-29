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
reg awaiting_present = 1'b0;
reg stop_ack_pending = 1'b0;
reg [31:0] number;
reg [3:0] digit_count;
integer i;

function automatic [7:0] picture_digit(input [31:0] picture, input [2:0] place);
	reg [31:0] divisor;
	begin
		case (place)
			3'd0: divisor = 32'd10000;
			3'd1: divisor = 32'd1000;
			3'd2: divisor = 32'd100;
			3'd3: divisor = 32'd10;
			default: divisor = 32'd1;
		endcase
		picture_digit = "0" + ((picture / divisor) % 10);
	end
endfunction

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
				reply_data = picture_digit(current_picture, reply_index - 1'b1);
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

task automatic request_picture(input [31:0] picture);
	reg [31:0] bounded;
	begin
		bounded = (picture < 1) ? 32'd1 : picture;
		if (frame_count != 0 && bounded > frame_count) bounded = frame_count;
		requested_picture <= bounded;
		frame_index <= bounded - 1'b1;
		frame_request <= media_present;
	end
endtask

always @(posedge clk) begin
	if (reset) begin
		for (i = 0; i < 16; i = i + 1) command[i] <= 8'h00;
		reply_kind <= REPLY_EMPTY;
		frame_request <= 1'b0;
		frame_index <= 32'd0;
		requested_picture <= 32'd1;
		awaiting_present <= 1'b0;
		stop_ack_pending <= 1'b0;
		vp_mode <= 3'd3;
		video_enabled <= 1'b1;
		audio_1_enabled <= 1'b0;
		audio_2_enabled <= 1'b0;
		playing <= 1'b0;
		reverse <= 1'b0;
		current_picture <= 32'd1;
	end else begin
		if (!media_present) begin
			frame_request <= 1'b0;
			awaiting_present <= 1'b0;
			playing <= 1'b0;
			current_picture <= 32'd1;
		end

		if (command_write && command_index < 16)
			command[command_index[3:0]] <= command_data;

		if (frame_request && frame_request_ack) begin
			frame_request <= 1'b0;
			awaiting_present <= 1'b1;
		end

		if (frame_presented && awaiting_present) begin
			current_picture <= requested_picture;
			awaiting_present <= 1'b0;
			if (stop_ack_pending) begin
				reply_kind <= REPLY_ACK2;
				stop_ack_pending <= 1'b0;
			end
			if (playing) begin
				if (reverse) begin
					if (requested_picture > 1) request_picture(requested_picture - 1'b1);
					else playing <= 1'b0;
				end else begin
					if (frame_count == 0 || requested_picture < frame_count)
						request_picture(requested_picture + 1'b1);
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
					request_picture((command[0] == "O" || command[0] == "V" || command[0] == "Z") ?
					                ((current_picture > 1) ? current_picture - 1'b1 : 32'd1) :
					                current_picture + 1'b1);
			end else if (command[0] == "L") begin
				playing <= 1'b0;
				request_picture(current_picture + 1'b1);
			end else if (command[0] == "M") begin
				playing <= 1'b0;
				request_picture((current_picture > 1) ? current_picture - 1'b1 : 32'd1);
			end else if (command[0] == "+" || command[0] == "-") begin
				number = 0; digit_count = 0;
				for (i = 1; i < 3; i = i + 1)
					if (command[i] >= "0" && command[i] <= "9") begin
						number = number * 10 + command[i] - "0"; digit_count = digit_count + 1'b1;
					end
				if (digit_count != 0 && number != 0) begin
					playing <= 1'b0;
					if (command[0] == "+") request_picture(current_picture + number);
					else request_picture((current_picture > number) ? current_picture - number : 32'd1);
				end
			end else if (command[0] == "F") begin
				number = 0; digit_count = 0;
				for (i = 1; i < 7; i = i + 1)
					if (command[i] >= "0" && command[i] <= "9") begin
						number = number * 10 + command[i] - "0"; digit_count = digit_count + 1'b1;
					end
				if (digit_count != 0) begin
					request_picture(number);
					case (command[digit_count + 1'b1])
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
