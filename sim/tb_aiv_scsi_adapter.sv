`timescale 1ns/1ps

// Bus-level regression for the AIV SCSI target.  The BBC side uses one
// explicit strobe per 1 MHz FRED access; status reads are combinational.
module tb_aiv_scsi_adapter;
	reg clk = 1'b0;
	reg reset = 1'b1;
	reg cs = 1'b1;
	reg strobe = 1'b0;
	reg rnw = 1'b1;
	reg [1:0] addr = 2'd1;
	reg [7:0] din = 8'h00;
	wire [7:0] dout;
	reg media_present = 1'b1;
	reg video_present = 1'b1;
	reg [63:0] media_size = 64'd1048576; // 4096 logical 256-byte blocks
	wire media_read;
	wire [31:0] media_lba;
	reg media_ready = 1'b0;
	wire [8:0] media_addr;
	reg [7:0] media_data = 8'h5a;
	wire irq;
	wire fcode_command_write;
	wire [8:0] fcode_command_index;
	wire [7:0] fcode_command_data;
	wire fcode_command_commit;
	wire [8:0] fcode_reply_index;
	wire [7:0] fcode_reply_data;
	reg [7:0] byte_read;
	integer n;

	always #5 clk = ~clk;

	aiv_scsi_adapter dut (
		.clk(clk), .reset(reset), .cs(cs), .strobe(strobe), .rnw(rnw),
		.addr(addr), .din(din), .dout(dout),
		.media_present(media_present), .media_size(media_size),
		.video_present(video_present),
		.fcode_command_write(fcode_command_write),
		.fcode_command_index(fcode_command_index),
		.fcode_command_data(fcode_command_data),
		.fcode_command_commit(fcode_command_commit),
		.fcode_reply_index(fcode_reply_index), .fcode_reply_data(fcode_reply_data),
		.media_read(media_read), .media_lba(media_lba), .media_ready(media_ready),
		.media_addr(media_addr), .media_data(media_data), .irq(irq)
	);

	vp415_player player (
		.clk(clk), .reset(reset), .media_present(video_present), .frame_count(32'd1000),
		.command_write(fcode_command_write), .command_index(fcode_command_index),
		.command_data(fcode_command_data), .command_commit(fcode_command_commit),
		.reply_index(fcode_reply_index), .reply_data(fcode_reply_data),
		.frame_request(), .frame_index(), .frame_request_ack(1'b0),
		.frame_presented(1'b0), .vp_mode(), .video_enabled(),
		.audio_1_enabled(), .audio_2_enabled(), .playing(), .reverse(),
		.current_picture()
	);

	task automatic wait_req(input bit wanted);
		integer timeout;
		begin
			addr = 2'd1;
			rnw = 1'b1;
			strobe = 1'b0;
			timeout = 0;
			while (dout[5] !== wanted) begin
				@(posedge clk);
				timeout = timeout + 1;
				if (timeout > 200) $fatal(1, "REQ did not become %0d; status=%02x", wanted, dout);
			end
		end
	endtask

	task automatic fred_write(input [1:0] register_address, input [7:0] value);
		begin
			addr = register_address;
			rnw = 1'b0;
			din = value;
			strobe = 1'b1;
			@(posedge clk);
			#1 strobe = 1'b0;
		end
	endtask

	task automatic write_command_byte(input [7:0] value);
		begin
			wait_req(1'b1);
			fred_write(2'd0, value);
			wait_req(1'b0);
		end
	endtask

	task automatic read_target_byte(output [7:0] value);
		begin
			wait_req(1'b1);
			addr = 2'd0;
			rnw = 1'b1;
			strobe = 1'b1;
			#1 value = dout;
			@(posedge clk);
			#1 strobe = 1'b0;
			wait_req(1'b0);
		end
	endtask

	task automatic write_fcode(
		input [7:0] b0, input [7:0] b1, input [7:0] b2,
		input [7:0] b3, input [7:0] b4
	);
		begin
			fred_write(2'd2, 8'h10);
			write_command_byte(8'hca);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			for (n = 0; n < 256; n = n + 1) begin
				wait_req(1'b1);
				fred_write(2'd0, (n == 0) ? b0 : (n == 1) ? b1 :
					(n == 2) ? b2 : (n == 3) ? b3 : (n == 4) ? b4 : 8'h00);
				wait_req(1'b0);
			end
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "menu WRITE F-Code status");
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "menu WRITE F-Code message");
		end
	endtask

	// kind 0=T title, 1=V0 video-only, 2=Y description, 3=X absent.
	task automatic read_menu_reply(input integer kind);
		begin
			fred_write(2'd2, 8'h10);
			write_command_byte(8'hc8);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			for (n = 0; n < 256; n = n + 1) begin
				read_target_byte(byte_read);
				case (kind)
					0: begin
						if (n == 0 && byte_read != "T") $fatal(1, "?T1 tag");
						if (n == 1 && byte_read != "M") $fatal(1, "?T1 title");
						if (n == 17 && byte_read != 8'h0d) $fatal(1, "?T1 terminator");
						if (n > 17 && byte_read != 8'h00) $fatal(1, "?T1 padding");
					end
					1: case (n)
						0: if (byte_read != "V") $fatal(1, "?V1 tag");
						1: if (byte_read != "0") $fatal(1, "?V1 video-only flag");
						2: if (byte_read != 8'h0d) $fatal(1, "?V1 terminator");
						default: if (byte_read != 8'h00) $fatal(1, "?V1 padding");
					endcase
					2: begin
						if (n == 0 && byte_read != "Y") $fatal(1, "?Y1 tag");
						if (n == 1 && byte_read != "M") $fatal(1, "?Y1 description");
						if (n == 22 && byte_read != 8'h0d) $fatal(1, "?Y1 terminator");
						if (n > 22 && byte_read != 8'h00) $fatal(1, "?Y1 padding");
					end
					3: case (n)
						0: if (byte_read != "X") $fatal(1, "absent directory tag");
						1: if (byte_read != 8'h0d) $fatal(1, "absent directory terminator");
						default: if (byte_read != 8'h00) $fatal(1, "absent directory padding");
					endcase
				endcase
			end
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "menu READ F-Code status");
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "menu READ F-Code message");
		end
	endtask

	task automatic read_player_status(input [7:0] expected_loaded);
		begin
			fred_write(2'd2, 8'h10);
			write_command_byte(8'hc8);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			write_command_byte(8'h00);
			for (n = 0; n < 256; n = n + 1) begin
				read_target_byte(byte_read);
				case (n)
					0: if (byte_read != "P") $fatal(1, "?P tag");
					1: if (byte_read != expected_loaded) $fatal(1, "?P loaded flag");
					2, 3: if (byte_read != 8'h41) $fatal(1, "?P CAV/frame-lock flag");
					4, 5: if (byte_read != 8'h40) $fatal(1, "?P player flag");
					6: if (byte_read != 8'h0d) $fatal(1, "?P terminator");
					default: if (byte_read != 8'h00) $fatal(1, "?P padding");
				endcase
			end
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "?P READ status");
			read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "?P READ message");
		end
	endtask

	initial begin
		repeat (3) @(posedge clk);
		reset = 1'b0;
		repeat (2) @(posedge clk);

		// Select the AIV target, then send READ CAPACITY(10).  The seventh
		// through tenth bytes must still see command phase (C/D set, I/O clear).
		fred_write(2'd2, 8'h10);
		write_command_byte(8'h25);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		wait_req(1'b1);
		if (dout[7:6] != 2'b10) $fatal(1, "READ CAPACITY left command phase after six bytes: status=%02x", dout);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);

		// 4096 blocks means the last address is 4095; logical block size is 256.
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "capacity byte 0");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "capacity byte 1");
		read_target_byte(byte_read); if (byte_read != 8'h0f) $fatal(1, "capacity byte 2");
		read_target_byte(byte_read); if (byte_read != 8'hff) $fatal(1, "capacity byte 3");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "block size byte 0");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "block size byte 1");
		read_target_byte(byte_read); if (byte_read != 8'h01) $fatal(1, "block size byte 2");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "block size byte 3");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ CAPACITY status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ CAPACITY message");

		// READ(6) requests one 256-byte logical block.  Block one is the
		// second half of MiSTer's sector zero, so this also proves the
		// 256-to-512 block conversion at the media boundary.
		fred_write(2'd2, 8'h10);
		write_command_byte(8'h08);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h01);
		write_command_byte(8'h01);
		write_command_byte(8'h00);
		wait (media_read);
		if (media_lba != 32'd0 || media_addr != 9'd256)
			$fatal(1, "READ(6) did not select the expected cache half");
		@(posedge clk);
		media_ready = 1'b1;
		@(posedge clk);
		media_ready = 1'b0;
		for (n = 0; n < 256; n = n + 1) begin
			read_target_byte(byte_read);
			if (byte_read != 8'h5a) $fatal(1, "READ(6) data byte %0d", n);
		end
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ(6) status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ(6) message");

		// VFS probes the VP415 player using group-6 F-code commands.  WRITE
		// F-code is target data-out; READ F-code returns an empty CR-padded
		// reply.  Both transfers must be exactly one 256-byte block.
		fred_write(2'd2, 8'h10);
		write_command_byte(8'hca);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		wait_req(1'b1);
		if (dout[7:5] != 3'b001) $fatal(1, "WRITE F-Code is not data-out: status=%02x", dout);
		for (n = 0; n < 256; n = n + 1) begin
			wait_req(1'b1);
			fred_write(2'd0, (n == 0) ? "?" : (n == 1) ? "P" : (n == 2) ? 8'h0d : 8'h00);
			wait_req(1'b0);
		end
		// FC42/FC43 readbacks are temporary hardware-diagnostic visibility:
		// the final F-code byte must be the sole transition to STATUS.
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "WRITE F-Code status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "WRITE F-Code message");

		fred_write(2'd2, 8'h10);
		write_command_byte(8'hc8);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		for (n = 0; n < 256; n = n + 1) begin
			read_target_byte(byte_read);
			case (n)
				0: if (byte_read != "P") $fatal(1, "READ F-Code status tag: got %02x", byte_read);
				1: if (byte_read != 8'h60) $fatal(1, "READ F-Code loaded flag");
				2, 3: if (byte_read != 8'h41) $fatal(1, "READ F-Code CAV/frame-lock flag");
				4, 5: if (byte_read != 8'h40) $fatal(1, "READ F-Code player flag");
				6: if (byte_read != 8'h0d) $fatal(1, "READ F-Code terminator");
				default: if (byte_read != 8'h00) $fatal(1, "READ F-Code padding byte %0d", n);
			endcase
		end
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ F-Code status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ F-Code message");

		// The Pi1MHz LaserVision menu scans directories 1-49 with ?T/?V/?Y.
		// A validated playback mount is published as one video-only disc in
		// directory 1; all other or malformed directory numbers return X.
		write_fcode("?", "T", "1", 8'h0d, 8'h00); read_menu_reply(0);
		write_fcode("?", "V", "1", 8'h0d, 8'h00); read_menu_reply(1);
		write_fcode("?", "Y", "1", 8'h0d, 8'h00); read_menu_reply(2);
		write_fcode("?", "T", "2", 8'h0d, 8'h00); read_menu_reply(3);
		write_fcode("?", "T", "1", "0", 8'h0d); read_menu_reply(3);
		video_present = 1'b0;
		write_fcode("?", "T", "1", 8'h0d, 8'h00); read_menu_reply(3);
		write_fcode("?", "P", 8'h0d, 8'h00, 8'h00); read_player_status(8'h40);
		video_present = 1'b1;

		// Ctrl+Break may arrive in the middle of an unbounded VFS handshake.
		// It must return the external adapter to BUS FREE so the next SELECT
		// begins a clean command rather than continuing the abandoned CDB.
		fred_write(2'd2, 8'h10);
		write_command_byte(8'h08);
		write_command_byte(8'h00);
		reset = 1'b1;
		repeat (2) @(posedge clk);
		reset = 1'b0;
		repeat (2) @(posedge clk);
		addr = 2'd1;
		rnw = 1'b1;
		if (dout != 8'h00) $fatal(1, "Ctrl+Break did not return SCSI bus free: status=%02x", dout);
		fred_write(2'd2, 8'h10);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		write_command_byte(8'h00);
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "post-reset TUR status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "post-reset TUR message");

		$display("PASS tb_aiv_scsi_adapter");
		$finish;
	end
endmodule
