//=============================================================================
// stream_32to64.v
//
// SLINK TX do NEORV32 (32 bits)  ->  entrada AXI-Stream da ISFFT (64 bits)
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
//-----------------------------------------------------------------------------
// ORDEM DAS PALAVRAS
//-----------------------------------------------------------------------------
// Primeira palavra de 32 bits -> [31:0]; segunda -> [63:32].
// E a mesma ordem em que o AXI DMA da Kria lia a memoria (little-endian):
// a matriz fica na DMEM exatamente como ficava na DDR. O firmware nao muda
// o formato dos dados.
//
//-----------------------------------------------------------------------------
// TLAST
//-----------------------------------------------------------------------------
// O 'last' do SLINK vira o tlast da palavra de 64 bits. O firmware marca a
// ultima palavra do pacote escrevendo-a no registrador DATA_LAST do SLINK
// (um segundo descritor de DMA, de 1 palavra). Este bloco NAO conta
// palavras nem conhece PKT_MAT: so repassa o 'last'.
//
// 'last' numa palavra IMPAR (metade baixa) e erro de protocolo do
// firmware: a palavra sai sozinha, com [63:32] = 0 e tlast = 1. A ISFFT
// vai acusar erro de tlast (pacote truncado) -- e isso e o esperado.
//
//-----------------------------------------------------------------------------
// VAZAO: aceita 1 palavra de 32 bits por ciclo se a saida estiver livre.
//=============================================================================

`timescale 1ns / 1ps

module stream_32to64 (
    input  wire        clk_i,
    input  wire        rstn_i,
    // entrada: 32 bits (SLINK TX)
    input  wire [31:0] s_data_i,
    input  wire        s_valid_i,
    input  wire        s_last_i,
    output wire        s_ready_o,
    // saida: 64 bits (AXI-Stream)
    output reg  [63:0] m_data_o,
    output reg         m_valid_o,
    output reg         m_last_o,
    input  wire        m_ready_i
);

    reg        tem_baixa;      // ja guardou a metade baixa
    reg [31:0] baixa;

    // Registrador de saida livre neste ciclo (vazio ou sendo consumido)
    wire saida_livre = ~m_valid_o | m_ready_i;
    assign s_ready_o = saida_livre;

    wire aceita = s_valid_i & s_ready_o;
    // fecha uma palavra de 64: segunda metade, ou 'last' sozinho na primeira
    wire fecha  = aceita & (tem_baixa | s_last_i);

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            tem_baixa <= 1'b0;
            baixa     <= 32'h0;
            m_data_o  <= 64'h0;
            m_valid_o <= 1'b0;
            m_last_o  <= 1'b0;
        end else begin
            if (fecha) begin
                m_data_o  <= tem_baixa ? {s_data_i, baixa} : {32'h0, s_data_i};
                m_last_o  <= s_last_i;
                m_valid_o <= 1'b1;
                tem_baixa <= 1'b0;
            end else begin
                if (aceita) begin               // metade baixa, sem last
                    baixa     <= s_data_i;
                    tem_baixa <= 1'b1;
                end
                if (m_ready_i) m_valid_o <= 1'b0;
            end
        end
    end

endmodule
