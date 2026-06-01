`timescale 1ns/1ps

module tb_bmm_all;

  reg clk;
  reg reset;

  // 256-bit maximum widths
  reg [255:0] A, B, M;
  reg [511:0] mu;

  // Outputs (ignored for TVLA, but required for instantiation)
  wire [63:0]  prod_64;
  wire [127:0] prod_128;
  wire [255:0] prod_256;

  // Instantiate 64-bit BMM
  bmm_64 #(.N(64), .a(7), .b(16), .t(64)) dut_64 (
    .clk(clk), .reset(reset), 
    .A(A[63:0]), .B(B[63:0]), .M(M[63:0]), .mu(mu[127:0]), 
    .product(prod_64)
  );

  // Instantiate 128-bit BMM
  bmm_128 #(.N(128), .a(7), .b(8), .t(128)) dut_128 (
    .clk(clk), .reset(reset), 
    .A(A[127:0]), .B(B[127:0]), .M(M[127:0]), .mu(mu[255:0]), 
    .product(prod_128)
  );

  // Instantiate 256-bit BMM
  bmm_256 #(.N(256), .a(7), .b(8), .t(256)) dut_256 (
    .clk(clk), .reset(reset), 
    .A(A[255:0]), .B(B[255:0]), .M(M[255:0]), .mu(mu[511:0]), 
    .product(prod_256)
  );

  // Clock Generation
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  integer i;
  initial begin
    $dumpfile("bmm_all_tvla.vcd");
    $dumpvars(0, tb_bmm_all);

    // Reset sequence
    reset = 1'b1;
    A = 0; B = 0; M = 0; mu = 0;
    repeat (5) @(posedge clk);
    reset = 1'b0;
    repeat (5) @(posedge clk);

    // 1000 Fixed Traces
    for (i = 0; i < 1000; i = i + 1) begin
      A  = {(8){32'h11111111}};
      B  = {(8){32'h22222222}};
      M  = {(8){32'hFFFFFFFF}};
      mu = {{(15){32'h00000000}}, 32'h00000001};
      
      repeat (5) @(posedge clk); // 5 cycles per operation
    end

    // 1000 Random Traces
    for (i = 0; i < 1000; i = i + 1) begin
      A  = {$random, $random, $random, $random, $random, $random, $random, $random};
      B  = {$random, $random, $random, $random, $random, $random, $random, $random};
      M  = {$random, $random, $random, $random, $random, $random, $random, $random};
      mu = {$random, $random, $random, $random, $random, $random, $random, $random, 
            $random, $random, $random, $random, $random, $random, $random, $random};
      
      repeat (5) @(posedge clk); // 5 cycles per operation
    end

    $finish;
  end
endmodule
