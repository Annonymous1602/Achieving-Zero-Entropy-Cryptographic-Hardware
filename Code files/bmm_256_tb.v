`timescale 1ns/1ps

module tb_bmm;

parameter N = 256;
parameter a = 7;
parameter b = 8;
parameter t = 256;

integer i;
integer NUM_TESTS = 10000;

reg clk;
reg reset;

reg [N-1:0] A;
reg [N-1:0] B;
reg [N-1:0] M;
reg [2*N-1:0] mu;

wire [N-1:0] product;

// ✅ FIXED: fully scalable widths
reg [N-1:0] A_ext, B_ext, M_ext;
reg [2*N-1:0] temp_ext;
reg [N:0] expected;

// Counters
integer error_count;
integer pass_count;

// DUT
bmm_256 #(N,a,b,t) dut (
    .clk(clk),
    .reset(reset),
    .A(A),
    .B(B),
    .M(M),
    .mu(mu),
    .product(product)
);

// Clock
always #5 clk = ~clk;

// --------------------------------------------------
// Random generator (FIXED for large N)
// --------------------------------------------------
function [N-1:0] randN;
    input dummy;
    integer k;
    begin
        randN = 0;
        for (k = 0; k < N/32; k = k + 1) begin
            randN = (randN << 32) | $random;
        end
    end
endfunction

// --------------------------------------------------
// Generate modulus M
// --------------------------------------------------
task gen_modulus;
    reg [N-1:0] temp;
    begin
        temp = randN(0);

        temp[N-1] = 1'b1;

        if (temp == (1 << (N-1)))
            temp = temp + 1;

        if (temp == {N{1'b1}})
            temp = temp - 1;

        M = temp;
    end
endtask

// --------------------------------------------------
// Generate operands
// --------------------------------------------------
task gen_operands;
    begin
        A = randN(0) % (M + 1);
        B = randN(0) % (M + 1);
    end
endtask

// --------------------------------------------------
// ✅ CORRECT mu computation for Barrett
// mu = floor(2^(2N) / M)
task compute_mu;
    reg [4*N-1:0] big_pow2;
    begin
        big_pow2 = 0;
        big_pow2[2*N + a] = 1'b1;
        mu = big_pow2 / M;
    end
endtask

// --------------------------------------------------
// Expected result
// --------------------------------------------------
task compute_expected;
    begin
        A_ext = A;
        B_ext = B;
        M_ext = M;

        temp_ext = A_ext * B_ext;
        expected = temp_ext % M_ext;
    end
endtask

// --------------------------------------------------
// Run test
// --------------------------------------------------
task run_test;
    begin
        gen_modulus();
        gen_operands();
        compute_mu();
        compute_expected();

        // Reset
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;

        // FSM latency (adjust if needed)
        repeat (8) @(posedge clk);

        #1;

        if (product !== expected) begin
            error_count = error_count + 1;

            $display("ERROR:");
            $display("A=%h", A);
            $display("B=%h", B);
            $display("M=%h", M);
            $display("mu=%h", mu);
            $display("Expected=%h", expected);
            $display("Got=%h", product);
            $display("------------------------------");
        end else begin
            pass_count = pass_count + 1;
        end

        @(posedge clk);
    end
endtask

// --------------------------------------------------
// MAIN
// --------------------------------------------------
initial begin
    clk = 0;
    reset = 1;

    error_count = 0;
    pass_count = 0;

    #20;

    for (i = 0; i < NUM_TESTS; i = i + 1) begin
        run_test();
    end

    $display("================================");
    $display("TOTAL TESTS = %d", NUM_TESTS);
    $display("PASS = %d", pass_count);
    $display("ERROR = %d", error_count);
    $display("================================");

    $finish;
end

endmodule