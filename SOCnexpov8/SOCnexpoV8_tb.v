`timescale 1us / 1ns
`define BENCH
module SOCnexpoV3_tb();
	`define BENCH
	reg clk=0;
	wire [7:0] leds;
	wire [3:0] lcol;
	wire TXD;
	reg key = 0;
	SOCnexpo uut(  
		.clk12MHz(clk),
		.key({3'b0,key}),
		.led(leds),
 		.lcol(lcol),
  		.TXD(TXD));
	always @(*) begin
		#1 clk<=~clk;
	end

	initial begin

		$dumpvars(0, SOCnexpoV3_tb);
		#1000000 $finish;
	end
endmodule
