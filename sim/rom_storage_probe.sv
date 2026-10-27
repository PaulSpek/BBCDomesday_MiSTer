// Isolated resource probe: both stores remain observable and writable.
module rom_storage_probe (
    input clk,
    input [17:0] builtin_read_addr,
    output [7:0] builtin_data,
    input builtin_write,
    input [17:0] builtin_write_addr,
    input [7:0] write_data,
    input [1:0] cartridge_slot,
    input [13:0] cartridge_read_addr,
    output [7:0] cartridge_data,
    output cartridge_valid,
    input download,
    input [7:0] file_index,
    input cartridge_write,
    input [24:0] cartridge_write_addr,
    output loading
);
    packed_bbc_rom builtin_rom (
        .clk(clk), .read_addr(builtin_read_addr), .read_data(builtin_data),
        .write_enable(builtin_write), .write_addr(builtin_write_addr),
        .write_data(write_data)
    );
    sideways_rom_bank cartridge_roms (
        .clk(clk), .read_slot(cartridge_slot), .read_addr(cartridge_read_addr),
        .read_data(cartridge_data), .valid(cartridge_valid),
        .download(download), .file_index(file_index),
        .write_enable(cartridge_write), .write_addr(cartridge_write_addr),
        .write_data(write_data), .loading(loading)
    );
endmodule
