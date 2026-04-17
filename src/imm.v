`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  imm — Immediate generator
//
//  instruction[6:0] (opcode) is architecturally unused —
//  ImmSrc already encodes the format so the opcode bits are
//  redundant here. Suppressed with an internal wire that
//  consumes the bits cleanly (Verilog-2001 compatible —
//  port-level pragmas are not supported in Verilog-2001).
// ============================================================
module imm (
    input  wire [2:0]  ImmSrc,
    input  wire [31:0] instruction,
    output reg  [31:0] ImmExt
);
    // Consume opcode bits to silence UNUSEDSIGNAL.
    // The reduction-AND ensures zero logic is synthesised.
    /* verilator lint_off UNUSEDSIGNAL */
    wire _unused_ok = &{1'b0, instruction[6:0]};
    /* verilator lint_on UNUSEDSIGNAL */

    always @(*) begin
        case (ImmSrc)
            // I-type: sign-extend imm[11:0]
            3'b000: ImmExt = {{20{instruction[31]}},
                               instruction[31:20]};
            // S-type: sign-extend {imm[11:5], imm[4:0]}
            3'b001: ImmExt = {{20{instruction[31]}},
                               instruction[31:25],
                               instruction[11:7]};
            // B-type: sign-extend branch offset
            3'b010: ImmExt = {{19{instruction[31]}},
                               instruction[31],
                               instruction[7],
                               instruction[30:25],
                               instruction[11:8],
                               1'b0};
            // J-type: sign-extend jump offset
            3'b011: ImmExt = {{11{instruction[31]}},
                               instruction[31],
                               instruction[19:12],
                               instruction[20],
                               instruction[30:21],
                               1'b0};
            // U-type: upper immediate — LUI / AUIPC
            3'b100: ImmExt = {instruction[31:12], 12'b0};
            default: ImmExt = 32'b0;
        endcase
    end
endmodule




