`timescale 1ns/1ps

module tb_vp415_player;
	reg clk = 0;
	reg reset = 1;
	reg media_present = 1;
	reg command_write = 0;
	reg [8:0] command_index = 0;
	reg [7:0] command_data = 0;
	reg command_commit = 0;
	reg [8:0] reply_index = 0;
	wire [7:0] reply_data;
	wire frame_request;
	wire [31:0] frame_index;
	reg frame_request_ack = 0;
	reg frame_presented = 0;
	wire [2:0] vp_mode;
	wire video_enabled, audio_1_enabled, audio_2_enabled, playing, reverse;
	wire [31:0] current_picture;
	integer n;

	always #5 clk = ~clk;

	vp415_player dut (
		.clk(clk), .reset(reset), .media_present(media_present), .frame_count(32'd1500),
		.command_write(command_write), .command_index(command_index),
		.command_data(command_data), .command_commit(command_commit),
		.reply_index(reply_index), .reply_data(reply_data),
		.frame_request(frame_request), .frame_index(frame_index),
		.frame_request_ack(frame_request_ack), .frame_presented(frame_presented),
		.vp_mode(vp_mode), .video_enabled(video_enabled),
		.audio_1_enabled(audio_1_enabled), .audio_2_enabled(audio_2_enabled),
		.playing(playing), .reverse(reverse), .current_picture(current_picture)
	);

	task automatic send(input [8*16-1:0] bytes, input integer length);
	begin
		for (n = 0; n < 16; n = n + 1) begin
			command_index = n[8:0];
			command_data = (n < length) ? bytes[8*(15-n) +: 8] : 8'h00;
			command_write = 1'b1; @(posedge clk); #1 command_write = 1'b0;
		end
		command_commit = 1'b1; @(posedge clk); #1 command_commit = 1'b0;
	end
	endtask

	task automatic accept_and_show;
	begin
		if (!frame_request) $fatal(1, "expected a frame request");
		frame_request_ack = 1; @(posedge clk); #1 frame_request_ack = 0;
		frame_presented = 1; @(posedge clk); #1 frame_presented = 0;
	end
	endtask

	initial begin
		repeat (3) @(posedge clk); reset = 0; @(posedge clk);

		send({"V","P","4",8'h0d,{12{8'h00}}}, 4);
		if (vp_mode != 4) $fatal(1, "VP4 did not set the compositor mode");
		send({"V","P","X",8'h0d,{12{8'h00}}}, 4);
		reply_index = 2; #1; if (reply_data != "4") $fatal(1, "VPX did not report VP4");

		send({"E","0",8'h0d,{13{8'h00}}}, 3);
		if (video_enabled) $fatal(1, "E0 did not disable video");
		send({"A","1",8'h0d,{13{8'h00}}}, 3);
		if (!audio_1_enabled) $fatal(1, "A1 did not enable channel one");

		// Picture numbers are one based; DDV indices are zero based.
		send({"F","0","0","1","2","3","R",8'h0d,{8{8'h00}}}, 8);
		if (!frame_request || frame_index != 122) $fatal(1, "F00123R targeted %0d", frame_index);
		accept_and_show();
		if (current_picture != 123 || playing) $fatal(1, "still completion state is wrong");
		repeat (18) @(posedge clk);
		send({"?","F",8'h0d,{13{8'h00}}}, 3);
		for (n = 0; n < 5; n = n + 1) begin
			reply_index = n + 1; #1;
			case (n)
				0,1: if (reply_data != "0") $fatal(1, "?F leading digit");
				2: if (reply_data != "1") $fatal(1, "?F hundreds digit");
				3: if (reply_data != "2") $fatal(1, "?F tens digit");
				4: if (reply_data != "3") $fatal(1, "?F units digit");
			endcase
		end
		send({"+","1","2",8'h0d,{12{8'h00}}}, 4);
		if (frame_index != 134) $fatal(1, "+12 did not request picture 135");
		accept_and_show();
		send({"-","1","2",8'h0d,{12{8'h00}}}, 4);
		if (frame_index != 122) $fatal(1, "-12 did not return to picture 123");
		accept_and_show();

		send({"L",8'h0d,{14{8'h00}}}, 2);
		if (frame_index != 123) $fatal(1, "step forward did not request picture 124");
		accept_and_show();
		send({"N",8'h0d,{14{8'h00}}}, 2);
		if (!playing || reverse || frame_index != 124) $fatal(1, "forward play did not request next frame");
		accept_and_show();
		if (!frame_request || frame_index != 125) $fatal(1, "forward play did not continue");

		// A stop-register acknowledgement is withheld until the target picture
		// has actually become visible.
		frame_request_ack = 1; @(posedge clk); #1 frame_request_ack = 0;
		send({"F","0","0","2","0","0","S",8'h0d,{8{8'h00}}}, 8);
		reply_index = 0; #1; if (reply_data != 8'h0d) $fatal(1, "F...S replied before completion");
		accept_and_show();
		reply_index = 0; #1; if (reply_data != "A") $fatal(1, "F...S completion missing");
		reply_index = 1; #1; if (reply_data != "2") $fatal(1, "F...S completion was not A2");

		$display("PASS tb_vp415_player");
		$finish;
	end
endmodule
