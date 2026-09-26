module D8_7059(addr, out, clk);
   input clk;
   output [15:0] out;
   reg [15:0] out, out2, out3;
   input [0:0] addr;

   always @(posedge clk) begin
      out2 <= out3;
      out <= out2;
   case(addr)
      0: out3 <= 16'h0;
      1: out3 <= 16'hc000;
      default: out3 <= 0;
   endcase
   end
// synthesis attribute rom_style of out3 is "block"
endmodule
