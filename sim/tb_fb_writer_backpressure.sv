`timescale 1ns/1ps
module tb_fb_writer_backpressure;
reg clk=0, reset=1, px_we=0, fill_idle=1;
reg [15:0] px_x=0, px_y=0;
reg [7:0] px_r=0, px_g=0, px_b=0;
wire px_ready;
wire [27:1] wraddr;
wire [63:0] din64;
wire [7:0] be64;
wire we_req;
reg we_ack=0;
integer delay_q=0, writes=0, stalled=0, i;
reg last_req=0;
reg [27:1] seen_addr [0:1];
reg [63:0] seen_data [0:1];
reg [7:0] seen_be [0:1];
always #5 clk=~clk;

fb_writer #(.STRIDE_HW(16'd8), .CLEAR_ON_RESET(1'b0),
            .FB_COLS(16'd8), .FB_ROWS(16'd1), .COALESCE(1'b1)) dut (
 .clk(clk), .reset(reset), .base_hw(27'd0), .fill_idle(fill_idle),
 .px_we(px_we), .px_x(px_x), .px_y(px_y),
 .px_r(px_r), .px_g(px_g), .px_b(px_b), .px_ready(px_ready),
 .wraddr(wraddr), .din(), .din64(din64), .be64(be64),
 .we_req(we_req), .we_ack(we_ack));

function [15:0] rgb565(input [7:0] n);
 begin rgb565={n[7:3],n[7:2],n[7:3]}; end
endfunction

// Deliberately slow DDR acknowledgement. The producer must remain stalled
// while a write is in flight, and no pixel may be dropped or duplicated.
always @(posedge clk) begin
 if(reset) begin we_ack<=0; last_req<=0; delay_q<=0; end
 else begin
  if(we_req != last_req) begin
   if(writes>1) $fatal(1,"too many DDR writes");
   seen_addr[writes] <= wraddr;
   seen_data[writes] <= din64;
   seen_be[writes] <= be64;
   writes <= writes+1;
   last_req <= we_req;
   delay_q <= 6;
  end else if(delay_q>1) delay_q<=delay_q-1;
  else if(delay_q==1) begin we_ack<=we_req; delay_q<=0; end
  if(we_req!=we_ack && !px_ready) stalled<=stalled+1;
 end
end

task send_pixel(input integer x);
 begin
  while(!px_ready) @(posedge clk);
  @(negedge clk);
  px_x=x; px_y=0; px_r=8'h20+x; px_g=8'h20+x; px_b=8'h20+x;
  px_we=1;
  @(negedge clk); px_we=0;
 end
endtask

reg [63:0] exp0, exp1;
initial begin
 repeat(4) @(posedge clk); @(negedge clk); reset=0;
 for(i=0;i<8;i=i+1) send_pixel(i);
 repeat(300) @(posedge clk);
 exp0={rgb565(8'h23),rgb565(8'h22),rgb565(8'h21),rgb565(8'h20)};
 exp1={rgb565(8'h27),rgb565(8'h26),rgb565(8'h25),rgb565(8'h24)};
 if(writes!=2) $fatal(1,"write count=%0d expected=2",writes);
 if(seen_addr[0]!==0 || seen_addr[1]!==4) $fatal(1,"addresses %0d %0d",seen_addr[0],seen_addr[1]);
 if(seen_be[0]!==8'hff || seen_be[1]!==8'hff) $fatal(1,"byte enables %02x %02x",seen_be[0],seen_be[1]);
 if(seen_data[0]!==exp0 || seen_data[1]!==exp1) $fatal(1,"coalesced data mismatch");
 if(stalled<5) $fatal(1,"DDR backpressure was not exercised");
 $display("PASS tb_fb_writer_backpressure: 8 pixels, 2 coalesced writes, %0d stalled cycles",stalled);
 $finish;
end
initial begin #100000; $fatal(1,"timeout"); end
endmodule
