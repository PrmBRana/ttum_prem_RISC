`default_nettype none
`timescale 1ns/1ps

// ============================================================
//  Adder — PC-target address calculator (reference only)
//
//  EX_Mux has been removed — all three muxes (forwarding A,
//  forwarding B, ALU source-B) are implemented inline in
//  pipeline.v with assign statements and are never instantiated
//  from a separate module.
//
//  This Adder is also implemented inline in pipeline.v.
//  It is kept here as a standalone reference only.
//  Verilog-2001 compatible — no SystemVerilog constructs.
// ============================================================
module Adder (
    input  wire [31:0] pc_E,
    input  wire [31:0] rd1_E,
    input  wire [31:0] imm_2,
    input  wire        JumpR,
    output wire [31:0] PCTarget
);
    wire [31:0] base_addr = JumpR ? rd1_E : pc_E;

    assign PCTarget = JumpR
                    ? ((base_addr + imm_2) & 32'hFFFF_FFFE)
                    :  (base_addr + imm_2);
endmodule





