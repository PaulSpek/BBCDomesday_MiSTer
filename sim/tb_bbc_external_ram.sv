`timescale 1ns/1ps
module tb_bbc_external_ram;
    reg clk=0;
    always #5 clk=~clk;
    reg [18:0] address=0;
    reg [7:0] data_in=0;
    reg write_pulse=0;
    wire [7:0] data_out;
    bbc_external_ram dut(.*);
    integer bank, offset, pass;
    function automatic [7:0] pattern(input integer b, input integer a);
        pattern = (b * 29) ^ a[7:0] ^ a[13:8];
    endfunction
    task automatic access(input integer b, input integer a, input bit wr, input [7:0] value);
        @(negedge clk);
        address=19'h40000 + b*16384 + a;
        write_pulse=wr;
        data_in=value;
        @(posedge clk); #1;
    endtask
    initial begin
        // All bytes, including every bank boundary, must remain independent.
        for(bank=0;bank<13;bank=bank+1)
            for(offset=0;offset<16384;offset=offset+1)
                access(bank,offset,1,pattern(bank,offset));
        for(offset=0;offset<16384;offset=offset+1)
            for(bank=0;bank<13;bank=bank+1) begin
                access(bank,offset,0,0);
                if(data_out !== pattern(bank,offset))
                    $fatal(1,"bank %0d offset %0h got %0h",bank,offset,data_out);
            end
        // Alternate Tube/sideways/video access on consecutive memory clocks.
        // Unallocated RAM and ROM accesses must never alias a valid bank.
        for(bank=13;bank<16;bank=bank+1) begin
            access(bank,0,1,8'hFF);
            if(data_out !== 0) $fatal(1,"unallocated RAM exposed");
        end
        @(negedge clk); address=0; write_pulse=1; data_in=8'hFF;
        @(posedge clk); #1;
        if(data_out !== 0) $fatal(1,"ROM access exposed RAM");
        access(0,0,0,0);
        if(data_out !== pattern(0,0)) $fatal(1,"invalid access corrupted Tube");
        $display("PASS tb_bbc_external_ram: all 13 banks, isolation and alternating owners");
        $finish;
    end
endmodule
