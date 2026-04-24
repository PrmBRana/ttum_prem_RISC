`default_nettype none
`timescale 1ns / 1ps

module Hazard_Unit (
    input  wire [4:0]  Rs1D,
    input  wire [4:0]  Rs2D,
    input  wire [4:0]  Rs1E,
    input  wire [4:0]  Rs2E,
    input  wire [4:0]  RdE,
    /* verilator lint_off UNUSEDSIGNAL */
    input  wire        RegWriteE,
    /* verilator lint_on  UNUSEDSIGNAL */
    input  wire [1:0]  ResultSrcE_in,
    input  wire [4:0]  RdM,
    input  wire        RegWriteM,
    input  wire [4:0]  RdW,
    input  wire        RegWriteW,
    input  wire        PCSRCE,
    output reg         StallF,
    output reg         StallD,
    output reg         FlushD,
    output reg         FlushE,
    output reg  [1:0]  Forward_AE,
    output reg  [1:0]  Forward_BE
);
    always @(*) begin
        Forward_AE = 2'b00;
        Forward_BE = 2'b00;
        if      (RegWriteM && (RdM != 5'd0) && (Rs1E == RdM)) Forward_AE = 2'b10;
        else if (RegWriteW && (RdW != 5'd0) && (Rs1E == RdW)) Forward_AE = 2'b01;
        if      (RegWriteM && (RdM != 5'd0) && (Rs2E == RdM)) Forward_BE = 2'b10;
        else if (RegWriteW && (RdW != 5'd0) && (Rs2E == RdW)) Forward_BE = 2'b01;
    end

    wire lw_stall = (ResultSrcE_in == 2'b01) && (RdE != 5'd0) &&
                    ((Rs1D == RdE) || (Rs2D == RdE));

    always @(*) begin
        StallF = 1'b0; StallD = 1'b0; FlushD = 1'b0; FlushE = 1'b0;
        if (PCSRCE) begin
            FlushD = 1'b1; FlushE = 1'b1;
        end else if (lw_stall) begin
            StallF = 1'b1; StallD = 1'b1; FlushE = 1'b1;
        end
    end
endmodule







