`timescale 1ns/1ps
// Execute the actual diagnostic ROM on the production Master CPU and its
// clock-enable equations. RAM is ideal; MOS character calls use RTS stubs.
// This tests the CPU/AIV timing boundary, not a complete BBC/MOS boot.
module tb_aiv_scsi_cpu;
    parameter LEGACY_STROBE = 0;
    parameter INITIAL_PHASE = 0;
    reg clk = 0;
    always #5 clk = ~clk; // 96:48 ratio; time scaled by 0.96
    reg ce48 = 0;
    always @(negedge clk) ce48 <= ~ce48;
    wire clk48 = clk & ce48;
    reg reset_n = 0;
    wire [15:0] cpu_a;
    wire [7:0] cpu_do;
    wire cpu_rnw, cpu_en, bus_en, cpu_sync;
    wire [63:0] regs;
    reg [7:0] memory [0:65535];
    wire cs = cpu_a[15:2] == (16'hFC40 >> 2);
    wire cs_q, strobe_q, rnw_q;
    wire [1:0] addr_q;
    wire [7:0] din_q;
    aiv_scsi_bus_register scsi_bus (
        .clk(clk48), .reset(!reset_n), .cs(cs), .strobe(cs && cpu_en),
        .rnw(cpu_rnw), .addr(cpu_a[1:0]), .din(cpu_do),
        .cs_q(cs_q), .strobe_q(strobe_q), .rnw_q(rnw_q),
        .addr_q(addr_q), .din_q(din_q)
    );
    wire strobe = LEGACY_STROBE ? (cs && bus_en) : (strobe_q && ce48);
    wire adapter_cs = LEGACY_STROBE ? cs : cs_q;
    wire adapter_rnw = LEGACY_STROBE ? cpu_rnw : rnw_q;
    wire [1:0] adapter_addr = LEGACY_STROBE ? cpu_a[1:0] : addr_q;
    wire [7:0] adapter_din = LEGACY_STROBE ? cpu_do : din_q;
    wire [7:0] dout;
    wire [7:0] cpu_di = !cpu_rnw ? cpu_do : cs ? dout : memory[cpu_a];
    wire media_read;
    wire [31:0] media_lba;
    wire [8:0] media_addr;
    wire [7:0] media_data = media_addr[7:0];
    integer cpu_writes = 0, accepted = 0;
    integer payload_writes = 0, payload_reads = 0;
    integer cdb_trace = 0;
    reg [15:0] last_pc = 0;

    bbc_scsi_cpu_timing #(.INITIAL_PHASE(INITIAL_PHASE)) cpu(
        .clock_48(clk48), .reset_n(reset_n), .di(cpu_di), .addr(cpu_a),
        .dout(cpu_do), .rnw(cpu_rnw), .cpu_enable(cpu_en),
        .bus_enable(bus_en), .opcode_sync(cpu_sync), .regs(regs));
    aiv_scsi_adapter dut(
        .clk(clk), .reset(!reset_n), .cs(adapter_cs), .strobe(strobe),
        .rnw(adapter_rnw), .addr(adapter_addr), .din(adapter_din), .dout(dout),
        .media_present(1'b1), .media_size(64'd2359552), .video_present(1'b1),
        .media_read(media_read), .media_lba(media_lba),
        .media_ready(1'b1), .media_addr(media_addr),
        .media_data(media_data), .irq());

    always @(posedge clk) if (reset_n && strobe && adapter_cs && !adapter_rnw && adapter_addr == 0 && dut.req_asserted) begin
        accepted = accepted + 1;
        if (dut.phase == 7) payload_writes = payload_writes + 1;
        if (dut.phase == 1 && cdb_trace < 40) begin
            $display("CDB time=%0t accepted=%0d index=%0d byte=%02x CPUwrites=%0d pc=%04x", $time, accepted, dut.cdb_count, adapter_din, cpu_writes, last_pc);
            cdb_trace = cdb_trace + 1;
        end
    end
    always @(posedge clk) if (reset_n && strobe && adapter_cs && adapter_rnw && adapter_addr == 0 && dut.req_asserted && dut.phase == 2 && dut.cdb[0] == 'hC8)
        payload_reads = payload_reads + 1;
    always @(posedge clk48) if (reset_n && cpu_en) begin
        if (LEGACY_STROBE && memory['h7D] == 1 && memory['h74] == 'h22 && regs[15:8] == 3) begin
            $display("\nREPRODUCED legacy: STEP=01 X=03 FC41=22 after 3 CPU CDB writes, 6 accepted CDB bytes");
            $finish;
        end
        if (cpu_sync) begin
            last_pc = cpu_a;
            if (cpu_a == 16'hFFEE || cpu_a == 16'hFFE3) begin
                if (regs[7:0] == 13) $write("\n");
                else if (regs[7:0] >= 32 && regs[7:0] < 127) $write("%c", regs[7:0]);
            end
        end
        if (!cpu_rnw) begin
            if (cpu_a == 16'hFC40) cpu_writes = cpu_writes + 1;
            else if (cpu_a == 16'h0400) begin
                $display("\nDONE CPUwrites=%0d accepted=%0d", cpu_writes, accepted);
                if (LEGACY_STROBE) $fatal(1,"legacy failure was not reproduced");
                if (cpu_writes != 290 || accepted != 290)
                    $fatal(1,"write count mismatch");
                if (payload_writes != 256 || payload_reads != 256)
                    $fatal(1,"payload count mismatch TX=%0d RX=%0d", payload_writes, payload_reads);
                if (memory['h79] != 0 || memory['h7A] != 1 || memory['h7B] != 0 || memory['h7C] != 1 || memory['h7D] != 7 || memory['h7F] != 3)
                    $fatal(1,"ROM did not complete both F-code transfers");
                if (memory['h78] != 'h80)
                    $fatal(1,"READ6 pattern checksum=%02x expected=80", memory['h78]);
                if (memory['h81] != 'h50 || memory['h82] != 'h60 || memory['h83] != 'h41 || memory['h84] != 'h41 || memory['h85] != 'h40 || memory['h86] != 'h40 || memory['h87] != 'h0D)
                    $fatal(1,"incorrect player reply");
                $display("PASS tb_aiv_scsi_cpu phase=%0d TX=256 RX=256", INITIAL_PHASE);
                $finish;
            end else if (!cs) memory[cpu_a] <= cpu_do;
        end
    end
    integer i;
    initial begin
        for (i=0; i<65536; i=i+1) memory[i]=0;
        $readmemh("scsi_diag.hex", memory, 16'h8000, 16'hBFFF);
        // SEI; CLD; LDX #FF; TXS; LDA #4; LDX #0; LDY #0; JSR &8003;
        // STA &0400; JMP &0212. F2/F3 points to the command at &0300.
        memory['h200]='h78; memory['h201]='hD8;
        memory['h202]='hA2; memory['h203]='hFF; memory['h204]='h9A;
        memory['h205]='hA9; memory['h206]='h04;
        memory['h207]='hA2; memory['h208]='h00;
        memory['h209]='hA0; memory['h20A]='h00;
        memory['h20B]='h20; memory['h20C]='h03; memory['h20D]='h80;
        memory['h20E]='h8D; memory['h20F]='h00; memory['h210]='h04;
        memory['h211]='h4C; memory['h212]='h11; memory['h213]='h02;
        memory['h300]="S"; memory['h301]="C"; memory['h302]="S";
        memory['h303]="I"; memory['h304]="T"; memory['h305]="E";
        memory['h306]="S"; memory['h307]="T"; memory['h308]=13;
        memory['hF2]=0; memory['hF3]=3;
        memory['hFFFC]=0; memory['hFFFD]=2;
        memory['hFFEE]='h60; memory['hFFE3]='h60;
        repeat(100) @(negedge clk);
        reset_n=1;
        #1000000000 $fatal(1,"CPU/ROM timeout pc=%04x", last_pc);
    end
endmodule
