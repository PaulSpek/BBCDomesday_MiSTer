`timescale 1ns/1ps

module tb_domesday_bridge;
	reg clk = 0;
	reg img_mounted = 0;
	reg [63:0] img_size = 0;
	wire disc_present;
	wire [63:0] disc_size;

	always #5 clk = ~clk;

	domesday_bridge dut
	(
		.clk(clk), .img_mounted(img_mounted), .img_size(img_size),
		.disc_present(disc_present), .disc_size(disc_size),
		.sd_lba(), .sd_blk_cnt(), .sd_rd(), .sd_wr(),
		.sd_ack(1'b0), .sd_buff_addr(9'd0), .sd_buff_dout(8'd0),
		.sd_buff_wr(1'b0), .sd_buff_din()
	);

	initial begin
		repeat (2) @(posedge clk);
		img_size <= 64'd123456789;
		img_mounted <= 1;
		@(posedge clk);
		img_mounted <= 0;
		@(posedge clk);
		if (!disc_present || disc_size != 64'd123456789) $fatal(1, "mount was not latched");

		img_size <= 0;
		img_mounted <= 1;
		@(posedge clk);
		img_mounted <= 0;
		@(posedge clk);
		if (disc_present || disc_size != 0) $fatal(1, "unmount was not latched");

		$display("PASS tb_domesday_bridge");
		$finish;
	end
endmodule
