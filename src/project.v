/*
 * AWEChip v1 - 8-bit programmable ALU / register core
 * Copyright (c) 2026 ARARAT33
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ararat33_awechip (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // Instruction format:
    // ui_in[3:0] = opcode
    // uio_in[7:0] = operand / data
    //
    // 0x0 LOAD A   A <- operand
    // 0x1 LOAD B   B <- operand
    // 0x2 ADD      A <- A + B
    // 0x3 SUB      A <- A - B
    // 0x4 AND      A <- A & B
    // 0x5 OR       A <- A | B
    // 0x6 XOR      A <- A ^ B
    // 0x7 MUL      A <- low 8 bits of A * B
    // 0x8 SHL      A <- A << B[2:0]
    // 0x9 SHR      A <- A >> B[2:0]
    // 0xA NOT      A <- ~A
    // 0xB NEG      A <- -A
    // 0xC INC      A <- A + 1
    // 0xD DEC      A <- A - 1
    // 0xE CMP      A <- (A == B) ? 1 : (A < B) ? 2 : 3
    // 0xF LOAD_IMM A <- operand (alias of LOAD A)
    //
    // The result is continuously visible on uo_out.
    // All operations are synchronous on the rising edge of clk.

    reg [7:0] reg_a;
    reg [7:0] reg_b;
    reg [7:0] result;

    wire [3:0] opcode = ui_in[3:0];
    wire [15:0] product = reg_a * reg_b;

    assign uo_out = result;
    assign uio_out = 8'b0;
    assign uio_oe = 8'b0;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_a  <= 8'b0;
            reg_b  <= 8'b0;
            result <= 8'b0;
        end else if (ena) begin
            case (opcode)
                4'h0: begin
                    reg_a  <= uio_in;
                    result <= uio_in;
                end
                4'h1: begin
                    reg_b  <= uio_in;
                    result <= reg_a;
                end
                4'h2: begin
                    reg_a  <= reg_a + reg_b;
                    result <= reg_a + reg_b;
                end
                4'h3: begin
                    reg_a  <= reg_a - reg_b;
                    result <= reg_a - reg_b;
                end
                4'h4: begin
                    reg_a  <= reg_a & reg_b;
                    result <= reg_a & reg_b;
                end
                4'h5: begin
                    reg_a  <= reg_a | reg_b;
                    result <= reg_a | reg_b;
                end
                4'h6: begin
                    reg_a  <= reg_a ^ reg_b;
                    result <= reg_a ^ reg_b;
                end
                4'h7: begin
                    reg_a  <= product[7:0];
                    result <= product[7:0];
                end
                4'h8: begin
                    reg_a  <= reg_a << reg_b[2:0];
                    result <= reg_a << reg_b[2:0];
                end
                4'h9: begin
                    reg_a  <= reg_a >> reg_b[2:0];
                    result <= reg_a >> reg_b[2:0];
                end
                4'hA: begin
                    reg_a  <= ~reg_a;
                    result <= ~reg_a;
                end
                4'hB: begin
                    reg_a  <= -reg_a;
                    result <= -reg_a;
                end
                4'hC: begin
                    reg_a  <= reg_a + 8'h01;
                    result <= reg_a + 8'h01;
                end
                4'hD: begin
                    reg_a  <= reg_a - 8'h01;
                    result <= reg_a - 8'h01;
                end
                4'hE: begin
                    if (reg_a == reg_b)
                        result <= 8'h01;
                    else if (reg_a < reg_b)
                        result <= 8'h02;
                    else
                        result <= 8'h03;
                    reg_a <= (reg_a == reg_b) ? 8'h01 :
                             (reg_a < reg_b) ? 8'h02 : 8'h03;
                end
                4'hF: begin
                    reg_a  <= uio_in;
                    result <= uio_in;
                end
                default: begin
                    result <= reg_a;
                end
            endcase
        end
    end

endmodule
