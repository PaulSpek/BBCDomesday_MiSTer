`timescale 1ns/1ps
module tb_sideways_rom_slot;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [13:0] read_addr = 0;
    wire [7:0] read_data;
    wire valid, loading;
    reg download = 0;
    reg [7:0] file_index = 0;
    reg write_enable = 0;
    reg [24:0] write_addr = 0;
    reg [7:0] write_data = 0;
    integer i;

    sideways_rom_slot #(.FILE_INDEX(8'd6), .INIT_FILE("roms/empty_sideways.mif"),
        .DEFAULT_VALID(1'b1)) dut (.*);

    task automatic send_byte(input integer address, input [7:0] value);
        begin
            @(negedge clk);
            write_enable = 1;
            write_addr = address;
            write_data = value;
            @(negedge clk);
            write_enable = 0;
        end
    endtask

    initial begin
        @(negedge clk);
        if (valid !== 1'b1) $fatal(1, "Built-in ROM unavailable");
        file_index = 8'd6;
        download = 1;
        for (i = 0; i < 16384; i = i + 1) send_byte(i, i[7:0]);
        download = 0;
        @(negedge clk);
        if (valid !== 1'b1) $fatal(1, "Full 16 KiB load rejected");
        read_addr = 14'h0123;
        repeat (2) @(negedge clk);
        if (read_data !== 8'h23) $fatal(1, "Loaded byte mismatch: %h", read_data);
        file_index = 8'd5;
        send_byte(0, 8'h99);
        if (valid !== 1'b1) $fatal(1, "Other index modified slot");
        file_index = 8'd6;
        download = 1;
        send_byte(0, 8'h42);
        download = 0;
        @(negedge clk);
        if (valid !== 1'b0) $fatal(1, "Truncated ROM accepted");
        $display("PASS tb_sideways_rom_slot");
        $finish;
    end
endmodule
