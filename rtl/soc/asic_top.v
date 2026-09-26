//=============================================================================
// asic_top.v -- topo do chip: NEORV32 + ISFFT
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
//   neorv32_asic (VHDL convertido pelo GHDL: CPU, IMEM/DMEM em macro, DMA,
//                 SLINK, UART0, ponte XBUS -> AXI4)
//      |-- AXI4-Lite -----------------------------> isfft_axi_v4 (s_axi)
//      |-- SLINK TX --> stream_32to64 ------------> isfft_axi_v4 (s00_axis)
//      |-- SLINK RX <-- stream_64to32 <------------ isfft_axi_v4 (m00_axis)
//
// isfft_axi_v4 = isfft_axi_v3 da Kria com in_mem e out_mem em macro
// OpenRAM (D26). Mesmos registradores, mesmo protocolo.
//
// Mapa: ISFFT em 0x4001_0000 (4 kB), o mesmo da Kria.
//
//-----------------------------------------------------------------------------
// DECODIFICACAO DE ENDERECO -- sem espelhamento
//-----------------------------------------------------------------------------
// A ISFFT e o unico escravo externo. So repassamos o handshake se o endereco
// cai na janela dela. Fora da janela a transacao nunca termina, o XBUS do
// NEORV32 estoura o XBUS_TIMEOUT (2048 ciclos) e a CPU recebe ERRO DE
// BARRAMENTO (excecao) -- em vez de ler/escrever a ISFFT espelhada por engano.
// A ponte segura o endereco num registrador durante toda a transacao, e a
// FIFO de dados dela e limpa quando o XBUS desiste; entao bloquear AW/W/AR
// pelo endereco e seguro.
// Bonus: usar os bits altos do endereco evita que a sintese os pode.
//=============================================================================

`timescale 1ns / 1ps

module asic_top (
    input  wire clk_i,
    input  wire rstn_i,
    output wire uart0_txd_o,
    input  wire uart0_rxd_i
);

    localparam [31:0] ISFFT_BASE = 32'h4001_0000;

    //-------------------------------------------------------------------------
    // Processador
    //-------------------------------------------------------------------------
    wire [31:0] awaddr, wdata, araddr, rdata;
    wire [2:0]  awprot, arprot;
    wire [3:0]  wstrb;
    wire [1:0]  bresp, rresp;
    wire        awvalid, awready, wvalid, wready, bvalid, bready;
    wire        arvalid, arready, rvalid, rready;

    wire [31:0] tx_dat, rx_dat;
    wire        tx_val, tx_lst, tx_rdy, rx_val, rx_lst, rx_rdy;

    neorv32_asic u_cpu (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .uart0_txd_o(uart0_txd_o), .uart0_rxd_i(uart0_rxd_i),
        .m_axi_awaddr(awaddr), .m_axi_awprot(awprot), .m_axi_awvalid(awvalid), .m_axi_awready(awready),
        .m_axi_wdata(wdata), .m_axi_wstrb(wstrb), .m_axi_wvalid(wvalid), .m_axi_wready(wready),
        .m_axi_bresp(bresp), .m_axi_bvalid(bvalid), .m_axi_bready(bready),
        .m_axi_araddr(araddr), .m_axi_arprot(arprot), .m_axi_arvalid(arvalid), .m_axi_arready(arready),
        .m_axi_rdata(rdata), .m_axi_rresp(rresp), .m_axi_rvalid(rvalid), .m_axi_rready(rready),
        .slink_rx_dat_i(rx_dat), .slink_rx_val_i(rx_val), .slink_rx_lst_i(rx_lst), .slink_rx_rdy_o(rx_rdy),
        .slink_tx_dat_o(tx_dat), .slink_tx_val_o(tx_val), .slink_tx_lst_o(tx_lst), .slink_tx_rdy_i(tx_rdy)
    );

    //-------------------------------------------------------------------------
    // Janela da ISFFT
    //-------------------------------------------------------------------------
    wire aw_ok = (awaddr[31:12] == ISFFT_BASE[31:12]);
    wire ar_ok = (araddr[31:12] == ISFFT_BASE[31:12]);

    wire s_awready, s_wready, s_arready;

    assign awready = s_awready & aw_ok;
    assign wready  = s_wready  & aw_ok;
    assign arready = s_arready & ar_ok;

    //-------------------------------------------------------------------------
    // Conversores de stream
    //-------------------------------------------------------------------------
    wire [63:0] in_dat, out_dat;
    wire        in_val, in_lst, in_rdy, out_val, out_lst, out_rdy;

    stream_32to64 u_up (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .s_data_i(tx_dat), .s_valid_i(tx_val), .s_last_i(tx_lst), .s_ready_o(tx_rdy),
        .m_data_o(in_dat), .m_valid_o(in_val), .m_last_o(in_lst), .m_ready_i(in_rdy));

    stream_64to32 u_down (
        .clk_i(clk_i), .rstn_i(rstn_i),
        .s_data_i(out_dat), .s_valid_i(out_val), .s_last_i(out_lst), .s_ready_o(out_rdy),
        .m_data_o(rx_dat), .m_valid_o(rx_val), .m_last_o(rx_lst), .m_ready_i(rx_rdy));

    //-------------------------------------------------------------------------
    // ISFFT: RTL da Kria com in_mem/out_mem em macro OpenRAM (v4)
    //-------------------------------------------------------------------------
    isfft_axi_v4 u_isfft (
        .aclk(clk_i), .aresetn(rstn_i),
        .s_axi_awaddr(awaddr[5:0]), .s_axi_awprot(awprot),
        .s_axi_awvalid(awvalid & aw_ok), .s_axi_awready(s_awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb),
        .s_axi_wvalid(wvalid & aw_ok), .s_axi_wready(s_wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr[5:0]), .s_axi_arprot(arprot),
        .s_axi_arvalid(arvalid & ar_ok), .s_axi_arready(s_arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s00_axis_tdata(in_dat), .s00_axis_tkeep(8'hFF), .s00_axis_tlast(in_lst),
        .s00_axis_tvalid(in_val), .s00_axis_tready(in_rdy),
        .m00_axis_tdata(out_dat), .m00_axis_tkeep(), .m00_axis_tlast(out_lst),
        .m00_axis_tvalid(out_val), .m00_axis_tready(out_rdy)
    );

endmodule
