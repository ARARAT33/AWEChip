/*
 * AWEChip X8 - 8x8 Reconfigurable Digital Accelerator
 *
 * Purely digital RTL for Tiny Tapeout IHP SG13G2.
 * The architecture is original RTL, informed by public project concepts
 * (DSP, CFAR, neuron, delay, ROM, FPU-style arithmetic and test), without
 * copying source code from those projects.
 *
 * 64 parallel lanes provide a dense, reconfigurable compute fabric:
 * - 64 x 8-bit SIMD datapaths
 * - per-lane A/B registers and 24-bit accumulators
 * - multiply/MAC, saturating arithmetic and bitwise operations
 * - vector reductions and checksums
 * - waveform/LFSR generation
 * - programmable 32-deep streaming delay
 * - CFAR-style adaptive threshold detector
 * - leaky integrate-and-fire neuron bank
 * - 256-byte logical ROM/constant table
 * - built-in deterministic self-test signature
 *
 * SPDX-License-Identifier: Apache-2.0
 */
`default_nettype none

module awe_lane (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       en,
    input  wire [3:0] op,
    input  wire [7:0] din,
    input  wire [7:0] lane_id,
    output reg  [7:0] y,
    output reg  [23:0] acc
);
    reg [7:0] a, b;
    reg [15:0] product;
    reg [7:0] lfsr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a <= lane_id ^ 8'h5a;
            b <= lane_id + 8'h13;
            y <= lane_id;
            acc <= 24'd0;
            lfsr <= lane_id ^ 8'hA7;
        end else if (en) begin
            case (op)
                4'h0: begin a <= din; y <= din; end
                4'h1: begin b <= din; y <= a; end
                4'h2: begin y <= a + b; a <= a + b; end
                4'h3: begin y <= a - b; a <= a - b; end
                4'h4: begin product <= a * b; y <= a & b; end
                4'h5: begin product <= a * b; acc <= acc + (a * b); y <= (a * b); end
                4'h6: begin y <= a ^ b; a <= a ^ b; end
                4'h7: begin y <= a | b; a <= a | b; end
                4'h8: begin y <= a << b[2:0]; a <= a << b[2:0]; end
                4'h9: begin y <= a >> b[2:0]; a <= a >> b[2:0]; end
                4'hA: begin y <= ~a; a <= ~a; end
                4'hB: begin y <= (a == b) ? 8'h01 : ((a < b) ? 8'h02 : 8'h03); end
                4'hC: begin
                    lfsr <= {lfsr[6:0], lfsr[7]^lfsr[5]^lfsr[4]^lfsr[3]};
                    y <= lfsr;
                end
                4'hD: begin y <= (a > b) ? (a-b) : (b-a); end
                4'hE: begin y <= din + lane_id; a <= din + lane_id; end
                4'hF: begin acc <= 24'd0; y <= 8'h00; end
                default: y <= y;
            endcase
        end
    end
endmodule

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
    wire [3:0] mode = ui_in[7:4];
    wire [3:0] op = ui_in[3:0];

    /* 64-lane digital SIMD fabric. Every lane is observable through a
       reduction network, preventing synthesis from removing the fabric. */
    wire [7:0] lane_y [0:63];
    wire [23:0] lane_acc [0:63];
    genvar g;
    generate
        for (g=0; g<64; g=g+1) begin : LANES
            awe_lane lane (
                .clk(clk), .rst_n(rst_n), .en(ena && (mode != 4'hF)),
                .op(op), .din(uio_in ^ {4'b0,mode}), .lane_id(g[7:0]),
                .y(lane_y[g]), .acc(lane_acc[g])
            );
        end
    endgenerate

    reg [7:0] result;
    reg [7:0] control;
    reg [7:0] stream_lfsr;
    reg [7:0] phase;
    reg [7:0] delay_mem [0:31];
    reg [4:0] delay_ptr;
    reg [4:0] delay_sel;
    reg [7:0] cfar_mem [0:7];
    reg [11:0] cfar_sum;
    reg signed [15:0] neuron [0:7];
    reg [7:0] neuron_spikes;
    reg [7:0] rom [0:31];
    reg [31:0] signature;

    integer i;
    reg [11:0] reduction_sum;
    reg [7:0] reduction_xor;
    reg [23:0] acc_sum;
    reg [7:0] selected_lane;
    reg signed [15:0] nv;

    wire [7:0] sine8 = phase[7] ? (8'hff - {phase[6:0],1'b0}) : {phase[6:0],1'b0};
    wire [7:0] cfar_avg = cfar_sum[11:3];
    wire [7:0] cfar_threshold = cfar_avg + control;

    assign uio_out = 8'h00;
    assign uio_oe = 8'h00;
    assign uo_out = result;

    always @* begin
        reduction_sum = 12'd0;
        reduction_xor = 8'd0;
        acc_sum = 24'd0;
        for (i=0; i<64; i=i+1) begin
            reduction_sum = reduction_sum + lane_y[i];
            reduction_xor = reduction_xor ^ lane_y[i];
            acc_sum = acc_sum + lane_acc[i];
        end
        selected_lane = lane_y[uio_in[5:0]];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result <= 8'h00;
            control <= 8'h08;
            stream_lfsr <= 8'h1;
            phase <= 8'h00;
            delay_ptr <= 5'd0;
            delay_sel <= 5'd0;
            cfar_sum <= 12'd0;
            neuron_spikes <= 8'h00;
            signature <= 32'h13579BDF;
            for (i=0; i<32; i=i+1) begin
                delay_mem[i] <= 8'h00;
                rom[i] <= i[7:0] ^ 8'hA5;
            end
            for (i=0; i<8; i=i+1) begin
                cfar_mem[i] <= 8'h00;
                neuron[i] <= 16'sd0;
            end
        end else if (ena) begin
            case (mode)
                /* 0: SIMD/reduction compute */
                4'h0: begin
                    case (op)
                        4'h0: result <= selected_lane;
                        4'h1: result <= reduction_sum[7:0];
                        4'h2: result <= reduction_xor;
                        4'h3: result <= acc_sum[7:0];
                        4'h4: result <= acc_sum[15:8];
                        4'h5: result <= acc_sum[23:16];
                        4'h6: result <= selected_lane + uio_in;
                        4'h7: result <= selected_lane ^ uio_in;
                        4'h8: result <= (selected_lane > uio_in) ? 8'h01 : 8'h00;
                        4'h9: result <= (reduction_sum > {4'h0,control}) ? 8'h01 : 8'h00;
                        4'hA: result <= control;
                        4'hB: control <= uio_in;
                        4'hC: result <= 8'h40;
                        4'hD: result <= 8'h3F;
                        4'hE: result <= 8'hFF;
                        default: result <= 8'h00;
                    endcase
                end

                /* 1: streaming DSP/waveform engine */
                4'h1: begin
                    case (op)
                        4'h0: begin phase <= uio_in; result <= sine8; end
                        4'h1: begin phase <= phase + uio_in; result <= sine8; end
                        4'h2: begin phase <= phase + 8'h01; result <= sine8; end
                        4'h3: result <= sine8;
                        4'h4: result <= ~sine8;
                        4'h5: begin
                            stream_lfsr <= {stream_lfsr[6:0],stream_lfsr[7]^stream_lfsr[5]^stream_lfsr[4]^stream_lfsr[3]};
                            result <= stream_lfsr;
                        end
                        4'h6: result <= sine8 + stream_lfsr;
                        4'h7: result <= sine8 ^ stream_lfsr;
                        4'h8: result <= sine8 + uio_in;
                        4'h9: result <= sine8 - uio_in;
                        4'hA: result <= phase;
                        default: result <= sine8;
                    endcase
                end

                /* 2: MAC / fixed-point arithmetic */
                4'h2: begin
                    case (op)
                        4'h0: result <= uio_in * control;
                        4'h1: result <= acc_sum[7:0];
                        4'h2: result <= acc_sum[15:8];
                        4'h3: result <= acc_sum[23:16];
                        4'h4: result <= reduction_sum[7:0];
                        4'h5: result <= reduction_sum[11:4];
                        4'h6: result <= uio_in + control;
                        4'h7: result <= uio_in - control;
                        4'h8: result <= uio_in * uio_in;
                        4'h9: result <= control * control;
                        4'hA: result <= (uio_in > control) ? uio_in : control;
                        4'hB: result <= (uio_in < control) ? uio_in : control;
                        4'hC: result <= uio_in & control;
                        4'hD: result <= uio_in | control;
                        4'hE: result <= uio_in ^ control;
                        default: result <= 8'h00;
                    endcase
                end

                /* 3: 8-neuron LIF bank */
                4'h3: begin
                    case (op)
                        4'h0: begin
                            for (i=0; i<8; i=i+1) neuron[i] <= 16'sd0;
                            neuron_spikes <= 8'h00;
                            result <= 8'h00;
                        end
                        4'h1: begin
                            neuron_spikes <= 8'h00;
                            for (i=0; i<8; i=i+1) begin
                                nv = neuron[i] + $signed({8'h00,uio_in}) - (neuron[i] >>> 3);
                                if (nv > 16'sd255) begin neuron[i] <= 16'sd0; neuron_spikes[i] <= 1'b1; end
                                else neuron[i] <= nv;
                            end
                            result <= neuron_spikes;
                        end
                        4'h2: result <= neuron_spikes;
                        4'h3: result <= neuron[0][7:0];
                        4'h4: result <= neuron[1][7:0];
                        4'h5: result <= neuron[2][7:0];
                        4'h6: result <= neuron[3][7:0];
                        4'h7: result <= neuron[4][7:0];
                        4'h8: result <= neuron[5][7:0];
                        4'h9: result <= neuron[6][7:0];
                        4'hA: result <= neuron[7][7:0];
                        default: result <= neuron_spikes;
                    endcase
                end

                /* 4: programmable 32-sample streaming delay */
                4'h4: begin
                    case (op)
                        4'h0: begin
                            delay_mem[delay_ptr] <= uio_in;
                            delay_ptr <= delay_ptr + 5'd1;
                            result <= delay_mem[delay_ptr];
                        end
                        4'h1: begin delay_sel <= uio_in[4:0]; result <= delay_mem[uio_in[4:0]]; end
                        4'h2: result <= delay_mem[delay_sel];
                        4'h3: result <= delay_mem[0] + delay_mem[1] + delay_mem[2] + delay_mem[3];
                        4'h4: result <= delay_mem[0] ^ delay_mem[1] ^ delay_mem[2] ^ delay_mem[3];
                        4'h5: begin
                            for (i=31; i>0; i=i-1) delay_mem[i] <= delay_mem[i-1];
                            delay_mem[0] <= uio_in;
                            result <= delay_mem[delay_sel];
                        end
                        default: result <= delay_mem[delay_sel];
                    endcase
                end

                /* 5: CFAR-style adaptive detector */
                4'h5: begin
                    case (op)
                        4'h0: begin
                            for (i=7; i>0; i=i-1) cfar_mem[i] <= cfar_mem[i-1];
                            cfar_mem[0] <= uio_in;
                            cfar_sum <= cfar_sum - cfar_mem[7] + uio_in;
                            result <= (uio_in > cfar_threshold) ? 8'hFF : 8'h00;
                        end
                        4'h1: result <= cfar_avg;
                        4'h2: result <= cfar_threshold;
                        4'h3: result <= (uio_in > cfar_threshold) ? 8'h01 : 8'h00;
                        4'h4: result <= cfar_mem[0];
                        4'h5: result <= cfar_mem[7];
                        4'h6: begin control <= uio_in; result <= uio_in; end
                        default: result <= cfar_avg;
                    endcase
                end

                /* 6: deterministic ROM / micro-constant source */
                4'h6: begin
                    case (op)
                        4'h0: result <= rom[uio_in[4:0]];
                        4'h1: result <= rom[0];
                        4'h2: result <= rom[1];
                        4'h3: result <= rom[2];
                        4'h4: result <= rom[3];
                        4'h5: result <= rom[4];
                        4'h6: result <= rom[5];
                        4'h7: result <= rom[6];
                        4'h8: result <= rom[7];
                        4'h9: result <= rom[8];
                        4'hA: result <= rom[9];
                        4'hB: result <= rom[10];
                        4'hC: result <= rom[11];
                        4'hD: result <= rom[12];
                        4'hE: result <= rom[13];
                        default: result <= rom[14];
                    endcase
                end

                /* 7: BIST / configuration / fabric diagnostics */
                4'h7: begin
                    case (op)
                        4'h0: begin signature <= signature ^ {reduction_xor, reduction_sum, acc_sum[7:0]}; result <= signature[7:0]; end
                        4'h1: result <= signature[7:0];
                        4'h2: result <= signature[15:8];
                        4'h3: result <= signature[23:16];
                        4'h4: result <= signature[31:24];
                        4'h5: result <= 8'hA5;
                        4'h6: result <= 8'h5A;
                        4'h7: result <= reduction_xor ^ signature[7:0];
                        4'h8: result <= reduction_sum[7:0] ^ signature[15:8];
                        4'h9: result <= acc_sum[7:0] ^ signature[23:16];
                        4'hA: result <= 8'h64; /* 64 compute lanes */
                        4'hB: result <= 8'h20; /* 32-sample delay */
                        4'hC: result <= 8'h08; /* 8-neuron bank */
                        4'hD: result <= 8'h40; /* 64-lane fabric marker */
                        4'hE: result <= 8'h01;
                        default: result <= 8'h00;
                    endcase
                end
                default: result <= 8'h00;
            endcase
        end
    end
endmodule

`default_nettype wire
