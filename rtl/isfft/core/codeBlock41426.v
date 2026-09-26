// Latency: 2
// Gap: 1
module codeBlock41426(clk, reset, next_in, next_out,
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

   shiftRegFIFO #(1, 1) shiftFIFO_41936(.X(next), .Y(next_out), .clk(clk));


   wire signed [15:0] a9;
   wire signed [15:0] a10;
   wire signed [15:0] a11;
   wire signed [15:0] a12;
   wire signed [16:0] tm60;
   wire signed [16:0] tm61;
   wire signed [16:0] tm62;
   wire signed [16:0] tm63;
   wire signed [15:0] Y0;
   wire signed [15:0] Y1;
   wire signed [15:0] Y2;
   wire signed [15:0] Y3;
   wire signed [15:0] t21;
   wire signed [15:0] t22;
   wire signed [15:0] t23;
   wire signed [15:0] t24;


   assign a9 = X0;
   assign a10 = X2;
   assign a11 = X1;
   assign a12 = X3;
   assign Y0 = t21;
   assign Y1 = t22;
   assign Y2 = t23;
   assign Y3 = t24;
   assign t21 = tm60[16:1];
   assign t22 = tm61[16:1];
   assign t23 = tm62[16:1];
   assign t24 = tm63[16:1];

    addfxp #(17, 1) add41438(.a({{1{a9[15]}}, a9}), .b({{1{a10[15]}}, a10}), .clk(clk), .q(tm60));    // 0
    addfxp #(17, 1) add41453(.a({{1{a11[15]}}, a11}), .b({{1{a12[15]}}, a12}), .clk(clk), .q(tm61));    // 0
    subfxp #(17, 1) sub41468(.a({{1{a9[15]}}, a9}), .b({{1{a10[15]}}, a10}), .clk(clk), .q(tm62));    // 0
    subfxp #(17, 1) sub41483(.a({{1{a11[15]}}, a11}), .b({{1{a12[15]}}, a12}), .clk(clk), .q(tm63));    // 0


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
