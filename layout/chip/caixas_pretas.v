//=============================================================================
// caixas_pretas.v -- modulos que o Yosys do LibreLane so precisa ver por fora
//                    (etapa 11, fluxo Chip; DIARIO_GDSII, 36a sessao)
//
// asic_top: o NUCLEO, ja pronto (etapas 1-9). No chip ele e uma MACRO:
//   o desenho vem do LEF/GDS da etapa 8 (MACROS no config.json). Sem esta
//   caixa-preta o Yosys pediria a definicao (ou, se lesse o netlist do
//   nucleo, achataria 100 mil celulas para dentro do chip).
// sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um: a fatia
//   do anel (L50). O PDK nao traz Liberty nem Verilog dela.
//
// Os pads (gpiov2, pads de alimentacao) NAO estao aqui: o Yosys os le como
// caixa-preta a partir do Liberty (PAD_LIBS).
//
// NAO usar na simulacao: la entram o netlist do nucleo e o modelo da fatia
// (layout/chip/10_simula.sh).
//=============================================================================
(* blackbox *)
module asic_top (
`ifdef USE_POWER_PINS
    inout  vccd1,       // pinos do LEF do nucleo (Magic.WriteLEF, met4/met5)
    inout  vssd1,
`endif
    input  clk_i,
    input  rstn_i,
    input  uart0_rxd_i,
    output uart0_txd_o
);
endmodule

(* blackbox *)
module sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um (
    inout AMUXBUS_A, inout AMUXBUS_B, inout VSSA, inout VDDA, inout VSWITCH,
    inout VDDIO_Q, inout VCCHIB, inout VDDIO, inout VCCD, inout VSSIO,
    inout VSSD, inout VSSIO_Q
);
endmodule
