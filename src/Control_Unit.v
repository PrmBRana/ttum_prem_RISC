`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
// Control.v
//
// Bug fixes:
//   LUI  (0110111): rd = imm (not rs1+imm).
//                   ALUSrcA=2'b10 forces SrcA=0 in pipeline.
//                   ALUControl=4'b1010 (passB) outputs ScrB directly.
//   AUIPC(0010111): rd = PC + imm (not rs1+imm).
//                   ALUSrcA=2'b01 forces SrcA=PC_E in pipeline.
//                   ALUType=2'b00 + ALUControl=ADD performs PC+imm.
//
// New output: ALUSrcA [1:0]
//   2'b00 = SrcA from forwarding mux (RD1) — all normal instructions
//   2'b01 = SrcA = PC_E                    — AUIPC
//   2'b10 = SrcA = 32'b0                   — LUI
// =============================================================================

module Control (
    input  wire [6:0]  Opcode,
    input  wire [2:0]  funct3,
    input  wire [6:0]  funct7,
    input  wire [11:0] imm,
    output reg         halt,
    output reg         RegWriteD,
    output reg  [1:0]  ResultSrcD,
    output reg         MemWriteD,
    output reg         jumpD,
    output reg         jumpR,
    output reg         BranchD,
    output reg  [3:0]  ALUControlD,
    output reg         ALUSrcD,      // SrcB select: 0=RD2, 1=Imm
    output reg  [1:0]  ALUSrcA,      // NEW: SrcA select (see header)
    output reg  [2:0]  ImmSrc,
    output reg  [1:0]  ALUType
);
    always @(*) begin
        // Defaults
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        jumpD       = 1'b0;
        jumpR       = 1'b0;
        BranchD     = 1'b0;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ALUSrcA     = 2'b00;   // default: use forwarding mux (RD1)
        ImmSrc      = 3'b000;
        ALUType     = 2'b00;
        halt        = 1'b0;

        case (Opcode)
            7'b0110011: begin // R-type
                RegWriteD = 1'b1;
                ALUSrcD   = 1'b0;
                ALUType   = 2'b00;
                case ({funct7, funct3})
                    {7'b0000000,3'b000}: ALUControlD = 4'b0010; // ADD
                    {7'b0100000,3'b000}: ALUControlD = 4'b0011; // SUB
                    {7'b0000000,3'b110}: ALUControlD = 4'b0001; // OR
                    {7'b0000000,3'b111}: ALUControlD = 4'b0000; // AND
                    {7'b0000000,3'b100}: ALUControlD = 4'b0100; // XOR
                    {7'b0000000,3'b001}: ALUControlD = 4'b0101; // SLL
                    {7'b0000000,3'b101}: ALUControlD = 4'b0110; // SRL
                    {7'b0100000,3'b101}: ALUControlD = 4'b0111; // SRA
                    {7'b0000000,3'b010}: ALUControlD = 4'b1000; // SLT
                    {7'b0000000,3'b011}: ALUControlD = 4'b1001; // SLTU
                    default:             ALUControlD = 4'b0000;
                endcase
            end

            7'b0010011: begin // I-type ALU
                RegWriteD = 1'b1;
                ALUSrcD   = 1'b1;
                ImmSrc    = 3'b000;
                ALUType   = 2'b00;
                case (funct3)
                    3'b000: ALUControlD = 4'b0010; // ADDI
                    3'b100: ALUControlD = 4'b0100; // XORI
                    3'b110: ALUControlD = 4'b0001; // ORI
                    3'b111: ALUControlD = 4'b0000; // ANDI
                    3'b001: ALUControlD = 4'b0101; // SLLI
                    3'b101: ALUControlD = (funct7 == 7'b0100000) ? 4'b0111 : 4'b0110;
                    3'b010: ALUControlD = 4'b1000; // SLTI
                    3'b011: ALUControlD = 4'b1001; // SLTIU
                    default: ALUControlD = 4'b0000;
                endcase
            end

            7'b0000011: begin // LOAD
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b01;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b000;
                ALUControlD = 4'b0010; // ADD (address)
                ALUType     = 2'b00;
            end

            7'b0100011: begin // STORE
                MemWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b001;
                ALUControlD = 4'b0010; // ADD (address)
                ALUType     = 2'b01;
            end

            7'b1100011: begin // BRANCH
                BranchD = 1'b1;
                ALUSrcD = 1'b0;
                ImmSrc  = 3'b010;
                ALUType = 2'b10;
                case (funct3)
                    3'b000: ALUControlD = 4'b0000; // BEQ
                    3'b001: ALUControlD = 4'b0001; // BNE
                    3'b100: ALUControlD = 4'b0010; // BLT
                    3'b101: ALUControlD = 4'b0011; // BGE
                    3'b110: ALUControlD = 4'b0100; // BLTU
                    3'b111: ALUControlD = 4'b0101; // BGEU
                    default: ALUControlD = 4'b0000;
                endcase
            end

            7'b1101111: begin // JAL
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b10;
                jumpD       = 1'b1;
                jumpR       = 1'b0;
                ImmSrc      = 3'b011;
                ALUSrcD     = 1'b1;
                ALUControlD = 4'b0010;
                ALUType     = 2'b11;
            end

            7'b1100111: begin // JALR
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b10;
                jumpD       = 1'b1;
                jumpR       = 1'b1;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b000;
                ALUControlD = 4'b0010;
                ALUType     = 2'b11;
            end

            7'b0110111: begin // LUI — FIX: rd = imm (SrcA forced to 0)
                RegWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ALUSrcA     = 2'b10;   // SrcA = 0
                ImmSrc      = 3'b100;
                ALUControlD = 4'b1010; // passB: ALUResult = ScrB
                ALUType     = 2'b00;
            end

            7'b0010111: begin // AUIPC — FIX: rd = PC + imm
                RegWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ALUSrcA     = 2'b01;   // SrcA = PC_E
                ImmSrc      = 3'b100;
                ALUControlD = 4'b0010; // ADD
                ALUType     = 2'b00;
            end

            7'b1110011: begin // ECALL/EBREAK
                if (funct3 == 3'b000)
                    halt = (imm == 12'h000 || imm == 12'h001) ? 1'b1 : 1'b0;
            end

            default: ;
        endcase
    end
endmodule



