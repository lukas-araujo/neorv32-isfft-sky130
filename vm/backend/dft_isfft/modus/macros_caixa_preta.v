// =============================================================================
// macros_caixa_preta.v -- as 2 macros OpenRAM do IP da ISFFT para o Modus
//
// DIARIO_DFT, T6. So as portas, sem corpo: o Modus (build_model) trata a
// instancia como CAIXA-PRETA. Na pratica:
//   - as saidas (dout0, dout1) viram fonte de X para o ATPG: a logica que
//     depende delas perde controlabilidade;
//   - as entradas (din0, addr*, csb*) nao sao observadas: falhas na logica
//     que so chega na macro ficam sem deteccao.
// E exatamente o custo que a frente quer medir (sessao 1: base, sem
// shadow logic). O modelo comportamental da OpenRAM (reg [..] mem, always
// em negedge) nao serve para o ATPG: nao e um modelo estrutural.
//
// Portas iguais ao .v da OpenRAM (macros/<macro>/<macro>.v), sem
// USE_POWER_PINS (o netlist do Genus nao liga alimentacao).
// =============================================================================

module sram_1rw1r_64x64_wpr2 (clk0, csb0, web0, addr0, din0, dout0,
                              clk1, csb1, addr1, dout1);
  input         clk0;
  input         csb0;
  input         web0;
  input  [5:0]  addr0;
  input  [63:0] din0;
  output [63:0] dout0;
  input         clk1;
  input         csb1;
  input  [5:0]  addr1;
  output [63:0] dout1;
endmodule

module sram_1rw1r_64x256 (clk0, csb0, web0, addr0, din0, dout0,
                          clk1, csb1, addr1, dout1);
  input         clk0;
  input         csb0;
  input         web0;
  input  [7:0]  addr0;
  input  [63:0] din0;
  output [63:0] dout0;
  input         clk1;
  input         csb1;
  input  [7:0]  addr1;
  output [63:0] dout1;
endmodule
