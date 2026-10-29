`timescale 1ns/1ps
module tb_domesday_field;
reg clk=0, reset=1, field=0, hb=1, vb=1;
always #5 clk=~clk;
domesday_video dut(
 .clk(clk), .reset(reset), .jpeg_byte(8'd0), .jpeg_valid(1'b0),
 .jpeg_last(1'b0), .jpeg_reset(1'b0), .ce_grid(1'b0),
 .bbc_r(4'd0), .bbc_g(4'd0), .bbc_b(4'd0),
 .bbc_hblank(hb), .bbc_vblank(vb), .bbc_hsync(1'b0),
 .bbc_vsync(1'b0), .odd_field(field), .vp_mode(3'd3),
 .laser_video_enabled(1'b1), .DDRAM_BUSY(1'b1),
 .DDRAM_DOUT(64'd0), .DDRAM_DOUT_READY(1'b0),
 .jpeg_ready(), .jpeg_next_frame(), .video_r(), .video_g(), .video_b(),
 .picture_ready(), .DDRAM_BURSTCNT(), .DDRAM_ADDR(), .DDRAM_RD(),
 .DDRAM_DIN(), .DDRAM_BE(), .DDRAM_WE());
integer b, f, y, expected, checked=0;
task tick; begin @(posedge clk); #1; end endtask
initial begin
 repeat(4) tick();
 @(negedge clk); reset=0;
 // Isolate scanline addressing from the decoder/DDR transfer handshake.
 force dut.shown=1'b1;
 for(b=0;b<3;b=b+1) begin
  dut.disp_idx=b;
  for(f=0;f<2;f=f+1) begin
   @(negedge clk); vb=1; hb=1;
   // Model a parity transition after the delayed BBC clock edge.
   #2; field=f;
   repeat(4) tick();
   @(negedge clk); vb=0;
   // One parent-clock boundary register precedes edge detection.
   repeat(2) tick();
   for(y=0;y<256;y=y+1) begin
    expected=b*479232+(32+2*y+f)*832;
    if(dut.fetch_base !== expected || dut.rdaddr2 !== expected)
      $fatal(1,"field address b=%0d f=%0d y=%0d got=%0d expected=%0d",b,f,y,dut.fetch_base,expected);
    if(dut.fetch_bank !== (y%2)) $fatal(1,"scanline bank mismatch");
    checked=checked+1;
    @(negedge clk); hb=0; repeat(2) tick();
    @(negedge clk); hb=1; repeat(2) tick();
   end
  end
 end
 $display("PASS tb_domesday_field: %0d scanline addresses, both fields and three buffers",checked);
 $finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
