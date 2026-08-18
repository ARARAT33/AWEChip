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


async def execute(dut, opcode, operand=0):
    dut.ui_in.value = opcode & 0x0F
    dut.uio_in.value = operand & 0xFF
    await ClockCycles(dut.clk, 1)
    return int(dut.uo_out.value)


@cocotb.test()
async def test_awechip(dut):
    dut._log.info("Starting AWEChip v1 verification")
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # LOAD A = 20, LOAD B = 7
    assert await execute(dut, 0x0, 20) == 20
    assert await execute(dut, 0x1, 7) == 20

    # Arithmetic
    assert await execute(dut, 0x2) == 27       # ADD
    assert await execute(dut, 0x3) == 20       # SUB
    assert await execute(dut, 0x7) == 140      # MUL

    # Reload known operands for logic tests.
    assert await execute(dut, 0x0, 0xAA) == 0xAA
    assert await execute(dut, 0x1, 0x0F) == 0xAA
    assert await execute(dut, 0x4) == 0x0A       # AND

    assert await execute(dut, 0x0, 0xAA) == 0xAA
    assert await execute(dut, 0x1, 0x0F) == 0xAA
    assert await execute(dut, 0x5) == 0xAF       # OR

    assert await execute(dut, 0x0, 0xAA) == 0xAA
    assert await execute(dut, 0x1, 0x0F) == 0xAA
    assert await execute(dut, 0x6) == 0xA5       # XOR

    # Shifts use B[2:0] as the shift amount.
    assert await execute(dut, 0x0, 0x03) == 0x03
    assert await execute(dut, 0x1, 0x02) == 0x03
    assert await execute(dut, 0x8) == 0x0C       # SHL

    assert await execute(dut, 0x0, 0x30) == 0x30
    assert await execute(dut, 0x1, 0x02) == 0x30
    assert await execute(dut, 0x9) == 0x0C       # SHR

    # Unary and increment/decrement.
    assert await execute(dut, 0x0, 0x55) == 0x55
    assert await execute(dut, 0xA) == 0xAA       # NOT
    assert await execute(dut, 0xB) == 0x56       # NEG
    assert await execute(dut, 0xC) == 0x57       # INC
    assert await execute(dut, 0xD) == 0x56       # DEC

    # Compare: result 1 == equal, 2 == less, 3 == greater.
    assert await execute(dut, 0x0, 10) == 10
    assert await execute(dut, 0x1, 10) == 10
    assert await execute(dut, 0xE) == 1

    assert await execute(dut, 0x0, 5) == 5
    assert await execute(dut, 0x1, 9) == 5
    assert await execute(dut, 0xE) == 2

    assert await execute(dut, 0x0, 12) == 12
    assert await execute(dut, 0x1, 4) == 12
    assert await execute(dut, 0xE) == 3

    # Ensure the unused bidirectional output path is disabled.
    assert int(dut.uio_oe.value) == 0
    assert int(dut.uio_out.value) == 0

    dut._log.info("AWEChip v1 verification completed successfully")
