// Domesday DDV JPEG decode, DDR framebuffer and BBC hard-key compositor.
//
// The DDV cache contains 832x576 baseline JPEG frames: the complete PAL
// 52 us x 576-line video grid used by Pi1MHz.  The first integration stage
// displays the central 640x512 BBC raster (source x=96..735, y=32..543) and
// uses VP415 mode 3 semantics: black BBC pixels reveal LaserDisc video.
// Full overscan and the other VP modes can be layered onto this boundary
// without changing the decoder or framebuffer format.

module domesday_video
(
    input             clk,
    input             reset,

    input       [7:0] jpeg_byte,
    input             jpeg_valid,
    output            jpeg_ready,
    input             jpeg_last,
    input             jpeg_reset,
    output reg        jpeg_next_frame = 1'b0,

    input             ce_grid,
    input       [3:0] bbc_r,
    input       [3:0] bbc_g,
    input       [3:0] bbc_b,
    input             bbc_hblank,
    input             bbc_vblank,
    input             bbc_hsync,
    input             bbc_vsync,
    input             odd_field,
    output      [3:0] video_r,
    output      [3:0] video_g,
    output      [3:0] video_b,
    output            picture_ready,

    input             DDRAM_BUSY,
    output      [7:0] DDRAM_BURSTCNT,
    output     [28:0] DDRAM_ADDR,
    input      [63:0] DDRAM_DOUT,
    input             DDRAM_DOUT_READY,
    output            DDRAM_RD,
    output     [63:0] DDRAM_DIN,
    output      [7:0] DDRAM_BE,
    output            DDRAM_WE
);

localparam [15:0] FB_W   = 16'd832;
localparam [15:0] FB_H   = 16'd576;
localparam [26:0] FB_BUF = 27'd479232; // 832*576 RGB565 halfwords
localparam  [7:0] WORDS  = 8'd208;     // 832 pixels / four RGB565 pixels

wire        px_we;
wire        px_ready;
wire [15:0] px_x;
wire [15:0] px_y;
wire  [7:0] px_r;
wire  [7:0] px_g;
wire  [7:0] px_b;
wire [15:0] decoded_width;
wire [15:0] decoded_height;
wire        frame_done;

jpeg_frame_decoder decoder
(
    .clk(clk), .rst(reset | jpeg_reset),
    .in_byte(jpeg_byte), .in_valid(jpeg_valid),
    .in_ready(jpeg_ready), .in_last(jpeg_last),
    .px_ready(px_ready), .px_we(px_we),
    .px_x(px_x), .px_y(px_y), .px_r(px_r), .px_g(px_g), .px_b(px_b),
    .frame_width(decoded_width), .frame_height(decoded_height),
    .frame_done(frame_done), .idle()
);

// Triple buffering makes later seek/play updates tear-free.  The initial
// decoder currently supplies frame zero; the handoff machinery is already
// ready for subsequent frames.
reg [1:0] wr_idx = 2'd0;
reg [1:0] disp_idx = 2'd1;
reg [1:0] ready_idx = 2'd1;
reg       have_new = 1'b0;
reg       shown = 1'b0;
reg       vs_d = 1'b0;
reg       frame_pending = 1'b0;
reg [15:0] frame_settle = 16'd0;

// The BBC raster signals are generated on the delayed/gated 48 MHz clock.
// Bring them across one parent-clock register before they control the 96 MHz
// DDR fetch state. Raster edges are many parent cycles wide, so this removes
// the clock-tree-skew path without changing which scanline is requested.
reg bbc_hblank_q = 1'b1;
reg bbc_vblank_q = 1'b1;
reg bbc_vsync_q  = 1'b0;
reg odd_field_q  = 1'b0;
always @(posedge clk) begin
    if (reset) begin
        bbc_hblank_q <= 1'b1;
        bbc_vblank_q <= 1'b1;
        bbc_vsync_q  <= 1'b0;
        odd_field_q  <= 1'b0;
    end else begin
        bbc_hblank_q <= bbc_hblank;
        bbc_vblank_q <= bbc_vblank;
        bbc_vsync_q  <= bbc_vsync;
        odd_field_q  <= odd_field;
    end
end

wire vblank_start = bbc_vsync_q & ~vs_d;
wire adopt = vblank_start & have_new;
wire [1:0] next_disp = adopt ? ready_idx : disp_idx;

always @(posedge clk) begin
    vs_d <= bbc_vsync_q;
    jpeg_next_frame <= 1'b0;
    if (reset) begin
        wr_idx <= 2'd0;
        disp_idx <= 2'd1;
        ready_idx <= 2'd1;
        have_new <= 1'b0;
        shown <= 1'b0;
        frame_pending <= 1'b0;
        frame_settle <= 16'd0;
    end else begin
        if (adopt) begin
            disp_idx <= ready_idx;
            have_new <= 1'b0;
            shown <= 1'b1;
            // The bridge does not fetch ahead until the completed frame has
            // actually become visible.  This keeps decoder, writer and the
            // three framebuffer owners from ever colliding.
            jpeg_next_frame <= 1'b1;
        end
        if (frame_done && decoded_width == FB_W && decoded_height == FB_H) begin
            frame_pending <= 1'b1;
            frame_settle <= 16'd0;
        end else if (frame_pending) begin
            // Allow fb_writer's coalescing tail and final DDR command to land.
            frame_settle <= frame_settle + 1'b1;
            if (&frame_settle) begin
                ready_idx <= wr_idx;
                wr_idx <= 2'd3 - wr_idx - next_disp;
                have_new <= 1'b1;
                frame_pending <= 1'b0;
            end
        end
    end
end

assign picture_ready = shown;

function automatic [26:0] buf_base(input [1:0] index);
begin
    buf_base = (index == 2'd0) ? 27'd0 :
               (index == 2'd1) ? FB_BUF : (FB_BUF * 2);
end
endfunction

wire [27:1] wraddr;
wire [15:0] wdin;
wire [63:0] din64;
wire  [7:0] be64;
wire        we_req;
wire        we_ack;
reg         fetching = 1'b0;

fb_writer #(
    .STRIDE_HW(FB_W), .CLEAR_ON_RESET(1'b0),
    .CLEAR_ROWS(FB_H), .FB_COLS(FB_W), .FB_ROWS(FB_H),
    .COALESCE(1'b1)
) writer (
    .clk(clk), .reset(reset), .base_hw(buf_base(wr_idx)),
    .fill_idle(~fetching),
    .px_we(px_we), .px_x(px_x), .px_y(px_y),
    .px_r(px_r), .px_g(px_g), .px_b(px_b), .px_ready(px_ready),
    .wraddr(wraddr), .din(wdin), .din64(din64), .be64(be64),
    .we_req(we_req), .we_ack(we_ack)
);

reg [27:1] rdaddr2 = 27'd0;
wire [63:0] dout2_64;
reg         rd_req2 = 1'b0;
wire        rd_ack2;

ddram framebuffer_ddr
(
    .DDRAM_CLK(clk), .DDRAM_BUSY(DDRAM_BUSY),
    .DDRAM_BURSTCNT(DDRAM_BURSTCNT), .DDRAM_ADDR(DDRAM_ADDR),
    .DDRAM_DOUT(DDRAM_DOUT), .DDRAM_DOUT_READY(DDRAM_DOUT_READY),
    .DDRAM_RD(DDRAM_RD), .DDRAM_DIN(DDRAM_DIN),
    .DDRAM_BE(DDRAM_BE), .DDRAM_WE(DDRAM_WE),
    .wraddr(wraddr), .din(wdin), .din64(din64), .be64(be64),
    .we_req(we_req), .we_ack(we_ack),
    .rdaddr(27'd0), .dout(), .rom_din(16'd0), .rom_be(2'b00),
    .rom_we(1'b0), .rom_req(1'b0), .rom_ack(),
    .rdaddr2(rdaddr2), .dout2(), .dout2_64(dout2_64),
    .rd_req2(rd_req2), .rd_ack2(rd_ack2)
);

// Two 832-pixel scanlines.  Quartus may use MLABs; if placement chooses M10K
// the one removed sideways-RAM bank still leaves sufficient capacity.
(* ramstyle = "MLAB, no_rw_check" *) reg [63:0] line_buffer [0:511];
reg [7:0] fetch_word = 8'd0;
reg       fetch_bank = 1'b0;
reg [26:0] fetch_base = 27'd0;

reg hblank_d = 1'b1;
reg vblank_d = 1'b1;
wire hblank_rise = bbc_hblank_q & ~hblank_d;
wire hblank_fall = ~bbc_hblank_q & hblank_d;
wire vblank_fall = ~bbc_vblank_q & vblank_d;
reg [7:0] active_y = 8'd0;
reg [9:0] active_x = 10'd0;

wire [9:0] source_y_next = 10'd32 + {active_y + 1'b1, 1'b0} + odd_field_q;

task automatic start_line_fetch(input [7:0] target_y, input [9:0] source_y);
begin
    fetching <= shown;
    fetch_word <= 8'd0;
    fetch_bank <= target_y[0];
    fetch_base <= buf_base(next_disp) + source_y * FB_W;
    rdaddr2 <= buf_base(next_disp) + source_y * FB_W;
    if (shown) rd_req2 <= ~rd_ack2;
end
endtask

always @(posedge clk) begin
    hblank_d <= bbc_hblank_q;
    vblank_d <= bbc_vblank_q;

    if (reset) begin
        fetching <= 1'b0;
        rd_req2 <= 1'b0;
        active_x <= 10'd0;
        active_y <= 8'd0;
    end else begin
        if (vblank_fall) begin
            active_y <= 8'd0;
            start_line_fetch(8'd0, 10'd32 + odd_field_q);
        end else if (hblank_rise && !bbc_vblank_q && active_y != 8'd255) begin
            active_y <= active_y + 1'b1;
            start_line_fetch(active_y + 1'b1, source_y_next);
        end

        if (hblank_fall) active_x <= 10'd0;
        else if (ce_grid && !bbc_hblank_q && active_x != 10'd639)
            active_x <= active_x + 1'b1;

        if (fetching && rd_req2 == rd_ack2) begin
            line_buffer[{fetch_bank, fetch_word}] <= dout2_64;
            if (fetch_word == WORDS - 1'b1) begin
                fetching <= 1'b0;
            end else begin
                fetch_word <= fetch_word + 1'b1;
                rdaddr2 <= fetch_base + {fetch_word + 1'b1, 2'b00};
                rd_req2 <= ~rd_req2;
            end
        end
    end
end

// The computer raster is centred in the 832x576 AIV grid: +96 columns and
// +32 frame lines.  Interlaced fields select alternating source rows.
wire [9:0] source_x = 10'd96 + active_x;
reg [63:0] pixel_word = 64'd0;
reg  [1:0] pixel_lane = 2'd0;
reg        laser_valid = 1'b0;
reg  [3:0] bbc_r_q = 4'd0;
reg  [3:0] bbc_g_q = 4'd0;
reg  [3:0] bbc_b_q = 4'd0;

always @(posedge clk) begin
    if (ce_grid) begin
        pixel_word <= line_buffer[{active_y[0], source_x[9:2]}];
        pixel_lane <= source_x[1:0];
        laser_valid <= shown && !bbc_hblank_q && !bbc_vblank_q;
        bbc_r_q <= bbc_r;
        bbc_g_q <= bbc_g;
        bbc_b_q <= bbc_b;
    end
end

wire [15:0] laser565 = pixel_word[{pixel_lane, 4'b0000} +: 16];
wire bbc_black = !(|bbc_r_q) && !(|bbc_g_q) && !(|bbc_b_q);

assign video_r = (laser_valid && bbc_black) ? laser565[15:12] : bbc_r_q;
assign video_g = (laser_valid && bbc_black) ? laser565[10:7]  : bbc_g_q;
assign video_b = (laser_valid && bbc_black) ? laser565[4:1]   : bbc_b_q;

endmodule
