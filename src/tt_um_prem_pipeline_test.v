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
    // UART (ONLY ONE)
    // --------------------------------------------------
    wire uart_rx = ui_in[3];
    wire uart_tx;

    // --------------------------------------------------
    // SPI signals
    // --------------------------------------------------
    wire spi2_mosi;
    wire spi2_sclk;
    wire spi2_cs_n;
    wire spi2_miso = uio_in[7];

    // --------------------------------------------------
    // Unused signals (cleaned)
    // --------------------------------------------------
    wire _unused = &{ui_in[7:4], ui_in[2:0], uio_in[6:0], ena};

    // --------------------------------------------------
    // Outputs (only UART1 now)
    // --------------------------------------------------
    assign uo_out = {
        7'b0000000,
        uart_tx
    };

    // --------------------------------------------------
    // UIO mapping
    // [0] UART TX
    // [2] MOSI
    // [3] SCLK
    // [4] CS
    // --------------------------------------------------
    assign uio_out = {
        3'b000,
        spi2_cs_n,   // [4]
        spi2_sclk,   // [3]
        spi2_mosi,   // [2]
        1'b0,        // [1] unused
        uart_tx      // [0]
    };

    // enable only used pins: 0,2,3,4
    assign uio_oe = 8'b00011101;

    // --------------------------------------------------
    // Pipeline core
    // --------------------------------------------------
    pipeline Top_inst (
        .clk(clk),
        .reset(reset),

        .rx(uart_rx),
        .tx(uart_tx),

        .spi2_cs_n(spi2_cs_n),
        .spi2_sclk(spi2_sclk),
        .spi2_mosi(spi2_mosi),
        .spi2_miso(spi2_miso)
    );

endmodule

