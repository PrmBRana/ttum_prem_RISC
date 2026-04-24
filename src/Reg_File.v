`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  Reg_file — 32×32 register file
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





