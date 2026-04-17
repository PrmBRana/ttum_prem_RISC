`default_nettype none
`timescale 1ns / 1ps

module uart_Tx_fixed0 #(
    parameter CLK_FREQ   = 50_000_000,
    parameter BAUD_RATE  = 115_200,
    parameter OVERSAMPLE = 16
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        tx_Start,
    input  wire [7:0]  tx_Data,
    output reg         tx,
    output reg         tx_busy,
    input  wire        rx,
    output reg  [7:0]  rx_Data,
    output reg         rx_ready
);
    localparam integer BAUD_DIV = CLK_FREQ / (BAUD_RATE * OVERSAMPLE);
    localparam integer CNT_W    = $clog2(BAUD_DIV + 1);
    /* verilator lint_off WIDTHTRUNC */
    localparam [CNT_W-1:0] BAUD_LAST = BAUD_DIV - 1;
    /* verilator lint_on WIDTHTRUNC */
    localparam integer    OS_W    = $clog2(OVERSAMPLE + 1);
    localparam [OS_W-1:0] OS_LAST = OVERSAMPLE - 1;
    localparam [OS_W-1:0] OS_HALF = OVERSAMPLE / 2;

    reg [CNT_W-1:0] baud_cnt;
    reg             baud_tick;

    always @(posedge clk) begin
        if (reset) begin baud_cnt <= 0; baud_tick <= 0; end
        else if (baud_cnt == BAUD_LAST) begin baud_cnt <= 0; baud_tick <= 1; end
        else begin baud_cnt <= baud_cnt + 1'b1; baud_tick <= 0; end
    end

    reg [7:0]      tx_buf;
    reg [3:0]      tx_bit_idx;
    reg [OS_W-1:0] tx_os_cnt;
    reg            tx_active;

    always @(posedge clk) begin
        if (reset) begin
            tx <= 1'b1; tx_busy <= 1'b0; tx_active <= 1'b0;
            tx_buf <= 0; tx_bit_idx <= 0; tx_os_cnt <= 0;
        end else begin
            if (tx_Start && !tx_busy && !tx_active) begin
                tx_buf <= tx_Data; tx_bit_idx <= 0;
                tx_os_cnt <= 0; tx_active <= 1'b1; tx_busy <= 1'b1;
            end
            if (tx_active && baud_tick) begin
                case (tx_bit_idx)
                    4'd0: tx <= 1'b0;
                    4'd1: tx <= tx_buf[0]; 4'd2: tx <= tx_buf[1];
                    4'd3: tx <= tx_buf[2]; 4'd4: tx <= tx_buf[3];
                    4'd5: tx <= tx_buf[4]; 4'd6: tx <= tx_buf[5];
                    4'd7: tx <= tx_buf[6]; 4'd8: tx <= tx_buf[7];
                    default: tx <= 1'b1;
                endcase
                if (tx_os_cnt == OS_LAST) begin
                    tx_os_cnt <= 0;
                    if (tx_bit_idx == 4'd9) begin
                        tx_active <= 1'b0; tx_busy <= 1'b0; tx <= 1'b1;
                    end else tx_bit_idx <= tx_bit_idx + 4'd1;
                end else tx_os_cnt <= tx_os_cnt + 1'b1;
            end
            if (!tx_active) tx <= 1'b1;
        end
    end

    reg [1:0]      rx_sync;
    reg            rx_active;
    reg [3:0]      rx_bit_idx;
    reg [OS_W-1:0] rx_os_cnt;
    reg [7:0]      rx_shift;

    always @(posedge clk) begin
        if (reset) begin
            rx_sync <= 2'b11; rx_active <= 1'b0; rx_bit_idx <= 0;
            rx_os_cnt <= 0; rx_shift <= 0; rx_Data <= 0; rx_ready <= 0;
        end else begin
            rx_sync  <= {rx_sync[0], rx};
            rx_ready <= 1'b0;
            if (!rx_active) begin
                if (rx_sync[1] == 1'b0) begin
                    rx_active <= 1'b1; rx_bit_idx <= 0;
                    rx_os_cnt <= 0; rx_shift <= 0;
                end
            end else if (baud_tick) begin
                if (rx_os_cnt == OS_HALF) begin
                    case (rx_bit_idx)
                        4'd0: if (rx_sync[1] != 1'b0) rx_active <= 1'b0;
                        4'd1: rx_shift[0] <= rx_sync[1];
                        4'd2: rx_shift[1] <= rx_sync[1];
                        4'd3: rx_shift[2] <= rx_sync[1];
                        4'd4: rx_shift[3] <= rx_sync[1];
                        4'd5: rx_shift[4] <= rx_sync[1];
                        4'd6: rx_shift[5] <= rx_sync[1];
                        4'd7: rx_shift[6] <= rx_sync[1];
                        4'd8: rx_shift[7] <= rx_sync[1];
                        default: ;
                    endcase
                end
                if (rx_os_cnt == OS_LAST) begin
                    rx_os_cnt <= 0;
                    if (rx_bit_idx == 4'd9) begin
                        rx_active <= 1'b0; rx_Data <= rx_shift; rx_ready <= 1'b1;
                    end else rx_bit_idx <= rx_bit_idx + 4'd1;
                end else rx_os_cnt <= rx_os_cnt + 1'b1;
            end
        end
    end
endmodule


