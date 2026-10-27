// Exact division by five, with two input pipeline stages.
// ceil(2^20/5)=209716: for every 0 <= address < 2^18, the high product
// bits equal floor(address/5). The remainder only needs three low bits.
// Capture the address before the DSP so the gated BBC bus does not feed a
// multiplier and RAM decoder in the same 96 MHz cycle.
module packed_rom_address #(parameter integer WIDTH = 18) (
    input clk,
    input [WIDTH-1:0] address,
    output [WIDTH-3:0] word_address,
    output [2:0] byte_lane
);
    reg [WIDTH-1:0] address_q = 0;
    reg [2:0] low_q = 0;
    (* multstyle = "dsp" *) reg [WIDTH+17:0] product_q = 0;
    always @(posedge clk) begin
        address_q <= address;
        product_q <= address_q * 18'd209716;
        low_q <= address_q[2:0];
    end
    assign word_address = product_q[WIDTH+17:20];
    wire [2:0] quotient_low = word_address[2:0];
    assign byte_lane = low_q - (quotient_low + {quotient_low[0], 2'b00});
endmodule
