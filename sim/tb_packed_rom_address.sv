`timescale 1ns/1ps
module tb_packed_rom_address;
    reg clk=0;
    always #5 clk=~clk;
    reg [17:0] address=0;
    wire [15:0] word_address;
    wire [2:0] byte_lane;
    packed_rom_address dut(.*);
    integer a;
    initial begin
        @(negedge clk);
        // Change address every cycle, checking the previous input after
        // the two register stages. Covers all quotient/remainder boundaries.
        for(a=0; a<262145; a=a+1) begin
            address=a;
            @(negedge clk);
            if(a>0 && (word_address !== (a-1)/5 || byte_lane !== (a-1)%5))
                $fatal(1,"address %h quotient %h lane %h",a-1,word_address,byte_lane);
        end
        $display("PASS tb_packed_rom_address: exact pipelined division for all 18-bit addresses");
        $finish;
    end
endmodule
