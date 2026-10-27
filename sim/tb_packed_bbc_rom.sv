`timescale 1ns/1ps
module tb_packed_bbc_rom;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [17:0] read_addr = 0, write_addr = 0;
    reg write_enable = 0;
    reg [7:0] write_data = 0;
    wire [7:0] read_data;
    packed_bbc_rom dut(.*);
    integer address;
    function automatic [7:0] pattern(input integer a);
        pattern = a[7:0] ^ a[15:8] ^ {6'd0,a[17:16]} ^ 8'hA7;
    endfunction
    initial begin
        @(negedge clk);
        for (address=0; address<262144; address=address+1) begin
            write_addr=address; write_data=pattern(address); write_enable=1;
            @(negedge clk);
            // ioctl_wr is a strobe, not a continuous download indicator.
            write_enable=0;
            repeat ((address % 3) + 1) @(negedge clk);
        end
        for (address=0; address<262144; address=address+1) begin
            read_addr=address; repeat (3) @(negedge clk);
            if (read_data !== pattern(address))
                $fatal(1,"ROM address %h got %h expected %h",address,read_data,pattern(address));
        end
        $display("PASS tb_packed_bbc_rom: all bytes, gapped uploads and final partial word");
        $finish;
    end
endmodule
