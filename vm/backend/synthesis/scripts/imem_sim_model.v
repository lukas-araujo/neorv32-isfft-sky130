//=============================================================================
// imem_sim_model.v
//
// Modelo de SIMULACAO da IMEM (macro sram_8kbyte_1rw_32x2048_8) que
// CARREGA O PROGRAMA sozinho. Usado na simulacao RTL (bloco 0) e na
// pos-sintese (bloco 2) do run_first.tcl, e no sim/run_gls_yosys.sh.
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
//-----------------------------------------------------------------------------
// HISTORICO -- substitui o sram_lib_view_model.v (front-end)
//-----------------------------------------------------------------------------
// No front-end o netlist ligava as macros de 1 porta com a interface do
// .lib ORIGINAL (32 bits, sem spare_wen0), e o adaptador convertia para o
// modelo da OpenRAM (33 bits). Agora o .lib foi corrigido para 33 bits
// (macros/lib_33bits.py, L1 do DIARIO_GDSII): RTL, netlist, .v, .lib e
// .lef usam a MESMA interface. Nao ha mais nada para converter:
//   - DMEM: o modelo da OpenRAM entra direto (so com VERBOSE = 0);
//   - IMEM: este modulo, so para carregar o programa.
//
//-----------------------------------------------------------------------------
// CARGA DO PROGRAMA (FE-D28: IMEM como ROM, carregada pelo testbench)
//-----------------------------------------------------------------------------
//     xrun ... +IMEM_HEX=<caminho>/neorv32_raw_exe.hex
// A carga e feita AQUI DENTRO, e nao pelo testbench, para a simulacao nao
// depender dos nomes de hierarquia que o Genus der ao netlist.
// O modelo da OpenRAM entra renomeado para <macro>_beh (o run_first.tcl
// gera com sed, ja com VERBOSE = 0).
//=============================================================================

`timescale 1ns / 1ps

module sram_8kbyte_1rw_32x2048_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire        spare_wen0,
    input  wire [11:0] addr0,
    input  wire [32:0] din0,
    output wire [32:0] dout0
);
    sram_8kbyte_1rw_32x2048_8_beh u_beh (
        .clk0(clk0), .csb0(csb0), .web0(web0), .wmask0(wmask0),
        .spare_wen0(spare_wen0), .addr0(addr0),
        .din0(din0), .dout0(dout0));

    // O .hex tem palavras de 32 bits; a memoria do modelo tem 33. Le numa
    // copia de 32 e poe o bit 32 (coluna sobressalente) em 0.
    reg [31:0]   img [0:2047];
    reg [1023:0] arq;
    integer      i;
    initial begin
        if ($value$plusargs("IMEM_HEX=%s", arq)) begin
            for (i = 0; i < 2048; i = i + 1) img[i] = 32'h0;
            $readmemh(arq, img);
            for (i = 0; i < 2048; i = i + 1) u_beh.mem[i] = {1'b0, img[i]};
            $display("[IMEM] programa: %0s", arq);
            $display("[IMEM] mem[0..2] = %h %h %h", u_beh.mem[0], u_beh.mem[1], u_beh.mem[2]);
        end else begin
            $display("[IMEM] ERRO: falta +IMEM_HEX=<neorv32_raw_exe.hex>.");
            $display("[IMEM] Sem programa a CPU busca X e nada roda.");
        end
    end
endmodule
