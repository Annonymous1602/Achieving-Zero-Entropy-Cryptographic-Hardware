`timescale 1ns/1ps

(* use_dsp = "no" *)
module bmm_256 #(parameter N=256, parameter a=7, parameter b=8, parameter t=256)(
    input clk, reset,
    input  [N-1:0] A, B, M,
    input  [2*N-1:0] mu,
    output reg [N-1:0] product
);

    localparam IDLE=0, S1=1, S2=2, S3=3, S4=4;

    reg [2:0] state;
    reg [2*N-1:0] mul_A, mul_B;
    wire [4*N-1:0] mul_P;

    reg [4*N-1:0] P_reg;
    reg signed [4*N:0] R_reg;

    reg [N-1:0] M_reg;
    reg [2*N-1:0] mu_reg;

    wire signed [4*N:0] M_ext;
    wire signed [4*N:0] r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10,r11,r12;

    assign M_ext = $signed({1'b0,{(3*N){1'b0}},M_reg});

    assign r0  = R_reg;
    assign r1  = (r0 < 0)      ? r0 + M_ext : r0;
    assign r2  = (r1 < 0)      ? r1 + M_ext : r1;
    assign r3  = (r2 >= M_ext) ? r2 - M_ext : r2;
    assign r4  = (r3 >= M_ext) ? r3 - M_ext : r3;
    assign r5  = (r4 >= M_ext) ? r4 - M_ext : r4;
    assign r6  = (r5 >= M_ext) ? r5 - M_ext : r5;
    assign r7  = (r6 >= M_ext) ? r6 - M_ext : r6;
    assign r8  = (r7 >= M_ext) ? r7 - M_ext : r7;
    assign r9  = (r8 >= M_ext) ? r8 - M_ext : r8;
    assign r10 = (r9 >= M_ext) ? r9 - M_ext : r9;
    assign r11 = (r10 >= M_ext)? r10 - M_ext: r10;
    assign r12 = (r11 >= M_ext)? r11 - M_ext: r11;

    karatsuba #(2*N,4,N/2) MUL (
        .A(mul_A),
        .B(mul_B),
        .P(mul_P)
    );

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            product <= 0;
            mul_A <= 0;
            mul_B <= 0;
            P_reg <= 0;
            R_reg <= 0;
            M_reg <= 0;
            mu_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    M_reg <= M;
                    mu_reg <= mu;
                    mul_A <= {{N{1'b0}}, A};
                    mul_B <= {{N{1'b0}}, B};
                    state <= S1;
                end

                S1: begin
                    P_reg <= mul_P;
                    mul_A <= mul_P >> (t-b);
                    mul_B <= mu_reg;
                    state <= S2;
                end

                S2: begin
                    mul_A <= mul_P >> (N+a+b);
                    mul_B <= {{N{1'b0}}, M_reg};
                    state <= S3;
                end

                S3: begin
                    R_reg <= $signed({1'b0,P_reg}) - $signed({1'b0,mul_P});
                    state <= S4;
                end

                S4: begin
                    product <= r12[N-1:0];
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule


(* use_dsp = "no" *)
module karatsuba #(parameter N=512, parameter k=4, parameter m=128)(
    input  [N-1:0] A,
    input  [N-1:0] B,
    output [2*N-1:0] P
);

    localparam W  = N/k;
    localparam RW = W+2;
    localparam MW = ((RW+3)/4)*4;
    localparam EW = 2*MW;
    localparam CW = EW+5;

    wire [W-1:0] A0,A1,A2,A3;
    wire [W-1:0] B0,B1,B2,B3;

    assign A0 = A[W-1:0];
    assign A1 = A[2*W-1:W];
    assign A2 = A[3*W-1:2*W];
    assign A3 = A[4*W-1:3*W];

    assign B0 = B[W-1:0];
    assign B1 = B[2*W-1:W];
    assign B2 = B[3*W-1:2*W];
    assign B3 = B[4*W-1:3*W];

    wire signed [RW-1:0] ar0,ar1,ar2,ar3,ar4,ar5,ar6,ar7,ar8;
    wire signed [RW-1:0] br0,br1,br2,br3,br4,br5,br6,br7,br8;

    assign ar0 = $signed({1'b0,A0});
    assign ar1 = $signed({1'b0,A1});
    assign ar2 = $signed({1'b0,A2});
    assign ar3 = $signed({1'b0,A3});
    assign ar4 = $signed({1'b0,A0}) - $signed({1'b0,A2});
    assign ar5 = $signed({1'b0,A0}) - $signed({1'b0,A1});
    assign ar6 = $signed({1'b0,A0}) - $signed({1'b0,A1}) - $signed({1'b0,A2}) + $signed({1'b0,A3});
    assign ar7 = $signed({1'b0,A1}) - $signed({1'b0,A3});
    assign ar8 = $signed({1'b0,A2}) - $signed({1'b0,A3});

    assign br0 = $signed({1'b0,B0});
    assign br1 = $signed({1'b0,B1});
    assign br2 = $signed({1'b0,B2});
    assign br3 = $signed({1'b0,B3});
    assign br4 = $signed({1'b0,B2}) - $signed({1'b0,B0});
    assign br5 = $signed({1'b0,B1}) - $signed({1'b0,B0});
    assign br6 = $signed({1'b0,B0}) - $signed({1'b0,B1}) - $signed({1'b0,B2}) + $signed({1'b0,B3});
    assign br7 = $signed({1'b0,B3}) - $signed({1'b0,B1});
    assign br8 = $signed({1'b0,B3}) - $signed({1'b0,B2});

    wire signed [MW:0] ae0,ae1,ae2,ae3,ae4,ae5,ae6,ae7,ae8;
    wire signed [MW:0] be0,be1,be2,be3,be4,be5,be6,be7,be8;

    assign ae0 = {{(MW+1-RW){ar0[RW-1]}},ar0};
    assign ae1 = {{(MW+1-RW){ar1[RW-1]}},ar1};
    assign ae2 = {{(MW+1-RW){ar2[RW-1]}},ar2};
    assign ae3 = {{(MW+1-RW){ar3[RW-1]}},ar3};
    assign ae4 = {{(MW+1-RW){ar4[RW-1]}},ar4};
    assign ae5 = {{(MW+1-RW){ar5[RW-1]}},ar5};
    assign ae6 = {{(MW+1-RW){ar6[RW-1]}},ar6};
    assign ae7 = {{(MW+1-RW){ar7[RW-1]}},ar7};
    assign ae8 = {{(MW+1-RW){ar8[RW-1]}},ar8};

    assign be0 = {{(MW+1-RW){br0[RW-1]}},br0};
    assign be1 = {{(MW+1-RW){br1[RW-1]}},br1};
    assign be2 = {{(MW+1-RW){br2[RW-1]}},br2};
    assign be3 = {{(MW+1-RW){br3[RW-1]}},br3};
    assign be4 = {{(MW+1-RW){br4[RW-1]}},br4};
    assign be5 = {{(MW+1-RW){br5[RW-1]}},br5};
    assign be6 = {{(MW+1-RW){br6[RW-1]}},br6};
    assign be7 = {{(MW+1-RW){br7[RW-1]}},br7};
    assign be8 = {{(MW+1-RW){br8[RW-1]}},br8};

    wire signed [EW-1:0] e0,e1,e2,e3,e4,e5,e6,e7,e8;

    mult #(MW,4,MW/4) m0 (.A(ae0), .B(be0), .P(e0));
    mult #(MW,4,MW/4) m1 (.A(ae1), .B(be1), .P(e1));
    mult #(MW,4,MW/4) m2 (.A(ae2), .B(be2), .P(e2));
    mult #(MW,4,MW/4) m3 (.A(ae3), .B(be3), .P(e3));
    mult #(MW,4,MW/4) m4 (.A(ae4), .B(be4), .P(e4));
    mult #(MW,4,MW/4) m5 (.A(ae5), .B(be5), .P(e5));
    mult #(MW,4,MW/4) m6 (.A(ae6), .B(be6), .P(e6));
    mult #(MW,4,MW/4) m7 (.A(ae7), .B(be7), .P(e7));
    mult #(MW,4,MW/4) m8 (.A(ae8), .B(be8), .P(e8));

    wire signed [CW-1:0] c0,c1,c2,c3,c4,c5,c6;

    assign c0 = e0;
    assign c1 = e0 + e1 + e5;
    assign c2 = e0 + e1 + e2 + e4;
    assign c3 = e0 + e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8;
    assign c4 = e1 + e2 + e3 + e7;
    assign c5 = e2 + e3 + e8;
    assign c6 = e3;

    wire signed [2*N-1:0] t0,t1,t2,t3,t4,t5,t6;

    assign t0 = {{(2*N-CW){c0[CW-1]}},c0};
    assign t1 = {{(2*N-CW){c1[CW-1]}},c1} << W;
    assign t2 = {{(2*N-CW){c2[CW-1]}},c2} << (2*W);
    assign t3 = {{(2*N-CW){c3[CW-1]}},c3} << (3*W);
    assign t4 = {{(2*N-CW){c4[CW-1]}},c4} << (4*W);
    assign t5 = {{(2*N-CW){c5[CW-1]}},c5} << (5*W);
    assign t6 = {{(2*N-CW){c6[CW-1]}},c6} << (6*W);

    assign P = t0+t1+t2+t3+t4+t5+t6;

endmodule

(* use_dsp = "no" *)
module mult #(
    parameter N = 128,
    parameter k = 4,
    parameter m = 32
)(
    input  [N:0]       A,
    input  [N:0]       B,
    output reg [2*N-1:0] P
);

    localparam W = N/k;

    reg [N-1:0] A_reg;
    reg [N-1:0] B_reg;

    reg sign_a;
    reg sign_b;
    reg sign;

    reg [W-1:0] A0, A1, A2, A3;
    reg [W-1:0] B0, B1, B2, B3;

    wire signed [W+1:0] aa0, aa1, aa2, aa3, aa4, aa5, aa6, aa7, aa8;
    wire signed [W+1:0] bb0, bb1, bb2, bb3, bb4, bb5, bb6, bb7, bb8;

    wire signed [2*W+3:0] e0, e1, e2, e3, e4, e5, e6, e7, e8;

    reg signed [2*W+4:0] c0, c1, c2, c3, c4, c5, c6;

    reg [2*N-1:0] temp0;
    reg [2*N-1:0] temp1;
    reg [2*N-1:0] temp2;
    reg [2*N-1:0] temp3;
    reg [2*N-1:0] temp4;
    reg [2*N-1:0] temp5;
    reg [2*N-1:0] temp6;

    assign aa0 = $signed({1'b0, A0});
    assign aa1 = $signed({1'b0, A1});
    assign aa2 = $signed({1'b0, A2});
    assign aa3 = $signed({1'b0, A3});
    assign aa4 = $signed({1'b0, A0}) - $signed({1'b0, A2});
    assign aa5 = $signed({1'b0, A0}) - $signed({1'b0, A1});
    assign aa6 = $signed({1'b0, A0}) - $signed({1'b0, A1}) - $signed({1'b0, A2}) + $signed({1'b0, A3});
    assign aa7 = $signed({1'b0, A1}) - $signed({1'b0, A3});
    assign aa8 = $signed({1'b0, A2}) - $signed({1'b0, A3});

    assign bb0 = $signed({1'b0, B0});
    assign bb1 = $signed({1'b0, B1});
    assign bb2 = $signed({1'b0, B2});
    assign bb3 = $signed({1'b0, B3});
    assign bb4 = $signed({1'b0, B2}) - $signed({1'b0, B0});
    assign bb5 = $signed({1'b0, B1}) - $signed({1'b0, B0});
    assign bb6 = $signed({1'b0, B0}) - $signed({1'b0, B1}) - $signed({1'b0, B2}) + $signed({1'b0, B3});
    assign bb7 = $signed({1'b0, B3}) - $signed({1'b0, B1});
    assign bb8 = $signed({1'b0, B3}) - $signed({1'b0, B2});

//    assign e0 = aa0 * bb0;
//    assign e1 = aa1 * bb1;
//    assign e2 = aa2 * bb2;
//    assign e3 = aa3 * bb3;
//    assign e4 = aa4 * bb4;
//    assign e5 = aa5 * bb5;
//    assign e6 = aa6 * bb6;
//    assign e7 = aa7 * bb7;
//    assign e8 = aa8 * bb8;
    
    
  booth #(W+2) inst0 (aa0,bb0,e0);
  
  booth #(W+2) inst1 (aa1,bb1,e1);
  
  booth #(W+2) inst2 (aa2,bb2,e2);
  
  booth #(W+2) inst3 (aa3,bb3,e3);
  
  booth #(W+2) inst4 (aa4,bb4,e4);
  
  booth #(W+2) inst5 (aa5,bb5,e5);
  
  booth #(W+2) inst6 (aa6,bb6,e6);
  
  booth #(W+2) inst7 (aa7,bb7,e7);
  
  booth #(W+2) inst8 (aa8,bb8,e8);

    always @(*) begin
        sign_a = 1'b0;
        sign_b = 1'b0;
        sign   = 1'b0;

        A_reg = A[N-1:0];
        B_reg = B[N-1:0];

        if (A[N] == 1'b1) begin
            sign_a = 1'b1;
            A_reg = (~A[N-1:0]) + 1'b1;
        end

        if (B[N] == 1'b1) begin
            sign_b = 1'b1;
            B_reg = (~B[N-1:0]) + 1'b1;
        end

        sign = sign_a ^ sign_b;

        A0 = A_reg[W-1:0];
        A1 = A_reg[2*W-1:W];
        A2 = A_reg[3*W-1:2*W];
        A3 = A_reg[4*W-1:3*W];

        B0 = B_reg[W-1:0];
        B1 = B_reg[2*W-1:W];
        B2 = B_reg[3*W-1:2*W];
        B3 = B_reg[4*W-1:3*W];

        c0 = e0;
        c1 = e0 + e1 + e5;
        c2 = e0 + e1 + e2 + e4;
        c3 = e0 + e1 + e2 + e3 + e4 + e5 + e6 + e7 + e8;
        c4 = e1 + e2 + e3 + e7;
        c5 = e2 + e3 + e8;
        c6 = e3;

        temp0 = {{(2*N-(2*W+5)){c0[2*W+4]}}, c0};
        temp1 = {{(2*N-(2*W+5)){c1[2*W+4]}}, c1} << W;
        temp2 = {{(2*N-(2*W+5)){c2[2*W+4]}}, c2} << (2*W);
        temp3 = {{(2*N-(2*W+5)){c3[2*W+4]}}, c3} << (3*W);
        temp4 = {{(2*N-(2*W+5)){c4[2*W+4]}}, c4} << (4*W);
        temp5 = {{(2*N-(2*W+5)){c5[2*W+4]}}, c5} << (5*W);
        temp6 = {{(2*N-(2*W+5)){c6[2*W+4]}}, c6} << (6*W);

        P = temp0 + temp1 + temp2 + temp3 + temp4 + temp5 + temp6;

        if (sign == 1'b1)
            P = (~P) + 1'b1;
    end

endmodule

module booth #(
    parameter N = 33   // ANY width (even or odd)
)(
    input  signed [N-1:0] A,
    input  signed [N-1:0] B,
    output reg signed [2*N-1:0] P
);

    // If N is odd → extend by 1 bit
    localparam NE = (N % 2 == 0) ? N : (N + 1);

    integer i;

    reg signed [NE-1:0] A_ext, B_ext;
    reg signed [2*NE:0] acc;
    reg [NE:0] booth_bits;

    always @(*) begin
        // SIGN EXTENSION to even width
        A_ext = {{(NE-N){A[N-1]}}, A};
        B_ext = {{(NE-N){B[N-1]}}, B};

        acc = 0;

        // Append extra zero for Booth
        booth_bits = {B_ext, 1'b0};

        for (i = 0; i < NE/2; i = i + 1) begin
            case (booth_bits[2*i +: 3])

                3'b000,
                3'b111: begin
                    // do nothing
                end

                3'b001,
                3'b010: begin
                    acc = acc + (A_ext <<< (2*i));
                end

                3'b011: begin
                    acc = acc + (A_ext <<< (2*i + 1));
                end

                3'b100: begin
                    acc = acc - (A_ext <<< (2*i + 1));
                end

                3'b101,
                3'b110: begin
                    acc = acc - (A_ext <<< (2*i));
                end

            endcase
        end

        // TRIM back to original width
        P = acc[2*N-1:0];
    end

endmodule





