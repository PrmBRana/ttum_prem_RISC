import cocotb
from cocotb.triggers import Timer, ClockCycles, RisingEdge, FallingEdge, with_timeout
from cocotb.clock import Clock
from cocotbext.uart import UartSource, UartSink
from cocotb.utils import get_sim_time


# ============================================================
# Helper
# ============================================================
def byte_to_ascii(val):
    return chr(val) if 31 < val < 127 else '?'



# --- Test 1: Bootloader Handshake & Upload ---
async def test_uart_bootloader(dut):
  """Test UART bootloader handshake: command 0x25, upload instructions."""
  uart_source = UartSource(dut.rx, baud=115200)
  uart_sink   = UartSink(dut.tx, baud=115200)

  # Reset DUT
  dut._log.info("Resetting DUT...")
  dut.rst_n.value = 0
  await ClockCycles(dut.clk, 10)
  dut.rst_n.value = 1
  await ClockCycles(dut.clk, 100)


  dut._log.info(f"Sending handshake command 0x25 at {get_sim_time('ns')} ns")
  await uart_source.write([0x25])


  # Read response (Expect 0x55 ACK)
  resp = await uart_sink.read(count=1)
  val = resp[0]
  dut._log.info(f"Response received: 0x{val:02X} ('{byte_to_ascii(val)}')")




  if val == 0x55:
      dut._log.info("✓ SUCCESS: Handshake ACK received")
      instructions = [
           0x40000537,
           0x30000937,
           0x100009b7,
           0x00850593,
           0x00450613,
           0x00c50693,
           0x00898a93,
           0x00490713,
           0x00100193,
           0x00000813,
           0x03200293,
           0x00300b13,
           0x01072023,
           0x0aa00393,
           0x02028663,
           0x00752023,
           0x0006a403,
           0xfe040ee3,
           0x0005a483,
           0x000aa303,
           0x01637333,
           0xfe031ce3,
           0x0099a023,
           0xfff28293,
           0xfd9ff06f,
           0x00372023,
           0x00000073,
      ]
      dut._log.info("Uploading instructions to processor...")
      for idx, inst in enumerate(instructions):
          bytes_to_send = [
              (inst >>  0) & 0xFF,
              (inst >>  8) & 0xFF,
              (inst >> 16) & 0xFF,
              (inst >> 24) & 0xFF,
          ]
          ascii_repr = ''.join(byte_to_ascii(b) for b in bytes_to_send)
          await uart_source.write(bytes_to_send)
          dut._log.info(f"[{idx+1}/{len(instructions)}] Sent 0x{inst:08X} ('{ascii_repr}')")
          await ClockCycles(dut.clk, 20000)  # Wait for UART serialization

      dut._log.info("All instructions uploaded.")
  else:
      dut._log.error(f"Handshake Failed! Expected 0x55, got 0x{val:02X}")

# ============================================================
# UART BOOTLOADER TEST
# ============================================================
# --- UART Peripheral Echo Test ---
# --- Helper: Format byte as ASCII ---
def byte_to_ascii(val):
   return chr(val) if 31 < val < 127 else '?'




# --- Helper: Robust Receiver with Idle Detection ---
async def collect_uart_data(uart_sink, log, timeout_ms=10):
   """
   Continually reads from UART until a period of silence (timeout) occurs.
   Returns a list of received bytes.
   """
   received = []
   log.info("Receiver started - waiting for data...")


   while True:
       try:
           byte_list = await with_timeout(uart_sink.read(count=1), timeout_ms, 'ms')
           val = byte_list[0]


           # Filter leading 0x00 (startup noise) if buffer is still empty
           if val == 0 and len(received) == 0:
               continue


           received.append(val)
           log.info(f"UART_tx Received: 0x{val:02X} ('{byte_to_ascii(val)}')")


       except cocotb.result.SimTimeoutError:
           log.info(f"Receiver timed out after {timeout_ms}ms of silence. Stopping.")
           break


   ascii_str = ''.join(byte_to_ascii(b) for b in received)
   log.info(f"Full ASCII output: '{ascii_str}'")
   return received

# ============================================================
# UART ECHO TEST
# ============================================================
async def UART_peripherals_test(dut):
   uart_source = UartSource(dut.UART_rx_line, baud=115200)
   uart_sink   = UartSink(dut.UART_tx, baud=115200)


   data_to_send = [ord(c) for c in "RISC-V is an open-source instruction set architecture (ISA) used for the development of custom processors targeting a variety of end applications. Originally developed at the University of California, Berkeley."]


   # Send each byte with realistic UART timing (~1 byte per 100 µs at 115200 baud)
   dut._log.info(f"Sending {len(data_to_send)} bytes: '{''.join(chr(b) for b in data_to_send)}'")
   for byte in data_to_send:
       await uart_source.write([byte])
       dut._log.info(f"Sent to DUT: 0x{byte:02X} ('{chr(byte)}')")
       await Timer(100, units='us')  # spacing to avoid overruns (Issue in 100us, overlap)


   # Collect all echoed bytes until idle
   received = await collect_uart_data(uart_sink, dut._log, timeout_ms=100)


   # Decode received ASCII safely
   received_str = "".join(chr(b) for b in received if 31 < b < 127)
   dut._log.info(f"Full received string: '{received_str}'")


   # Verification
   sent_str = "".join(chr(b) for b in data_to_send)
   if sent_str != received_str:
       dut._log.error("✗ MISMATCH: Sent and received strings differ!")
       for i, b in enumerate(data_to_send):
           rec = received[i] if i < len(received) else None
           dut._log.error(f"Byte[{i}]: sent 0x{b:02X} ('{chr(b)}') vs received {rec} ('{chr(rec) if rec else '?'}')")
       assert False, "UART echo failed!"
   else:
       dut._log.info("✓ UART echo test passed successfully!")


# ============================================================
# SPI SLAVE (Mode-0 Correct)
# --- Full-Duplex SPI Slave Implementation ---
# ============================================================
async def spi_slave_full_duplex(dut, slave_tx_data):

    sclk = dut.spi2_sclk
    mosi = dut.spi2_mosi
    miso = dut.spi2_miso
    cs   = dut.spi2_cs_n
    uart_sink   = UartSink(dut.UART_tx, baud=115200)

    received = []
    idx = 0

    dut._log.info("Waiting for SPI CS LOW...")
    await FallingEdge(cs)

    dut._log.info(f"SPI START @ {get_sim_time('ns')} ns")

    while cs.value == 0:

        tx_byte = slave_tx_data[idx] if idx < len(slave_tx_data) else 0x00
        rx_byte = 0

        # Preload MSB BEFORE first rising edge
        miso.value = (tx_byte >> 7) & 1

        for bit in range(8):

            await RisingEdge(sclk)

            if cs.value == 1:
                break

            rx_byte = (rx_byte << 1) | int(mosi.value)

            await FallingEdge(sclk)

            if bit < 7:
                miso.value = (tx_byte >> (6 - bit)) & 1

        received.append(rx_byte)

        dut._log.info(
            f"[{idx}] MOSI=0x{rx_byte:02X} ('{byte_to_ascii(rx_byte)}') "
        f"| MISO=0x{tx_byte:02X} ('{byte_to_ascii(tx_byte)}') "
        f"| UART_tx=0x{tx_byte:02X} ('{byte_to_ascii(tx_byte)}')"
        )

        idx += 1

    dut._log.info(f"SPI END @ {get_sim_time('ns')} ns")
    return received


# ============================================================
# DEBUG: Monitor SPI signals
# ============================================================
async def spi_debug_monitor(dut):
    while True:
        await Timer(500, units='us')
        dut._log.info(
            f"DEBUG → CS={int(dut.spi2_cs_n.value)} "
            f"SCLK={int(dut.spi2_sclk.value)} "
            f"MOSI={int(dut.spi2_mosi.value)}"
        )


# ============================================================
# MAIN TEST
# ============================================================
@cocotb.test()
async def uart_spi_test(dut):

    # Clock
    cocotb.start_soon(Clock(dut.clk, 20, units="ns").start())

    # Reset
    dut.rst_n.value = 0
    dut.spi2_miso.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 50)
# ===========================================================
# SPI SLAVE TEST
# ===========================================================
    # Debug monitor
    cocotb.start_soon(spi_debug_monitor(dut))

    # SPI response
    slave_tx = [ord(c) for c in "My Name is Prem Rana. Iam from Nepal. I am a student of computer engineering. I am interested in embedded system design and RISC-V architecture. I am currently working on a project to design and implement a RISC-V processor using Verilog HDL. I am also learning about FPGA development and hardware-software co-design. I am passionate about learning new technologies and improving my skills in the field of computer engineering."]

    # ✅ START SLAVE FIRST (CRITICAL FIX)
    slave_task = cocotb.start_soon(
        spi_slave_full_duplex(dut, slave_tx)
    )
#==========================================================
# CODE UPLOAD & BOOTLOADER TEST
# aSSEMBLY INSTRUCTIONS TO UPLOAD
# ==========================================================
    # THEN bootloader
    await test_uart_bootloader(dut)

      # Wait for SPI
    try:
        result = await with_timeout(slave_task, 5, 'ms')
    except Exception:                    # catch anything — version safe
        dut._log.warning("SPI timed out — partial result")
        result = []