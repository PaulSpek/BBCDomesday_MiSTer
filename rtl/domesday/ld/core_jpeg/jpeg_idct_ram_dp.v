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

module jpeg_idct_ram_dp
(
    // Inputs
     input           clk0_i
    ,input           rst0_i
    ,input  [  5:0]  addr0_i
    ,input  [ 15:0]  data0_i
    ,input           wr0_i
    ,input           clk1_i
    ,input           rst1_i
    ,input  [  5:0]  addr1_i
    ,input  [ 15:0]  data1_i
    ,input           wr1_i

    // Outputs
    ,output [ 15:0]  data0_o
    ,output [ 15:0]  data1_o
);



//-----------------------------------------------------------------
// Dual Port RAM
// Mode: Read First.  Port 0 is write-only in every caller (data0_o is unused),
// so express this as a simple dual-port RAM.  This is an MLAB-supported shape;
// BIDIR_DUAL_PORT forced Quartus 17 to consume M10Ks for every scratch RAM.
//-----------------------------------------------------------------
altsyncram ram
(
    .clock0(clk0_i), .clock1(clk0_i),
    .address_a(addr0_i), .data_a(data0_i), .wren_a(wr0_i), .q_a(),
    .address_b(addr1_i), .data_b(16'd0), .wren_b(1'b0), .q_b(data1_o),
    .aclr0(1'b0), .aclr1(1'b0),
    .addressstall_a(1'b0), .addressstall_b(1'b0),
    .byteena_a(1'b1), .byteena_b(1'b1),
    .clocken0(1'b1), .clocken1(1'b1), .clocken2(1'b1), .clocken3(1'b1),
    .eccstatus(), .rden_a(1'b1), .rden_b(1'b1)
);
defparam
    ram.operation_mode = "DUAL_PORT",
    ram.width_a = 16, ram.widthad_a = 6, ram.numwords_a = 64,
    ram.width_b = 16, ram.widthad_b = 6, ram.numwords_b = 64,
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
