`default_nettype none
`timescale 1ns / 1ps

module imm (
    input  wire [2:0]  ImmSrc,
    input  wire [31:0] instruction,
    output reg  [31:0] ImmExt
);
    // instruction[6:0] is the opcode — not needed here since
    // ImmSrc already encodes the format. Suppressed cleanly.
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_opcode = &{1'b0, instruction[6:0]};
    /* verilator lint_on  UNUSEDSIGNAL */

    always @(*) begin
        case (ImmSrc)
            3'b000: ImmExt = {{20{instruction[31]}}, instruction[31:20]};
            3'b001: ImmExt = {{20{instruction[31]}}, instruction[31:25], instruction[11:7]};
            3'b010: ImmExt = {{19{instruction[31]}}, instruction[31], instruction[7],
                               instruction[30:25], instruction[11:8], 1'b0};
            3'b011: ImmExt = {{11{instruction[31]}}, instruction[31], instruction[19:12],
                               instruction[20], instruction[30:21], 1'b0};
            3'b100: ImmExt = {instruction[31:12], 12'b0};
            default: ImmExt = 32'd0;
        endcase
    end
endmodule







