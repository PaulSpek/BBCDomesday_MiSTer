//-----------------------------------------------------------------
//                      Baseline JPEG Decoder
//                             V0.1
//                       Ultra-Embedded.com
//                        Copyright 2020
//
//                   admin@ultra-embedded.com
//-----------------------------------------------------------------
//                      License: Apache 2.0
// This IP can be freely used in commercial projects, however you may
// want access to unreleased materials such as verification environments,
// or test vectors, as well as changes to the IP for integration purposes.
// If this is the case, contact the above address.
// I am interested to hear how and where this IP is used, so please get
// in touch!
//-----------------------------------------------------------------
// Copyright 2020 Ultra-Embedded.com
// 
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
// 
//     http://www.apache.org/licenses/LICENSE-2.0
// 
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//-----------------------------------------------------------------

module jpeg_output_y_ram
(
    // Inputs
     input           clk_i
    ,input           rst_i
    ,input  [  5:0]  wr_idx_i
    ,input  [ 31:0]  data_in_i
    ,input           push_i
    ,input           pop_i
    ,input           flush_i

    // Outputs
    ,output [ 31:0]  data_out_o
    ,output          valid_o
    ,output [ 31:0]  level_o
);



//-----------------------------------------------------------------
// Registers
//-----------------------------------------------------------------
reg [8:0]   rd_ptr_q;
reg [8:0]   wr_ptr_q;

//-----------------------------------------------------------------
// Write Side
//-----------------------------------------------------------------
wire [8:0] write_next_w = wr_ptr_q + 9'd1;

always @ (posedge clk_i )
if (rst_i)
    wr_ptr_q <= 9'b0;
else if (flush_i)
    wr_ptr_q <= 9'b0;
// Push
else if (push_i)
    wr_ptr_q <= write_next_w;

//-----------------------------------------------------------------
// Read Side
//-----------------------------------------------------------------
wire read_ok_w = (wr_ptr_q != rd_ptr_q);
reg  rd_q;

always @ (posedge clk_i )
if (rst_i)
    rd_q <= 1'b0;
else if (flush_i)
    rd_q <= 1'b0;
else
    rd_q <= read_ok_w;

wire [8:0] rd_ptr_next_w = rd_ptr_q + 9'd1;

always @ (posedge clk_i )
if (rst_i)
    rd_ptr_q <= 9'b0;
else if (flush_i)
    rd_ptr_q <= 9'b0;
else if (read_ok_w && ((!valid_o) || (valid_o && pop_i)))
    rd_ptr_q <= rd_ptr_next_w;

wire [8:0] rd_addr_w = rd_ptr_q;

//-------------------------------------------------------------------
// Read Skid Buffer
//-------------------------------------------------------------------
reg                rd_skid_q;
reg [31:0] rd_skid_data_q;

always @ (posedge clk_i )
if (rst_i)
begin
    rd_skid_q <= 1'b0;
    rd_skid_data_q <= 32'b0;
end
else if (flush_i)
begin
    rd_skid_q <= 1'b0;
    rd_skid_data_q <= 32'b0;
end
else if (valid_o && !pop_i)
begin
    rd_skid_q      <= 1'b1;
    rd_skid_data_q <= data_out_o;
end
else
begin
    rd_skid_q      <= 1'b0;
    rd_skid_data_q <= 32'b0;
end

//-------------------------------------------------------------------
// Combinatorial
//-------------------------------------------------------------------
assign valid_o       = rd_skid_q | rd_q;

//-------------------------------------------------------------------
// Dual port RAM
//-------------------------------------------------------------------
wire [31:0] data_out_w;

jpeg_output_y_ram_ram_dp_512_9
u_ram
(
    // Inputs
    .clk0_i(clk_i),
    .rst0_i(rst_i),
    .clk1_i(clk_i),
    .rst1_i(rst_i),

    // Write side
    .addr0_i({wr_ptr_q[8:6], wr_idx_i}),
    .wr0_i(push_i),
    .data0_i(data_in_i),
    .data0_o(),

    // Read side
    .addr1_i(rd_addr_w),
    .data1_i(32'b0),
    .wr1_i(1'b0),
    .data1_o(data_out_w)
);

assign data_out_o = rd_skid_q ? rd_skid_data_q : data_out_w;


//-------------------------------------------------------------------
// Level
//-------------------------------------------------------------------
reg [31:0]  count_q;
reg [31:0]  count_r;

always @ *
begin
    count_r = count_q;

    if (pop_i && valid_o)
        count_r = count_r - 32'd1;

    if (push_i)
        count_r = count_r + 32'd1;
end

always @ (posedge clk_i )
if (rst_i)
    count_q   <= 32'b0;
else if (flush_i)
    count_q   <= 32'b0;
else
    count_q <= count_r;

assign level_o = count_q;

endmodule

//-------------------------------------------------------------------
// Dual port RAM
//-------------------------------------------------------------------
module jpeg_output_y_ram_ram_dp_512_9
(
    // Inputs
     input           clk0_i
    ,input           rst0_i
    ,input  [ 8:0]  addr0_i
    ,input  [ 31:0]  data0_i
    ,input           wr0_i
    ,input           clk1_i
    ,input           rst1_i
    ,input  [ 8:0]  addr1_i
    ,input  [ 31:0]  data1_i
    ,input           wr1_i

    // Outputs
    ,output [ 31:0]  data0_o
    ,output [ 31:0]  data1_o
);

// Quartus 17 sometimes stops recognising this RAM when the decoder is placed
// in the complete MiSTer hierarchy, even though it infers correctly in the
// standalone resource probe.  An explicit primitive prevents a 16K-register
// fallback and preserves the original one-cycle dual-port behaviour.
altsyncram ram
(
    .clock0(clk0_i), .clock1(clk1_i),
    .address_a(addr0_i), .data_a(data0_i), .wren_a(wr0_i), .q_a(data0_o),
    .address_b(addr1_i), .data_b(32'd0), .wren_b(1'b0), .q_b(data1_o),
    .aclr0(1'b0), .aclr1(1'b0),
    .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1),
    .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
);
defparam
    ram.operation_mode = "BIDIR_DUAL_PORT",
    ram.width_a = 32, ram.widthad_a = 9, ram.numwords_a = 512,
    ram.width_b = 32, ram.widthad_b = 9, ram.numwords_b = 512,
    ram.address_reg_b = "CLOCK1",
    ram.outdata_reg_a = "UNREGISTERED",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.power_up_uninitialized = "TRUE",
    ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
    ram.width_byteena_a = 1,
    ram.width_byteena_b = 1;



endmodule
