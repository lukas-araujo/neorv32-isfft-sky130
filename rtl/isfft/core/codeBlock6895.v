// Latency: 8
// Gap: 1
module codeBlock6895(clk, reset, next_in, next_out,
   i2_in,
   X0_in, Y0,
   X1_in, Y1,
   X2_in, Y2,
   X3_in, Y3);

   output next_out;
   input clk, reset, next_in;

   reg next;
   input [0:0] i2_in;
   reg [0:0] i2;

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

   shiftRegFIFO #(7, 1) shiftFIFO_7838(.X(next), .Y(next_out), .clk(clk));


   wire signed [15:0] a113;
   wire signed [15:0] a102;
   wire signed [15:0] a116;
   wire signed [15:0] a106;
   wire signed [15:0] a117;
   wire signed [15:0] a118;
   reg signed [15:0] tm64;
   reg signed [15:0] tm68;
   reg signed [15:0] tm80;
   reg signed [15:0] tm87;
   reg signed [15:0] tm65;
   reg signed [15:0] tm69;
   reg signed [15:0] tm81;
   reg signed [15:0] tm88;
   wire signed [15:0] tm2;
   wire signed [15:0] a107;
   wire signed [15:0] tm3;
   wire signed [15:0] a109;
   reg signed [15:0] tm66;
   reg signed [15:0] tm70;
   reg signed [15:0] tm82;
   reg signed [15:0] tm89;
   reg signed [15:0] tm12;
   reg signed [15:0] tm13;
   reg signed [15:0] tm67;
   reg signed [15:0] tm71;
   reg signed [15:0] tm83;
   reg signed [15:0] tm90;
   reg signed [15:0] tm84;
   reg signed [15:0] tm91;
   wire signed [15:0] a108;
   wire signed [15:0] a110;
   wire signed [15:0] a111;
   wire signed [15:0] a112;
   reg signed [15:0] tm85;
   reg signed [15:0] tm92;
   wire signed [15:0] Y0;
   wire signed [15:0] Y1;
   wire signed [15:0] Y2;
   wire signed [15:0] Y3;
   reg signed [15:0] tm86;
   reg signed [15:0] tm93;


   assign a113 = X0;
   assign a102 = a113;
   assign a116 = X1;
   assign a106 = a116;
   assign a117 = X2;
   assign a118 = X3;
   assign a107 = tm2;
   assign a109 = tm3;
   assign Y0 = tm86;
   assign Y1 = tm93;

   D8_7059 instD8inst0_7059(.addr(i2[0:0]), .out(tm3), .clk(clk));

   D6_7067 instD6inst0_7067(.addr(i2[0:0]), .out(tm2), .clk(clk));

    multfix #(16, 2) m6994(.a(tm12), .b(tm67), .clk(clk), .q_sc(a108), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7016(.a(tm13), .b(tm71), .clk(clk), .q_sc(a110), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7034(.a(tm13), .b(tm67), .clk(clk), .q_sc(a111), .q_unsc(), .rst(reset));
    multfix #(16, 2) m7045(.a(tm12), .b(tm71), .clk(clk), .q_sc(a112), .q_unsc(), .rst(reset));
    subfxp #(16, 1) sub7023(.a(a108), .b(a110), .clk(clk), .q(Y2));    // 6
    addfxp #(16, 1) add7052(.a(a111), .b(a112), .clk(clk), .q(Y3));    // 6


   always @(posedge clk) begin
      if (reset == 1) begin
         next <= 0;   // ASIC: frame sync limpo no reset (DIARIO, D34)
         tm12 <= 0;
         tm67 <= 0;
         tm13 <= 0;
         tm71 <= 0;
         tm13 <= 0;
         tm67 <= 0;
         tm12 <= 0;
         tm71 <= 0;
      end
      else begin
         i2 <= i2_in;
         X0 <= X0_in;
         X1 <= X1_in;
         X2 <= X2_in;
         X3 <= X3_in;
         next <= next_in;
         tm64 <= a117;
         tm68 <= a118;
         tm80 <= a102;
         tm87 <= a106;
         tm65 <= tm64;
         tm69 <= tm68;
         tm81 <= tm80;
         tm88 <= tm87;
         tm66 <= tm65;
         tm70 <= tm69;
         tm82 <= tm81;
         tm89 <= tm88;
         tm12 <= a107;
         tm13 <= a109;
         tm67 <= tm66;
         tm71 <= tm70;
         tm83 <= tm82;
         tm90 <= tm89;
         tm84 <= tm83;
         tm91 <= tm90;
         tm85 <= tm84;
         tm92 <= tm91;
         tm86 <= tm85;
         tm93 <= tm92;
      end
   end
endmodule
