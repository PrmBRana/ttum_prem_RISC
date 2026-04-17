`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// EX_stage.v — ID/EX pipeline latch
//
// Added: ALUSrcA_in [1:0] / ALUSrcA_out [1:0]
//   Passes the new Control.ALUSrcA signal through the latch so pipeline.v
//   can select SrcA correctly for LUI (force 0) and AUIPC (force PC_E).
// =============================================================================

module EX_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        flushE,

    input  wire [31:0] RD1D_in,
    input  wire [31:0] RD2D_in,
    input  wire [31:0] ImmExtD_in,
    input  wire [31:0] PCPlus4D_in,
    input  wire [31:0] PC_D_in,
    input  wire [4:0]  Rs1D_in,
    input  wire [4:0]  Rs2D_in,
    input  wire [4:0]  RdD_in,
    input  wire [3:0]  ALUControlD_in,
    input  wire        ALUSrcD_in,
    input  wire [1:0]  ALUSrcA_in,     // NEW
    input  wire        RegWriteD_in,
    input  wire [1:0]  ResultSrcD_in,
    input  wire        MemWriteD_in,
    input  wire        BranchD_in,
    input  wire        JumpD_in,
    input  wire        JumpR_in,
    input  wire [1:0]  ALUType_in,

    output reg  [31:0] RD1E_out,
    output reg  [31:0] RD2E_out,
    output reg  [31:0] ImmExtD_out,
    output reg  [31:0] PCPlus4D_out,
    output reg  [31:0] PC_D_out,
    output reg  [4:0]  Rs1D_out,
    output reg  [4:0]  Rs2D_out,
    output reg  [4:0]  RdD_out,
    output reg  [3:0]  ALUControlD_out,
    output reg         ALUSrcD_out,
    output reg  [1:0]  ALUSrcA_out,    // NEW
    output reg         RegWriteD_out,
    output reg  [1:0]  ResultSrcD_out,
    output reg         MemWriteD_out,
    output reg         BranchD_out,
    output reg         JumpD_out,
    output reg         JumpR_out,
    output reg  [1:0]  ALUType_out
);
    always @(posedge clk) begin
        if (reset || flushE) begin
            RD1E_out        <= 32'd0;
            RD2E_out        <= 32'd0;
            ImmExtD_out     <= 32'd0;
            PCPlus4D_out    <= 32'd0;
            PC_D_out        <= 32'd0;
            Rs1D_out        <= 5'd0;
            Rs2D_out        <= 5'd0;
            RdD_out         <= 5'd0;
            ALUControlD_out <= 4'd0;
            ALUSrcD_out     <= 1'b0;
            ALUSrcA_out     <= 2'b00;
            RegWriteD_out   <= 1'b0;
            ResultSrcD_out  <= 2'd0;
            MemWriteD_out   <= 1'b0;
            BranchD_out     <= 1'b0;
            JumpD_out       <= 1'b0;
            JumpR_out       <= 1'b0;
            ALUType_out     <= 2'd0;
        end else begin
            RD1E_out        <= RD1D_in;
            RD2E_out        <= RD2D_in;
            ImmExtD_out     <= ImmExtD_in;
            PCPlus4D_out    <= PCPlus4D_in;
            PC_D_out        <= PC_D_in;
            Rs1D_out        <= Rs1D_in;
            Rs2D_out        <= Rs2D_in;
            RdD_out         <= RdD_in;
            ALUControlD_out <= ALUControlD_in;
            ALUSrcD_out     <= ALUSrcD_in;
            ALUSrcA_out     <= ALUSrcA_in;
            RegWriteD_out   <= RegWriteD_in;
            ResultSrcD_out  <= ResultSrcD_in;
            MemWriteD_out   <= MemWriteD_in;
            BranchD_out     <= BranchD_in;
            JumpD_out       <= JumpD_in;
            JumpR_out       <= JumpR_in;
            ALUType_out     <= ALUType_in;
        end
    end
endmodule



