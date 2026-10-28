// BBC shared memory bus: separate Tube, sideways and host/video stores.
// All stores retain the original rising-edge read and write timing.
module bbc_external_ram (
    input clk,
    input [18:0] address,
    input [7:0] data_in,
    input write_pulse,
    output reg [7:0] data_out
);
    reg [7:0] tube_ram [0:65535];
    reg [7:0] sideways_ram [0:65535];
    reg [7:0] host_ram [0:81919];
    reg [7:0] tube_q, sideways_q, host_q;
    wire tube_selected = address[18:16] == 3'b100;
    wire sideways_selected = address[18:16] == 3'b101;
    wire host_selected = address[18] && address[17:14] >= 4'd8 && address[17:14] <= 4'd12;

    always @(posedge clk) begin
        if (tube_selected) begin
            if (write_pulse) tube_ram[address[15:0]] <= data_in;
            tube_q <= tube_ram[address[15:0]];
        end
        if (sideways_selected) begin
            if (write_pulse) sideways_ram[address[15:0]] <= data_in;
            sideways_q <= sideways_ram[address[15:0]];
        end
        if (host_selected) begin
            if (write_pulse) host_ram[address[16:0]] <= data_in;
            host_q <= host_ram[address[16:0]];
        end
    end
    always @* begin
        if (tube_selected) data_out = tube_q;
        else if (sideways_selected) data_out = sideways_q;
        else if (host_selected) data_out = host_q;
        else data_out = 8'd0;
    end
endmodule
