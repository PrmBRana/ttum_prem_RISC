`default_nettype none
`timescale 1ns/1ps

module DataMem #(
    parameter integer UART_FIFO_DEPTH = 4,
    parameter integer SPI_RX_DEPTH    = 4
)(
    input  wire        clk,
    input  wire        reset,
    input  wire [31:0] aluAddress_in,
    input  wire [7:0]  DataWriteM_in,   // CHANGED: now 8-bit (matches pipeline usage)
    input  wire        memwriteM_in,
    output reg  [31:0] DataMem_out,

    // ── UART TX only ──────────────────────────────────────────
    output reg  [7:0]  uart_out_data,
    output reg         uart_tx_start,
    input  wire        uart_tx_busy,

    // ── SPI2 ──────────────────────────────────────────────────
    output reg  [7:0]  spi2_tx_data,
    output reg         spi2_start,
    output wire        spi2_pending_out,
    input  wire [7:0]  spi2_rx_data,
    input  wire        spi2_busy,
    input  wire        spi2_done,

    // ── GPIO2 → SPI2 CS_N ─────────────────────────────────────
    output reg         gpio2_wr_en,
    output reg         gpio2_wdata
);

    // ── Address decode ────────────────────────────────────────
    wire sel_uart_tx   = (aluAddress_in == 32'h1000_0000);
    wire sel_uart_txst = (aluAddress_in == 32'h1000_0008);
    wire sel_spi2_tx   = (aluAddress_in == 32'h4000_0000);
    wire sel_spi2_txst = (aluAddress_in == 32'h4000_0004);
    wire sel_spi2_rx   = (aluAddress_in == 32'h4000_0008);
    wire sel_spi2_rxst = (aluAddress_in == 32'h4000_000C);
    wire sel_gpio2     = (aluAddress_in == 32'h3000_0004);

    // =========================================================
    // UART TX FIFO
    // =========================================================
    wire       uart_tx_full, uart_tx_empty;
    wire [7:0] uart_tx_rd_data;

    reg uart_tx_wr_lock;
    always @(posedge clk) begin
        if (reset)
            uart_tx_wr_lock <= 1'b0;
        else if (!sel_uart_tx)
            uart_tx_wr_lock <= 1'b0;
        else if (memwriteM_in && sel_uart_tx && !uart_tx_wr_lock)
            uart_tx_wr_lock <= 1'b1;
    end

    wire uart_tx_wr = memwriteM_in && sel_uart_tx
                      && !uart_tx_wr_lock && !uart_tx_full;

    wire uart_tx_rd_level = !uart_tx_busy && !uart_tx_empty
                             && !uart_tx_start;
    reg  uart_tx_rd_prev;
    always @(posedge clk) begin
        if (reset) uart_tx_rd_prev <= 1'b0;
        else       uart_tx_rd_prev <= uart_tx_rd_level;
    end
    wire uart_tx_rd = uart_tx_rd_level && !uart_tx_rd_prev;

    CircularBuffer #(
        .DATA_WIDTH (8),
        .DEPTH      (UART_FIFO_DEPTH)
    ) UART_TX_FIFO (
        .clk     (clk),
        .reset   (reset),
        .wr_en   (uart_tx_wr),
        .wr_data (DataWriteM_in),  // CHANGED
        .rd_en   (uart_tx_rd),
        .rd_data (uart_tx_rd_data),
        .full    (uart_tx_full),
        .empty   (uart_tx_empty)
    );

    always @(posedge clk) begin
        if (reset) begin
            uart_out_data <= 8'd0;
            uart_tx_start <= 1'b0;
        end else begin
            uart_tx_start <= 1'b0;
            if (uart_tx_rd) begin
                uart_out_data <= uart_tx_rd_data;
                uart_tx_start <= 1'b1;
            end
        end
    end

    // =========================================================
    // SPI2 TX
    // =========================================================
    reg        spi2_pending;
    reg [7:0]  spi2_tx_buf;
    reg        spi2_tx_wr_lock;

    always @(posedge clk) begin
        if (reset)
            spi2_tx_wr_lock <= 1'b0;
        else if (!sel_spi2_tx)
            spi2_tx_wr_lock <= 1'b0;
        else if (memwriteM_in && sel_spi2_tx && !spi2_tx_wr_lock)
            spi2_tx_wr_lock <= 1'b1;
    end

    wire spi2_tx_wr = memwriteM_in && sel_spi2_tx && !spi2_tx_wr_lock;
    assign spi2_pending_out = spi2_pending;

    always @(posedge clk) begin
        if (reset) begin
            spi2_start   <= 1'b0;
            spi2_tx_data <= 8'd0;
            spi2_pending <= 1'b0;
            spi2_tx_buf  <= 8'd0;
        end else begin
            spi2_start <= 1'b0;

            if (spi2_tx_wr && !spi2_pending) begin
                spi2_tx_buf  <= DataWriteM_in; // CHANGED
                spi2_pending <= 1'b1;
            end

            if (spi2_pending && !spi2_busy && !spi2_done) begin
                spi2_tx_data <= spi2_tx_buf;
                spi2_start   <= 1'b1;
                spi2_pending <= 1'b0;
            end
        end
    end

    // =========================================================
    // SPI2 RX FIFO
    // =========================================================
    reg spi2_done_r;
    always @(posedge clk) begin
        if (reset) spi2_done_r <= 1'b0;
        else       spi2_done_r <= spi2_done;
    end
    wire spi2_done_rise = spi2_done & ~spi2_done_r;

    wire       spi2_rx_full, spi2_rx_empty;
    wire [7:0] spi2_rx_rd_data;
    reg        spi2_rx_rd_lock;

    always @(posedge clk) begin
        if (reset)
            spi2_rx_rd_lock <= 1'b0;
        else if (!sel_spi2_rx)
            spi2_rx_rd_lock <= 1'b0;
        else if (!memwriteM_in && sel_spi2_rx && !spi2_rx_rd_lock)
            spi2_rx_rd_lock <= 1'b1;
    end

    wire spi2_rx_rd = !memwriteM_in && sel_spi2_rx
                      && !spi2_rx_rd_lock && !spi2_rx_empty;

    CircularBuffer #(
        .DATA_WIDTH (8),
        .DEPTH      (SPI_RX_DEPTH)
    ) SPI2_RX_FIFO (
        .clk     (clk),
        .reset   (reset),
        .wr_en   (spi2_done_rise),
        .wr_data (spi2_rx_data),
        .rd_en   (spi2_rx_rd),
        .rd_data (spi2_rx_rd_data),
        .full    (spi2_rx_full),
        .empty   (spi2_rx_empty)
    );

    // =========================================================
    // GPIO2
    // =========================================================
    always @(posedge clk) begin
        if (reset) begin
            gpio2_wr_en <= 1'b0;
            gpio2_wdata <= 1'b1; // CS_N idle high
        end else begin
            gpio2_wr_en <= 1'b0;
            if (memwriteM_in && sel_gpio2) begin
                gpio2_wdata <= DataWriteM_in[0];
                gpio2_wr_en <= 1'b1;
            end
        end
    end

    // =========================================================
    // READ MUX — combinational
    // =========================================================
    always @(*) begin
        DataMem_out = 32'hDEAD_BADD;
        if (!memwriteM_in) begin
            if      (sel_uart_txst) DataMem_out = {30'd0, uart_tx_busy, uart_tx_full};
            else if (sel_spi2_tx)   DataMem_out = {24'd0, spi2_tx_buf};
            else if (sel_spi2_txst) DataMem_out = {30'd0, spi2_pending, spi2_busy};
            else if (sel_spi2_rx)   DataMem_out = {24'd0, spi2_rx_rd_data};
            else if (sel_spi2_rxst) DataMem_out = {30'd0, spi2_rx_full, ~spi2_rx_empty};
            else if (sel_gpio2)     DataMem_out = {31'd0, gpio2_wdata};
        end
    end

endmodule









