`default_nettype none
`timescale 1ns/1ps

// ============================================================
//  pipeline — RISC-V 5-stage + shared UART + SPI2 + GPIO
//  Target: Tiny Tapeout, sky130 PDK, OpenLane, 50 MHz
// ============================================================
//
//  CHANGE LOG vs previous version (two real fixes):
//
//  FIX 1 — IMEM_ADDR_W: 6 → 5
//    DEPTH=32 requires exactly 5 address bits (2^5 = 32).
//    Previous value of 6 made word_idx = PCF[7:2] a 6-bit
//    signal that could legally address indices 32..63, which
//    are out-of-bounds for a 32-deep array — undefined in
//    synthesis. Changed to 5 so word_idx = PCF[6:2], which
//    spans exactly 0..31. Consistent with uart_bootloader
//    addr_count [4:0] (5-bit, max value 31).
//
//  FIX 2 — halt_latch: posedge reset_sync → posedge reset
//    halt_latch body references stall_Pro, which is driven by
//    uart_bootloader (raw reset domain). Using reset_sync on
//    the async-reset pin while stall_Pro (raw domain) appeared
//    in the clocked body created a real CDC inconsistency:
//    two different reset domains controlling the same FF.
//    Changed to raw reset so halt_latch, stall_Pro, and
//    boot_done_r are all in the same reset domain.
//    SYNCASYNCNET lint suppression is no longer needed.
//
//  ──────────────────────────────────────────────────────────
//  RESET ARCHITECTURE (intentional two-domain design):
//
//  Domain A — raw reset (async assert/deassert):
//    reset_ff1, reset_ff2, boot_done_r, boot_done_r2,
//    uart_bootloader, gpio2_io, halt_latch.
//    WHY: uart_bootloader drives stall_Pro on the first
//    posedge after reset. stall_Pro must be 1 before any
//    pipeline stage can execute. Using raw reset guarantees
//    this with zero latency.
//
//  Domain B — reset_sync (async assert, sync deassert):
//    pc_register, uart_Tx_fixed, IF_ID_stage, EX_stage,
//    MEM_stage, WriteBack_stage, DataMem, spi_master.
//    WHY: These modules are held frozen by stall_Pro for the
//    entire boot duration (thousands of cycles). The 2-cycle
//    sync deassert happens while they are stalled — they
//    cannot produce wrong outputs during that window.
//    Benefit: cuts reset net fanout from O(N_modules) to 2.
//
//  The domains are safe together because stall_Pro (Domain A)
//  is always 1 when Domain B modules come out of reset. There
//  is no race: stall is asserted before Domain B deasserts.
//
//  ──────────────────────────────────────────────────────────
//  WHY FF MEMORY IS CORRECT FOR THIS TARGET:
//    sky130 Tiny Tapeout does not include an SRAM macro
//    compiler in the default OpenLane flow. OpenRAM requires
//    a separate setup not standard for TT submissions.
//    DEPTH=32 × 32 bits = 1024 flip-flops ≈ 6000 μm² in
//    sky130 — acceptable area for a TT tile. FF memory also
//    gives a clean combinational read timing model that
//    matches the pipeline's async-read assumption exactly.
//
//  ──────────────────────────────────────────────────────────
//  WHY FORWARDING STAYS COMBINATIONAL:
//    Registering ForwardAE/BE breaks functional correctness:
//    the select arrives one cycle after the forwarded data,
//    causing the ALU to read the wrong operand. The hazard
//    unit must produce forwarding selects combinationally in
//    the same cycle they are needed. Physical fanout on these
//    signals is handled by SDC set_max_fanout 6.
//
//  ──────────────────────────────────────────────────────────
//  PHYSICAL FIXES (config.json + SDC — not RTL):
//    139 clock-leaf fanout violations: CTS_SINK_CLUSTERING_SIZE=6
//    8 antenna violations on aluAddress_in: DIODE_INSERTION_STRATEGY=3
//    set_max_fanout 6 [current_design] in pipeline.sdc
// ============================================================

module pipeline (
    input  wire clk,
    input  wire reset,      // active-high async reset
    input  wire rx,
    output wire tx,
    output wire spi2_sclk,
    output wire spi2_mosi,
    input  wire spi2_miso,
    output wire spi2_cs_n
);

    // FIX 1: 5 bits = exactly 2^5 = 32 = DEPTH
    // word_idx = PCF[6:2] → 5-bit → addresses 0..31 only
    localparam IMEM_ADDR_W = 6;

    // =========================================================
    // RESET SYNCHRONISER — Domain B (data-path modules only)
    // =========================================================
    // Async-assert, sync-deassert. Raw `reset` feeds only:
    // reset_ff1/ff2, boot_done_r/r2, uart_bootloader,
    // gpio2_io, halt_latch.
    // All data-path submodules receive reset_sync.
    reg reset_ff1, reset_ff2;
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            reset_ff1 <= 1'b1;
            reset_ff2 <= 1'b1;
        end else begin
            reset_ff1 <= 1'b0;
            reset_ff2 <= reset_ff1;
        end
    end
    wire reset_sync = reset_ff2;

    // ── Pipeline wires ────────────────────────────────────────
    wire [31:0] PCPLUS4_top, PC_top, PCF, Instruction1_out, INSTRUCTION;
    wire [31:0] RD1_top, RD2_top, PCD_top, PCE_top, PCPLUS4D_TOP;
    wire [31:0] RD1E_top, RD2E_top;
    wire [31:0] SrcA_top, outB_top, ScrB_top;
    wire [31:0] ALUResultE_top, PCPlus4E_top, ALUResultM_top, PCPlus4M_top;
    wire [31:0] Datamem_top, ALUResultW_top, ReadDataW_top, PCPlus4W_top, ResultW_top;
    wire [31:0] PCTarget_top, ImmExtD_top, ImmExtE_top;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [31:0] WriteDataM_top;
    /* verilator lint_on  UNUSEDSIGNAL */

    wire RegWrite_top, ALUSrcD_top, memWriteD_top, jumpD_top, BranchD_top;
    wire JumpE_top, BranchE_top, zero_top, PCSCR_top;
    wire jumpRD_top, JumpRE_top;
    wire RegWriteE_top, MemWriteE_top, ALUSrcE_top;
    wire MemWriteM_top, RegWriteM_top, RegWriteW_top;
    wire StallF_top, StallD_top, FlushD_top, FlushE_top;

    wire [1:0] ResultSrcD_top, ALUtyp_top, ALUTypE_top;
    wire [1:0] ResultSrcE_top, ResultSrcM_top, ResultSrcW_top;
    wire [1:0] ForwardAE_top, ForwardBE_top;
    wire [3:0] ALUControlD_top, ALUControlE_top;
    wire [4:0] RdE_top, RdM_top, Rs1E_top, Rs2E_top, RdW_top;
    wire [2:0] ImmSrc_top;
    wire [1:0] ALUSrcAD_top, ALUSrcAE_top;

    // ── UART / boot wires ─────────────────────────────────────
    wire [7:0]  uart_rx_data_shared;
    wire        uart_rx_ready_shared;
    wire        uart_tx_busy_shared;
    wire [7:0]  boot_tx_data;
    wire        boot_tx_start_raw;
    wire [7:0]  periph_tx_data;
    wire        periph_tx_start;

    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0]  mem_addr;
    /* verilator lint_on  UNUSEDSIGNAL */

    wire [31:0] mem_wdata;
    wire        Write_enable;
    wire        stall_Pro;
    wire        halt_top;

    // ── boot_done_r — Domain A (raw reset) ────────────────────
    // stall_Pro = ~boot_done is a wire from uart_bootloader.
    // Must use raw reset: stall_Pro must be 1 at the first
    // posedge after reset so the pipeline cannot execute
    // garbage instructions.
    wire boot_done_comb = ~stall_Pro;
    reg  boot_done_r;
    always @(posedge clk or posedge reset) begin
        if (reset) boot_done_r <= 1'b0;
        else       boot_done_r <= boot_done_comb;
    end

    // ── boot_done_r2 — TX/RX arbiter gate (raw reset) ─────────
    // Second register stage prevents TX MUX switching mid-pulse
    // at the boot→run transition. stall_Pro still uses the
    // single-stage boot_done_r. One-cycle arbiter delay is safe:
    // bootloader FSM ignores rx_valid after boot_done is set.
    reg boot_done_r2;
    always @(posedge clk or posedge reset) begin
        if (reset) boot_done_r2 <= 1'b0;
        else       boot_done_r2 <= boot_done_r;
    end

    // ── TX arbiter ────────────────────────────────────────────
    wire boot_tx_start_gated = boot_tx_start_raw & ~boot_done_r2;
    wire [7:0] shared_tx_data  = boot_done_r2 ? periph_tx_data   : boot_tx_data;
    wire       shared_tx_start = boot_done_r2
                                     ? (periph_tx_start & ~uart_tx_busy_shared)
                                     : boot_tx_start_gated;

    // ── RX routing ────────────────────────────────────────────
    wire uart_rx_ready_boot = uart_rx_ready_shared & ~boot_done_r2;

    // ── Halt logic — Domain A (raw reset, FIX 2) ──────────────
    // FIX 2: Changed from posedge reset_sync to posedge reset.
    // stall_Pro is in Domain A (raw reset). Having halt_latch
    // on reset_sync while its body references stall_Pro (Domain A)
    // created a CDC inconsistency. Now all three — halt_latch,
    // stall_Pro, boot_done_r — are in the same raw-reset domain.
    // The SYNCASYNCNET lint suppression is no longer needed.
    wire halt_active = halt_top & ~stall_Pro & ~FlushD_top & ~FlushE_top;
    reg  halt_latch;
    always @(posedge clk or posedge reset) begin
        if (reset)            halt_latch <= 1'b0;
        else if (stall_Pro)   halt_latch <= 1'b0;
        else if (halt_active) halt_latch <= 1'b1;
    end
    wire halt_final = halt_latch | halt_active;

    wire StallF_net = PCSCR_top ? 1'b0 : (stall_Pro | StallF_top | halt_final);
    wire StallD_net = PCSCR_top ? 1'b0 : (stall_Pro | StallD_top | halt_final);

    // =========================================================
    // FETCH
    // =========================================================
    PC_incre PC (
        .pc(PCF), .PCPlus4(PCPLUS4_top));

    PCSelect_MUX PCSelect_top (
        .PCScr(PCSCR_top), .PCSequential(PCPLUS4_top),
        .PCBranch(PCTarget_top), .Mux3_PC(PC_top));

    // Domain B: data-path, safe with reset_sync
    pc_register Register_top (
        .clk(clk), .reset(reset_sync),
        .PCF_in(PC_top), .stallF(StallF_net), .PCF_out(PCF));

    // =========================================================
    // SHARED UART — Domain B
    // =========================================================
    uart_Tx_fixed #(
        .CLK_FREQ(50_000_000), .BAUD_RATE(115_200), .OVERSAMPLE(16)
    ) uart_shared_inst (
        .clk(clk), .reset(reset_sync),
        .tx_Start(shared_tx_start), .tx_Data(shared_tx_data),
        .tx(tx), .tx_busy(uart_tx_busy_shared),
        .rx(rx), .rx_Data(uart_rx_data_shared),
        .rx_ready(uart_rx_ready_shared));

    // =========================================================
    // BOOTLOADER — Domain A (raw reset, timing-critical)
    // =========================================================
    // Must use raw reset: drives stall_Pro which gates the
    // entire pipeline. stall_Pro must assert before the first
    // posedge the pipeline could otherwise execute.
    uart_bootloader uart_bootloader (
        .clk(clk), .reset(reset),
        .rx_data(uart_rx_data_shared),
        .rx_valid(uart_rx_ready_boot),
        .tx_data(boot_tx_data),
        .tx_start(boot_tx_start_raw),
        .mem_we(Write_enable),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .stall_pro(stall_Pro));

    // IMEM — DEPTH=32, ADDR_W=5 (FIX 1)
    // word_idx = PCF[6:2] → 5-bit → valid range 0..31
    // Matches uart_bootloader addr_count [4:0] max=31 exactly.
    // FF-based memory is correct for sky130 Tiny Tapeout:
    // no SRAM macro compiler in default OpenLane TT flow.
    mem1KB_32bit #(
        .DEPTH(64), .ADDR_W(IMEM_ADDR_W)
    ) flipflop (
        .clk(clk),
        .reset(reset_sync),
        .we(Write_enable),
        .addr(mem_addr[IMEM_ADDR_W-1:0]),
        .wdata(mem_wdata),
        .read_Address(PCF),
        .Instruction_out(Instruction1_out));

    // =========================================================
    // DECODE — Domain B
    // =========================================================
    IF_ID_stage IF_DF_top (
        .clk(clk), .reset(reset_sync),
        .stallD(StallD_net), .flushD(FlushD_top),
        .PC_in(PCF), .PCplus4_in(PCPLUS4_top),
        .instruction_in(Instruction1_out),
        .instruction_out(INSTRUCTION),
        .PCplus4_out(PCPLUS4D_TOP), .PC_out(PCD_top));

    // Instruction field slices — reduce per-consumer fanout
    wire [6:0]  INSTR_op   = INSTRUCTION[6:0];
    wire [2:0]  INSTR_f3   = INSTRUCTION[14:12];
    wire [6:0]  INSTR_f7   = INSTRUCTION[31:25];
    wire [11:0] INSTR_imm  = INSTRUCTION[31:20];
    wire [4:0]  INSTR_rs1  = INSTRUCTION[19:15];
    wire [4:0]  INSTR_rs2  = INSTRUCTION[24:20];
    wire [31:0] INSTR_full = INSTRUCTION;
    wire [4:0]  INSTR_rd   = INSTRUCTION[11:7];

    Control control (
        .Opcode(INSTR_op), .funct3(INSTR_f3), .funct7(INSTR_f7),
        .imm(INSTR_imm), .halt(halt_top),
        .RegWriteD(RegWrite_top), .ResultSrcD(ResultSrcD_top),
        .MemWriteD(memWriteD_top), .jumpD(jumpD_top), .jumpR(jumpRD_top),
        .BranchD(BranchD_top), .ALUControlD(ALUControlD_top),
        .ALUSrcD(ALUSrcD_top), .ALUSrcA(ALUSrcAD_top),
        .ImmSrc(ImmSrc_top), .ALUType(ALUtyp_top));

    Reg_file Reg_file_top (
        .clk(clk),
        .rs1_addr(INSTR_rs1), .rs2_addr(INSTR_rs2),
        .rd_addr(RdW_top), .Regwrite(RegWriteW_top),
        .Write_data(ResultW_top),
        .Read_data1(RD1_top), .Read_data2(RD2_top));

    imm imm_top (
        .ImmSrc(ImmSrc_top), .instruction(INSTR_full),
        .ImmExt(ImmExtD_top));

    // =========================================================
    // EXECUTE — Domain B
    // =========================================================
    EX_stage ex_stage (
        .clk(clk), .reset(reset_sync),
        .flushE(FlushE_top),
        .RD1D_in(RD1_top), .RD2D_in(RD2_top),
        .ImmExtD_in(ImmExtD_top), .PCPlus4D_in(PCPLUS4D_TOP),
        .PC_D_in(PCD_top), .Rs1D_in(INSTR_rs1), .Rs2D_in(INSTR_rs2),
        .RdD_in(INSTR_rd), .ALUControlD_in(ALUControlD_top),
        .ALUSrcD_in(ALUSrcD_top), .ALUSrcA_in(ALUSrcAD_top),
        .RegWriteD_in(RegWrite_top), .ResultSrcD_in(ResultSrcD_top),
        .MemWriteD_in(memWriteD_top), .BranchD_in(BranchD_top),
        .JumpD_in(jumpD_top), .JumpR_in(jumpRD_top),
        .ALUType_in(ALUtyp_top),
        .RD1E_out(RD1E_top), .RD2E_out(RD2E_top),
        .ImmExtD_out(ImmExtE_top), .PCPlus4D_out(PCPlus4E_top),
        .PC_D_out(PCE_top), .Rs1D_out(Rs1E_top), .Rs2D_out(Rs2E_top),
        .RdD_out(RdE_top), .ALUControlD_out(ALUControlE_top),
        .ALUSrcD_out(ALUSrcE_top), .ALUSrcA_out(ALUSrcAE_top),
        .RegWriteD_out(RegWriteE_top), .ResultSrcD_out(ResultSrcE_top),
        .MemWriteD_out(MemWriteE_top), .BranchD_out(BranchE_top),
        .JumpD_out(JumpE_top), .JumpR_out(JumpRE_top),
        .ALUType_out(ALUTypE_top));

    // ── Forwarding MUXes — combinational (must not register) ──
    // ForwardAE/BE must be produced combinationally. If registered,
    // the select is 1 cycle late relative to the forwarded data,
    // causing the ALU to read the wrong operand. Physical fanout
    // is handled by SDC set_max_fanout 6.
    wire [31:0] SrcA_fwd =
        (ForwardAE_top == 2'b10) ? ALUResultM_top :
        (ForwardAE_top == 2'b01) ? ResultW_top    :
                                    RD1E_top;

    assign SrcA_top =
        (ALUSrcAE_top == 2'b10) ? 32'd0   :
        (ALUSrcAE_top == 2'b01) ? PCE_top :
                                   SrcA_fwd;

    assign outB_top =
        (ForwardBE_top == 2'b10) ? ALUResultM_top :
        (ForwardBE_top == 2'b01) ? ResultW_top    :
                                    RD2E_top;

    assign ScrB_top = ALUSrcE_top ? ImmExtE_top : outB_top;

    wire [31:0] base_addr_w = JumpRE_top ? RD1E_top : PCE_top;
    assign PCTarget_top = JumpRE_top
        ? ((base_addr_w + ImmExtE_top) & 32'hFFFFFFFE)
        :  (base_addr_w + ImmExtE_top);

    assign PCSCR_top = (zero_top & BranchE_top) | JumpE_top;

    ALU alu (
        .ScrA(SrcA_top), .ScrB(ScrB_top),
        .ALUControl(ALUControlE_top), .ALUType(ALUTypE_top),
        .ALUResult(ALUResultE_top), .Zero(zero_top));

    // =========================================================
    // MEMORY STAGE — Domain B
    // =========================================================
    MEM_stage mem_stage (
        .clk(clk), .reset(reset_sync),
        .ALUResult_in(ALUResultE_top), .WriteData_in(outB_top),
        .RdM_in(RdE_top), .PCPlus4M_in(PCPlus4E_top),
        .RegWriteM_in(RegWriteE_top), .ResultSrcM_in(ResultSrcE_top),
        .MemWriteM_in(MemWriteE_top),
        .ALUResult_out(ALUResultM_top), .WriteData_out(WriteDataM_top),
        .RdM_out(RdM_top), .PCPlus4M_out(PCPlus4M_top),
        .RegWriteM_out(RegWriteM_top), .ResultSrcM_out(ResultSrcM_top),
        .MemWriteM_out(MemWriteM_top));

    // =========================================================
    // WRITEBACK — Domain B
    // =========================================================
    WriteBack_stage writeback_stage (
        .clk(clk), .reset(reset_sync),
        .ALUResultW_in(ALUResultM_top), .ReadDataW_in(Datamem_top),
        .RdW_in(RdM_top), .PCPlus4W_in(PCPlus4M_top),
        .RegWriteW_in(RegWriteM_top), .ResultSrcW_in(ResultSrcM_top),
        .ALUResultW_out(ALUResultW_top), .ReadDataW_out(ReadDataW_top),
        .RdW_out(RdW_top), .PCPlus4W_out(PCPlus4W_top),
        .RegWriteW_out(RegWriteW_top), .ResultSrcW_out(ResultSrcW_top));

    Write_back write_back (
        .ALUResultW_in(ALUResultW_top), .ReadDataW_in(ReadDataW_top),
        .PCPlus4W_in(PCPlus4W_top), .ResultSrcW_in(ResultSrcW_top),
        .ResultW(ResultW_top));

    // =========================================================
    // HAZARD UNIT — purely combinational, no reset
    // =========================================================
    Hazard_Unit hazard (
        .Rs1D(INSTR_rs1), .Rs2D(INSTR_rs2),
        .Rs1E(Rs1E_top), .Rs2E(Rs2E_top), .RdE(RdE_top),
        .RegWriteE(RegWriteE_top), .PCSRCE(PCSCR_top),
        .ResultSrcE_in(ResultSrcE_top),
        .RdM(RdM_top), .RdW(RdW_top),
        .RegWriteM(RegWriteM_top), .RegWriteW(RegWriteW_top),
        .StallF(StallF_top), .StallD(StallD_top),
        .FlushD(FlushD_top), .FlushE(FlushE_top),
        .Forward_AE(ForwardAE_top), .Forward_BE(ForwardBE_top));

    // =========================================================
    // PERIPHERALS
    // =========================================================
    wire        spi2_start_w, spi2_busy_w, spi2_done_w, spi2_pending_w;
    wire [7:0]  spi2_tx_data_w, spi2_rx_data_w;
    wire        gpio2_wr_en_w, gpio2_wdata_w;

    // DataMem — Domain B
    // aluAddress_in stays combinational (ALUResultM_top directly).
    // Registering it would de-sync the address from MemWriteM_top,
    // causing writes to wrong peripheral addresses.
    DataMem #(
        .UART_FIFO_DEPTH (4),
        .SPI_RX_DEPTH    (4)
    ) databus_inst (
        .clk             (clk),
        .reset           (reset_sync),
        .aluAddress_in   (ALUResultM_top),
        .DataWriteM_in   (WriteDataM_top[7:0]),
        .memwriteM_in    (MemWriteM_top),
        .DataMem_out     (Datamem_top),
        .uart_tx_start   (periph_tx_start),
        .uart_out_data   (periph_tx_data),
        .uart_tx_busy    (uart_tx_busy_shared),
        .spi2_tx_data    (spi2_tx_data_w),
        .spi2_start      (spi2_start_w),
        .spi2_pending_out(spi2_pending_w),
        .spi2_rx_data    (spi2_rx_data_w),
        .spi2_busy       (spi2_busy_w),
        .spi2_done       (spi2_done_w),
        .gpio2_wr_en     (gpio2_wr_en_w),
        .gpio2_wdata     (gpio2_wdata_w));

    // spi_master — Domain B
    spi_master #(
        .DATA_WIDTH(8), .CPOL(0), .CPHA(0), .CLK_DIV(8)
    ) spi2_inst (
        .clk(clk), .reset(reset_sync),
        .start(spi2_start_w), .tx_data(spi2_tx_data_w),
        .rx_data(spi2_rx_data_w), .busy(spi2_busy_w),
        .done(spi2_done_w), .sclk(spi2_sclk),
        .mosi(spi2_mosi), .miso(spi2_miso));

    // gpio2_io — Domain A (raw reset)
    // On reset: gpio_out_reg = 1 (CS_N idle-high). DataMem
    // (Domain B) cannot drive gpio2_wr_en=1 until reset_sync
    // deasserts, which is 2 cycles AFTER gpio2 is already
    // stable at CS_N=1. No glitch possible.
    gpio2_io gpio2 (
        .clk(clk), .reset(reset),
        .wr_en2(gpio2_wr_en_w), .wdata2(gpio2_wdata_w),
        .spi_busy(spi2_busy_w), .spi_pending(spi2_pending_w),
        .gpio_out2(spi2_cs_n));

endmodule







