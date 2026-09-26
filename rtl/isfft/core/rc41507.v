// Latency: 5
// Gap: 4
module rc41507(clk, reset, next, next_out,
   X0, Y0,
   X1, Y1,
   X2, Y2,
   X3, Y3);

   output next_out;
   input clk, reset, next;

   input [15:0] X0,
      X1,
      X2,
      X3;

   output [15:0] Y0,
      Y1,
      Y2,
      Y3;

   wire [31:0] t0;
   wire [31:0] s0;
   assign t0 = {X0, X1};
   wire [31:0] t1;
   wire [31:0] s1;
   assign t1 = {X2, X3};
   assign Y0 = s0[31:16];
   assign Y1 = s0[15:0];
   assign Y2 = s1[31:16];
   assign Y3 = s1[15:0];

   perm41505 instPerm41937(.x0(t0), .y0(s0),
    .x1(t1), .y1(s1),
   .clk(clk), .next(next), .next_out(next_out), .reset(reset)
);
endmodule
