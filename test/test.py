# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


async def reset(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 3)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 1)


async def execute(dut, mode, op, data=0):
    dut.ui_in.value = ((mode & 0xF) << 4) | (op & 0xF)
    dut.uio_in.value = data & 0xFF
    await ClockCycles(dut.clk, 1)
    return int(dut.uo_out.value)


@cocotb.test()
async def test_awechip(dut):
    dut._log.info("Starting AWEChip v2 verification")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Mode 0: legacy 8-bit ALU.
    assert await execute(dut, 0, 0, 20) == 20
    assert await execute(dut, 0, 1, 7) == 20
    assert await execute(dut, 0, 2) == 27
    assert await execute(dut, 0, 3) == 20
    assert await execute(dut, 0, 7) == 140
    assert await execute(dut, 0, 0, 0xAA) == 0xAA
    assert await execute(dut, 0, 1, 0x0F) == 0xAA
    assert await execute(dut, 0, 4) == 0x0A
    assert await execute(dut, 0, 0, 0x03) == 0x03
    assert await execute(dut, 0, 1, 0x02) == 0x03
    assert await execute(dut, 0, 8) == 0x0C

    # Mode 1: waveform engine. Basic sine/cosine and phase stepping must be active.
    await execute(dut, 1, 0, 0)
    s0 = await execute(dut, 1, 3)
    assert s0 == 0
    assert await execute(dut, 1, 4) != 0
    await execute(dut, 1, 1, 16)
    s1 = await execute(dut, 1, 2)
    assert s1 != s0

    # Mode 2: fixed-point MAC.
    await execute(dut, 2, 0, 12)
    await execute(dut, 2, 1, 10)
    await execute(dut, 2, 3)
    assert await execute(dut, 2, 4) == 120 & 0xFF
    assert await execute(dut, 2, 5) == 0
    await execute(dut, 2, 9)
    assert await execute(dut, 2, 4) == 0

    # Mode 3: leaky integrate-and-fire neuron.
    await execute(dut, 3, 0, 0x11)  # leak/threshold configuration
    for _ in range(8):
        await execute(dut, 3, 1, 0x20)
    v = await execute(dut, 3, 3)
    assert v != 0
    spike = await execute(dut, 3, 2)
    assert spike in (0, 1)

    # Mode 4: 32-tap delay line.
    await execute(dut, 4, 1, 0)  # select tap 0
    assert await execute(dut, 4, 0, 0x5A) == 0
    assert await execute(dut, 4, 2) == 0x5A
    await execute(dut, 4, 1, 3)
    for _ in range(3):
        await execute(dut, 4, 0, 0)
    assert await execute(dut, 4, 2) == 0x5A

    # Mode 5: ROM signature and deterministic lookup table.
    assert await execute(dut, 5, 0, 0) == 0x41  # A
    assert await execute(dut, 5, 0, 1) == 0x57  # W
    assert await execute(dut, 5, 0, 2) == 0x45  # E

    # Mode 6: CFAR-style streaming detector.
    await execute(dut, 6, 6)
    await execute(dut, 6, 1, 5)  # threshold offset
    for x in [10, 10, 10, 10, 10, 10, 10]:
        await execute(dut, 6, 0, x)
    assert await execute(dut, 6, 0, 100) in (0, 1)
    assert await execute(dut, 6, 2) == 10

    # Mode 7: self-test signatures.
    assert await execute(dut, 7, 0) == 0xA7
    assert await execute(dut, 7, 1) == 0xE1
    assert await execute(dut, 7, 7) == 0x5A

    # Bidirectional pins remain safely disabled in this digital-only revision.
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0
    dut._log.info("AWEChip v2 verification completed successfully")
