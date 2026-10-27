`timescale 1ns/1ps
// Exercise the new stages through the real Y/Cb/Cr FIFOs and block sequencer.
module tb_jpeg_output_pipeline;
    reg clk=0;
    always #5 clk=~clk;
    reg rst=1, start=0, input_valid=0, accept=1;
    reg [1:0] mode=0;
    reg [31:0] data=0, id=0;
    reg [5:0] idx=0;
    wire input_ready, valid, idle;
    wire [15:0] width,height,x,y;
    wire [7:0] r,g,b;
    jpeg_output dut (
        .clk_i(clk), .rst_i(rst), .img_start_i(start), .img_end_i(1'b0),
        .img_width_i(16'd32), .img_height_i(16'd32), .img_mode_i(mode),
        .inport_valid_i(input_valid), .inport_data_i(data),
        .inport_idx_i(idx), .inport_id_i(id), .outport_accept_i(accept),
        .inport_accept_o(input_ready), .outport_valid_o(valid),
        .outport_width_o(width), .outport_height_o(height),
        .outport_pixel_x_o(x), .outport_pixel_y_o(y),
        .outport_pixel_r_o(r), .outport_pixel_g_o(g), .outport_pixel_b_o(b),
        .idle_o(idle)
    );
    integer tick=0, received=0, target=0, block_no, pos, sample_y, expected_x, expected_y;
    reg checking=0;
    reg [23:0] expected_rgb;
    function automatic [7:0] clip(input integer v);
        clip=(v<0) ? 0 : (v>255 ? 255 : v);
    endfunction
    function automatic [23:0] rgb(input integer yy, input bit mono);
        rgb=mono ? {clip(128+yy),clip(128+yy),clip(128+yy)} :
            {clip(128+yy+((25*5743)>>>12)),
             clip(128+yy-((-12*1410)>>>12)-((25*2925)>>>12)),
             clip(128+yy+((-12*7258)>>>12))};
    endfunction
    always @(negedge clk) begin
        tick=tick+1;
        accept=(tick%29>=11); // long stalls spanning MCU/block boundaries
    end
    always @(posedge clk) if(checking && !rst && !start) begin
        if(valid && accept) begin
            block_no=received/64;
            pos=received%64;
            sample_y=(mode==0) ? pos*4-128 : (mode==1 ? -70+pos*2 : -40+block_no*30);
            expected_x=(mode==2 ? (block_no%2)*8 : 16)+(pos%8);
            expected_y=(mode==2 ? (block_no/2)*8 : 24)+(pos/8);
            expected_rgb=rgb(sample_y,mode==0);
            if(received>=target || x!=expected_x || y!=expected_y || {r,g,b}!==expected_rgb)
                $fatal(1,"mode %0d pixel %0d xy=%0d,%0d RGB=%h expected xy=%0d,%0d RGB=%h",mode,received,x,y,{r,g,b},expected_x,expected_y,expected_rgb);
            received=received+1;
        end
        if(idle && received<target)
            $fatal(1,"idle asserted before all pixels drained: %0d/%0d",received,target);
    end
    task automatic send_block(input integer kind, input integer block_x, input integer block_y, input integer luma);
        integer i;
        begin
            // core_jpeg's IDCT reserves space at block START; after that
            // its 64 coefficients arrive without per-coefficient ready.
            while(!input_ready) @(negedge clk);
            for(i=0;i<64;i=i+1) begin
                input_valid=1;
                id=(kind<<30)|(block_y<<16)|block_x;
                idx=i;
                data=(kind==1) ? -12 : (kind==2) ? 25 :
                     mode==0 ? i*4-128 : mode==1 ? -70+i*2 : luma;
                @(negedge clk);
            end
            input_valid=0;
        end
    endtask
    task automatic run_case(input integer m);
        integer block_index, timeout;
        begin
            checking=0; mode=m; start=1; input_valid=0;
            repeat(3) @(negedge clk);
            start=0; received=0; target=(m==2 ? 256 : 64); checking=1;
            if(m==2) begin
                for(block_index=0;block_index<4;block_index=block_index+1)
                    send_block(0,block_index%2,block_index/2,-40+block_index*30);
            end else send_block(0,2,3,0);
            if(m!=0) begin send_block(1,0,0,0); send_block(2,0,0,0); end
            // The EOF marker follows the final Y block in the ID FIFO.
            while(!input_ready) @(negedge clk);
            input_valid=1; id=32'hC0000000; idx=0; data=0;
            @(negedge clk); input_valid=0;
            timeout=0;
            while((received!=target || !idle) && timeout<3000) begin
                @(negedge clk); timeout=timeout+1;
            end
            if(received!=target || !idle) $fatal(1,"mode %0d timeout %0d/%0d",m,received,target);
            repeat(8) @(negedge clk);
            checking=0;
            $display("PASS tb_jpeg_output_pipeline mode=%0d pixels=%0d",m,received);
        end
    endtask
    initial begin
        fork
            begin #1000000; $fatal(1,"JPEG output integration timeout"); end
        join_none
        repeat(4) @(negedge clk); rst=0;
        run_case(0); run_case(1); run_case(2);
        $finish;
    end
endmodule
