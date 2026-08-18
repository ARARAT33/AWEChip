/*
 * AWEChip v2 - Unified Adaptive Workload Engine
 *
 * Original RTL inspired by public Tiny Tapeout design ideas:
 * arithmetic/FPU, waveform synthesis, ROM, neural dynamics, delay lines,
 * and CFAR-style detection. No source code is copied from those projects.
 *
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

    wire [3:0] mode = ui_in[7:4];
    wire [3:0] op   = ui_in[3:0];

    reg [7:0] a, b, result;
    reg [15:0] acc16;

    reg [7:0] phase, phase_step, sine_value, pdm_acc;
    function [7:0] sine_lut;
        input [5:0] idx;
        begin
            case (idx)
                6'd0:sine_lut=8'd0; 6'd1:sine_lut=8'd13; 6'd2:sine_lut=8'd25; 6'd3:sine_lut=8'd37;
                6'd4:sine_lut=8'd49; 6'd5:sine_lut=8'd60; 6'd6:sine_lut=8'd71; 6'd7:sine_lut=8'd81;
                6'd8:sine_lut=8'd90; 6'd9:sine_lut=8'd98; 6'd10:sine_lut=8'd106; 6'd11:sine_lut=8'd113;
                6'd12:sine_lut=8'd118; 6'd13:sine_lut=8'd123; 6'd14:sine_lut=8'd126; 6'd15:sine_lut=8'd127;
                6'd16:sine_lut=8'd127; 6'd17:sine_lut=8'd127; 6'd18:sine_lut=8'd126; 6'd19:sine_lut=8'd123;
                6'd20:sine_lut=8'd118; 6'd21:sine_lut=8'd113; 6'd22:sine_lut=8'd106; 6'd23:sine_lut=8'd98;
                6'd24:sine_lut=8'd90; 6'd25:sine_lut=8'd81; 6'd26:sine_lut=8'd71; 6'd27:sine_lut=8'd60;
                6'd28:sine_lut=8'd49; 6'd29:sine_lut=8'd37; 6'd30:sine_lut=8'd25; 6'd31:sine_lut=8'd13;
                6'd32:sine_lut=8'd0; 6'd33:sine_lut=8'hF3; 6'd34:sine_lut=8'hE7; 6'd35:sine_lut=8'hDB;
                6'd36:sine_lut=8'hCF; 6'd37:sine_lut=8'hC4; 6'd38:sine_lut=8'hB9; 6'd39:sine_lut=8'hAF;
                6'd40:sine_lut=8'hA6; 6'd41:sine_lut=8'h9E; 6'd42:sine_lut=8'h96; 6'd43:sine_lut=8'h8F;
                6'd44:sine_lut=8'h8A; 6'd45:sine_lut=8'h85; 6'd46:sine_lut=8'h82; 6'd47:sine_lut=8'h81;
                6'd48:sine_lut=8'h81; 6'd49:sine_lut=8'h82; 6'd50:sine_lut=8'h85; 6'd51:sine_lut=8'h8A;
                6'd52:sine_lut=8'h8F; 6'd53:sine_lut=8'h96; 6'd54:sine_lut=8'h9E; 6'd55:sine_lut=8'hA6;
                6'd56:sine_lut=8'hAF; 6'd57:sine_lut=8'hB9; 6'd58:sine_lut=8'hC4; 6'd59:sine_lut=8'hCF;
                6'd60:sine_lut=8'hDB; 6'd61:sine_lut=8'hE7; 6'd62:sine_lut=8'hF3; 6'd63:sine_lut=8'd0;
                default:sine_lut=8'd0;
            endcase
        end
    endfunction
    wire [5:0] lut_index=phase[7:2];
    wire [7:0] sine_now=sine_lut(lut_index);
    wire [7:0] cosine_now=sine_lut((lut_index+6'd16)&6'h3f);

    reg [7:0] delay0,delay1,delay2,delay3,delay4,delay5,delay6,delay7;
    reg [7:0] delay8,delay9,delay10,delay11,delay12,delay13,delay14,delay15;
    reg [7:0] delay16,delay17,delay18,delay19,delay20,delay21,delay22,delay23;
    reg [7:0] delay24,delay25,delay26,delay27,delay28,delay29,delay30,delay31;
    reg [4:0] delay_sel;
    wire [7:0] delay_selected=
        (delay_sel==0)?delay0:(delay_sel==1)?delay1:(delay_sel==2)?delay2:(delay_sel==3)?delay3:
        (delay_sel==4)?delay4:(delay_sel==5)?delay5:(delay_sel==6)?delay6:(delay_sel==7)?delay7:
        (delay_sel==8)?delay8:(delay_sel==9)?delay9:(delay_sel==10)?delay10:(delay_sel==11)?delay11:
        (delay_sel==12)?delay12:(delay_sel==13)?delay13:(delay_sel==14)?delay14:(delay_sel==15)?delay15:
        (delay_sel==16)?delay16:(delay_sel==17)?delay17:(delay_sel==18)?delay18:(delay_sel==19)?delay19:
        (delay_sel==20)?delay20:(delay_sel==21)?delay21:(delay_sel==22)?delay22:(delay_sel==23)?delay23:
        (delay_sel==24)?delay24:(delay_sel==25)?delay25:(delay_sel==26)?delay26:(delay_sel==27)?delay27:
        (delay_sel==28)?delay28:(delay_sel==29)?delay29:(delay_sel==30)?delay30:delay31;

    reg signed [11:0] neuron_v;
    reg neuron_spike;
    wire signed [11:0] neuron_input={{4{uio_in[7]}},uio_in};

    reg [7:0] c0,c1,c2,c3,c4,c5,c6,c7;
    reg [11:0] csum;
    wire [7:0] cavg=csum[11:3];
    wire [7:0] cthreshold=cavg+b;
    wire cdet=(c7>cthreshold);

    function [7:0] awe_rom;
        input [4:0] addr;
        begin
            case(addr)
                5'd0:awe_rom=8'h41; 5'd1:awe_rom=8'h57; 5'd2:awe_rom=8'h45; 5'd3:awe_rom=8'h43;
                5'd4:awe_rom=8'h48; 5'd5:awe_rom=8'h49; 5'd6:awe_rom=8'h50; 5'd7:awe_rom=8'h01;
                5'd8:awe_rom=8'h02; 5'd9:awe_rom=8'h04; 5'd10:awe_rom=8'h08; 5'd11:awe_rom=8'h10;
                5'd12:awe_rom=8'h20; 5'd13:awe_rom=8'h40; 5'd14:awe_rom=8'h80; 5'd15:awe_rom=8'hFF;
                5'd16:awe_rom=8'h3C; 5'd17:awe_rom=8'h5A; 5'd18:awe_rom=8'h81; 5'd19:awe_rom=8'hA5;
                5'd20:awe_rom=8'hC3; 5'd21:awe_rom=8'h18; 5'd22:awe_rom=8'h24; 5'd23:awe_rom=8'h42;
                5'd24:awe_rom=8'h7E; 5'd25:awe_rom=8'hDB; 5'd26:awe_rom=8'hBD; 5'd27:awe_rom=8'h66;
                5'd28:awe_rom=8'h99; 5'd29:awe_rom=8'hE7; 5'd30:awe_rom=8'h00; 5'd31:awe_rom=8'hAE;
                default:awe_rom=8'h00;
            endcase
        end
    endfunction

    wire [15:0] mul16=a*b;
    assign uio_out=8'b0;
    assign uio_oe=8'b0;
    assign uo_out=result;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            a<=0;b<=0;result<=0;acc16<=0;phase<=0;phase_step<=1;sine_value<=0;pdm_acc<=0;delay_sel<=0;
            delay0<=0;delay1<=0;delay2<=0;delay3<=0;delay4<=0;delay5<=0;delay6<=0;delay7<=0;
            delay8<=0;delay9<=0;delay10<=0;delay11<=0;delay12<=0;delay13<=0;delay14<=0;delay15<=0;
            delay16<=0;delay17<=0;delay18<=0;delay19<=0;delay20<=0;delay21<=0;delay22<=0;delay23<=0;
            delay24<=0;delay25<=0;delay26<=0;delay27<=0;delay28<=0;delay29<=0;delay30<=0;delay31<=0;
            neuron_v<=0;neuron_spike<=0;c0<=0;c1<=0;c2<=0;c3<=0;c4<=0;c5<=0;c6<=0;c7<=0;csum<=0;
        end else if(ena) begin
            case(mode)
                4'h0: begin
                    case(op)
                        4'h0:begin a<=uio_in;result<=uio_in;end 4'h1:begin b<=uio_in;result<=a;end
                        4'h2:begin a<=a+b;result<=a+b;end 4'h3:begin a<=a-b;result<=a-b;end
                        4'h4:begin a<=a&b;result<=a&b;end 4'h5:begin a<=a|b;result<=a|b;end
                        4'h6:begin a<=a^b;result<=a^b;end 4'h7:begin a<=a*b;result<=a*b;end
                        4'h8:begin a<=a<<b[2:0];result<=a<<b[2:0];end 4'h9:begin a<=a>>b[2:0];result<=a>>b[2:0];end
                        4'hA:begin a<=~a;result<=~a;end 4'hB:begin a<=-a;result<=-a;end
                        4'hC:begin a<=a+1'b1;result<=a+1'b1;end 4'hD:begin a<=a-1'b1;result<=a-1'b1;end
                        4'hE:begin result<=(a==b)?8'h01:(a<b)?8'h02:8'h03;a<=(a==b)?8'h01:(a<b)?8'h02:8'h03;end
                        default:begin a<=uio_in;result<=uio_in;end
                    endcase
                end
                4'h1: begin
                    case(op)
                        4'h0:begin phase<=uio_in;result<=sine_now;end 4'h1:begin phase_step<=uio_in;result<=phase_step;end
                        4'h2:begin phase<=phase+phase_step;result<=sine_now;end 4'h3:begin sine_value<=sine_now;result<=sine_now;end
                        4'h4:result<=cosine_now; 4'h5:begin pdm_acc<=pdm_acc+sine_now;result<={7'b0,pdm_acc[7]};end
                        4'h6:begin phase<=phase+uio_in;result<=sine_now;end default:result<=sine_now;
                    endcase
                end
                4'h2: begin
                    case(op)
                        4'h0:begin a<=uio_in;result<=uio_in;end 4'h1:begin b<=uio_in;result<=b;end
                        4'h2:begin acc16<=acc16+mul16;result<=mul16[15:8];end 4'h3:begin acc16<=mul16;result<=mul16[15:8];end
                        4'h4:result<=acc16[7:0]; 4'h5:result<=acc16[15:8]; 4'h6:result<=mul16[7:0]; 4'h7:result<=mul16[15:8];
                        4'h8:begin acc16<=acc16+{{8{uio_in[7]}},uio_in};result<=acc16[7:0];end 4'h9:begin acc16<=0;result<=0;end
                        default:result<=acc16[7:0];
                    endcase
                end
                4'h3: begin
                    case(op)
                        4'h0:begin b<=uio_in;neuron_v<=0;neuron_spike<=0;result<=0;end
                        4'h1:begin neuron_v<=neuron_v+neuron_input-(neuron_v>>>b[7:4]);neuron_spike<=0;result<=neuron_v[7:0];end
                        4'h2:begin if(neuron_v>=$signed({4'b0,b[3:0],4'b0}))begin neuron_v<=0;neuron_spike<=1;end else neuron_spike<=0;result<={7'b0,neuron_spike};end
                        4'h3:result<=neuron_v[7:0]; 4'h4:result<={7'b0,neuron_spike};
                        4'h5:begin neuron_v<=neuron_v+neuron_input;result<=neuron_v[7:0];end default:result<=neuron_v[7:0];
                    endcase
                end
                4'h4: begin
                    case(op)
                        4'h0:begin
                            delay31<=delay30;delay30<=delay29;delay29<=delay28;delay28<=delay27;delay27<=delay26;delay26<=delay25;delay25<=delay24;delay24<=delay23;
                            delay23<=delay22;delay22<=delay21;delay21<=delay20;delay20<=delay19;delay19<=delay18;delay18<=delay17;delay17<=delay16;delay16<=delay15;
                            delay15<=delay14;delay14<=delay13;delay13<=delay12;delay12<=delay11;delay11<=delay10;delay10<=delay9;delay9<=delay8;delay8<=delay7;
                            delay7<=delay6;delay6<=delay5;delay5<=delay4;delay4<=delay3;delay3<=delay2;delay2<=delay1;delay1<=delay0;delay0<=uio_in;result<=delay_selected;
                        end
                        4'h1:begin delay_sel<=uio_in[4:0];result<=uio_in;end 4'h2:result<=delay_selected;
                        4'h3:result<=delay0+delay1+delay2+delay3; 4'h4:result<=delay0^delay1^delay2^delay3;
                        4'h5:begin delay0<=uio_in;result<=uio_in;end default:result<=delay_selected;
                    endcase
                end
                4'h5: begin
                    case(op) 4'h0:result<=awe_rom(uio_in[4:0]); 4'h1:begin a<=uio_in;result<=awe_rom(uio_in[4:0]);end 4'h2:result<=awe_rom(a[4:0]); default:result<=awe_rom(uio_in[4:0]); endcase
                end
                4'h6: begin
                    case(op)
                        4'h0:begin c0<=c1;c1<=c2;c2<=c3;c3<=c4;c4<=c5;c5<=c6;c6<=c7;c7<=uio_in;csum<=c0+c1+c2+c3+c4+c5+c6;result<={7'b0,cdet};end
                        4'h1:begin b<=uio_in;result<=uio_in;end 4'h2:result<=cavg; 4'h3:result<=cthreshold; 4'h4:result<={7'b0,cdet}; 4'h5:result<=c7;
                        4'h6:begin c0<=0;c1<=0;c2<=0;c3<=0;c4<=0;c5<=0;c6<=0;c7<=0;csum<=0;result<=0;end default:result<=cavg;
                    endcase
                end
                4'h7: begin
                    case(op) 4'h0:result<=8'hA7;4'h1:result<=8'hE1;4'h2:result<=8'hC5;4'h3:result<=8'h26;4'h4:result<={mode,op};4'h5:result<=a^b^acc16[7:0];4'h6:result<=phase^delay0^c7;4'h7:result<=8'h5A;default:result<=8'hA5; endcase
                end
                default:result<=result;
            endcase
        end
    end
endmodule
