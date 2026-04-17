`default_nettype none
`timescale 1ns/1ps

// ============================================================
//  pipeline — RISC-V 5-stage + UART + SPI1(÷4) + SPI2(÷8) + GPIO
// ============================================================
module pipeline(
    input  wire clk,
    input  wire reset,
    input  wire rx,
    output wire tx,
    output wire UART_tx,
    input  wire UART_rx_line,
    output wire spi2_sclk,
    output wire spi2_mosi,
    input  wire spi2_miso,
    output wire spi2_cs_n
);

    // ── Reset buffer groups ───────────────────────────────────
    wire rst_core   = reset;
    wire rst_mem    = reset;
    wire rst_periph = reset;
    wire rst_boot   = reset;

    // ── Clock buffer groups ───────────────────────────────────
    wire clk_core    = clk;
    wire clk_imem    = clk;
    wire clk_regfile = clk;
    wire clk_periph  = clk;

    // ── mem1KB address width ──────────────────────────────────
    localparam IMEM_ADDR_W = 5;   // DEPTH=32 → $clog2(32)=5

    // ── Pipeline wires ────────────────────────────────────────
    wire [31:0] PCPLUS4_top, PC_top, PCF, Instruction1_out, INSTRUCTION;
    wire [31:0] RD1_top, RD2_top, PCD_top, PCE_top, PCPLUS4D_TOP;
    wire [31:0] RD1E_top, RD2E_top;
    wire [31:0] SrcA_top, outB_top, ScrB_top;
    wire [31:0] ALUResultE_top, PCPlus4E_top, ALUResultM_top, PCPlus4M_top;
    wire [31:0] Datamem_top, ALUResultW_top, ReadDataW_top, PCPlus4W_top, ResultW_top;
    wire [31:0] PCTarget_top, ImmExtD_top, ImmExtE_top;

    // WriteDataM_top: full 32-bit pipeline bus; only [7:0] used
    // by byte-wide peripherals — upper bits suppressed below.
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

    // ── Bootloader wires ──────────────────────────────────────
    wire [7:0]  uart_rx_data_boot, boot_tx_data;
    wire        uart_rx_ready_boot, boot_tx_start;
    wire        Write_enable;

    // mem_addr [7:0] matches uart_bootloader output port.
    // Upper bits [7:IMEM_ADDR_W] are unused — suppressed below.
    /* verilator lint_off UNUSEDSIGNAL */
    wire [7:0]  mem_addr;
    /* verilator lint_on  UNUSEDSIGNAL */

    wire [31:0] mem_wdata;
    wire        stall_Pro;
    wire        halt_top;

    // ── Halt latch ────────────────────────────────────────────
    wire halt_active = halt_top & ~stall_Pro & ~FlushD_top & ~FlushE_top;
    reg  halt_latch;

    /* verilator lint_off SYNCASYNCNET */
    always @(posedge clk_regfile or posedge rst_mem) begin
        if (rst_mem)          halt_latch <= 1'b0;
        else if (stall_Pro)   halt_latch <= 1'b0;
        else if (halt_active) halt_latch <= 1'b1;
    end
    /* verilator lint_on  SYNCASYNCNET */

    wire halt_final = halt_latch | halt_active;

    // ── Stall / flush ─────────────────────────────────────────
    wire StallF_net = PCSCR_top ? 1'b0 : (stall_Pro | StallF_top | halt_final);
    wire StallD_net = PCSCR_top ? 1'b0 : (stall_Pro | StallD_top | halt_final);

    // =========================================================
    // FETCH
    // =========================================================
    PC_incre PC(
        .pc(PCF),
        .PCPlus4(PCPLUS4_top));

    PCSelect_MUX PCSelect_top(
        .PCScr(PCSCR_top),
        .PCSequential(PCPLUS4_top),
        .PCBranch(PCTarget_top),
        .Mux3_PC(PC_top));

    pc_register Register_top(
        .clk(clk_core), .reset(rst_core),
        .PCF_in(PC_top), .stallF(StallF_net),
        .PCF_out(PCF));

    // =========================================================
    // BOOTLOADER
    // =========================================================
    uart_Tx_fixed #(
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(115_200),
        .OVERSAMPLE(16)
    ) uart_boot_inst (
        .clk(clk_periph), .reset(rst_boot),
        .tx_Start(boot_tx_start), .tx_Data(boot_tx_data),
        .tx(tx), .rx(rx),
        .rx_Data(uart_rx_data_boot),
        .rx_ready(uart_rx_ready_boot));

    uart_bootloader uart_bootloader(
        .clk(clk_periph), .reset(rst_boot),
        .rx_data(uart_rx_data_boot), .rx_valid(uart_rx_ready_boot),
        .tx_data(boot_tx_data),      .tx_start(boot_tx_start),
        .mem_we(Write_enable),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata),
        .stall_pro(stall_Pro));

    // Slice mem_addr to IMEM_ADDR_W bits at the port connection.
    // uart_bootloader outputs [7:0]; mem1KB_32bit.addr is [4:0].
    mem1KB_32bit #(
        .DEPTH(32),
        .ADDR_W(IMEM_ADDR_W)
    ) flipflop (
        .clk(clk_imem), .reset(rst_core),
        .we(Write_enable),
        .addr(mem_addr[IMEM_ADDR_W-1:0]),
        .wdata(mem_wdata),
        .read_Address(PCF),
        .Instruction_out(Instruction1_out));

    // =========================================================
    // DECODE
    // =========================================================
    IF_ID_stage IF_DF_top(
        .clk(clk_core), .reset(rst_core),
        .stallD(StallD_net), .flushD(FlushD_top),
        .PC_in(PCF), .PCplus4_in(PCPLUS4_top),
        .instruction_in(Instruction1_out),
        .instruction_out(INSTRUCTION),
        .PCplus4_out(PCPLUS4D_TOP),
        .PC_out(PCD_top));

    // ── INSTRUCTION fanout — per-field sliced wires ───────────
    wire [6:0]  INSTR_op  = INSTRUCTION[6:0];
    wire [2:0]  INSTR_f3  = INSTRUCTION[14:12];
    wire [6:0]  INSTR_f7  = INSTRUCTION[31:25];
    wire [11:0] INSTR_imm = INSTRUCTION[31:20];
    wire [4:0]  INSTR_rs1 = INSTRUCTION[19:15];
    wire [4:0]  INSTR_rs2 = INSTRUCTION[24:20];
    wire [31:0] INSTR_full = INSTRUCTION;   // imm generator needs all bits
    wire [4:0]  INSTR_rd  = INSTRUCTION[11:7];

    Control control(
        .Opcode     (INSTR_op),
        .funct3     (INSTR_f3),
        .funct7     (INSTR_f7),
        .imm        (INSTR_imm),
        .halt       (halt_top),
        .RegWriteD  (RegWrite_top),
        .ResultSrcD (ResultSrcD_top),
        .MemWriteD  (memWriteD_top),
        .jumpD      (jumpD_top),
        .jumpR      (jumpRD_top),
        .BranchD    (BranchD_top),
        .ALUControlD(ALUControlD_top),
        .ALUSrcD    (ALUSrcD_top),
        .ALUSrcA    (ALUSrcAD_top),
        .ImmSrc     (ImmSrc_top),
        .ALUType    (ALUtyp_top));

    // Reg_file has no reset port
    Reg_file Reg_file_top(
        .clk       (clk_regfile),
        .rs1_addr  (INSTR_rs1),
        .rs2_addr  (INSTR_rs2),
        .rd_addr   (RdW_top),
        .Regwrite  (RegWriteW_top),
        .Write_data(ResultW_top),
        .Read_data1(RD1_top),
        .Read_data2(RD2_top));

    imm imm_top(
        .ImmSrc     (ImmSrc_top),
        .instruction(INSTR_full),
        .ImmExt     (ImmExtD_top));

    // =========================================================
    // EXECUTE
    // =========================================================
    EX_stage ex_stage(
        .clk            (clk_core),
        .reset          (rst_core),
        .flushE         (FlushE_top),
        .RD1D_in        (RD1_top),
        .RD2D_in        (RD2_top),
        .ImmExtD_in     (ImmExtD_top),
        .PCPlus4D_in    (PCPLUS4D_TOP),
        .PC_D_in        (PCD_top),
        .Rs1D_in        (INSTR_rs1),
        .Rs2D_in        (INSTR_rs2),
        .RdD_in         (INSTR_rd),
        .ALUControlD_in (ALUControlD_top),
        .ALUSrcD_in     (ALUSrcD_top),
        .ALUSrcA_in     (ALUSrcAD_top),
        .RegWriteD_in   (RegWrite_top),
        .ResultSrcD_in  (ResultSrcD_top),
        .MemWriteD_in   (memWriteD_top),
        .BranchD_in     (BranchD_top),
        .JumpD_in       (jumpD_top),
        .JumpR_in       (jumpRD_top),
        .ALUType_in     (ALUtyp_top),
        .RD1E_out       (RD1E_top),
        .RD2E_out       (RD2E_top),
        .ImmExtD_out    (ImmExtE_top),
        .PCPlus4D_out   (PCPlus4E_top),
        .PC_D_out       (PCE_top),
        .Rs1D_out       (Rs1E_top),
        .Rs2D_out       (Rs2E_top),
        .RdD_out        (RdE_top),
        .ALUControlD_out(ALUControlE_top),
        .ALUSrcD_out    (ALUSrcE_top),
        .ALUSrcA_out    (ALUSrcAE_top),
        .RegWriteD_out  (RegWriteE_top),
        .ResultSrcD_out (ResultSrcE_top),
        .MemWriteD_out  (MemWriteE_top),
        .BranchD_out    (BranchE_top),
        .JumpD_out      (JumpE_top),
        .JumpR_out      (JumpRE_top),
        .ALUType_out    (ALUTypE_top));

    // ── ALU fanout buffer wires ───────────────────────────────
    wire [31:0] ALUResM_fwdA = ALUResultM_top;
    wire [31:0] ALUResM_fwdB = ALUResultM_top;
    wire [31:0] ALUResM_dmem = ALUResultM_top;
    wire [31:0] ALUResM_wb   = ALUResultM_top;
    wire [31:0] ResultW_fwdA = ResultW_top;
    wire [31:0] ResultW_fwdB = ResultW_top;

    // ── Forwarding MUX A — with LUI/AUIPC override ───────────
    wire [31:0] SrcA_fwd =
        (ForwardAE_top == 2'b10) ? ALUResM_fwdA :
        (ForwardAE_top == 2'b01) ? ResultW_fwdA :
                                    RD1E_top;

    assign SrcA_top =
        (ALUSrcAE_top == 2'b10) ? 32'd0    :   // LUI:   SrcA = 0
        (ALUSrcAE_top == 2'b01) ? PCE_top  :   // AUIPC: SrcA = PC_E
                                   SrcA_fwd;   // normal forwarding

    // ── Forwarding MUX B ──────────────────────────────────────
    assign outB_top =
        (ForwardBE_top == 2'b10) ? ALUResM_fwdB :
        (ForwardBE_top == 2'b01) ? ResultW_fwdB :
                                    RD2E_top;

    // ── ALU source-B MUX ──────────────────────────────────────
    assign ScrB_top = ALUSrcE_top ? ImmExtE_top : outB_top;

    // ── PC-target adder ───────────────────────────────────────
    wire [31:0] base_addr_w = JumpRE_top ? RD1E_top : PCE_top;
    assign PCTarget_top = JumpRE_top
        ? ((base_addr_w + ImmExtE_top) & 32'hFFFFFFFE)
        :  (base_addr_w + ImmExtE_top);

    // ── Branch/Jump → PC select ───────────────────────────────
    assign PCSCR_top = (zero_top & BranchE_top) | JumpE_top;

    ALU alu(
        .ScrA      (SrcA_top),
        .ScrB      (ScrB_top),
        .ALUControl(ALUControlE_top),
        .ALUType   (ALUTypE_top),
        .ALUResult (ALUResultE_top),
        .Zero      (zero_top));

    // =========================================================
    // MEMORY STAGE
    // =========================================================
    MEM_stage mem_stage(
        .clk           (clk_core),
        .reset         (rst_core),
        .ALUResult_in  (ALUResultE_top),
        .WriteData_in  (outB_top),
        .RdM_in        (RdE_top),
        .PCPlus4M_in   (PCPlus4E_top),
        .RegWriteM_in  (RegWriteE_top),
        .ResultSrcM_in (ResultSrcE_top),
        .MemWriteM_in  (MemWriteE_top),
        .ALUResult_out (ALUResultM_top),
        .WriteData_out (WriteDataM_top),
        .RdM_out       (RdM_top),
        .PCPlus4M_out  (PCPlus4M_top),
        .RegWriteM_out (RegWriteM_top),
        .ResultSrcM_out(ResultSrcM_top),
        .MemWriteM_out (MemWriteM_top));

    // =========================================================
    // WRITEBACK
    // =========================================================
    WriteBack_stage writeback_stage(
        .clk           (clk_core),
        .reset         (rst_core),
        .ALUResultW_in (ALUResM_wb),
        .ReadDataW_in  (Datamem_top),
        .RdW_in        (RdM_top),
        .PCPlus4W_in   (PCPlus4M_top),
        .RegWriteW_in  (RegWriteM_top),
        .ResultSrcW_in (ResultSrcM_top),
        .ALUResultW_out(ALUResultW_top),
        .ReadDataW_out (ReadDataW_top),
        .RdW_out       (RdW_top),
        .PCPlus4W_out  (PCPlus4W_top),
        .RegWriteW_out (RegWriteW_top),
        .ResultSrcW_out(ResultSrcW_top));

    Write_back write_back(
        .ALUResultW_in(ALUResultW_top),
        .ReadDataW_in (ReadDataW_top),
        .PCPlus4W_in  (PCPlus4W_top),
        .ResultSrcW_in(ResultSrcW_top),
        .ResultW      (ResultW_top));

    // =========================================================
    // HAZARD UNIT
    // =========================================================
    Hazard_Unit hazard(
        .Rs1D         (INSTR_rs1),
        .Rs2D         (INSTR_rs2),
        .Rs1E         (Rs1E_top),
        .Rs2E         (Rs2E_top),
        .RdE          (RdE_top),
        .RegWriteE    (RegWriteE_top),
        .PCSRCE       (PCSCR_top),
        .ResultSrcE_in(ResultSrcE_top),
        .RdM          (RdM_top),
        .RdW          (RdW_top),
        .RegWriteM    (RegWriteM_top),
        .RegWriteW    (RegWriteW_top),
        .StallF       (StallF_top),
        .StallD       (StallD_top),
        .FlushD       (FlushD_top),
        .FlushE       (FlushE_top),
        .Forward_AE   (ForwardAE_top),
        .Forward_BE   (ForwardBE_top));

    // =========================================================
    // PERIPHERALS
    // =========================================================
     wire        spi2_start_w, spi2_busy_w, spi2_done_w, spi2_pending_w;
    wire [7:0]  spi2_tx_data_w, spi2_rx_data_w;
    wire        gpio2_wr_en_w, gpio2_wdata_w;
    wire        UART_tx_start_w, UART_tx_busy_w, UART_rx_ready_w;
    wire [7:0]  UART_tx_data_w, UART_rx_data_w;

    // DataMem — byte-wide write port: connect [7:0] only
    DataMem #(
        .UART_FIFO_DEPTH(2),
        .SPI_RX_DEPTH(2)
    ) databus_inst (
        .clk             (clk_core),
        .reset           (rst_core),
        .aluAddress_in   (ALUResM_dmem),
        .DataWriteM_in   (WriteDataM_top[7:0]),
        .memwriteM_in    (MemWriteM_top),
        .DataMem_out     (Datamem_top),
        .uart_tx_start   (UART_tx_start_w),
        .uart_out_data   (UART_tx_data_w),
        .uart_tx_busy    (UART_tx_busy_w),
        .uart_in_data    (UART_rx_data_w),
        .uart_rx_ready   (UART_rx_ready_w),
        .spi2_tx_data    (spi2_tx_data_w),
        .spi2_start      (spi2_start_w),
        .spi2_pending_out(spi2_pending_w),
        .spi2_rx_data    (spi2_rx_data_w),
        .spi2_busy       (spi2_busy_w),
        .spi2_done       (spi2_done_w),
        .gpio2_wr_en     (gpio2_wr_en_w),
        .gpio2_wdata     (gpio2_wdata_w));

    // Peripheral UART
    uart_Tx_fixed0 #(
        .CLK_FREQ(50_000_000),
        .BAUD_RATE(115_200),
        .OVERSAMPLE(16)
    ) uart_inst0 (
        .clk     (clk_periph),
        .reset   (rst_periph),
        .tx_Start(UART_tx_start_w),
        .tx_Data (UART_tx_data_w),
        .tx      (UART_tx),
        .tx_busy (UART_tx_busy_w),
        .rx      (UART_rx_line),
        .rx_Data (UART_rx_data_w),
        .rx_ready(UART_rx_ready_w));


    // SPI2 — slow (CLK_DIV=8, 6.25 MHz)
    spi_master #(
        .DATA_WIDTH(8), .CPOL(0), .CPHA(0), .CLK_DIV(8)
    ) spi2_inst (
        .clk    (clk_periph),
        .reset  (rst_periph),
        .start  (spi2_start_w),
        .tx_data(spi2_tx_data_w),
        .rx_data(spi2_rx_data_w),
        .busy   (spi2_busy_w),
        .done   (spi2_done_w),
        .sclk   (spi2_sclk),
        .mosi   (spi2_mosi),
        .miso   (spi2_miso));


    // GPIO2 → SPI2 CS
    gpio2_io gpio2(
        .clk        (clk_periph),
        .reset      (rst_periph),
        .wr_en2     (gpio2_wr_en_w),
        .wdata2     (gpio2_wdata_w),
        .spi_busy   (spi2_busy_w),
        .spi_pending(spi2_pending_w),
        .gpio_out2  (spi2_cs_n));

endmodule






