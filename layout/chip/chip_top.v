//=============================================================================
// chip_top.v -- o CHIP: anel de pads sky130_ef_io + o nucleo asic_top
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130) -- DIARIO_GDSII, etapa 10
// (35a sessao). Verilog ESTRUTURAL escrito a mao: so instancias e fios, o
// Genus nao entra aqui (L15). No nivel 2 do layout (etapa 11, fluxo Chip
// do LibreLane) o nucleo entra como macro (LEF + GDS da etapa 8).
//
//                 +-------------------------------------------+
//   clk_pad  ---->| pad_clk  (gpiov2, entrada) --IN--> clk_i  |
//   rstn_pad ---->| pad_rstn (gpiov2, entrada) --IN--> rstn_i |  asic_top
//   rx_pad   ---->| pad_rx   (gpiov2, entrada) --IN--> rxd_i  |  (nucleo)
//   tx_pad   <----| pad_tx   (gpiov2, saida)  <-OUT--- txd_o  |
//                 |  + 6 pads de alimentacao, 1 fatia VCCHIB  |
//                 +-------------------------------------------+
//
//-----------------------------------------------------------------------------
// OS DOIS DOMINIOS DE TENSAO DO PAD DE GPIO (sky130_fd_io__top_gpiov2)
//-----------------------------------------------------------------------------
//   1,8 V (lado do nucleo): OUT, OE_N, DM[2:0], INP_DIS, IB_MODE_SEL,
//        VTRIP_SEL, SLOW, HLD_OVR, ANALOG_EN/SEL/POL, ENABLE_VDDIO, e a
//        saida IN. Constantes vem de celulas de amarracao do nucleo
//        (sky130_fd_sc_hd__conb_1), uma por pad, perto dele.
//   3,3 V (lado do pad, sufixo _H): ENABLE_H, HLD_H_N, ENABLE_INP_H,
//        ENABLE_VDDA_H, ENABLE_VSWITCH_H. NAO podem vir de 1,8 V: vem das
//        saidas TIE_HI_ESD / TIE_LO_ESD do proprio pad (como no Caravel).
//
// Configuracao (tabela no DIARIO_GDSII, 35a sessao; semantica conferida no
// modelo sky130_fd_io__top_gpiov2.functional.pp.v):
//
//   pino          | entrada (clk, rstn, rx) | saida (tx)
//   --------------+-------------------------+---------------------------
//   DM[2:0]       | 001 so entrada          | 110 push-pull forte
//   OE_N          | 1 (driver desligado)    | 0 (driver ligado)
//   OUT           | 0                       | uart0_txd_o do nucleo
//   INP_DIS       | 0 (buffer de entrada on)| 1 (nao precisa ler o pino)
//   IB_MODE_SEL   | 0 (limiar ref. VDDIO)   | 0
//   VTRIP_SEL     | 0 (limiar CMOS)         | 0
//   SLOW          | 0 (borda rapida)        | 0
//   HLD_OVR       | 0                       | 0
//   ANALOG_EN/SEL/POL | 0                   | 0
//   ENABLE_VDDIO  | 1                       | 1
//   ENABLE_H      | 1 (TIE_HI_ESD)          | 1 (TIE_HI_ESD)
//   HLD_H_N       | 1 (TIE_HI_ESD): sem "hold" | 1
//   ENABLE_INP_H, ENABLE_VDDA_H, ENABLE_VSWITCH_H | 0 (TIE_LO_ESD)
//
// ENABLE_H = 1 fixo (L49): o Caravel liga ENABLE_H a um power-on-reset de
// 3,3 V; aqui o pad liga assim que o VDDIO sobe. Para estudo, basta.
//
//-----------------------------------------------------------------------------
// ALIMENTACAO E O ANEL
//-----------------------------------------------------------------------------
// O anel tem 12 barramentos que correm por todos os pads (AMUXBUS_A/B,
// VSSA, VDDA, VSWITCH, VDDIO_Q, VCCHIB, VDDIO, VCCD, VSSIO, VSSD, VSSIO_Q).
// No layout eles se ligam por ENCOSTO (connect_by_abutment do PadRing);
// aqui, so com USE_POWER_PINS (simulacao, LVS), pela macro ANEL abaixo.
// Pads de alimentacao (um de cada, L48):
//   vccd/vssd  1,8 V do nucleo        vddio/vssio 3,3 V dos pads
//   vdda/vssa  dominio analogico do anel (VSSA = 0 e exigido pelo driver
//              de saida do gpiov2 no modelo)
// + a fatia connect_vcchib_vccd_and_vswitch_vddio (L50): VCCHIB <- VCCD
//   (buffer de entrada de 1,8 V dos pads) e VSWITCH <- VDDIO.
//   No LEF dela a faixa de met4 que nas outras fatias e VDDIO se chama
//   VSWITCH, e o met5 do VCCHIB cobre o do VCCD: como os barramentos
//   correm por todo o anel, VSWITCH e VDDIO sao UMA rede so, VCCHIB e VCCD
//   tambem. O netlist tem de dizer isso, senao o PadRing (connect_by_
//   abutment) acha duas redes se tocando: PAD-0002 (DIARIO_GDSII L63).
//=============================================================================

// ANEL_ = as 12 ligacoes do anel seguidas de virgula (antes de outras
// portas); ANEL = sem a virgula (instancia que so tem o anel).
`ifdef USE_POWER_PINS
`define ANEL .AMUXBUS_A(amuxbus_a), .AMUXBUS_B(amuxbus_b), .VSSA(vssa), .VDDA(vdda), .VSWITCH(vddio), .VDDIO_Q(vddio_q), .VCCHIB(vccd), .VDDIO(vddio), .VCCD(vccd), .VSSIO(vssio), .VSSD(vssd), .VSSIO_Q(vssio_q)
`define ANEL_ `ANEL,
`else
`define ANEL
`define ANEL_
`endif

module chip_top (
    // sinais (o PAD de cada gpiov2)
    inout clk_pad,
    inout rstn_pad,
    inout rx_pad,
    inout tx_pad,
    // alimentacao (o P_PAD de cada pad de alimentacao)
    inout vccd_pad,
    inout vssd_pad,
    inout vddio_pad,
    inout vssio_pad,
    inout vdda_pad,
    inout vssa_pad
);

`ifdef USE_POWER_PINS
    // 10 redes, nao 12: VSWITCH = VDDIO e VCCHIB = VCCD no anel inteiro
    // (a fatia fatia_vcchib as junta no metal; ver o cabecalho, L63)
    wire amuxbus_a, amuxbus_b, vssa, vdda, vddio_q,
         vddio, vccd, vssio, vssd, vssio_q;
`endif

    // nucleo <-> pads (1,8 V)
    wire clk_core, rstn_core, rx_core, tx_core;

    //=========================================================================
    // Nucleo (etapas 1-9): asic_top
    //=========================================================================
    // Alimentacao do nucleo = os barramentos VCCD/VSSD do anel (36a sessao).
    // So no layout (Yosys.JsonHeader do LibreLane, LVS): o netlist do nucleo
    // usado na simulacao nao tem pinos de alimentacao, e o 10_simula.sh
    // define NUCLEO_SEM_ALIMENTACAO (pinos_alimentacao_pads.v).
    asic_top u_core (
`ifdef USE_POWER_PINS
`ifndef NUCLEO_SEM_ALIMENTACAO
        .vccd1       (vccd),
        .vssd1       (vssd),
`endif
`endif
        .clk_i       (clk_core),
        .rstn_i      (rstn_core),
        .uart0_rxd_i (rx_core),
        .uart0_txd_o (tx_core)
    );

    //=========================================================================
    // Pads de ENTRADA: clk, rstn, rx
    //=========================================================================
    wire clk_hi,  clk_lo,  clk_hi_h,  clk_lo_h;
    wire rstn_hi, rstn_lo, rstn_hi_h, rstn_lo_h;
    wire rx_hi,   rx_lo,   rx_hi_h,   rx_lo_h;

    sky130_fd_sc_hd__conb_1 tie_clk  (.HI(clk_hi),  .LO(clk_lo));
    sky130_fd_sc_hd__conb_1 tie_rstn (.HI(rstn_hi), .LO(rstn_lo));
    sky130_fd_sc_hd__conb_1 tie_rx   (.HI(rx_hi),   .LO(rx_lo));

    sky130_ef_io__gpiov2_pad_wrapped pad_clk (
        `ANEL_
        .PAD(clk_pad), .IN(clk_core), .OUT(clk_lo),
        .DM({clk_lo, clk_lo, clk_hi}), .OE_N(clk_hi), .INP_DIS(clk_lo),
        .IB_MODE_SEL(clk_lo), .VTRIP_SEL(clk_lo), .SLOW(clk_lo), .HLD_OVR(clk_lo),
        .ANALOG_EN(clk_lo), .ANALOG_SEL(clk_lo), .ANALOG_POL(clk_lo),
        .ENABLE_VDDIO(clk_hi),
        .TIE_HI_ESD(clk_hi_h), .TIE_LO_ESD(clk_lo_h),
        .ENABLE_H(clk_hi_h), .HLD_H_N(clk_hi_h),
        .ENABLE_INP_H(clk_lo_h), .ENABLE_VDDA_H(clk_lo_h), .ENABLE_VSWITCH_H(clk_lo_h),
        .IN_H(), .PAD_A_NOESD_H(), .PAD_A_ESD_0_H(), .PAD_A_ESD_1_H()
    );

    sky130_ef_io__gpiov2_pad_wrapped pad_rstn (
        `ANEL_
        .PAD(rstn_pad), .IN(rstn_core), .OUT(rstn_lo),
        .DM({rstn_lo, rstn_lo, rstn_hi}), .OE_N(rstn_hi), .INP_DIS(rstn_lo),
        .IB_MODE_SEL(rstn_lo), .VTRIP_SEL(rstn_lo), .SLOW(rstn_lo), .HLD_OVR(rstn_lo),
        .ANALOG_EN(rstn_lo), .ANALOG_SEL(rstn_lo), .ANALOG_POL(rstn_lo),
        .ENABLE_VDDIO(rstn_hi),
        .TIE_HI_ESD(rstn_hi_h), .TIE_LO_ESD(rstn_lo_h),
        .ENABLE_H(rstn_hi_h), .HLD_H_N(rstn_hi_h),
        .ENABLE_INP_H(rstn_lo_h), .ENABLE_VDDA_H(rstn_lo_h), .ENABLE_VSWITCH_H(rstn_lo_h),
        .IN_H(), .PAD_A_NOESD_H(), .PAD_A_ESD_0_H(), .PAD_A_ESD_1_H()
    );

    sky130_ef_io__gpiov2_pad_wrapped pad_rx (
        `ANEL_
        .PAD(rx_pad), .IN(rx_core), .OUT(rx_lo),
        .DM({rx_lo, rx_lo, rx_hi}), .OE_N(rx_hi), .INP_DIS(rx_lo),
        .IB_MODE_SEL(rx_lo), .VTRIP_SEL(rx_lo), .SLOW(rx_lo), .HLD_OVR(rx_lo),
        .ANALOG_EN(rx_lo), .ANALOG_SEL(rx_lo), .ANALOG_POL(rx_lo),
        .ENABLE_VDDIO(rx_hi),
        .TIE_HI_ESD(rx_hi_h), .TIE_LO_ESD(rx_lo_h),
        .ENABLE_H(rx_hi_h), .HLD_H_N(rx_hi_h),
        .ENABLE_INP_H(rx_lo_h), .ENABLE_VDDA_H(rx_lo_h), .ENABLE_VSWITCH_H(rx_lo_h),
        .IN_H(), .PAD_A_NOESD_H(), .PAD_A_ESD_0_H(), .PAD_A_ESD_1_H()
    );

    //=========================================================================
    // Pad de SAIDA: tx (UART)
    //=========================================================================
    wire tx_hi, tx_lo, tx_hi_h, tx_lo_h;

    sky130_fd_sc_hd__conb_1 tie_tx (.HI(tx_hi), .LO(tx_lo));

    sky130_ef_io__gpiov2_pad_wrapped pad_tx (
        `ANEL_
        .PAD(tx_pad), .IN(), .OUT(tx_core),
        .DM({tx_hi, tx_hi, tx_lo}), .OE_N(tx_lo), .INP_DIS(tx_hi),
        .IB_MODE_SEL(tx_lo), .VTRIP_SEL(tx_lo), .SLOW(tx_lo), .HLD_OVR(tx_lo),
        .ANALOG_EN(tx_lo), .ANALOG_SEL(tx_lo), .ANALOG_POL(tx_lo),
        .ENABLE_VDDIO(tx_hi),
        .TIE_HI_ESD(tx_hi_h), .TIE_LO_ESD(tx_lo_h),
        .ENABLE_H(tx_hi_h), .HLD_H_N(tx_hi_h),
        .ENABLE_INP_H(tx_lo_h), .ENABLE_VDDA_H(tx_lo_h), .ENABLE_VSWITCH_H(tx_lo_h),
        .IN_H(), .PAD_A_NOESD_H(), .PAD_A_ESD_0_H(), .PAD_A_ESD_1_H()
    );

    //=========================================================================
    // Pads de ALIMENTACAO (L48) e a fatia VCCHIB/VSWITCH (L50)
    //=========================================================================
    sky130_ef_io__vccd_lvc_clamped_pad  pad_vccd  (`ANEL_ .VCCD_PAD(vccd_pad));
    sky130_ef_io__vssd_lvc_clamped_pad  pad_vssd  (`ANEL_ .VSSD_PAD(vssd_pad));
    sky130_ef_io__vddio_hvc_clamped_pad pad_vddio (`ANEL_ .VDDIO_PAD(vddio_pad));
    sky130_ef_io__vssio_hvc_clamped_pad pad_vssio (`ANEL_ .VSSIO_PAD(vssio_pad));
    sky130_ef_io__vdda_hvc_clamped_pad  pad_vdda  (`ANEL_ .VDDA_PAD(vdda_pad));
    sky130_ef_io__vssa_hvc_clamped_pad  pad_vssa  (`ANEL_ .VSSA_PAD(vssa_pad));

    sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um fatia_vcchib (`ANEL);

endmodule

`undef ANEL
`undef ANEL_
