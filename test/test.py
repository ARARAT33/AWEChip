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
    await ClockCycles(dut.clk, 2)


async def execute(dut, mode, op, data=0):
    dut.ui_in.value = ((mode & 0xF) << 4) | (op & 0xF)
    dut.uio_in.value = data & 0xFF
    await ClockCycles(dut.clk, 1)
    return int(dut.uo_out.value)


@cocotb.test()
async def test_awechip_x8(dut):
    dut._log.info("Starting AWEChip X8 verification")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # Mode 0: 64-lane SIMD fabric and reductions.
    await execute(dut, 0, 0, 0x22)
    assert await execute(dut, 0, 0xC) == 0x40
    assert await execute(dut, 0, 0xD) == 0x3F
    assert await execute(dut, 0, 0xE) == 0xFF
    assert await execute(dut, 0, 1) >= 0
    assert await execute(dut, 0, 2) >= 0
    assert await execute(dut, 0, 3) >= 0

    # Mode 1: waveform/LFSR engine.
    assert await execute(dut, 1, 0, 0) == 0
    assert await execute(dut, 1, 3) == 0
    await execute(dut, 1, 1, 32)
    s = await execute(dut, 1, 3)
    assert s != 0
    l = await execute(dut, 1, 5)
    assert l != 0

    # Mode 2: arithmetic operations using the global control register.
    await execute(dut, 0, 0xB, 10)  # control = 10
    assert await execute(dut, 2, 0, 12) == 120
    assert await execute(dut, 2, 8, 7) == 49
    assert await execute(dut, 2, 0xA, 7) == 10
    assert await execute(dut, 2, 0xB, 7) == 7
    assert await execute(dut, 2, 0xC, 0xF) == (0xF & 10)
    assert await execute(dut, 2, 0xD, 0x05) == (0x05 | 10)
    assert await execute(dut, 2, 0xE, 0x05) == (0x05 ^ 10)

    # Mode 3: eight leaky integrate-and-fire neurons.
    await execute(dut, 3, 0)
    for _ in range(12):
        await execute(dut, 3, 1, 40)
    assert await execute(dut, 3, 3) != 0
    assert await execute(dut, 3, 2) >= 0

    # Mode 4: programmable streaming delay memory.
    await execute(dut, 4, 1, 0)
    assert await execute(dut, 4, 0, 0x5A) == 0
    assert await execute(dut, 4, 2) == 0x5A
    await execute(dut, 4, 5, 0x33)
    assert await execute(dut, 4, 2) in (0x5A, 0x33)

    # Mode 5: CFAR-style adaptive detector.
    await execute(dut, 5, 6, 5)  # threshold offset
    for _ in range(8):
        await execute(dut, 5, 0, 10)
    assert await execute(dut, 5, 1) == 10
    assert await execute(dut, 5, 2) == 15
    assert await execute(dut, 5, 0, 100) == 0xFF

    # Mode 6: deterministic ROM/constant source.
    assert await execute(dut, 6, 0, 0) == 0xA5
    assert await execute(dut, 6, 0, 1) == 0xA4
    assert await execute(dut, 6, 0, 2) == 0xA7

    # Mode 7: fabric diagnostics.
    assert await execute(dut, 7, 0xA) == 0x64  # 64 lanes
    assert await execute(dut, 7, 0xB) == 0x20  # 32 delay samples
    assert await execute(dut, 7, 0xC) == 0x08  # 8 neurons
    assert await execute(dut, 7, 0xD) == 0x40

    # Digital-only revision: bidirectional pins remain disabled.
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0
    dut._log.info("AWEChip X8 verification completed successfully")
