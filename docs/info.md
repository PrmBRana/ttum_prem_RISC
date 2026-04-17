<!---

This file is used to generate your project datasheet. Please fill in the information below and delete any unused
sections.

You can also include images in this folder and reference them in the markdown. Each image must be less than
512 kb in size, and the combined size of all images must be less than 1 MB.
-->

## How it work

This project implements a programmable RISC-V processor with a 5-stage pipeline:

Fetch (IF) – Instruction is fetched from memory.
Decode (ID) – Instruction type is decoded, and operands are read.
Execute (EX) – Arithmetic or logical operations are performed.
Memory Access (MEM) – Load/store instructions interact with memory.
Write Back (WB) – Results are written back to the register file.

The processor can be programmed via UART, enabling you to send instructions directly. The pipelined design allows multiple instructions to be processed simultaneously, increasing throughput and efficiency.

## How to test

To ensure correct functionality:

Verify execution of different instruction types:
Arithmetic (add, sub, mul)
Logical (and, or, xor)
Load/Store (lw, sw)
Branch/Jump (beq, jal)
Check that instructions move correctly through the pipeline stages.
Monitor pipeline hazards, stalls, and forwarding to ensure smooth execution.
Use UART to send test programs and verify output.

## External hardware

Control signals like clock, reset and enable signals,
SRAM for instruction memory, 
connecting cables
