`default_nettype none
`timescale 1ns / 1ps

module CircularBuffer #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 4
)(
    input  wire                  clk,
    input  wire                  reset,
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,
    output wire                  full,
    output wire                  empty
);

    localparam integer PTR_W = $clog2(DEPTH);

    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    reg [PTR_W:0]        wr_ptr;
    reg [PTR_W:0]        rd_ptr;

    assign full  = (wr_ptr[PTR_W] != rd_ptr[PTR_W]) &&
                   (wr_ptr[PTR_W-1:0] == rd_ptr[PTR_W-1:0]);

    assign empty = (wr_ptr == rd_ptr);

    assign rd_data = empty ? {DATA_WIDTH{1'b0}} : mem[rd_ptr[PTR_W-1:0]];

    integer i;

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= 0;
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr[PTR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1;
            end

            if (rd_en && !empty)
                rd_ptr <= rd_ptr + 1;
        end
    end

endmodule






