`default_nettype none
`timescale 1ns / 1ps

module MEM_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] ALUResult_in,
    input  wire [31:0] WriteData_in,
    input  wire [4:0]  RdM_in,
    input  wire [31:0] PCPlus4M_in,
    input  wire        RegWriteM_in,
    input  wire [1:0]  ResultSrcM_in,
    input  wire        MemWriteM_in,
    output reg  [31:0] ALUResult_out,
    output reg  [31:0] WriteData_out,
    output reg  [4:0]  RdM_out,
    output reg  [31:0] PCPlus4M_out,
    output reg         RegWriteM_out,
    output reg  [1:0]  ResultSrcM_out,
    output reg         MemWriteM_out
);
    always @(posedge clk) begin
        if (reset) begin
            ALUResult_out  <= 32'b0;
            WriteData_out  <= 32'b0;
            RdM_out        <= 5'b0;
            PCPlus4M_out   <= 32'b0;
            RegWriteM_out  <= 1'b0;
            ResultSrcM_out <= 2'b0;
            MemWriteM_out  <= 1'b0;
        end else begin
            ALUResult_out  <= ALUResult_in;
            WriteData_out  <= WriteData_in;
            RdM_out        <= RdM_in;
            PCPlus4M_out   <= PCPlus4M_in;
            RegWriteM_out  <= RegWriteM_in;
            ResultSrcM_out <= ResultSrcM_in;
            MemWriteM_out  <= MemWriteM_in;
        end
    end
endmodule

