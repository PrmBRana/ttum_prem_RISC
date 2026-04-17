`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  mem1KB_32bit — Instruction memory (DEPTH × 32-bit words)
//  Optimized for ASIC: port widths explicitly sized
//  Option 1: explicitly mark unused bits to silence Verilator warning
// ============================================================

module mem1KB_32bit #(
    parameter DEPTH  = 64,                       // number of 32-bit words
    parameter ADDR_W = $clog2(DEPTH)            // width of address bus
)(
    input  wire              clk,               // clock for write
    input  wire              reset,             // simulation reset only
    input  wire              we,                // write enable
    input  wire [ADDR_W-1:0] addr,             // write address (word index)
    input  wire [31:0]       wdata,            // write data

    input  wire [31:0]       read_Address,     // PC byte address
    output wire [31:0]       Instruction_out   // read data
);

    localparam [31:0] NOP = 32'h0000_0013;      // ADDI x0,x0,0

    // memory array
    reg [31:0] mem [0:DEPTH-1];

    // ── Synchronous write with simulation reset ─────────────────
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

    // ── Combinational asynchronous read ────────────────────────
    // slice read_Address to match DEPTH exactly
    wire [ADDR_W-1:0] word_idx;
    assign word_idx = read_Address[ADDR_W+1:2];  // word-aligned address

    // explicitly mark unused bits as ignored to silence warning
    wire [31:ADDR_W+2] unused_high = read_Address[31:ADDR_W+2];
    wire [1:0] unused_low = read_Address[1:0];

    assign Instruction_out = mem[word_idx];

endmodule



