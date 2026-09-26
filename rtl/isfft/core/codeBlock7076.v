// Latency: 2
// Gap: 1
module codeBlock7076(clk, reset, next_in, next_out,
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

   shiftRegFIFO #(1, 1) shiftFIFO_7841(.X(next), .Y(next_out), .clk(clk));


   wire signed [15:0] a69;
   wire signed [15:0] a70;
   wire signed [15:0] a71;
   wire signed [15:0] a72;
   wire signed [16:0] tm56;
   wire signed [16:0] tm57;
   wire signed [16:0] tm58;
   wire signed [16:0] tm59;
   wire signed [15:0] Y0;
   wire signed [15:0] Y1;
   wire signed [15:0] Y2;
   wire signed [15:0] Y3;
   wire signed [15:0] t45;
   wire signed [15:0] t46;
   wire signed [15:0] t47;
   wire signed [15:0] t48;


   assign a69 = X0;
   assign a70 = X2;
   assign a71 = X1;
   assign a72 = X3;
   assign Y0 = t45;
   assign Y1 = t46;
   assign Y2 = t47;
   assign Y3 = t48;
   assign t45 = tm56[16:1];
   assign t46 = tm57[16:1];
   assign t47 = tm58[16:1];
   assign t48 = tm59[16:1];

    addfxp #(17, 1) add7088(.a({{1{a69[15]}}, a69}), .b({{1{a70[15]}}, a70}), .clk(clk), .q(tm56));    // 0
    addfxp #(17, 1) add7103(.a({{1{a71[15]}}, a71}), .b({{1{a72[15]}}, a72}), .clk(clk), .q(tm57));    // 0
    subfxp #(17, 1) sub7118(.a({{1{a69[15]}}, a69}), .b({{1{a70[15]}}, a70}), .clk(clk), .q(tm58));    // 0
    subfxp #(17, 1) sub7133(.a({{1{a71[15]}}, a71}), .b({{1{a72[15]}}, a72}), .clk(clk), .q(tm59));    // 0


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
