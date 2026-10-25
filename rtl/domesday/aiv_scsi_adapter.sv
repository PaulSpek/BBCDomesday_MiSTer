// Acorn AIV / Pi1MHz compatible register boundary at BBC FRED &FC40-&FC43.
//
// Bit order of FC41: C/D, I/O, REQ, IRQ, spare, spare, BSY, MSG.
// A data register access consumes REQ in the same clocked action, matching
// the real adapter's behaviour and avoiding stale-REQ polling races.
module aiv_scsi_adapter
(
	input        clk,
	input        reset,
	input        cs,
	input        rnw,
	input  [1:0] addr,
	input  [7:0] din,
	output reg [7:0] dout,
	input        media_present
);
localparam [7:0] ST_CND = 8'h80;
localparam [7:0] ST_REQ = 8'h20;
localparam [7:0] ST_BSY = 8'h02;

reg [7:0] data_reg = 8'h00;
reg [7:0] status_reg = 8'h00;
reg       irq_enable = 1'b0;

always @* begin
	case (addr)
		2'd0: dout = data_reg;
		2'd1: dout = status_reg;
		default: dout = 8'hFF;
	endcase
end

always @(posedge clk) begin
	if (reset) begin
		data_reg <= 8'h00;
		status_reg <= 8'h00;
		irq_enable <= 1'b0;
	end else if (cs && !rnw) begin
		case (addr)
		2'd0: begin
			data_reg <= din;
			status_reg <= status_reg & ~ST_REQ;
		end
		// FC41 is reserved for VFS jukebox selection; retain the byte now
		// so the later command engine can consume it without changing the bus.
		2'd1: data_reg <= din;
		2'd2: begin
			if (media_present) status_reg <= ST_CND | ST_BSY | ST_REQ;
			else status_reg <= 8'h00;
		end
		2'd3: irq_enable <= din[0];
		endcase
	end else if (!media_present) begin
		status_reg <= 8'h00;
	end
end
endmodule
