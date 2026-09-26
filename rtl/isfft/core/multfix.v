module multfix(clk, rst, a, b, q_sc, q_unsc);
   parameter WIDTH=35, CYCLES=6;

   input signed [WIDTH-1:0]    a,b;
   output [WIDTH-1:0]          q_sc;
   output [WIDTH-1:0]              q_unsc;

   input                       clk, rst;
   
   reg signed [2*WIDTH-1:0]    q[CYCLES-1:0];
   wire signed [2*WIDTH-1:0]   res;   
   integer                     i;

   assign                      res = q[CYCLES-1];   
   
   assign                      q_unsc = res[WIDTH-1:0];
   assign                      q_sc = {res[2*WIDTH-1], res[2*WIDTH-4:WIDTH-2]};
      
   always @(posedge clk) begin
      q[0] <= a * b;
      for (i = 1; i < CYCLES; i=i+1) begin
         q[i] <= q[i-1];
      end
   end
                  
endmodule 
