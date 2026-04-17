`default_nettype none
`timescale 1ns / 1ps

module IF_ID_stage (
    input  wire        clk,
    input  wire        reset,
    input  wire        stallD,
    input  wire        flushD,
    input  wire [31:0] PC_in,
    input  wire [31:0] PCplus4_in,
    input  wire [31:0] instruction_in,
    output reg  [31:0] instruction_out,
    output reg  [31:0] PCplus4_out,
    output reg  [31:0] PC_out
);
    always @(posedge clk) begin
        if (reset || flushD) begin
            instruction_out <= 32'h00000013;
            PCplus4_out     <= 32'd0;
            PC_out          <= 32'd0;
        end else if (!stallD) begin
            instruction_out <= instruction_in;
            PCplus4_out     <= PCplus4_in;
            PC_out          <= PC_in;
        end
    end
endmodule

