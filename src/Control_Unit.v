`default_nettype none
`timescale 1ns / 1ps

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
    output reg         ALUSrcD,
    output reg  [1:0]  ALUSrcA,
    output reg  [2:0]  ImmSrc,
    output reg  [1:0]  ALUType
);

    always @(*) begin
        // ---------------- DEFAULTS ----------------
        RegWriteD   = 1'b0;
        ResultSrcD  = 2'b00;
        MemWriteD   = 1'b0;
        jumpD       = 1'b0;
        jumpR       = 1'b0;
        BranchD     = 1'b0;
        ALUControlD = 4'b0000;
        ALUSrcD     = 1'b0;
        ALUSrcA     = 2'b00;
        ImmSrc      = 3'b000;
        ALUType     = 2'b00;
        halt        = 1'b0;

        // ---------------- DECODE ----------------
        case (Opcode)

            // ================= R TYPE =================
            7'b0110011: begin
                RegWriteD = 1'b1;
                ALUSrcD   = 1'b0;
                ALUType   = 2'b00;

                case ({funct7, funct3})
                    {7'b0000000,3'b000}: ALUControlD = 4'b0010;
                    {7'b0100000,3'b000}: ALUControlD = 4'b0011;
                    {7'b0000000,3'b110}: ALUControlD = 4'b0001;
                    {7'b0000000,3'b111}: ALUControlD = 4'b0000;
                    {7'b0000000,3'b100}: ALUControlD = 4'b0100;
                    {7'b0000000,3'b001}: ALUControlD = 4'b0101;
                    {7'b0000000,3'b101}: ALUControlD = 4'b0110;
                    {7'b0100000,3'b101}: ALUControlD = 4'b0111;
                    {7'b0000000,3'b010}: ALUControlD = 4'b1000;
                    {7'b0000000,3'b011}: ALUControlD = 4'b1001;
                    default:             ALUControlD = 4'b0000;
                endcase
            end

            // ================= I TYPE =================
            7'b0010011: begin
                RegWriteD = 1'b1;
                ALUSrcD   = 1'b1;
                ImmSrc    = 3'b000;
                ALUType   = 2'b00;

                case (funct3)
                    3'b000: ALUControlD = 4'b0010;
                    3'b100: ALUControlD = 4'b0100;
                    3'b110: ALUControlD = 4'b0001;
                    3'b111: ALUControlD = 4'b0000;
                    3'b001: ALUControlD = 4'b0101;
                    3'b101: ALUControlD = (funct7 == 7'b0100000) ? 4'b0111 : 4'b0110;
                    3'b010: ALUControlD = 4'b1000;
                    3'b011: ALUControlD = 4'b1001;
                    default: ALUControlD = 4'b0000;
                endcase
            end

            // ================= LOAD =================
            7'b0000011: begin
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b01;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b000;
                ALUControlD = 4'b0010;
                ALUType     = 2'b00;
            end

            // ================= STORE =================
            7'b0100011: begin
                MemWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b001;
                ALUControlD = 4'b0010;
                ALUType     = 2'b01;
            end

            // ================= BRANCH =================
            7'b1100011: begin
                BranchD = 1'b1;
                ALUSrcD = 1'b0;
                ImmSrc  = 3'b010;
                ALUType = 2'b10;

                case (funct3)
                    3'b000: ALUControlD = 4'b0000;
                    3'b001: ALUControlD = 4'b0001;
                    3'b100: ALUControlD = 4'b0010;
                    3'b101: ALUControlD = 4'b0011;
                    3'b110: ALUControlD = 4'b0100;
                    3'b111: ALUControlD = 4'b0101;
                    default: ALUControlD = 4'b0000;
                endcase
            end

            // ================= JAL =================
            7'b1101111: begin
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b10;
                jumpD       = 1'b1;
                ImmSrc      = 3'b011;
                ALUSrcD     = 1'b1;
                ALUControlD = 4'b0010;
                ALUType     = 2'b11;
            end

            // ================= JALR =================
            7'b1100111: begin
                RegWriteD   = 1'b1;
                ResultSrcD  = 2'b10;
                jumpD       = 1'b1;
                jumpR       = 1'b1;
                ALUSrcD     = 1'b1;
                ImmSrc      = 3'b000;
                ALUControlD = 4'b0010;
                ALUType     = 2'b11;
            end

            // ================= LUI =================
            7'b0110111: begin
                RegWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ALUSrcA     = 2'b10;
                ImmSrc      = 3'b100;
                ALUControlD = 4'b1010;
                ALUType     = 2'b00;
            end

            // ================= AUIPC =================
            7'b0010111: begin
                RegWriteD   = 1'b1;
                ALUSrcD     = 1'b1;
                ALUSrcA     = 2'b01;
                ImmSrc      = 3'b100;
                ALUControlD = 4'b0010;
                ALUType     = 2'b00;
            end

            // ================= SYSTEM =================
            7'b1110011: begin
                if (funct3 == 3'b000)
                    halt = (imm == 12'h000 || imm == 12'h001);
            end

            default: ;
        endcase
    end

endmodule




