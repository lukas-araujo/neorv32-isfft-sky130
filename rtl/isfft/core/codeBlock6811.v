// Latency: 2
// Gap: 1
module codeBlock6811(clk, reset, next_in, next_out,
   X0_in, Y0,
   X1_in, Y1,
   X2_in, Y2,
   X3_in, Y3);

   output next_out;
   input clk, reset, next_in;

   reg next;

   input [15:0] X0_in,
      X1_in,
      X2_in,
      X3_in;

   reg   [15:0] X0,
      X1,
      X2,
      X3;

   output [15:0] Y0,
      Y1,
      Y2,
      Y3;

   shiftRegFIFO #(1, 1) shiftFIFO_7824(.X(next), .Y(next_out), .clk(clk));


   wire signed [15:0] a129;
   wire signed [15:0] a130;
   wire signed [15:0] a131;
   wire signed [15:0] a132;
   wire signed [16:0] tm52;
   wire signed [16:0] tm53;
   wire signed [16:0] tm54;
   wire signed [16:0] tm55;
   wire signed [15:0] Y0;
   wire signed [15:0] Y1;
   wire signed [15:0] Y2;
   wire signed [15:0] Y3;
   wire signed [15:0] t69;
   wire signed [15:0] t70;
   wire signed [15:0] t71;
   wire signed [15:0] t72;


   assign a129 = X0;
   assign a130 = X2;
   assign a131 = X1;
   assign a132 = X3;
   assign Y0 = t69;
   assign Y1 = t70;
   assign Y2 = t71;
   assign Y3 = t72;
   assign t69 = tm52[16:1];
   assign t70 = tm53[16:1];
   assign t71 = tm54[16:1];
   assign t72 = tm55[16:1];

    addfxp #(17, 1) add6823(.a({{1{a129[15]}}, a129}), .b({{1{a130[15]}}, a130}), .clk(clk), .q(tm52));    // 0
    addfxp #(17, 1) add6838(.a({{1{a131[15]}}, a131}), .b({{1{a132[15]}}, a132}), .clk(clk), .q(tm53));    // 0
    subfxp #(17, 1) sub6853(.a({{1{a129[15]}}, a129}), .b({{1{a130[15]}}, a130}), .clk(clk), .q(tm54));    // 0
    subfxp #(17, 1) sub6868(.a({{1{a131[15]}}, a131}), .b({{1{a132[15]}}, a132}), .clk(clk), .q(tm55));    // 0


   always @(posedge clk) begin
      if (reset == 1) begin
         next <= 0;   // ASIC: frame sync limpo no reset (DIARIO, D34)
      end
      else begin
         X0 <= X0_in;
         X1 <= X1_in;
         X2 <= X2_in;
         X3 <= X3_in;
         next <= next_in;
      end
   end
endmodule
