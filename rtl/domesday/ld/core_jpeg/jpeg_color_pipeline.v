// Four-stage, bit-exact version of core_jpeg's original YCbCr -> RGB math.
// A stalled output freezes every stage, its pixel coordinates and the FIFO
// pop enable together. This retains one-pixel-per-cycle steady throughput.
module jpeg_color_pipeline (
    input clk_i, rst_i, flush_i,
    input in_valid_i, mono_i,
    input signed [31:0] y_i, cb_i, cr_i,
    input [15:0] x_i, y_pos_i,
    output in_accept_o,
    input out_accept_i,
    output out_valid_o,
    output reg [15:0] x_o, y_pos_o,
    output reg [7:0] r_o, g_o, b_o,
    output busy_o
);
    reg [3:0] valid_q = 0;
    wire advance = !valid_q[3] || out_accept_i;
    assign in_accept_o = advance;
    assign out_valid_o = valid_q[3];
    assign busy_o = |valid_q;

    reg signed [31:0] sample_y_q, sample_cb_q, sample_cr_q;
    reg mono_q;
    reg signed [31:0] bias_q, cr_red_q, cr_green_q, cb_green_q, cb_blue_q;
    reg signed [31:0] red_sum_q, green_partial_q, blue_sum_q, cr_green_delay_q;
    reg [15:0] x_q [0:2];
    reg [15:0] y_pos_q [0:2];

    // Preserve the original signed 32-bit product, arithmetic shift and
    // wraparound semantics. A separate stage performs the additions.
    (* multstyle = "dsp" *) wire signed [31:0] cr_red_w = (sample_cr_q * 32'sd5743) >>> 12;
    (* multstyle = "dsp" *) wire signed [31:0] cr_green_w = (sample_cr_q * 32'sd2925) >>> 12;
    (* multstyle = "dsp" *) wire signed [31:0] cb_green_w = (sample_cb_q * 32'sd1410) >>> 12;
    (* multstyle = "dsp" *) wire signed [31:0] cb_blue_w = (sample_cb_q * 32'sd7258) >>> 12;

    function [7:0] clip;
        input signed [31:0] value;
        begin
            clip = (|value[31:8]) ? (value[31:24] ^ 8'hff) : value[7:0];
        end
    endfunction

    integer i;
    always @(posedge clk_i) begin
        if (rst_i || flush_i)
            valid_q <= 0;
        else if (advance)
            valid_q <= {valid_q[2:0], in_valid_i};

        if (advance) begin
            sample_y_q <= y_i;
            sample_cb_q <= cb_i;
            sample_cr_q <= cr_i;
            mono_q <= mono_i;
            x_q[0] <= x_i;
            y_pos_q[0] <= y_pos_i;
            for (i=1; i<3; i=i+1) begin
                x_q[i] <= x_q[i-1];
                y_pos_q[i] <= y_pos_q[i-1];
            end

            bias_q <= 32'sd128 + sample_y_q;
            cr_red_q <= mono_q ? 32'sd0 : cr_red_w;
            cr_green_q <= mono_q ? 32'sd0 : cr_green_w;
            cb_green_q <= mono_q ? 32'sd0 : cb_green_w;
            cb_blue_q <= mono_q ? 32'sd0 : cb_blue_w;

            red_sum_q <= bias_q + cr_red_q;
            green_partial_q <= bias_q - cb_green_q;
            cr_green_delay_q <= cr_green_q;
            blue_sum_q <= bias_q + cb_blue_q;

            r_o <= clip(red_sum_q);
            g_o <= clip(green_partial_q - cr_green_delay_q);
            b_o <= clip(blue_sum_q);
            x_o <= x_q[2];
            y_pos_o <= y_pos_q[2];
        end
    end
endmodule
