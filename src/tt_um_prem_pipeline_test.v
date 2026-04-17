`default_nettype none
`timescale 1ns/1ps

module tt_um_prem_pipeline_test (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // --------------------------------------------------
    // Reset
    // --------------------------------------------------
    wire reset = ~rst_n;

    // --------------------------------------------------
    // Inputs (UART RX)
    // --------------------------------------------------
    wire uart1_rx = ui_in[3];
    wire uart2_rx = ui_in[4];

    // --------------------------------------------------
    // Outputs (UART TX)
    // --------------------------------------------------
    wire uart1_tx;
    wire uart2_tx;

    // --------------------------------------------------
    // SPI signals
    // --------------------------------------------------
    wire spi2_mosi;
    wire spi2_sclk;
    wire spi2_cs_n;
    wire spi2_miso = uio_in[7];

    // --------------------------------------------------
    // Unused signals
    // --------------------------------------------------
    wire _unused = &{ui_in[7:5], ui_in[2:0], uio_in[6:0], ena};

    // --------------------------------------------------
    // UART output mapping
    // --------------------------------------------------
    assign uo_out = {
        6'b000000,
        uart2_tx,
        uart1_tx
    };

    // --------------------------------------------------
    // SERIAL UIO mapping (UART + SPI share 0–4)
    // --------------------------------------------------
    assign uio_out = {
        3'b000,
        spi2_cs_n,   // [4]
        spi2_sclk,   // [3]
        spi2_mosi,   // [2]
        uart2_tx,    // [1]
        uart1_tx     // [0]
    };

    // --------------------------------------------------
    // Enable only used pins 0–4
    // --------------------------------------------------
    assign uio_oe = 8'b00011111;

    // --------------------------------------------------
    // Pipeline core
    // --------------------------------------------------
    pipeline Top_inst (
        .clk(clk),
        .reset(reset),

        .rx(uart1_rx),
        .tx(uart1_tx),

        .UART_tx(uart2_tx),
        .UART_rx_line(uart2_rx),

        .spi2_cs_n(spi2_cs_n),
        .spi2_sclk(spi2_sclk),
        .spi2_mosi(spi2_mosi),
        .spi2_miso(spi2_miso)
    );

endmodule