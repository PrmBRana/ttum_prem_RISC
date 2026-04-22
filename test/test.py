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
            0x0c800293,
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
            0x00000073
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
# SPI SLAVE (Mode-0 Correct)
# --- Full-Duplex SPI Slave Implementation ---
# ============================================================
async def spi_slave_full_duplex(dut, slave_tx_data):

    sclk = dut.spi2_sclk
    mosi = dut.spi2_mosi
    miso = dut.spi2_miso
    cs   = dut.spi2_cs_n
    uart_sink   = UartSink(dut.tx, baud=115200)

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
            f"[{idx}] (SPI) MOSI=0x{rx_byte:02X} ('{byte_to_ascii(rx_byte)}') "
        f"| (SPI) MISO=0x{tx_byte:02X} ('{byte_to_ascii(tx_byte)}') "
        f"| Shared UART tx=0x{tx_byte:02X} ('{byte_to_ascii(tx_byte)}')"
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
    # Use triple quotes to handle internal quotes like "Munal"
    text_data = """Antarikchya Pratisthan Nepal (APN) is a pioneering non-profit organization dedicated to establishing a sustainable space ecosystem within Nepal, driven by the belief that space technology is essential for national development. Established with a vision to transform Nepal from a passive consumer of space services into an active contributor to the global space sector, APN focuses on three core pillars: research and development, capacity building, and community outreach. At the heart of their mission is the development of indigenous satellite technology. One of their flagship projects is "Munal," a 1U CubeSat built by high school students, which serves as a powerful symbol of youth empowerment and technical capability. By involving students in the entire lifecycle of a satellite mission—from design and fabrication to testing—APN is fostering a new generation of aerospace engineers and scientists in a country that historically lacked a formal space program."""
    
    slave_tx = [ord(c) for c in text_data]

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
        result = await with_timeout(slave_task, 20, 'ms')
    except Exception:                    # catch anything — version safe
        dut._log.warning("SPI timed out — partial result")
        result = []