`timescale 1ns/1ps

module tb_domesday_bridge;
	reg clk = 0;
	reg img_mounted = 0;
	reg [63:0] img_size = 0;
	reg sd_ack = 0;
	reg [8:0] sd_buff_addr = 0;
	reg [7:0] sd_buff_dout = 0;
	reg sd_buff_wr = 0;
	wire disc_present;
	wire [63:0] disc_size;
	wire pvf_valid;
	wire pvf_error;
	wire [31:0] pvf_width;
	wire [31:0] pvf_height;
	wire [31:0] pvf_frames;
	wire [31:0] pvf_fps_num;
	wire [31:0] pvf_fps_den;
	wire [31:0] pvf_audio_hz;
	wire [31:0] sd_lba;
	wire sd_rd;

	reg [7:0] sector [0:511];
	integer n;

	always #5 clk = ~clk;

	domesday_bridge dut
	(
		.clk(clk), .img_mounted(img_mounted), .img_size(img_size),
		.disc_present(disc_present), .disc_size(disc_size),
		.pvf_valid(pvf_valid), .pvf_error(pvf_error),
		.pvf_width(pvf_width), .pvf_height(pvf_height),
		.pvf_frames(pvf_frames), .pvf_fps_num(pvf_fps_num),
		.pvf_fps_den(pvf_fps_den), .pvf_audio_hz(pvf_audio_hz),
		.sd_lba(sd_lba), .sd_blk_cnt(), .sd_rd(sd_rd), .sd_wr(),
		.sd_ack(sd_ack), .sd_buff_addr(sd_buff_addr),
		.sd_buff_dout(sd_buff_dout), .sd_buff_wr(sd_buff_wr),
		.sd_buff_din()
	);

	task put_u32(input integer offset, input [31:0] value);
	begin
		sector[offset + 0] = value[7:0];
		sector[offset + 1] = value[15:8];
		sector[offset + 2] = value[23:16];
		sector[offset + 3] = value[31:24];
	end
	endtask

	task mount_and_serve(input [63:0] size);
	begin
		img_size = size;
		img_mounted = 1'b1;
		@(posedge clk);
		#1 img_mounted = 1'b0;
		wait (sd_rd);
		if (sd_lba != 32'd0) $fatal(1, "header read did not target sector zero");
		@(posedge clk);
		sd_ack = 1'b1;
		@(posedge clk);
		for (n = 0; n < 512; n = n + 1) begin
			sd_buff_addr = n[8:0];
			sd_buff_dout = sector[n];
			sd_buff_wr = 1'b1;
			@(posedge clk);
		end
		sd_buff_wr = 1'b0;
		sd_ack = 1'b0;
		repeat (3) @(posedge clk);
	end
	endtask

	initial begin
		for (n = 0; n < 512; n = n + 1) sector[n] = 8'd0;
		// Header copied from the representative 3.4 GB Pi1MHz PVF.
		put_u32( 0, 32'h31465650); // PVF1
		put_u32( 4, 32'd1);
		put_u32( 8, 32'd832);
		put_u32(12, 32'd576);
		put_u32(16, 32'd25);
		put_u32(20, 32'd1);
		put_u32(24, 32'd54000);
		put_u32(28, 32'd48000);
		put_u32(32, 32'd2);
		put_u32(36, 32'd7680);
		put_u32(40, 32'd64);
		put_u32(44, 32'd216064);
		put_u32(48, 32'd132953);
		put_u32(52, 32'd12);
		put_u32(56, 32'd13);

		repeat (2) @(posedge clk);
		mount_and_serve(64'd3396845104);
		if (!disc_present || disc_size != 64'd3396845104)
			$fatal(1, "mount metadata was not latched");
		if (!pvf_valid || pvf_error)
			$fatal(1, "valid PVF header was rejected");
		if (pvf_width != 832 || pvf_height != 576 || pvf_frames != 54000 ||
		    pvf_fps_num != 25 || pvf_fps_den != 1 || pvf_audio_hz != 48000)
			$fatal(1, "PVF metadata was decoded incorrectly");

		// A fresh invalid mount must clear the previous valid state.
		sector[0] = 8'h00;
		mount_and_serve(64'd1024);
		if (pvf_valid || !pvf_error)
			$fatal(1, "invalid PVF magic was accepted");

		img_size = 0;
		img_mounted = 1'b1;
		@(posedge clk);
		#1 img_mounted = 1'b0;
		@(posedge clk);
		if (disc_present || disc_size != 0 || pvf_valid || pvf_error)
			$fatal(1, "unmount was not latched");

		$display("PASS tb_domesday_bridge");
		$finish;
	end
endmodule
