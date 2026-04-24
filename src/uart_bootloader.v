`default_nettype none
`timescale 1ns / 1ps

module uart_bootloader (
    input  wire        clk,
    input  wire        reset,     // async reset (match pipeline style)

    input  wire [7:0] rx_data,
    input  wire       rx_valid,

    output reg  [7:0] tx_data,
    output reg         tx_start,

    // boot writes into instruction memory / imem
    output reg         mem_we,
    output reg  [5:0] mem_addr,   // 6-bit IMEM word index
    output reg  [31:0] mem_wdata,

    output reg         stall_pro
);

    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;

    reg        handshake_done, boot_done, rx_valid_d;
    reg [31:0] buffer0, buffer1;
    reg         buffer_full0, buffer_full1, buffer_sel;
    reg [1:0]   byte_count;

    // DEPTH=64 => word addresses 0..63
    reg [5:0] addr_count;

    reg [31:0] mem_wdata_reg;
    reg [5:0]  mem_addr_reg;
    reg         mem_we_reg;

    wire rx_edge = rx_valid & ~rx_valid_d;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            rx_valid_d <= 1'b0;
            tx_data    <= 8'b0;
            tx_start   <= 1'b0;

            mem_we     <= 1'b0;
            mem_addr   <= 6'b0;
            mem_wdata  <= 32'b0;

            handshake_done <= 1'b0;
            boot_done      <= 1'b0;

            buffer0 <= 32'b0;
            buffer1 <= 32'b0;

            buffer_full0 <= 1'b0;
            buffer_full1 <= 1'b0;
            buffer_sel   <= 1'b0;
            byte_count   <= 2'b0;

            addr_count    <= 6'd0;
            mem_wdata_reg <= 32'b0;
            mem_addr_reg  <= 6'd0;
            mem_we_reg    <= 1'b0;

            stall_pro <= 1'b1;
        end else begin
            rx_valid_d <= rx_valid;
            tx_start   <= 1'b0;

            // drive registered outputs (no padding)
            mem_we     <= mem_we_reg;
            mem_addr   <= mem_addr_reg;
            mem_wdata  <= mem_wdata_reg;

            stall_pro <= ~boot_done;

            // ---------------- handshake ----------------
            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data <= ACK;
                    tx_start <= 1'b1;
                    handshake_done <= 1'b1;
                end else begin
                    tx_data <= NACK;
                    tx_start <= 1'b1;
                end
            end
            // ---------------- receive 8 bytes per word? (2 buffers of 4 bytes = 32-bit each word) ----------------
            else if (handshake_done && rx_edge && !boot_done) begin
                if (!buffer_sel) begin
                    case (byte_count)
                        2'd0: buffer0[7:0]    <= rx_data;
                        2'd1: buffer0[15:8]   <= rx_data;
                        2'd2: buffer0[23:16]  <= rx_data;
                        2'd3: begin buffer0[31:24] <= rx_data; buffer_full0 <= 1'b1; end
                        default: ;
                    endcase
                end else begin
                    case (byte_count)
                        2'd0: buffer1[7:0]    <= rx_data;
                        2'd1: buffer1[15:8]   <= rx_data;
                        2'd2: buffer1[23:16]  <= rx_data;
                        2'd3: begin buffer1[31:24] <= rx_data; buffer_full1 <= 1'b1; end
                        default: ;
                    endcase
                end

                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0;
                    buffer_sel <= ~buffer_sel;
                end else begin
                    byte_count <= byte_count + 2'd1;
                end
            end

            // ---------------- write buffered words into imem ----------------
            if (buffer_full0) begin
                mem_wdata_reg <= buffer0;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;

                if (buffer0 == SENTINEL) begin
                    boot_done <= 1'b1;
                    addr_count <= addr_count; // hold
                end else if (addr_count != 6'd63) begin
                    addr_count <= addr_count + 6'd1;
                end

                buffer_full0 <= 1'b0;
            end else if (buffer_full1) begin
                mem_wdata_reg <= buffer1;
                mem_addr_reg  <= addr_count;
                mem_we_reg    <= 1'b1;

                if (buffer1 == SENTINEL) begin
                    boot_done <= 1'b1;
                    addr_count <= addr_count; // hold
                end else if (addr_count != 6'd63) begin
                    addr_count <= addr_count + 6'd1;
                end

                buffer_full1 <= 1'b0;
            end else begin
                mem_we_reg <= 1'b0;
            end
        end
    end

endmodule













