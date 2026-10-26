// Four shared OSD ROM images, available in slots 0..3 in either BBC model.
module sideways_rom_bank (
    input clk,
    input [1:0] read_slot,
    input [13:0] read_addr,
    output [7:0] read_data,
    output valid,
    input download,
    input [7:0] file_index,
    input write_enable,
    input [24:0] write_addr,
    input [7:0] write_data,
    output loading
);
    wire [31:0] data_slots;
    wire [3:0] valid_slots, loading_slots;
    genvar slot;
    generate for (slot=0; slot<4; slot=slot+1) begin : slots
        sideways_rom_slot #(
            .FILE_INDEX(5 + slot),
            .INIT_FILE(slot == 1 ? "roms/scsi_diag.mif" : "roms/empty_sideways.mif"),
            .DEFAULT_VALID(slot == 1)
        ) image (
            .clk(clk), .read_addr(read_addr), .read_data(data_slots[slot * 8 +: 8]),
            .valid(valid_slots[slot]), .download(download), .file_index(file_index),
            .write_enable(write_enable), .write_addr(write_addr), .write_data(write_data),
            .loading(loading_slots[slot])
        );
    end endgenerate
    assign read_data = data_slots[read_slot * 8 +: 8];
    assign valid = valid_slots[read_slot];
    assign loading = |loading_slots;
endmodule

// Built-in ROM routing, plus model-independent overlays in cartridge 0..3.
// Slot 4 here denotes the MOS physical ROM bank, not sideways RAM slot 4.
module sideways_rom_mux (
    input master,
    input [3:0] slot,
    input dfs, mmfs,
    input [7:0] builtin_data, cartridge_data,
    input cartridge_valid,
    output reg [7:0] data
);
    always @* begin
        data = 8'h00;
        case ({master, slot})
            5'b0_0000, 5'b0_0001, 5'b0_0010,
            5'b1_0000, 5'b1_0001, 5'b1_0010:
                data = cartridge_valid ? cartridge_data : 8'h00;
            5'b0_0011: data = cartridge_valid ? cartridge_data : (dfs ? builtin_data : 8'h00);
            5'b1_0011: data = cartridge_valid ? cartridge_data : (mmfs ? builtin_data : 8'h00);
            5'b0_1000: data = mmfs ? builtin_data : 8'h00;
            5'b1_1001: data = dfs ? builtin_data : 8'h00;
            5'b0_0100, 5'b0_1110, 5'b0_1111,
            5'b1_0100, 5'b1_1000, 5'b1_1010, 5'b1_1011,
            5'b1_1100, 5'b1_1101, 5'b1_1110, 5'b1_1111:
                data = builtin_data;
            default: data = 8'h00;
        endcase
    end
endmodule
