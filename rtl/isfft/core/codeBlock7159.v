// Latency: 8
// Gap: 1
module codeBlock7159(clk, reset, next_in, next_out,
   i1_in,
   X0_in, Y0,
   X1_in, Y1,
   X2_in, Y2,
   X3_in, Y3);

   output next_out;
   input clk, reset, next_in;

   reg next;
   input [1:0] i1_in;
   reg [1:0] i1;

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

   shiftRegFIFO #(7, 1) shiftFIFO_7855(.X(next), .Y(next_out), .clk(clk));


   wire signed [15:0] a53;
   wire signed [15:0] a42;
   wire signed [15:0] a56;
   wire signed [15:0] a46;
   wire signed [15:0] a57;
   wire signed [15:0] a58;
   reg signed [15:0] tm94;
   reg signed [15:0] tm98;
   reg signed [15:0] tm110;
   reg signed [15:0] tm117;
   reg signed [15:0] tm95;
   reg signed [15:0] tm99;
   reg signed [15:0] tm111;
   reg signed [15:0] tm118;
   wire signed [15:0] tm6;
   wire signed [15:0] a47;
   wire signed [15:0] tm7;
   wire signed [15:0] a49;
   reg signed [15:0] tm96;
   reg signed [15:0] tm100;
   reg signed [15:0] tm112;
   reg signed [15:0] tm119;
   reg signed [15:0] tm20;
   reg signed [15:0] tm21;
   reg signed [15:0] tm97;
   reg signed [15:0] tm101;
   reg signed [15:0] tm113;
   reg signed [15:0] tm120;
   reg signed [15:0] tm114;
   reg signed [15:0] tm121;
   wire signed [15:0] a48;
   wire signed [15:0] a50;
   wire signed [15:0] a51;
   wire signed [15:0] a52;
   reg signed [15:0] tm115;
   reg signed [15:0] tm122;
   wire signed [15:0] Y0;
   wire signed [15:0] Y1;
   wire signed [15:0] Y2;
   wire signed [15:0] Y3;
   reg signed [15:0] tm116;
   reg signed [15:0] tm123;


   assign a53 = X0;
   assign a42 = a53;
   assign a56 = X1;
   assign a46 = a56;
   assign a57 = X2;
   assign a58 = X3;
   assign a47 = tm6;
   assign a49 = tm7;
   assign Y0 = tm116;
   assign Y1 = tm123;

   D4_7325 instD4inst0_7325(.addr(i1[1:0]), .out(tm7), .clk(clk));

   D2_7337 instD2inst0_7337(.addr(i1[1:0]), .out(tm6), .clk(clk));

    multfix #(16, 2) m7258(.a(tm20), .b(tm97), .clk(clk), .q_sc(a48), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7280(.a(tm21), .b(tm101), .clk(clk), .q_sc(a50), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7298(.a(tm21), .b(tm97), .clk(clk), .q_sc(a51), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7309(.a(tm20), .b(tm101), .clk(clk), .q_sc(a52), .q_unsc(), .rst(reset));
    subfxp #(16, 1) sub7287(.a(a48), .b(a50), .clk(clk), .q(Y2));    // 6
    addfxp #(16, 1) add7316(.a(a51), .b(a52), .clk(clk), .q(Y3));    // 6


   always @(posedge clk) begin
      if (reset == 1) begin
         next <= 0;   // ASIC: frame sync limpo no reset (DIARIO, D34)
         tm20 <= 0;
         tm97 <= 0;
         tm21 <= 0;
         tm101 <= 0;
         tm21 <= 0;
         tm97 <= 0;
         tm20 <= 0;
         tm101 <= 0;
      end
      else begin
         i1 <= i1_in;
         X0 <= X0_in;
         X1 <= X1_in;
         X2 <= X2_in;
         X3 <= X3_in;
         next <= next_in;
         tm94 <= a57;
         tm98 <= a58;
         tm110 <= a42;
         tm117 <= a46;
         tm95 <= tm94;
         tm99 <= tm98;
         tm111 <= tm110;
         tm118 <= tm117;
         tm96 <= tm95;
         tm100 <= tm99;
         tm112 <= tm111;
         tm119 <= tm118;
         tm20 <= a47;
         tm21 <= a49;
         tm97 <= tm96;
         tm101 <= tm100;
         tm113 <= tm112;
         tm120 <= tm119;
         tm114 <= tm113;
         tm121 <= tm120;
         tm115 <= tm114;
         tm122 <= tm121;
         tm116 <= tm115;
         tm123 <= tm122;
      end
   end
endmodule
