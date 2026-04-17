`default_nettype none
`timescale 1ns / 1ps

module CircularBuffer #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH      = 3
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

    reg [DATA_WIDTH-1:0]      mem    [0:DEPTH-1];
    reg [$clog2(DEPTH)-1:0]   wr_ptr, rd_ptr;
    reg [$clog2(DEPTH+1)-1:0] count;
    integer i;

    assign full    = (count == DEPTH[$clog2(DEPTH+1)-1:0]);
    assign empty   = (count == 0);
    assign rd_data = mem[rd_ptr];

    always @(posedge clk) begin
        if (reset) begin
            wr_ptr <= 0;
            rd_ptr <= 0;
            count  <= 0;
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            if (wr_en && !full) begin
                mem[wr_ptr] <= wr_data;
                wr_ptr      <= wr_ptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
            case ({(wr_en && !full), (rd_en && !empty)})
                2'b10:   count <= count + 1'b1;
                2'b01:   count <= count - 1'b1;
                default: count <= count;
            endcase
        end
    end

endmodule



