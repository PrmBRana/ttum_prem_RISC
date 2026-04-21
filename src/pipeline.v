`default_nettype none
`timescale 1ns/1ps

// ============================================================
//  pipeline — RISC-V 5-stage + shared UART + SPI2 + GPIO
//
//  FROM WAVEFORM (root causes fixed here):
//
//  BUG 1 — aluAddress_in=0 (core executing wrong):
//    Caused by stall_Pro releasing too late.
//    stall_pro was a REG in bootloader (1 extra cycle).
//    Combined with boot_done_r registration = 2 cycles late.
//    Pipeline executed 2 garbage cycles → garbage addresses.
//    Fixed: uart_bootloader now drives stall_pro as a wire.
//    Only ONE registration here (boot_done_r). Correct.
//
//  BUG 2 — DataMem_out=DEADBADD constantly:
//    Follows from BUG 1 — core computing wrong addresses.
//    Once stall_Pro fix is applied, core computes correct
//    addresses (0x10000000, 0x40000000 etc.).
//
//  BUG 3 — uart_out_data shows 0x00 before 'M':
//    Fixed in DataMem + uart_Tx_fixed async reset.
//    Async reset ensures CircularBuffer mem[] is 0 (not X),
//    tx resets to 1 (not X), preventing UartSink crash.
//
//  ASIC TAPEOUT NOTES:
//    - No clock/reset alias wires (rst_core, clk_core etc.)
//      — these are transparent to synthesis and create extra
//      antenna net segments in OpenLane routing.
//    - No ALUResultM_top alias wires (ALUResM_fwdA etc.)
//      — synthesis collapses to same net. SDC handles fanout.
//    - boot_tx_start gated with ~boot_done_r: prevents MUX
//      switching mid-pulse → no X on tx at boot→run transition.
//    - All submodules use active-high async reset consistently.
//
//  SDC (pipeline.sdc):
//    set_max_fanout 4  [get_ports reset]
//    set_max_fanout 8  [current_design]
//    set_max_transition 0.5 [current_design]
//    set_ideal_network [get_ports clk]
//    DIODE_INSERTION_STRATEGY=3 in OpenLane config.json
//    for aluAddress_in bus antenna violations.
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

    localparam IMEM_ADDR_W = 5;

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
    wire        stall_Pro;      // wire from bootloader = ~boot_done
    wire        halt_top;

    // ── boot_done_r — ONE registered path buffer ──────────────
    // stall_Pro is now a combinational wire (~boot_done).
    // Register once here to break the hazard critical path
    // before the arbiter MUXes. Safe: 0→1 transition once only.
    wire boot_done_comb = ~stall_Pro;
    reg  boot_done_r;
    always @(posedge clk or posedge reset) begin
        if (reset) boot_done_r <= 1'b0;
        else       boot_done_r <= boot_done_comb;
    end

    // ── TX arbiter ────────────────────────────────────────────
    // Boot path: gate boot_tx_start_raw with ~boot_done_r.
    //   If boot_done_r rises the same cycle boot_tx_start fires,
    //   the MUX would switch source mid-pulse → X on tx line.
    //   Gating prevents this: bootloader TX is suppressed the
    //   exact cycle the arbiter switches to peripheral.
    // Periph path: gate on ~uart_tx_busy_shared so DataMem
    //   cannot start a new byte while serialiser is running.
    wire boot_tx_start_gated = boot_tx_start_raw & ~boot_done_r;
    wire [7:0] shared_tx_data  = boot_done_r ? periph_tx_data      : boot_tx_data;
    wire       shared_tx_start = boot_done_r
                                     ? (periph_tx_start & ~uart_tx_busy_shared)
                                     : boot_tx_start_gated;

    // ── RX routing ────────────────────────────────────────────
    // Only bootloader sees RX during boot. Core is TX-only.
    wire uart_rx_ready_boot = uart_rx_ready_shared & ~boot_done_r;

    // ── Halt logic ────────────────────────────────────────────
    wire halt_active = halt_top & ~stall_Pro & ~FlushD_top & ~FlushE_top;
    reg  halt_latch;
    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clk or posedge reset) begin
        if (reset)            halt_latch <= 1'b0;
        else if (stall_Pro)   halt_latch <= 1'b0;
        else if (halt_active) halt_latch <= 1'b1;
    end
    /* verilator lint_on  SYNCASYNCNET */
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

    pc_register Register_top (
        .clk(clk), .reset(reset),
        .PCF_in(PC_top), .stallF(StallF_net), .PCF_out(PCF));

    // =========================================================
    // SHARED UART
    // =========================================================
    uart_Tx_fixed #(
        .CLK_FREQ(50_000_000), .BAUD_RATE(115_200), .OVERSAMPLE(16)
    ) uart_shared_inst (
        .clk(clk), .reset(reset),
        .tx_Start(shared_tx_start), .tx_Data(shared_tx_data),
        .tx(tx), .tx_busy(uart_tx_busy_shared),
        .rx(rx), .rx_Data(uart_rx_data_shared),
        .rx_ready(uart_rx_ready_shared));

    // =========================================================
    // BOOTLOADER
    // =========================================================
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

    mem1KB_32bit #(
        .DEPTH(32), .ADDR_W(IMEM_ADDR_W)
    ) flipflop (
        .clk(clk), .reset(reset),
        .we(Write_enable),
        .addr(mem_addr[IMEM_ADDR_W-1:0]),
        .wdata(mem_wdata),
        .read_Address(PCF),
        .Instruction_out(Instruction1_out));

    // =========================================================
    // DECODE
    // =========================================================
    IF_ID_stage IF_DF_top (
        .clk(clk), .reset(reset),
        .stallD(StallD_net), .flushD(FlushD_top),
        .PC_in(PCF), .PCplus4_in(PCPLUS4_top),
        .instruction_in(Instruction1_out),
        .instruction_out(INSTRUCTION),
        .PCplus4_out(PCPLUS4D_TOP), .PC_out(PCD_top));

    // Named field slices reduce per-consumer routing fanout
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
    // EXECUTE
    // =========================================================
    EX_stage ex_stage (
        .clk(clk), .reset(reset), .flushE(FlushE_top),
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

    // ── Forwarding MUXes — combinational, no alias wires ──────
    // Alias wires (ALUResM_fwdA etc.) collapse to same net in
    // synthesis — they don't help fanout. SDC set_max_fanout 8
    // causes the tool to insert BUFX cells automatically.
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
    // MEMORY STAGE
    // =========================================================
    MEM_stage mem_stage (
        .clk(clk), .reset(reset),
        .ALUResult_in(ALUResultE_top), .WriteData_in(outB_top),
        .RdM_in(RdE_top), .PCPlus4M_in(PCPlus4E_top),
        .RegWriteM_in(RegWriteE_top), .ResultSrcM_in(ResultSrcE_top),
        .MemWriteM_in(MemWriteE_top),
        .ALUResult_out(ALUResultM_top), .WriteData_out(WriteDataM_top),
        .RdM_out(RdM_top), .PCPlus4M_out(PCPlus4M_top),
        .RegWriteM_out(RegWriteM_top), .ResultSrcM_out(ResultSrcM_top),
        .MemWriteM_out(MemWriteM_top));

    // =========================================================
    // WRITEBACK
    // =========================================================
    WriteBack_stage writeback_stage (
        .clk(clk), .reset(reset),
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
    // HAZARD UNIT
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

    DataMem #(
        .UART_FIFO_DEPTH (4),
        .SPI_RX_DEPTH    (4)
    ) databus_inst (
        .clk             (clk),
        .reset           (reset),
        .aluAddress_in   (ALUResultM_top),
        .DataWriteM_in   (WriteDataM_top[7:0]),
        .memwriteM_in    (MemWriteM_top),
        .DataMem_out     (Datamem_top),
        // UART TX only
        .uart_tx_start   (periph_tx_start),
        .uart_out_data   (periph_tx_data),
        .uart_tx_busy    (uart_tx_busy_shared),
        // SPI2
        .spi2_tx_data    (spi2_tx_data_w),
        .spi2_start      (spi2_start_w),
        .spi2_pending_out(spi2_pending_w),
        .spi2_rx_data    (spi2_rx_data_w),
        .spi2_busy       (spi2_busy_w),
        .spi2_done       (spi2_done_w),
        // GPIO2
        .gpio2_wr_en     (gpio2_wr_en_w),
        .gpio2_wdata     (gpio2_wdata_w));

    spi_master #(
        .DATA_WIDTH(8), .CPOL(0), .CPHA(0), .CLK_DIV(8)
    ) spi2_inst (
        .clk(clk), .reset(reset),
        .start(spi2_start_w), .tx_data(spi2_tx_data_w),
        .rx_data(spi2_rx_data_w), .busy(spi2_busy_w),
        .done(spi2_done_w), .sclk(spi2_sclk),
        .mosi(spi2_mosi), .miso(spi2_miso));

    gpio2_io gpio2 (
        .clk(clk), .reset(reset),
        .wr_en2(gpio2_wr_en_w), .wdata2(gpio2_wdata_w),
        .spi_busy(spi2_busy_w), .spi_pending(spi2_pending_w),
        .gpio_out2(spi2_cs_n));

endmodule






