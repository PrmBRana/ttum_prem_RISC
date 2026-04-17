`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  uart_bootloader
//
//  TX behaviour: ACK/NACK only.
//    ACK  (0x55) — sent once when valid handshake byte (0x25)
//                  is received.
//    NACK (0xFF) — sent when an invalid handshake byte is
//                  received before handshake is complete.
//    Nothing else is ever transmitted.
//
//  Fix: removed the echo block that was re-transmitting all
//  4 bytes of every instruction word written to IMEM.
//  That echo was the source of the "unusual data" seen on the
//  TX line. Removed registers: echo_buffer, echo_byte_count,
//  echo_active. Removed echo setup from memory write pipeline.
//
//  mem_addr port is [7:0] for pipeline compatibility.
//  Internal addr_count is [4:0] (DEPTH=32 → max address 31).
// ============================================================
module uart_bootloader (
    input  wire        clk,
    input  wire        reset,
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,
    output reg  [7:0]  tx_data,
    output reg         tx_start,
    output reg         mem_we,
    output reg  [7:0]  mem_addr,
    output reg  [31:0] mem_wdata,
    output reg         stall_pro
);

    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;  // ECALL — marks end of program

    reg handshake_done;
    reg boot_done;
    reg rx_valid_d;

    reg [31:0] buffer0, buffer1;
    reg        buffer_full0, buffer_full1;
    reg        buffer_sel;
    reg [1:0]  byte_count;
    reg [4:0]  addr_count;    // 5-bit: covers addresses 0..31

    wire rx_edge = rx_valid & ~rx_valid_d;

    // Internal pipeline registers
    reg [31:0] mem_wdata_reg;
    reg [4:0]  mem_addr_reg;
    reg        mem_we_reg;

    always @(posedge clk) begin
        if (reset) begin
            rx_valid_d     <= 1'b0;
            tx_data        <= 8'd0;
            tx_start       <= 1'b0;
            mem_we         <= 1'b0;
            mem_addr       <= 8'd0;
            mem_wdata      <= 32'd0;
            handshake_done <= 1'b0;
            boot_done      <= 1'b0;
            buffer0        <= 32'd0;
            buffer1        <= 32'd0;
            buffer_full0   <= 1'b0;
            buffer_full1   <= 1'b0;
            buffer_sel     <= 1'b0;
            byte_count     <= 2'd0;
            addr_count     <= 5'd0;
            stall_pro      <= 1'b1;
            mem_wdata_reg  <= 32'd0;
            mem_addr_reg   <= 5'd0;
            mem_we_reg     <= 1'b0;
        end else begin
            rx_valid_d <= rx_valid;

            // Default: no TX, no mem write
            tx_start <= 1'b0;

            // Propagate pipelined memory write to outputs
            mem_we    <= mem_we_reg;
            mem_addr  <= {3'b000, mem_addr_reg};
            mem_wdata <= mem_wdata_reg;
            stall_pro <= ~boot_done;

            // ── Handshake: send ACK or NACK ──────────────────
            // ONLY place that ever asserts tx_start.
            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data        <= ACK;
                    tx_start       <= 1'b1;
                    handshake_done <= 1'b1;
                end else begin
                    tx_data  <= NACK;
                    tx_start <= 1'b1;
                end
            end

            // ── Data reception (after handshake) ─────────────
            else if (handshake_done && rx_edge && !boot_done) begin
                if (!buffer_sel) begin
                    case (byte_count)
                        2'd0: buffer0[7:0]   <= rx_data;
                        2'd1: buffer0[15:8]  <= rx_data;
                        2'd2: buffer0[23:16] <= rx_data;
                        2'd3: begin
                            buffer0[31:24] <= rx_data;
                            buffer_full0   <= 1'b1;
                        end
                        default: ;
                    endcase
                end else begin
                    case (byte_count)
                        2'd0: buffer1[7:0]   <= rx_data;
                        2'd1: buffer1[15:8]  <= rx_data;
                        2'd2: buffer1[23:16] <= rx_data;
                        2'd3: begin
                            buffer1[31:24] <= rx_data;
                            buffer_full1   <= 1'b1;
                        end
                        default: ;
                    endcase
                end

                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0;
                    buffer_sel <= ~buffer_sel;
                end else begin
                    byte_count <= byte_count + 1'b1;
                end
            end

            // ── Memory write pipeline ─────────────────────────
            // No echo — just write to IMEM silently.
            if (buffer_full0) begin
                mem_wdata_reg <= buffer0;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;
                addr_count    <= addr_count + 1'b1;
                buffer_full0  <= 1'b0;
                if (buffer0 == SENTINEL) boot_done <= 1'b1;
            end else if (buffer_full1) begin
                mem_wdata_reg <= buffer1;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;
                addr_count    <= addr_count + 1'b1;
                buffer_full1  <= 1'b0;
                if (buffer1 == SENTINEL) boot_done <= 1'b1;
            end else begin
                mem_we_reg <= 1'b0;
            end
        end
    end
endmodule







