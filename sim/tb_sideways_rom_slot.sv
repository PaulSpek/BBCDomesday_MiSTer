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
        // Check all five lanes of every packed word, including bank boundaries
        // and the very last byte, at the original one-clock read latency.
        for (i = 0; i < 16384; i = i + 1) begin
            read_addr = i[13:0];
            @(negedge clk);
            if (read_data !== i[7:0]) $fatal(1, "Byte %h mismatch: %h", i, read_data);
        end
        file_index = 8'd5;
        send_byte(0, 8'h99);
        if (valid !== 1'b1) $fatal(1, "Other index modified slot");
        file_index = 8'd6;
        download = 1;
        send_byte(0, 8'h42);
        download = 0;
        @(negedge clk);
        if (valid !== 1'b0) $fatal(1, "Truncated ROM accepted");
        // A new complete upload must not reuse the partial word left behind
        // by the truncated upload. Also exercise consecutive ioctl writes.
        download = 1;
        for (i = 0; i < 16384; i = i + 1) begin
            write_enable = 1;
            write_addr = i;
            write_data = ~i[7:0];
            @(negedge clk);
        end
        write_enable = 0;
        download = 0;
        @(negedge clk);
        if (valid !== 1'b1) $fatal(1, "Replacement ROM rejected");
        for (i = 0; i < 16384; i = i + 1) begin
            read_addr = i[13:0];
            @(negedge clk);
            if (read_data !== ~i[7:0]) $fatal(1, "Replacement byte %h mismatch: %h", i, read_data);
        end
        $display("PASS tb_sideways_rom_slot");
        $finish;
    end
endmodule
