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

module jpeg_idct_transpose_ram
(
    // Inputs
     input           clk0_i
    ,input           rst0_i
    ,input  [  4:0]  addr0_i
    ,input  [ 31:0]  data0_i
    ,input           wr0_i
    ,input           clk1_i
    ,input           rst1_i
    ,input  [  4:0]  addr1_i
    ,input  [ 31:0]  data1_i
    ,input           wr1_i

    // Outputs
    ,output [ 31:0]  data0_o
    ,output [ 31:0]  data1_o
);



//-----------------------------------------------------------------
// Dual Port RAM
// Mode: Read First.  Explicit MLAB mapping avoids a large register fallback
// when this dual-clock scratch RAM is instantiated below the BBC hierarchy.
//-----------------------------------------------------------------
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
    ram.width_a = 32, ram.widthad_a = 5, ram.numwords_a = 32,
    ram.width_b = 32, ram.widthad_b = 5, ram.numwords_b = 32,
    ram.address_reg_b = "CLOCK1",
    ram.outdata_reg_a = "UNREGISTERED",
    ram.outdata_reg_b = "UNREGISTERED",
    ram.ram_block_type = "MLAB",
    ram.intended_device_family = "Cyclone V",
    ram.lpm_type = "altsyncram",
    ram.power_up_uninitialized = "TRUE",
    ram.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
    ram.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
    ram.width_byteena_a = 1,
    ram.width_byteena_b = 1;



endmodule
