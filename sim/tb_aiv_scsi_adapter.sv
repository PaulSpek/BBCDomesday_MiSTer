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
	reg [63:0] media_size = 64'd1048576; // 4096 logical 256-byte blocks
	wire media_read;
	wire [31:0] media_lba;
	reg media_ready = 1'b0;
	wire [8:0] media_addr;
	reg [7:0] media_data = 8'h5a;
	reg [7:0] byte_read;
	integer n;

	always #5 clk = ~clk;

	aiv_scsi_adapter dut (
		.clk(clk), .reset(reset), .cs(cs), .strobe(strobe), .rnw(rnw),
		.addr(addr), .din(din), .dout(dout),
		.media_present(media_present), .media_size(media_size),
		.media_read(media_read), .media_lba(media_lba), .media_ready(media_ready),
		.media_addr(media_addr), .media_data(media_data)
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
		if (dout[7:5] != 3'b001) $fatal(1, "WRITE F-Code is not data-out: status=%02x", dout);
		for (n = 0; n < 256; n = n + 1) begin
			wait_req(1'b1);
			fred_write(2'd0, n[7:0]);
			wait_req(1'b0);
		end
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
			if (byte_read != (n == 0 ? 8'h0d : 8'h00)) $fatal(1, "READ F-Code byte %0d", n);
		end
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ F-Code status");
		read_target_byte(byte_read); if (byte_read != 8'h00) $fatal(1, "READ F-Code message");

		$display("PASS tb_aiv_scsi_adapter");
		$finish;
	end
endmodule
