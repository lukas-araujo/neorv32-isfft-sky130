//=============================================================================
// neorv32_dmem.v
//
// Substituto da DMEM do NEORV32 (fluxo "Replaceable Modules"): a memoria
// de dados vira a macro OpenRAM de 4 kB em vez de um array em VHDL.
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Uso na conversao para Verilog:
//   make VHDL_EXCLUDE=neorv32_dmem.vhd VERILOG_SRC=<este arquivo> ...
//
//-----------------------------------------------------------------------------
// REFERENCIA: rtl/core/neorv32_dmem.vhd -- NAO o exemplo em Verilog
//-----------------------------------------------------------------------------
// O exemplo rtl/verilog/modules/neorv32_dmem.v NAO reconhece escrita
// (so tem ack de leitura): o primeiro 'sw' travaria o barramento. Este
// arquivo segue o VHDL, que tem 'wrack'. Ver DIARIO.md (D15).
//
// Diferenca deliberada em relacao ao VHDL: numa leitura, o VHDL so atualiza
// os bytes habilitados por req_ben_i; a macro le a palavra inteira. Os bytes
// nao habilitados sao ignorados pela CPU, entao o comportamento visivel e o
// mesmo. O testbench compara so os bytes habilitados.
//
//-----------------------------------------------------------------------------
// LIMITES DESTA VERSAO
//-----------------------------------------------------------------------------
//   AWIDTH = 12 (4 kB)  -- e o tamanho da macro
//   OUTREG = 0          -- a macro ja entrega o dado em 1 ciclo
// Qualquer outro valor PARA A ELABORACAO (em todas as ferramentas) por
// instanciar um modulo inexistente com o motivo no nome.
//=============================================================================

`timescale 1ns / 1ps

module neorv32_dmem #(
    parameter AWIDTH = 12,   // largura do endereco de BYTE
    parameter OUTREG = 0     // registrador extra de saida
)(
    input  wire        clk_i,
    input  wire        rstn_i,
    // requisicao
    input  wire [31:0] req_addr_i,   // endereco de byte
    input  wire [31:0] req_data_i,
    input  wire [3:0]  req_ben_i,
    input  wire        req_stb_i,    // pulso de 1 ciclo
    input  wire        req_rw_i,     // 0 = leitura, 1 = escrita
    // resposta
    output wire [31:0] rsp_data_o,
    output wire        rsp_ack_o,
    output wire        rsp_err_o
);

    //-------------------------------------------------------------------------
    // Checagem de configuracao (falha na elaboracao, nao so em simulacao)
    //-------------------------------------------------------------------------
    generate
        if (AWIDTH != 12) begin : g_erro_awidth
            ERRO_neorv32_dmem_macro_so_suporta_AWIDTH_12 u_erro ();
        end
        if (OUTREG != 0) begin : g_erro_outreg
            ERRO_neorv32_dmem_macro_nao_suporta_OUTREG u_erro ();
        end
    endgenerate

    //-------------------------------------------------------------------------
    // Macro
    //-------------------------------------------------------------------------
    wire [31:0] rdata;

    sram4k_1rw u_sram (
        .clk_i   (clk_i),
        .cs_i    (req_stb_i),
        .we_i    (req_rw_i),
        .ben_i   (req_ben_i),
        .addr_i  (req_addr_i[11:2]),
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

    // Portao de saida: 0 fora da resposta de leitura (as respostas dos
    // escravos sao combinadas por OU no barramento do NEORV32).
    assign rsp_data_o = rdack ? rdata : 32'h0000_0000;
    assign rsp_ack_o  = rdack | wrack;
    assign rsp_err_o  = 1'b0;

endmodule
