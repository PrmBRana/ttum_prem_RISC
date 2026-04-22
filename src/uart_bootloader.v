`default_nettype none
`timescale 1ns / 1ps

// uart_bootloader: reset is used synchronously here (inside
// always @(posedge clk)). This is intentional — stall_pro and
// mem_we must not glitch on async reset assertion.
// SYNCASYNCNET suppressed: the async usage lives in pipeline.v
// (reset_ff1/ff2 synchroniser), not here.
/* verilator lint_off SYNCASYNCNET */
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
/* verilator lint_on  SYNCASYNCNET */

    localparam [7:0]  HANDSHAKE_BYTE = 8'h25;
    localparam [7:0]  ACK            = 8'h55;
    localparam [7:0]  NACK           = 8'hFF;
    localparam [31:0] SENTINEL       = 32'h00000073;

    reg handshake_done, boot_done, rx_valid_d;
    reg [31:0] buffer0, buffer1;
    reg        buffer_full0, buffer_full1, buffer_sel;
    reg [1:0]  byte_count;
    reg [4:0]  addr_count;
    wire rx_edge = rx_valid & ~rx_valid_d;
    reg [31:0] mem_wdata_reg;
    reg [4:0]  mem_addr_reg;
    reg        mem_we_reg;

    always @(posedge clk) begin
        if (reset) begin
            rx_valid_d <= 0; tx_data <= 0; tx_start <= 0;
            mem_we <= 0; mem_addr <= 0; mem_wdata <= 0;
            handshake_done <= 0; boot_done <= 0;
            buffer0 <= 0; buffer1 <= 0;
            buffer_full0 <= 0; buffer_full1 <= 0;
            buffer_sel <= 0; byte_count <= 0; addr_count <= 0;
            stall_pro <= 1; mem_wdata_reg <= 0;
            mem_addr_reg <= 0; mem_we_reg <= 0;
        end else begin
            rx_valid_d <= rx_valid;
            tx_start   <= 1'b0;
            mem_we     <= mem_we_reg;
            mem_addr   <= {3'b000, mem_addr_reg};
            mem_wdata  <= mem_wdata_reg;
            stall_pro  <= ~boot_done;

            if (!handshake_done && rx_edge) begin
                if (rx_data == HANDSHAKE_BYTE) begin
                    tx_data <= ACK; tx_start <= 1'b1; handshake_done <= 1'b1;
                end else begin
                    tx_data <= NACK; tx_start <= 1'b1;
                end
            end else if (handshake_done && rx_edge && !boot_done) begin
                if (!buffer_sel) begin
                    case (byte_count)
                        2'd0: buffer0[7:0]   <= rx_data;
                        2'd1: buffer0[15:8]  <= rx_data;
                        2'd2: buffer0[23:16] <= rx_data;
                        2'd3: begin buffer0[31:24] <= rx_data; buffer_full0 <= 1'b1; end
                        default: ;
                    endcase
                end else begin
                    case (byte_count)
                        2'd0: buffer1[7:0]   <= rx_data;
                        2'd1: buffer1[15:8]  <= rx_data;
                        2'd2: buffer1[23:16] <= rx_data;
                        2'd3: begin buffer1[31:24] <= rx_data; buffer_full1 <= 1'b1; end
                        default: ;
                    endcase
                end
                if (byte_count == 2'd3) begin
                    byte_count <= 2'd0; buffer_sel <= ~buffer_sel;
                end else byte_count <= byte_count + 1'b1;
            end

            if (buffer_full0) begin
                mem_wdata_reg <= buffer0; mem_addr_reg <= addr_count;
                mem_we_reg <= 1'b1; addr_count <= addr_count + 1'b1;
                buffer_full0 <= 1'b0;
                if (buffer0 == SENTINEL) boot_done <= 1'b1;
            end else if (buffer_full1) begin
                mem_wdata_reg <= buffer1; mem_addr_reg <= addr_count;
                mem_we_reg <= 1'b1; addr_count <= addr_count + 1'b1;
                buffer_full1 <= 1'b0;
                if (buffer1 == SENTINEL) boot_done <= 1'b1;
            end else begin
                mem_we_reg <= 1'b0;
            end
        end
    end
endmodule










