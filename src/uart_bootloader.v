`default_nettype none
`timescale 1ns / 1ps

// =============================================================================
//  uart_bootloader.v
//  UART bootloader — loads 32-bit RISC-V instructions over UART into an
//  instruction memory, then releases the processor from stall.
//
//  Protocol
//  --------
//  1. Host sends HANDSHAKE_BYTE (0x25).  Core replies ACK (0x55).
//  2. Host streams little-endian 32-bit words, one byte at a time.
//  3. When the ECALL sentinel (0x00000073) is received the core asserts
//     boot_done and releases stall_pro.
//
//  Lint / tapeout notes
//  --------------------
//  • word_buf is only 24 bits — byte[3] of each word is taken directly
//    from rx_data, so it was never read from the MSB slot.  Declared
//    [23:0] to silence the Verilator UNUSEDSIGNAL warning cleanly.
//  • `default_nettype none is set for tapeout hygiene.
//  • All outputs have a defined reset state.
// =============================================================================

module uart_bootloader (
    input  wire        clk,
    input  wire        reset,

    // ── UART RX ──────────────────────────────────────────────────────────────
    input  wire [7:0]  rx_data,
    input  wire        rx_valid,

    // ── UART TX ──────────────────────────────────────────────────────────────
    output reg  [7:0]  tx_data,
    output reg         tx_start,

    // ── Instruction memory write port ────────────────────────────────────────
    output reg         mem_we,
    output reg  [5:0]  mem_addr,
    output reg  [31:0] mem_wdata,

    // ── Processor stall ──────────────────────────────────────────────────────
    output wire        stall_pro
);

    // ── Constants ─────────────────────────────────────────────────────────────
    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073; // ECALL = halt

    // ── Internal registers ────────────────────────────────────────────────────
    reg        handshake_done;
    reg        boot_done;
    reg        rx_valid_d;

    // Only bytes [0:2] are buffered; byte[3] is consumed directly from rx_data
    // on the cycle byte_idx reaches 3, so [31:24] would never be read.
    reg [23:0] word_buf;   // assembles bytes 0-2 (little-endian)
    reg [1:0]  byte_idx;   // 0-3: which byte of the current word
    reg [5:0]  addr_count; // write address into instruction memory

    // Rising-edge detector on rx_valid
    wire rx_edge = rx_valid & ~rx_valid_d;

    // Stall the processor until booting is complete
    assign stall_pro = ~boot_done;

    // ── Main FSM (single always block, synchronous reset) ─────────────────────
    always @(posedge clk) begin
        if (reset) begin
            handshake_done <= 1'b0;
            boot_done      <= 1'b0;
            rx_valid_d     <= 1'b0;
            tx_data        <= 8'b0;
            tx_start       <= 1'b0;
            mem_we         <= 1'b0;
            mem_addr       <= 6'b0;
            mem_wdata      <= 32'b0;
            word_buf       <= 24'b0;
            byte_idx       <= 2'b0;
            addr_count     <= 6'b0;
        end else begin
            // ── Defaults (single-cycle pulses) ────────────────────────────
            rx_valid_d <= rx_valid;
            tx_start   <= 1'b0;
            mem_we     <= 1'b0;

            // ── Handshake phase ───────────────────────────────────────────
            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data        <= ACK;
                    tx_start       <= 1'b1;
                    handshake_done <= 1'b1;
                end else begin
                    tx_data  <= NACK;
                    tx_start <= 1'b1;
                end

            // ── Receive & write phase ─────────────────────────────────────
            end else if (handshake_done && !boot_done && rx_edge) begin

                // Buffer bytes 0-2.  Byte 3 is used directly from rx_data
                // in the write below (avoids the UNUSEDSIGNAL lint warning).
                case (byte_idx)
                    2'd0: word_buf[ 7: 0] <= rx_data;
                    2'd1: word_buf[15: 8] <= rx_data;
                    2'd2: word_buf[23:16] <= rx_data;
                    default: ; // byte 3 — not buffered, read directly below
                endcase

                if (byte_idx == 2'd3) begin
                    // ── Full word assembled ───────────────────────────────
                    // Reconstruct word: {byte3=rx_data, byte2, byte1, byte0}
                    mem_wdata <= {rx_data,
                                  word_buf[23:16],
                                  word_buf[15: 8],
                                  word_buf[ 7: 0]};
                    mem_addr  <= addr_count;
                    mem_we    <= 1'b1;

                    // ── Sentinel check (ECALL → halt) ─────────────────────
                    if ({rx_data,
                         word_buf[23:16],
                         word_buf[15: 8],
                         word_buf[ 7: 0]} == SENTINEL) begin
                        boot_done <= 1'b1;
                        // addr_count intentionally not incremented;
                        // ECALL is the last instruction written.
                    end else if (addr_count != 6'd63) begin
                        addr_count <= addr_count + 6'd1;
                    end
                    // Silently saturate at 63 if no sentinel seen yet —
                    // prevents wrap-around overwriting instructions.

                    byte_idx <= 2'd0;
                end else begin
                    byte_idx <= byte_idx + 2'd1;
                end
            end
        end
    end

endmodule














