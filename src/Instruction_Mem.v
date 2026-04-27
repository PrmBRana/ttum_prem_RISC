`default_nettype none
`timescale 1ns/1ps

module instruction_mem #(
    parameter integer DEPTH  = 64,
    parameter integer ADDR_W = 6
)(
    input  wire              clk,
    input  wire              reset,
    input  wire              we,

    input  wire [ADDR_W-1:0] addr,
    input  wire [31:0]       wdata,

    input  wire [ADDR_W-1:0] read_word_idx,
    output wire [31:0]       Instruction_out
);

    localparam [31:0] NOP = 32'h0000_0013;

    reg [31:0] mem [0:DEPTH-1];

`ifndef SYNTHESIS
    integer i;
`endif

    // ── Write + simulation reset ──────────────────────────────
    always @(posedge clk) begin
`ifndef SYNTHESIS
        if (reset) begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= NOP;
        end else
`endif
        begin
            if (we)
                mem[addr] <= wdata;
        end
    end

    // ── Async read (required by your pipeline) ────────────────
    assign Instruction_out = mem[read_word_idx];

endmodule







