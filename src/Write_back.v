`default_nettype none
`timescale 1ns / 1ps

module Write_back (
    input  wire [31:0] ALUResultW_in,
    input  wire [31:0] ReadDataW_in,
    input  wire [31:0] PCPlus4W_in,
    input  wire [1:0]  ResultSrcW_in,
    output wire [31:0] ResultW
);
    assign ResultW = (ResultSrcW_in == 2'b00) ? ALUResultW_in :
                     (ResultSrcW_in == 2'b01) ? ReadDataW_in  :
                     (ResultSrcW_in == 2'b10) ? PCPlus4W_in  :
                                                32'b0;
endmodule



