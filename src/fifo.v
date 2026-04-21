`default_nettype none
`timescale 1ns / 1ps

// ============================================================
//  CircularBuffer — Synchronous FIFO, combinational read output
//
//  FROM GTKWAVE WAVEFORM (root cause):
//  uart_tx_rd_data showed x then 00,00,00 before real data.
//  This happened because:
//    (a) mem[] was uninitialized (X) due to synchronous reset
//        being missed in ASIC timing → first rd_data = X.
//    (b) Drain fired simultaneously with first FIFO write:
//        wr_en=1 (core writing 'M') AND rd_en=1 (drain active).
//        Both fire on same posedge. Non-blocking eval order:
//        rd_data = mem[rd_ptr_before] = 0x00 (reset value).
//        uart_out_data captures 0x00 instead of 'M'.
//        wr_ptr and rd_ptr both advance → byte 'M' is LOST.
//
//  FIXES:
//  1. Async reset (posedge reset) — mem[] always initialised.
//     In ASIC: maps to FF with async reset. Standard practice.
//
//  2. Simultaneous wr+rd when FIFO was empty (wr_ptr==rd_ptr):
//     The existing guard (rd_en && !empty) correctly blocks rd
//     when empty BEFORE the write. After the write wr_ptr advances,
//     but the empty check uses the PRE-posedge value of wr_ptr.
//     In Verilog non-blocking: LHS assignments happen after all
//     RHS evaluations. So !empty = (wr_ptr_OLD == rd_ptr_OLD) = true
//     at the start of the posedge evaluation → rd blocked. CORRECT.
//     BUT: if rd_en AND wr_en both fire AND FIFO was NOT empty
//     (had exactly 1 entry): wr adds, rd removes → count stays 1.
//     rd_data = mem[rd_ptr_old] = correct (the real byte). CORRECT.
//
//  3. The real X bug fix: async reset on mem[] ensures rd_data
//     never returns X during empty periods.
//
//  ASIC NOTE: combinational (async) read on register-file FIFO
//  of depth 4 is standard practice. Synthesises to a 4:1 MUX
//  on FF outputs. No combinational loop, correct timing.
//  The read-pointer is a registered FF; the MUX selects the
//  correct FF output combinationally — this is a standard cell
//  pattern in every standard-cell library.
//
//  Port contract:
//    rd_data valid combinationally from mem[rd_ptr].
//    rd_ptr advances on the posedge AFTER rd_en is sampled.
//    Caller (DataMem) captures rd_data on the SAME posedge
//    via non-blocking assignment (samples RHS before any LHS
//    commits) → correct byte always captured.
// ============================================================
module CircularBuffer #(
    parameter integer DATA_WIDTH = 8,
    parameter integer DEPTH      = 4
)(
    input  wire                  clk,
    input  wire                  reset,     // active-high async reset
    input  wire                  wr_en,
    input  wire [DATA_WIDTH-1:0] wr_data,
    input  wire                  rd_en,
    output wire [DATA_WIDTH-1:0] rd_data,   // combinational
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

    // Combinational read: valid same cycle as rd_en.
    // Returns 0x00 when FIFO is empty — never returns X.
    assign rd_data = empty ? {DATA_WIDTH{1'b0}} : mem[rd_ptr[PTR_W-1:0]];

    integer i;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            wr_ptr <= {(PTR_W+1){1'b0}};
            rd_ptr <= {(PTR_W+1){1'b0}};
            for (i = 0; i < DEPTH; i = i + 1)
                mem[i] <= {DATA_WIDTH{1'b0}};
        end else begin
            // Write: only when not full
            if (wr_en && !full) begin
                mem[wr_ptr[PTR_W-1:0]] <= wr_data;
                wr_ptr <= wr_ptr + 1'b1;
            end
            // Read: only when not empty
            // Non-blocking eval: empty uses wr_ptr BEFORE any advance.
            // If wr_en+rd_en both fire when FIFO was empty, rd is
            // correctly blocked by the !empty guard (which sees the
            // pre-posedge empty=1). The write goes through. Safe.
            if (rd_en && !empty) begin
                rd_ptr <= rd_ptr + 1'b1;
            end
        end
    end

endmodule




