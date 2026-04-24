`default_nettype none
`timescale 1ns/1ps

module instruction_mem #(
    parameter integer DEPTH  = 64,
    parameter integer ADDR_W = 6
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  we,

    input  wire [ADDR_W-1:0]    addr,            // write word addr (0..DEPTH-1)
    input  wire [31:0]          wdata,

    input  wire [ADDR_W-1:0]    read_word_idx, // read word idx only
    output wire [31:0]          Instruction_out
);

    localparam [31:0] NOP = 32'h0000_0013;

    reg [31:0] mem [0:DEPTH-1];
    integer i;

    always @(posedge clk) begin
        `ifndef SYNTHESIS
        if (reset) begin
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= NOP;
        end else
        `endif
        begin
            if (we) begin
                mem[addr] <= wdata;
            end
        end
    end

    assign Instruction_out = mem[read_word_idx];

endmodule






