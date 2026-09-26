//=============================================================================
// sram8k_1rw.v
//
// Interface normalizada para a macro OpenRAM sram_4kbyte_1rw_32x1024_8
// (1024 palavras x 32 bits, 1 porta leitura/escrita, escrita por byte).
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Usada pela IMEM (D27). Mesma interface e mesma temporizacao da
// sram4k_1rw (DMEM); so o endereco tem 1 bit a mais.
//
//-----------------------------------------------------------------------------
// TEMPORIZACAO DA MACRO
//-----------------------------------------------------------------------------
// Entradas capturadas na borda de SUBIDA; escrita e leitura executadas na
// borda de DESCIDA do mesmo ciclo. Dado lido valido da metade do ciclo
// seguinte ate logo depois da proxima subida. Latencia: 1 ciclo -- a mesma
// da IMEM/DMEM originais do NEORV32.
//
//-----------------------------------------------------------------------------
// AS TRES VIEWS DA MACRO NAO CONCORDAM
//-----------------------------------------------------------------------------
//     view        din0/dout0   spare_wen0
//     .v          33 bits      existe       (simulacao)
//     .lef        33 bits      existe       (layout -- LibreLane)
//     .lib        32 bits      NAO existe   (timing -- Genus)
//
// Padrao: interface de 33 bits, igual a .v e a .lef. O bit 32 (coluna
// sobressalente) e o spare_wen0 ficam em 0.
// Para o Genus, que so le o .lib, defina SRAM_LIB_VIEW:
//     read_hdl -define SRAM_LIB_VIEW ...
//=============================================================================

`timescale 1ns / 1ps

module sram8k_1rw (
    input  wire        clk_i,
    input  wire        cs_i,      // acesso neste ciclo (ativo alto)
    input  wire        we_i,      // 1 = escrita, 0 = leitura
    input  wire [3:0]  ben_i,     // habilita cada byte na escrita
    input  wire [10:0] addr_i,    // endereco de PALAVRA (2048 palavras)
    input  wire [31:0] wdata_i,
    output wire [31:0] rdata_o
);

    // A macro tem 1 bit de endereco a mais (linha sobressalente): fica em 0.
    wire [11:0] macro_addr = {1'b0, addr_i};

`ifdef SRAM_LIB_VIEW
    sram_8kbyte_1rw_32x2048_8 u_macro (
        .clk0   (clk_i),
        .csb0   (~cs_i),
        .web0   (~we_i),
        .wmask0 (ben_i),
        .addr0  (macro_addr),
        .din0   (wdata_i),
        .dout0  (rdata_o)
    );
`else
    wire [32:0] dout_33;

    sram_8kbyte_1rw_32x2048_8 u_macro (
        .clk0       (clk_i),
        .csb0       (~cs_i),
        .web0       (~we_i),
        .wmask0     (ben_i),
        .spare_wen0 (1'b0),
        .addr0      (macro_addr),
        .din0       ({1'b0, wdata_i}),
        .dout0      (dout_33)
    );

    assign rdata_o = dout_33[31:0];
`endif

endmodule
