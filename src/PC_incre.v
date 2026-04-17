`default_nettype none
`timescale 1ns / 1ps

module PC_incre (
    input  wire [31:0] pc,
    output wire [31:0] PCPlus4
);
    assign PCPlus4 = pc + 32'd4;
endmodule


