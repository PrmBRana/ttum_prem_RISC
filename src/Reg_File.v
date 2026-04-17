`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  Reg_file — 32×32 register file
//
//  No reset port: x0..x31 start as 0 via Verilog initial values
//  in simulation (reg default = 0). RISC-V programs are responsible
//  for initialising any register they use before reading it.
//  Removing reset avoids a 32×32 reset fanout which is expensive
//  on ASIC and unnecessary for correctness.
//
//  Write-first forwarding: if WB is writing the same register
//  being read in ID this cycle, the new value is forwarded
//  combinatorially, avoiding a 1-cycle stale-read hazard.
// ============================================================

module Reg_file (
    input  wire        clk,
    input  wire [4:0]  rs1_addr,
    input  wire [4:0]  rs2_addr,
    input  wire [4:0]  rd_addr,
    input  wire        Regwrite,
    input  wire [31:0] Write_data,
    output wire [31:0] Read_data1,
    output wire [31:0] Read_data2
);

    reg [31:0] rf [0:31];

    // ── Write (ignore x0) ─────────────────────────────────────
    always @(posedge clk) begin
        if (Regwrite && rd_addr != 5'd0)
            rf[rd_addr] <= Write_data;
    end

    // ── Read with write-first forwarding ──────────────────────
    wire [31:0] raw1 = (rs1_addr == 5'd0) ? 32'd0 : rf[rs1_addr];
    wire [31:0] raw2 = (rs2_addr == 5'd0) ? 32'd0 : rf[rs2_addr];

    assign Read_data1 = (Regwrite && rd_addr != 5'd0 && rd_addr == rs1_addr)
                        ? Write_data : raw1;
    assign Read_data2 = (Regwrite && rd_addr != 5'd0 && rd_addr == rs2_addr)
                        ? Write_data : raw2;

endmodule



