`timescale 1ns/1ps
module tb_sideways_rom_bank;
    reg clk = 0;
    always #5 clk = ~clk;
    reg [1:0] read_slot = 0;
    reg [13:0] read_addr = 0;
    wire [7:0] read_data;
    wire valid, loading;
    reg download = 0;
    reg [7:0] file_index = 0;
    reg write_enable = 0;
    reg [24:0] write_addr = 0;
    reg [7:0] write_data = 0;
    reg master = 0, dfs = 0, mmfs = 0;
    reg [3:0] mux_slot = 0;
    wire [7:0] routed_data;
    sideways_rom_bank bank(.*);
    sideways_rom_mux mux(.master(master), .slot(mux_slot), .dfs(dfs), .mmfs(mmfs),
        .builtin_data(8'hA9), .cartridge_data(read_data),
        .cartridge_valid(valid), .data(routed_data));
    integer slot, address, model, options;
    function automatic [7:0] pattern(input integer s, input integer a);
        pattern = (s * 53) ^ a[7:0] ^ a[13:6];
    endfunction
    task automatic select_slot(input integer s);
        begin
            read_slot = s;
            mux_slot = s;
            repeat (3) @(negedge clk);
        end
    endtask
    task automatic send(input integer a, input [7:0] d);
        begin
            write_enable = 1; write_addr = a; write_data = d;
            @(negedge clk);
        end
    endtask
    task automatic begin_load(input integer s);
        begin
            file_index = 5 + s; download = 1;
            @(negedge clk);
            if (!loading) $fatal(1,"ROM upload did not assert CPU reset request");
        end
    endtask
    task automatic end_load;
        begin
            download = 0; write_enable = 0;
            @(negedge clk);
            if (loading) $fatal(1,"ROM reset request did not release");
        end
    endtask
    initial begin
        @(negedge clk);
        for (slot=0; slot<4; slot=slot+1) begin
            select_slot(slot);
            if (valid !== (slot == 1)) $fatal(1,"initial validity slot %0d",slot);
        end
`ifndef DOMESDAY_BEHAVIORAL_ROM
        // Check the actual Altera MIF loader before replacing the ROM image.
        select_slot(1); read_addr=0; repeat (3) @(negedge clk);
        if (read_data !== 8'h4C) $fatal(1,"diagnostic ROM initial header");
        read_addr=5; repeat (3) @(negedge clk);
        if (read_data !== 8'h80) $fatal(1,"diagnostic ROM packed word boundary");
`endif
        // Slots 2 and 3 have no upload storage. Slot 2 remains empty and slot
        // 3 always follows the built-in filing-system selection.
        select_slot(2);
        if (valid || routed_data !== 8'h00) $fatal(1,"slot 2 must remain empty");
        select_slot(3);
        for (model=0; model<2; model=model+1)
            for (options=0; options<4; options=options+1) begin
                master = model; dfs = options[0]; mmfs = options[1]; #1;
                if (routed_data !== ((master ? mmfs : dfs) ? 8'hA9 : 8'h00))
                    $fatal(1,"slot 3 built-in fallback");
            end
        // Distinct images in both loadable slots; check every byte and every
        // word lane including the 4-byte tail, then route in both models.
        for (slot=0; slot<2; slot=slot+1) begin
            begin_load(slot);
            for (address=0; address<16384; address=address+1)
                send(address, pattern(slot,address));
            end_load;
        end
        for (model=0; model<2; model=model+1) begin
            master = model; dfs=0; mmfs=0;
            for (slot=0; slot<2; slot=slot+1) begin
                select_slot(slot);
                if (!valid) $fatal(1,"slot %0d missing",slot);
                for (address=0; address<16384; address=address+1) begin
                    read_addr=address; repeat (3) @(negedge clk);
                    if (routed_data !== pattern(slot,address))
                        $fatal(1,"model %0d slot %0d address %0d got %02x",model,slot,address,routed_data);
                end
            end
        end
        // Removed file indices must not claim a download or reset the CPU.
        for (slot=2; slot<4; slot=slot+1) begin
            file_index=5+slot; download=1; @(negedge clk);
            if (loading) $fatal(1,"removed slot %0d still accepts upload",slot);
            download=0; @(negedge clk);
        end
        // Interrupted upload must hide only its target slot.
        // Verify every non-cartridge physical ROM bank still follows the
        // original model/Filesystem routing after factoring out the mux.
        for (model=0; model<2; model=model+1)
            for (options=0; options<4; options=options+1)
                for (slot=4; slot<16; slot=slot+1) begin
                    master=model; dfs=options[0]; mmfs=options[1]; mux_slot=slot; #1;
                    if (slot == 4 || slot == 14 || slot == 15 || (master && slot >= 8 && slot != 9)) begin
                        if (routed_data !== 8'hA9) $fatal(1,"built-in ROM lost model %0d slot %0d",model,slot);
                    end else if ((master && slot == 9) || (!master && slot == 8)) begin
                        if (routed_data !== ((master ? dfs : mmfs) ? 8'hA9 : 8'h00))
                            $fatal(1,"built-in filesystem routing model %0d slot %0d",model,slot);
                    end else if (routed_data !== 8'h00) $fatal(1,"empty bank exposed");
                end
        // Repeated/out-of-order and oversized uploads are rejected.
        begin_load(0); send(0,1); send(0,2); end_load;
        select_slot(0); if (valid) $fatal(1,"duplicate byte accepted");
        begin_load(1);
        for (address=0; address<16385; address=address+1) send(address,8'h61);
        end_load;
        select_slot(1); if (valid) $fatal(1,"oversized image accepted");
        select_slot(3); master=1; mmfs=1; #1;
        if (valid || routed_data !== 8'hA9) $fatal(1,"slot3 built-in fallback lost");
        $display("PASS tb_sideways_rom_bank: two slots, both models, all bytes, fallback and rejection");
        $finish;
    end
endmodule
