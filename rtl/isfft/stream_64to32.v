//=============================================================================
// stream_64to32.v
//
// saida AXI-Stream da ISFFT (64 bits)  ->  SLINK RX do NEORV32 (32 bits)
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Ordem: [31:0] sai primeiro, [63:32] depois -- o inverso do stream_32to64,
// e a mesma ordem em que o AXI DMA da Kria escrevia na DDR.
// tlast da palavra de 64 vira o 'last' da SEGUNDA metade.
//
// Vazao: 1 palavra de 32 bits por ciclo; aceita a proxima palavra de 64 no
// mesmo ciclo em que a segunda metade da atual e consumida (sem bolha).
//=============================================================================

`timescale 1ns / 1ps

module stream_64to32 (
    input  wire        clk_i,
    input  wire        rstn_i,
    // entrada: 64 bits (AXI-Stream)
    input  wire [63:0] s_data_i,
    input  wire        s_valid_i,
    input  wire        s_last_i,
    output wire        s_ready_o,
    // saida: 32 bits (SLINK RX)
    output wire [31:0] m_data_o,
    output wire        m_valid_o,
    output wire        m_last_o,
    input  wire        m_ready_i
);

    reg        cheio;        // ha uma palavra de 64 guardada
    reg        fase;         // 0 = mandando [31:0], 1 = mandando [63:32]
    reg [63:0] dado;
    reg        ultimo;

    wire sai        = cheio & m_ready_i;
    wire fim_palavra = sai & fase;             // segunda metade consumida

    assign s_ready_o = ~cheio | fim_palavra;
    wire   entra     = s_valid_i & s_ready_o;

    assign m_valid_o = cheio;
    assign m_data_o  = fase ? dado[63:32] : dado[31:0];
    assign m_last_o  = cheio & fase & ultimo;

    always @(posedge clk_i or negedge rstn_i) begin
        if (!rstn_i) begin
            cheio  <= 1'b0;
            fase   <= 1'b0;
            dado   <= 64'h0;
            ultimo <= 1'b0;
        end else begin
            if (entra) begin
                dado   <= s_data_i;
                ultimo <= s_last_i;
                cheio  <= 1'b1;
                fase   <= 1'b0;
            end else if (fim_palavra) begin
                cheio  <= 1'b0;
                fase   <= 1'b0;
            end else if (sai) begin
                fase   <= 1'b1;
            end
        end
    end

endmodule
