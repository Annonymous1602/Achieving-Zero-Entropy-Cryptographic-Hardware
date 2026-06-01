`timescale 1ns/1ps

module tb_bmm_all_qif;

  reg clk, reset;
  reg [255:0] A, B, M;
  reg [511:0] mu;

  wire [63:0]  prod_64;
  wire [127:0] prod_128;
  wire [255:0] prod_256;

  bmm_64 #(.N(64),.a(7),.b(16),.t(64)) dut_64 (clk, reset, A[63:0], B[63:0], M[63:0], mu[127:0], prod_64);
  bmm_128 #(.N(128),.a(7),.b(8),.t(128)) dut_128 (clk, reset, A[127:0], B[127:0], M[127:0], mu[255:0], prod_128);
  bmm_256 #(.N(256),.a(7),.b(8),.t(256)) dut_256 (clk, reset, A[255:0], B[255:0], M[255:0], mu[511:0], prod_256);

  initial begin clk = 0; forever #5 clk = ~clk; end

  integer k;
  initial begin
    $dumpfile("bmm_all_qif.vcd");
    $dumpvars(0, tb_bmm_all_qif);

    reset = 1; A = 0; B = 0; M = 0; mu = 0;
    repeat (5) @(posedge clk);
    reset = 0;
    repeat (5) @(posedge clk);

    // Fixed background data
    A  = {(8){32'hAAAA_AAAA}};
    M  = {(8){32'hFFFF_FFFF}};
    mu = {{(15){32'h0000_0000}}, 32'h0000_0001};

    // QIF Sweep: 256 variations on the lowest byte of Operand B
    for (k = 0; k < 256; k = k + 1) begin
      B = {(8){32'h5555_5555}};
      B[7:0] = k[7:0]; // Inject the swept byte
      
      repeat (5) @(posedge clk); // 5 cycles per operation
    end

    $finish;
  end
endmodule
