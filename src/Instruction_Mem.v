`default_nettype none
`timescale 1ns / 1ps

module mem1KB_32bit #(
    parameter DEPTH  = 64,
    parameter ADDR_W = 6
)(
    input  wire              clk,
    input  wire              reset,
    input  wire              we,
    input  wire [ADDR_W-1:0] addr,
    input  wire [31:0]       wdata,

    input  wire [31:0]       read_Address,
    output wire [31:0]       Instruction_out
);

    localparam [31:0] NOP = 32'h0000_0013;

    // ---------------------------------------------------------
    // Explicitly mark unused bits (ASIC-clean)
    // ---------------------------------------------------------
    wire _unused_read_addr;
    assign _unused_read_addr = |{
        read_Address[1:0],
        read_Address[31:ADDR_W+2]
    };

    // =========================================================
    // Memory array
    // =========================================================
    reg [31:0] mem [0:DEPTH-1];

    integer i;

    always @(posedge clk) begin
        `ifndef SYNTHESIS
        if (reset) begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= NOP;
        end else
        `endif
        if (we) begin
            mem[addr] <= wdata;
        end
    end

    // =========================================================
    // Address decode
    // =========================================================
    wire [ADDR_W-1:0] word_idx;
    assign word_idx = read_Address[ADDR_W+1:2];

    // =========================================================
    // Read
    // =========================================================
    assign Instruction_out = mem[word_idx];

endmodule





