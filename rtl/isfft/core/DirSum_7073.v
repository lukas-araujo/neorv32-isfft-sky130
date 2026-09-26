// Latency: 8
// Gap: 2
module DirSum_7073(clk, reset, next, next_out,
      X0, Y0,
      X1, Y1,
      X2, Y2,
      X3, Y3);

   output next_out;
   input clk, reset, next;

   reg [0:0] i2;

   input [15:0] X0,
      X1,
      X2,
      X3;

   output [15:0] Y0,
      Y1,
      Y2,
      Y3;

   always @(posedge clk) begin
      if (reset == 1) begin
         i2 <= 0;
      end
      else begin
         if (next == 1)
            i2 <= 0;
         else if (i2 == 1)
            i2 <= 0;
         else
            i2 <= i2 + 1;
      end
   end

   codeBlock6895 codeBlockIsnt7835(.clk(clk), .reset(reset), .next_in(next), .next_out(next_out),
.i2_in(i2),
       .X0_in(X0), .Y0(Y0),
       .X1_in(X1), .Y1(Y1),
       .X2_in(X2), .Y2(Y2),
       .X3_in(X3), .Y3(Y3));

endmodule
