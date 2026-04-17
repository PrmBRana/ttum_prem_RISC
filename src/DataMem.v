`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  DataMem — Memory-mapped peripheral controller
//
//  ADDRESS MAP:
//  ─────────────────────────────────────────────────────────
//  UART  base 0x10000000
//    0x10000000  TX data      sw
//    0x10000004  RX data      lw
//    0x10000008  TX status    lw  {30b0, tx_busy, tx_full}
//    0x1000000C  RX status    lw  {30b0, rx_full, rx_not_empty}
//
//  SPI1  base 0x20000000  (CLK_DIV=4, 12.5MHz — flash/EEPROM)
//    0x20000000  TX data      sw
//    0x20000004  TX status    lw  {30b0, pending, busy}
//    0x20000008  RX data      lw
//    0x2000000C  RX status    lw  {30b0, full, not_empty}
//
//  SPI2  base 0x40000000  (CLK_DIV=8, 6.25MHz — sensors)
//    0x40000000  TX data      sw
//    0x40000004  TX status    lw  {30b0, pending, busy}
//    0x40000008  RX data      lw
//    0x4000000C  RX status    lw  {30b0, full, not_empty}
//
//  GPIO1 = 0x30000000  → SPI1 CS
//  GPIO2 = 0x30000004  → SPI2 CS
//
//  DataWriteM_in is [7:0] — all peripherals are byte-wide.
//  Pipeline connects WriteDataM_top[7:0] at instantiation.
//
//  FIX: SPI start timing — added !spi_done condition
//    Old: if (spi_pending && !spi_busy)          → MISSED
//    New: if (spi_pending && !spi_busy && !spi_done) ✓
// ============================================================
module DataMem #(
    parameter UART_FIFO_DEPTH = 4,
    parameter SPI_RX_DEPTH    = 3
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] aluAddress_in,
    input  wire [7:0]  DataWriteM_in,      // byte-wide: only [7:0] consumed
    input  wire        memwriteM_in,
    output reg  [31:0] DataMem_out,

    // UART
    output reg  [7:0]  uart_out_data,
    output reg         uart_tx_start,
    input  wire        uart_tx_busy,
    input  wire [7:0]  uart_in_data,
    input  wire        uart_rx_ready,

    // SPI2 (slow, CLK_DIV=8, 6.25MHz)
    output reg  [7:0]  spi2_tx_data,
    output reg         spi2_start,
    output wire        spi2_pending_out,
    input  wire [7:0]  spi2_rx_data,
    input  wire        spi2_busy,
    input  wire        spi2_done,


    // GPIO2 → SPI2 CS
    output reg         gpio2_wr_en,
    output reg         gpio2_wdata
);

    // ── Address decode ────────────────────────────────────────
    wire sel_uart_tx   = (aluAddress_in == 32'h1000_0000);
    wire sel_uart_rx   = (aluAddress_in == 32'h1000_0004);
    wire sel_uart_txst = (aluAddress_in == 32'h1000_0008);
    wire sel_uart_rxst = (aluAddress_in == 32'h1000_000C);

    wire sel_spi2_tx   = (aluAddress_in == 32'h4000_0000);
    wire sel_spi2_txst = (aluAddress_in == 32'h4000_0004);
    wire sel_spi2_rx   = (aluAddress_in == 32'h4000_0008);
    wire sel_spi2_rxst = (aluAddress_in == 32'h4000_000C);

    wire sel_gpio2     = (aluAddress_in == 32'h3000_0004);

    // ── UART TX FIFO ──────────────────────────────────────────
    wire       uart_tx_full, uart_tx_empty;
    wire [7:0] uart_tx_rd_data;

    reg uart_tx_wr_lock;
    always @(posedge clk or posedge reset) begin
        if (reset)                                                  uart_tx_wr_lock <= 0;
        else if (!sel_uart_tx)                                      uart_tx_wr_lock <= 0;
        else if (memwriteM_in && sel_uart_tx && !uart_tx_wr_lock)   uart_tx_wr_lock <= 1;
    end
    wire uart_tx_wr = memwriteM_in && sel_uart_tx && !uart_tx_wr_lock && !uart_tx_full;

    wire uart_tx_rd_level = !uart_tx_busy && !uart_tx_empty && !uart_tx_start;
    reg  uart_tx_rd_prev;
    always @(posedge clk or posedge reset) begin
        if (reset) uart_tx_rd_prev <= 0;
        else       uart_tx_rd_prev <= uart_tx_rd_level;
    end
    wire uart_tx_rd = uart_tx_rd_level && !uart_tx_rd_prev;

    CircularBuffer #(.DATA_WIDTH(8), .DEPTH(UART_FIFO_DEPTH)) UART_TX_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(uart_tx_wr),  .wr_data(DataWriteM_in),
        .rd_en(uart_tx_rd),  .rd_data(uart_tx_rd_data),
        .full(uart_tx_full), .empty(uart_tx_empty)
    );

    always @(posedge clk or posedge reset) begin
        if (reset) begin uart_tx_start <= 0; uart_out_data <= 0; end
        else begin
            uart_tx_start <= 0;
            if (uart_tx_rd) begin
                uart_out_data <= uart_tx_rd_data;
                uart_tx_start <= 1;
            end
        end
    end

    // ── UART RX FIFO ──────────────────────────────────────────
    wire       uart_rx_full, uart_rx_empty;
    wire [7:0] uart_rx_rd_data;

    reg uart_rx_rd_lock;
    always @(posedge clk or posedge reset) begin
        if (reset)                                                    uart_rx_rd_lock <= 0;
        else if (!sel_uart_rx)                                        uart_rx_rd_lock <= 0;
        else if (!memwriteM_in && sel_uart_rx && !uart_rx_rd_lock)    uart_rx_rd_lock <= 1;
    end
    wire uart_rx_rd = !memwriteM_in && sel_uart_rx && !uart_rx_rd_lock && !uart_rx_empty;

    CircularBuffer #(.DATA_WIDTH(8), .DEPTH(UART_FIFO_DEPTH)) UART_RX_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(uart_rx_ready),  .wr_data(uart_in_data),
        .rd_en(uart_rx_rd),     .rd_data(uart_rx_rd_data),
        .full(uart_rx_full),    .empty(uart_rx_empty)
    );



    // ── SPI2 TX (slow, 6.25MHz) ───────────────────────────────
    reg        spi2_pending;
    reg [7:0]  spi2_tx_buf;
    reg        spi2_tx_wr_lock;

    always @(posedge clk or posedge reset) begin
        if (reset)                                                    spi2_tx_wr_lock <= 0;
        else if (!sel_spi2_tx)                                        spi2_tx_wr_lock <= 0;
        else if (memwriteM_in && sel_spi2_tx && !spi2_tx_wr_lock)     spi2_tx_wr_lock <= 1;
    end
    wire spi2_tx_wr = memwriteM_in && sel_spi2_tx && !spi2_tx_wr_lock;
    assign spi2_pending_out = spi2_pending;

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            spi2_start <= 0; spi2_tx_data <= 0; spi2_pending <= 0; spi2_tx_buf <= 0;
        end else begin
            spi2_start <= 0;
            if (spi2_tx_wr && !spi2_pending) begin
                spi2_tx_buf  <= DataWriteM_in;
                spi2_pending <= 1;
            end
            if (spi2_pending && !spi2_busy && !spi2_done) begin
                spi2_tx_data <= spi2_tx_buf;
                spi2_start   <= 1;
                spi2_pending <= 0;
            end
        end
    end

    // SPI2 RX FIFO
    reg spi2_done_r;
    always @(posedge clk or posedge reset) begin
        if (reset) spi2_done_r <= 0;
        else       spi2_done_r <= spi2_done;
    end
    wire spi2_done_rise = spi2_done & ~spi2_done_r;

    wire       spi2_rx_full, spi2_rx_empty;
    wire [7:0] spi2_rx_rd_data;
    reg        spi2_rx_rd_lock;

    always @(posedge clk or posedge reset) begin
        if (reset)                                                    spi2_rx_rd_lock <= 0;
        else if (!sel_spi2_rx)                                        spi2_rx_rd_lock <= 0;
        else if (!memwriteM_in && sel_spi2_rx && !spi2_rx_rd_lock)    spi2_rx_rd_lock <= 1;
    end
    wire spi2_rx_rd = !memwriteM_in && sel_spi2_rx && !spi2_rx_rd_lock && !spi2_rx_empty;

    CircularBuffer #(.DATA_WIDTH(8), .DEPTH(SPI_RX_DEPTH)) SPI2_RX_FIFO (
        .clk(clk), .reset(reset),
        .wr_en(spi2_done_rise), .wr_data(spi2_rx_data),
        .rd_en(spi2_rx_rd),     .rd_data(spi2_rx_rd_data),
        .full(spi2_rx_full),    .empty(spi2_rx_empty)
    );

    // ── GPIO ──────────────────────────────────────────────────
    always @(posedge clk or posedge reset) begin
        if (reset) begin gpio2_wr_en <= 0; gpio2_wdata <= 1; end
        else begin
            gpio2_wr_en <= 0;
            if (memwriteM_in && sel_gpio2) begin
                gpio2_wdata <= DataWriteM_in[0];
                gpio2_wr_en <= 1;
            end
        end
    end

    // ── Read MUX ──────────────────────────────────────────────
    always @(*) begin
        DataMem_out = 32'hDEAD_BADD;
        if (!memwriteM_in) begin
            if      (sel_uart_tx)   DataMem_out = {24'b0, uart_tx_rd_data};
            else if (sel_uart_rx)   DataMem_out = {24'b0, uart_rx_rd_data};
            else if (sel_uart_txst) DataMem_out = {30'b0, uart_tx_busy,  uart_tx_full};
            else if (sel_uart_rxst) DataMem_out = {30'b0, uart_rx_full, ~uart_rx_empty};
            else if (sel_spi2_tx)   DataMem_out = {24'b0, spi2_tx_buf};
            else if (sel_spi2_txst) DataMem_out = {30'b0, spi2_pending,  spi2_busy};
            else if (sel_spi2_rx)   DataMem_out = {24'b0, spi2_rx_rd_data};
            else if (sel_spi2_rxst) DataMem_out = {30'b0, spi2_rx_full, ~spi2_rx_empty};
            else if (sel_gpio2)     DataMem_out = {31'b0, gpio2_wdata};
        end
    end

endmodule





