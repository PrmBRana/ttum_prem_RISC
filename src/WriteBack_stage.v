`default_nettype none
`timescale 1ns / 1ps

module WriteBack_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] ALUResultW_in,
    input  wire [31:0] ReadDataW_in,
    input  wire [4:0]  RdW_in,
    input  wire [31:0] PCPlus4W_in,
    input  wire        RegWriteW_in,
    input  wire [1:0]  ResultSrcW_in,
    output reg  [31:0] ALUResultW_out,
    output reg  [31:0] ReadDataW_out,
    output reg  [4:0]  RdW_out,
    output reg  [31:0] PCPlus4W_out,
    output reg         RegWriteW_out,
    output reg  [1:0]  ResultSrcW_out
);
    always @(posedge clk) begin
        if (reset) begin
            ALUResultW_out <= 32'b0;
            ReadDataW_out  <= 32'b0;
            RdW_out        <= 5'b0;
            PCPlus4W_out   <= 32'b0;
            RegWriteW_out  <= 1'b0;
            ResultSrcW_out <= 2'b0;
        end else begin
            ALUResultW_out <= ALUResultW_in;
            ReadDataW_out  <= ReadDataW_in;
            RdW_out        <= RdW_in;
            PCPlus4W_out   <= PCPlus4W_in;
            RegWriteW_out  <= RegWriteW_in;
            ResultSrcW_out <= ResultSrcW_in;
        end
    end
endmodule

