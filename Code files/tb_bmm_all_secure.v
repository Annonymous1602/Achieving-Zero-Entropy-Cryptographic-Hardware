`timescale 1ns/1ps

module tb_bmm_all_secure;
  reg clk, reset;
  reg [255:0] A, B, M;
  reg [511:0] mu;
  reg [1:0] variant_select; 

  wire [63:0]  prod_64;
  wire [127:0] prod_128;
  wire [255:0] prod_256;

  // Instantiations
  bmm_64 dut_64   (clk, reset, A[63:0],  B[63:0],  M[63:0],  mu[127:0], prod_64);
  bmm_128 dut_128 (clk, reset, A[127:0], B[127:0], M[127:0], mu[255:0], prod_128);
  bmm_256 dut_256 (clk, reset, A[255:0], B[255:0], M[255:0], mu[511:0], prod_256);

  initial begin clk = 0; forever #5 clk = ~clk; end

  integer i;
  initial begin
    $dumpfile("bmm_all_secure.vcd");
    $dumpvars(0, tb_bmm_all_secure);

    reset = 1; A = 0; B = 0; M = 0; mu = 0; variant_select = 0;
    repeat (5) @(posedge clk);
    reset = 0;
    repeat (5) @(posedge clk);

    for (i = 0; i < 2000; i = i + 1) begin
      variant_select = $random % 4; // Simulate polymorphism

      if (i < 1000) begin
        A = {(8){32'hAAAA_AAAA}}; B = {(8){32'h5555_5555}};
        M = {(8){32'hFFFF_FFFF}}; mu = {{(15){32'h0000_0000}}, 32'h0000_0001};
      end else begin
        A = {$random, $random, $random, $random, $random, $random, $random, $random};
        B = {$random, $random, $random, $random, $random, $random, $random, $random};
        M = {$random, $random, $random, $random, $random, $random, $random, $random};
        mu = {$random, $random, $random, $random, $random, $random, $random, $random, 
              $random, $random, $random, $random, $random, $random, $random, $random};
      end
      repeat (5) @(posedge clk);
    end
    $finish;
  end
endmodule
