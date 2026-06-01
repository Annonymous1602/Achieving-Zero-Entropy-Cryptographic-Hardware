`timescale 1ns/1ps

(* use_dsp = "no" *)
module bmm_64 #(
    parameter N = 64,
    parameter a = 7,
    parameter b = 16,
    parameter t = 64
)(
    input clk,
    input reset,

    input  [N-1:0]     A,
    input  [N-1:0]     B,
    input  [N-1:0]     M,
    input  [2*N-1:0]   mu,

    output reg [N-1:0] product
);

    localparam IDLE = 3'd0;
    localparam S1   = 3'd1;
    localparam S2   = 3'd2;
    localparam S3   = 3'd3;
    localparam S4   = 3'd4;

    reg [2:0] state;

    reg [2*N-1:0] mul_A;
    reg [2*N-1:0] mul_B;
    wire [4*N-1:0] mul_P;

    reg [2*N-1:0] P_reg;
    reg [2*N-1:0] Ps_reg;
    reg [2*N-1:0] q_reg;
    reg [2*N-1:0] Z_reg;

    reg [N-1:0] M_reg;
    reg [2*N-1:0] mu_reg;

    mult #(
        .N(2*N),
        .k(4),
        .m(N/2)
    ) u_mult (
        .A({1'b0, mul_A}),
        .B({1'b0, mul_B}),
        .P(mul_P)
    );

    always @(posedge clk) begin
        if (reset) begin
            state   <= IDLE;
            product <= {N{1'b0}};

            mul_A  <= {(2*N){1'b0}};
            mul_B  <= {(2*N){1'b0}};

            P_reg  <= {(2*N){1'b0}};
            Ps_reg <= {(2*N){1'b0}};
            q_reg  <= {(2*N){1'b0}};
            Z_reg  <= {(2*N){1'b0}};

            M_reg  <= {N{1'b0}};
            mu_reg <= {(2*N){1'b0}};
        end
        else begin
            case (state)

                IDLE: begin
                    M_reg  <= M;
                    mu_reg <= mu;

                    mul_A <= {{N{1'b0}}, A};
                    mul_B <= {{N{1'b0}}, B};

                    state <= S1;
                end

                S1: begin
                    P_reg  <= mul_P[2*N-1:0];
                    Ps_reg <= mul_P[4*N-1 : t-b];

                    mul_A <= mul_P[4*N-1 : t-b];
                    mul_B <= mu_reg;

                    state <= S2;
                end

                S2: begin
                    q_reg <= mul_P[4*N-1 : N+a+b];

                    mul_A <= mul_P[4*N-1 : N+a+b];
                    mul_B <= {{N{1'b0}}, M_reg};

                    state <= S3;
                end

                S3: begin
                    Z_reg <= P_reg - mul_P[2*N-1:0];

                    state <= S4;
                end

                S4: begin
                    if (Z_reg >= {{N{1'b0}}, M_reg})
                        product <= Z_reg -  M_reg;
                    else begin
                        product <= Z_reg[N-1:0];
                        state <= IDLE;
                        end
                       
                        
                end

                default: begin
                    state <= IDLE;
                end

            endcase
        end
    end

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



