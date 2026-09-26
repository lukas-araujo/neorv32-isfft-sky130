//=============================================================================
// neorv32_imem.v
//
// Substituto da IMEM do NEORV32 (fluxo "Replaceable Modules"): a memoria
// de programa vira a macro OpenRAM de 8 kB (D27).
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Uso na conversao para Verilog:
//   make VHDL_EXCLUDE=neorv32_imem.vhd VERILOG_SRC=<este arquivo> ...
//
//-----------------------------------------------------------------------------
// REFERENCIA: rtl/core/neorv32_imem.vhd
//-----------------------------------------------------------------------------
// INITROM = 0: RAM comum (leitura e escrita), igual a DMEM.
// INITROM = 1: ROM pre-inicializada (BOOT_MODE_SELECT = 2). Como no VHDL:
//              escrita NAO altera a memoria e NAO recebe ack.
//
// ⚠️ A macro e fisicamente uma RAM: nao existe ROM gerada pela OpenRAM.
// Com INITROM = 1 o conteudo inicial so existe em SIMULACAO, carregado por
// $readmemh no modelo da macro (tb). Num chip real, alguem teria que
// escrever o programa antes -- bootloader ou depurador (fora de escopo).
//
//-----------------------------------------------------------------------------
// LIMITES DESTA VERSAO: AWIDTH = 13 (8 kB), OUTREG = 0.
//=============================================================================

`timescale 1ns / 1ps

module neorv32_imem #(
    parameter AWIDTH  = 13,
    parameter INITROM = 0,
    parameter OUTREG  = 0
)(
    input  wire        clk_i,
    input  wire        rstn_i,
    input  wire [31:0] req_addr_i,
    input  wire [31:0] req_data_i,
    input  wire [3:0]  req_ben_i,
    input  wire        req_stb_i,
    input  wire        req_rw_i,
    output wire [31:0] rsp_data_o,
    output wire        rsp_ack_o,
    output wire        rsp_err_o
);

    generate
        if (AWIDTH != 13) begin : g_erro_awidth
            ERRO_neorv32_imem_macro_so_suporta_AWIDTH_13 u_erro ();
        end
        if (OUTREG != 0) begin : g_erro_outreg
            ERRO_neorv32_imem_macro_nao_suporta_OUTREG u_erro ();
        end
    endgenerate

    localparam ROM = (INITROM != 0);

    //-------------------------------------------------------------------------
    // Macro. Como ROM, a escrita e bloqueada aqui: a macro nem e acionada.
    //-------------------------------------------------------------------------
    wire        acesso = req_stb_i & ~(ROM & req_rw_i);
    wire [31:0] rdata;

    sram8k_1rw u_sram (
        .clk_i   (clk_i),
        .cs_i    (acesso),
        .we_i    (req_rw_i),
        .ben_i   (req_ben_i),
        .addr_i  (req_addr_i[12:2]),
        .wdata_i (req_data_i),
        .rdata_o (rdata)
    );

    //-------------------------------------------------------------------------
    // Handshake -- identico ao VHDL
    //-------------------------------------------------------------------------
    reg rdack, wrack;

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            rdack <= 1'b0;
            wrack <= 1'b0;
        end else begin
            rdack <= req_stb_i & ~req_rw_i;
            wrack <= req_stb_i &  req_rw_i;
        end
    end

    assign rsp_data_o = rdack ? rdata : 32'h0000_0000;
    assign rsp_ack_o  = ROM ? rdack : (rdack | wrack);
    assign rsp_err_o  = 1'b0;

endmodule
