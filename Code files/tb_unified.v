`timescale 1ns / 1ps
module tb_unified;
    reg clk, rst; reg [1:0] variant_select;
    reg [63:0] A_64, B_64; wire [63:0] Res_64;
    reg [127:0] A_128, B_128; wire [127:0] Res_128;
    reg [255:0] A_256, B_256; wire [255:0] Res_256;

    unified_bmm_eval UUT (
        .clk(clk), .rst(rst), .variant_select(variant_select),
        .A_64(A_64), .B_64(B_64), .Res_64(Res_64),
        .A_128(A_128), .B_128(B_128), .Res_128(Res_128),
        .A_256(A_256), .B_256(B_256), .Res_256(Res_256)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("unified_skew.vcd");
        $dumpvars(0, tb_unified);
        
        rst = 1; variant_select = 0; A_64 = 0; B_64 = 0; A_128 = 0; B_128 = 0; A_256 = 0; B_256 = 0;
        #20 rst = 0;

        // Sequence through all variants to dump SDF timing into VCD
        variant_select = 2'b00; A_64 = ~0; A_128 = ~0; A_256 = ~0; #50; A_64 = 0; A_128 = 0; A_256 = 0; #50;
        variant_select = 2'b01; A_64 = ~0; A_128 = ~0; A_256 = ~0; #50; A_64 = 0; A_128 = 0; A_256 = 0; #50;
        variant_select = 2'b10; A_64 = ~0; A_128 = ~0; A_256 = ~0; #50; A_64 = 0; A_128 = 0; A_256 = 0; #50;
        variant_select = 2'b11; A_64 = ~0; A_128 = ~0; A_256 = ~0; #50;
        
        $finish;
    end
endmodule
