`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// ALU.v
//
// Fix: added ALUControl 4'b1010 = passB (ALUResult = ScrB).
//      Used by LUI so the immediate is written directly to rd.
// =============================================================================

module ALU (
    input  wire [31:0] ScrA,
    input  wire [31:0] ScrB,
    input  wire [3:0]  ALUControl,
    input  wire [1:0]  ALUType,
    output reg  [31:0] ALUResult,
    output reg         Zero
);

    wire [31:0] sum  = ScrA + ScrB;
    wire [31:0] diff = ScrA - ScrB;

    always @(*) begin
        ALUResult = 32'd0;
        Zero      = 1'b0;

        case (ALUType)
            // ── Store / JAL address: always ADD ──────────────
            2'b01, 2'b11: ALUResult = sum;

            // ── Branch: produces Zero flag only ──────────────
            2'b10: begin
                ALUResult = 32'd0;
                case (ALUControl)
                    4'b0000: Zero = (ScrA == ScrB);           // BEQ
                    4'b0001: Zero = (ScrA != ScrB);           // BNE
                    4'b0010: Zero = ($signed(ScrA) <  $signed(ScrB)); // BLT
                    4'b0011: Zero = ($signed(ScrA) >= $signed(ScrB)); // BGE
                    4'b0100: Zero = (ScrA <  ScrB);           // BLTU
                    4'b0101: Zero = (ScrA >= ScrB);           // BGEU
                    default: Zero = 1'b0;
                endcase
            end

            // ── Arithmetic / logic / shift ────────────────────
            2'b00: begin
                case (ALUControl)
                    4'b0000: ALUResult = ScrA & ScrB;                          // AND/ANDI
                    4'b0001: ALUResult = ScrA | ScrB;                          // OR/ORI
                    4'b0010: ALUResult = sum;                                  // ADD/ADDI/LOAD/STORE/AUIPC
                    4'b0011: ALUResult = diff;                                 // SUB
                    4'b0100: ALUResult = ScrA ^ ScrB;                          // XOR/XORI
                    4'b0101: ALUResult = ScrA << ScrB[4:0];                    // SLL/SLLI
                    4'b0110: ALUResult = ScrA >> ScrB[4:0];                    // SRL/SRLI
                    4'b0111: ALUResult = $signed(ScrA) >>> ScrB[4:0];          // SRA/SRAI
                    4'b1000: ALUResult = ($signed(ScrA) < $signed(ScrB)) ? 32'd1 : 32'd0; // SLT
                    4'b1001: ALUResult = (ScrA < ScrB) ? 32'd1 : 32'd0;       // SLTU
                    4'b1010: ALUResult = ScrB;                                 // passB — LUI
                    default: ALUResult = 32'd0;
                endcase
                Zero = (ALUResult == 32'd0);
            end

            default: begin
                ALUResult = 32'd0;
                Zero      = 1'b0;
            end
        endcase
    end
endmodule


