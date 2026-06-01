`timescale 1ns/1ps

module tb_bmm;

parameter N = 128;
parameter a = 7;
parameter b = 8;
parameter t = 128;

integer i;
integer NUM_TESTS = 10000;

reg clk;
reg reset;

reg [N-1:0] A;
reg [N-1:0] B;
reg [N-1:0] M;
reg [2*N-1:0] mu;

wire [N-1:0] product;

// Expected calculation (safe for <=64-bit)
reg [127:0] A_ext, B_ext, M_ext;
reg [256:0] temp_ext;
reg [128:0] expected;

// Counters
integer error_count;
integer pass_count;

// DUT
bmm_128 #(N,a,b,t) dut (
    .clk(clk),
    .reset(reset),
    .A(A),
    .B(B),
    .M(M),
    .mu(mu),
    .product(product)
);

// Clock generation
always #5 clk = ~clk;

// --------------------------------------------------
// Random generator (FIXED: function must have input)
// --------------------------------------------------
function [N-1:0] randN;
    input dummy;
    begin
        randN = {$random, $random} & {N{1'b1}};
    end
endfunction

// --------------------------------------------------
// Generate valid modulus M
// --------------------------------------------------
task gen_modulus;
    reg [N-1:0] temp;
    begin
        temp = randN(0);

        // Ensure M in [2^(N-1)+1 , 2^N-2]
        temp[N-1] = 1'b1;

        if (temp == (1 << (N-1)))
            temp = temp + 1;

        if (temp == {N{1'b1}})
            temp = temp - 1;

        M = temp;
    end
endtask

// --------------------------------------------------
// Generate operands A, B such that A,B <= M
// --------------------------------------------------
task gen_operands;
    begin
        A = randN(0) % (M + 1);
        B = randN(0) % (M + 1);
    end
endtask

// --------------------------------------------------
// Compute mu = floor(2^(N+a+b) / M)  (FIXED)
// --------------------------------------------------
task compute_mu;
    reg [127:0] pow2;
    begin
        pow2 = 1;
        pow2 = pow2 << (2*N + a);
        mu = pow2 / M;
    end
endtask

// --------------------------------------------------
// Compute expected = (A * B) % M
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
// Run one test
// --------------------------------------------------
task run_test;
    begin
        gen_modulus();
        gen_operands();
        compute_mu();
        compute_expected();

        // Reset DUT
        reset = 1;
        @(posedge clk);
        @(posedge clk);
        reset = 0;

        // Wait FSM cycles
        @(posedge clk); // IDLE
        @(posedge clk); // S1
        @(posedge clk); // S2
        @(posedge clk); // S3

        #1;

        if (product !== expected) begin
            error_count = error_count + 1;
            $display("ERROR:");
            $display("A=%h B=%h M=%h", A, B, M);
            $display("mu=%h", mu);
            $display("Expected=%h Got=%h", expected, product);
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



//`timescale 1ns/1ps

//module tb_bmm;

//parameter N = 16;

//reg clk, reset;
//reg [N-1:0] A, B, M;
//reg [2*N-1:0] mu,P;
//wire [N-1:0] product;

//reg [N-1:0] expected;
//reg error_flag;

//// DUT
//bmm_128 #(N,7,8,N) uut (
//    .clk(clk),
//    .reset(reset),
//    .A(A),
//    .B(B),
//    .M(M),
//    .mu(mu),
//    .product(product)
//);

//// Clock
//always #5 clk = ~clk;

//initial begin
//    clk = 0;
//    reset = 1;
//    error_flag = 0;

//    #10 reset = 0;

//    // -----------------------------
//    // SINGLE TEST CASE (16-bit)
//    // -----------------------------
//    A = 16'h1234;
//    B = 16'h00F1;

//    // M in range [2^(N-1), 2^N)
//    M = 16'h8003;   // valid 16-bit modulus

//    // Safe for 16-bit (no overflow issue here)
//    mu = 'd16775680;

//    // Expected result
//    P = (A * B);
//    expected = P % M;

//    $display("========================================");
//    $display("A        = %h", A);
//    $display("B        = %h", B);
//    $display("M        = %h", M);
//    $display("mu       = %h", mu);
//    $display("Expected = %h", expected);
//    $display("========================================");

//    // Wait for FSM completion
//    #100;

//    // Check result
//    if (product !== expected) begin
//        error_flag = 1;
//        $display("❌ ERROR: Mismatch!");
//        $display("Got      = %h", product);
//        $display("Expected = %h", expected);
//    end else begin
//        $display("✅ PASS: Result matches");
//    end

//    $display("Error Flag = %b", error_flag);

//    $finish;
//end

//// Debug monitor
//initial begin
//    $monitor("T=%0t | state=%0d | acc=%h | mux=%h | product=%h",
//             $time, uut.state, uut.acc_reg, uut.mux_out, uut.product);
//end

//endmodule
