`timescale 1ns/1ps
module tb_jpeg_color_pipeline;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, flush=0, in_valid=0, mono=0, out_accept=1;
    reg signed [31:0] y=0, cb=0, cr=0;
    reg [15:0] x=0, y_pos=0;
    wire in_accept, out_valid, busy;
    wire [15:0] x_out, y_out;
    wire [7:0] r,g,b;
    jpeg_color_pipeline dut (
        .clk_i(clk), .rst_i(rst), .flush_i(flush),
        .in_valid_i(in_valid), .mono_i(mono), .y_i(y), .cb_i(cb), .cr_i(cr),
        .x_i(x), .y_pos_i(y_pos), .in_accept_o(in_accept),
        .out_accept_i(out_accept), .out_valid_o(out_valid),
        .x_o(x_out), .y_pos_o(y_out), .r_o(r), .g_o(g), .b_o(b), .busy_o(busy)
    );
    reg [55:0] expected [0:20000];
    integer wr=0, rd=0, cycles=0, checked=0;
    reg [31:0] random_state=32'h568AF971;
    reg stalled=0;
    reg [55:0] held;
    function automatic [7:0] clip(input signed [31:0] v);
        clip=(|v[31:8]) ? (v[31:24]^8'hFF) : v[7:0];
    endfunction
    function automatic [23:0] reference_rgb(input signed [31:0] yy,cc,rr, input mm);
        reg signed [31:0] r1,g1,g2,b1;
        begin
            r1=rr*5743; r1=r1>>>12;
            g1=cc*1410; g1=g1>>>12;
            g2=rr*2925; g2=g2>>>12;
            b1=cc*7258; b1=b1>>>12;
            reference_rgb=mm ? {clip(128+yy),clip(128+yy),clip(128+yy)} :
                {clip(128+yy+r1),clip(128+yy-g1-g2),clip(128+yy+b1)};
        end
    endfunction
    always @(posedge clk) begin
        if (rst || flush) begin
            wr=0; rd=0; stalled=0;
        end else begin
            if (stalled && (!out_valid || {x_out,y_out,r,g,b} !== held))
                $fatal(1,"output changed during backpressure");
            if (out_valid && out_accept) begin
                if (rd>=wr || {x_out,y_out,r,g,b} !== expected[rd])
                    $fatal(1,"RGB/coordinates mismatch at %0d got=%h expected=%h",rd,{x_out,y_out,r,g,b},expected[rd]);
                rd=rd+1; checked=checked+1;
            end
            if (in_valid && in_accept) begin
                expected[wr]={x,y_pos,reference_rgb(y,cb,cr,mono)};
                wr=wr+1;
            end
            stalled=out_valid && !out_accept;
            held={x_out,y_out,r,g,b};
        end
    end
    initial begin
        repeat(3) @(negedge clk);
        rst=0;
        for(cycles=0;cycles<12000;cycles=cycles+1) begin
            random_state=random_state ^ (random_state<<13);
            random_state=random_state ^ (random_state>>17);
            random_state=random_state ^ (random_state<<5);
            flush=(cycles==4000 || cycles==8000);
            out_accept=!(cycles%41<15) && random_state[1];
            in_valid=(cycles%7!=0);
            mono=(cycles<256 || random_state[2:0]==0);
            x=cycles; y_pos=cycles^16'hA913;
            if(cycles<256) begin y=cycles-128; cb=0; cr=0; end
            else if(random_state[5:4]==0) begin
                // Overflow cases verify the old 32-bit arithmetic exactly.
                y=random_state; cb=~random_state; cr=random_state^32'h7359A3D1;
            end else begin
                y=$signed({1'b0,random_state[9:0]})-512;
                cb=$signed({1'b0,random_state[19:10]})-512;
                cr=$signed({1'b0,random_state[29:20]})-512;
            end
            @(negedge clk);
        end
        in_valid=0; flush=0; out_accept=1;
        repeat(8) @(negedge clk);
        if(busy || rd!=wr || checked<1000) $fatal(1,"pipeline did not drain");
        $display("PASS tb_jpeg_color_pipeline: %0d bit-exact pixels, stalls, flush, coordinates",checked);
        $finish;
    end
endmodule
