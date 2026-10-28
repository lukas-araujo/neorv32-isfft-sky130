//=============================================================================
// sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um
//   -- modelo de SIMULACAO escrito por nos (DIARIO_GDSII, 35a sessao)
//
// O PDK (open_pdks 8afc8346, sky130/custom/sky130_fd_io) traz LEF, GDS e
// .mag desta fatia do anel de pads, mas NAO traz modelo Verilog.
//
// O que ela faz no desenho: e um pedaco de 20 um do anel, igual a um
// com_bus_slice, mas com o barramento VCCHIB ligado ao VCCD e o VSWITCH
// ligado ao VDDIO. No sky130:
//   VCCHIB  = alimentacao de 1,8 V do buffer de ENTRADA dos pads de GPIO
//             (o pino IN, do lado do nucleo)
//   VSWITCH = alimentacao do chaveamento analogico (AMUXBUS)
// Sem esta fatia, VCCHIB fica sem fonte e o modelo do gpiov2 da IN = X
// (pwr_good_inpbuff_lv exige VCCHIB === 1). O Caravel usa a mesma fatia.
//
// Pinos: os mesmos do LEF (sky130_ef_io__connect_..._20um.lef, CLASS PAD
// AREAIO). So entram as duas ligacoes; o resto atravessa o anel.
//=============================================================================
module sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um (
    AMUXBUS_A, AMUXBUS_B, VSSA, VDDA, VSWITCH, VDDIO_Q, VCCHIB, VDDIO, VCCD,
    VSSIO, VSSD, VSSIO_Q
);
  inout AMUXBUS_A;
  inout AMUXBUS_B;
  inout VSSA;
  inout VDDA;
  inout VSWITCH;
  inout VDDIO_Q;
  inout VCCHIB;
  inout VDDIO;
  inout VCCD;
  inout VSSIO;
  inout VSSD;
  inout VSSIO_Q;

  tran t_vcchib  (VCCHIB,  VCCD);
  tran t_vswitch (VSWITCH, VDDIO);
endmodule
