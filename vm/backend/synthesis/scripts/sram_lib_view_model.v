//=============================================================================
// sram_lib_view_model.v
//
// Adaptadores de SIMULACAO para as duas macros de 1 porta (IMEM e DMEM).
// Usados na simulacao pos-sintese E na simulacao RTL da VM (com
// +define+SRAM_LIB_VIEW), para as duas usarem exatamente os mesmos
// modelos de memoria.
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
//-----------------------------------------------------------------------------
// O PROBLEMA QUE ESTE ARQUIVO RESOLVE (licao do projeto OpenRAM)
//-----------------------------------------------------------------------------
// O netlist instancia a macro com a interface do .lib:
//     din0[31:0]  dout0[31:0]  (sem spare_wen0)
// O modelo comportamental da OpenRAM tem outra:
//     din0[32:0]  dout0[32:0]  spare_wen0      (33o bit = coluna sobressalente)
//
// Cada modulo abaixo tem o NOME EXATO da macro e a interface do .lib, e
// instancia o modelo da OpenRAM renomeado para <macro>_beh (o run_first.tcl
// gera o _beh com sed, ja com VERBOSE = 0). Bit 32 da entrada em 0, bit 32
// da saida descartado, spare_wen0 desligado.
//
// As macros 1rw1r da ISFFT NAO precisam disto: o .lib e o .v delas tem a
// mesma interface (64 bits, sem coluna sobressalente).
//
//-----------------------------------------------------------------------------
// CARGA DO PROGRAMA (D28: IMEM como ROM, carregada pelo testbench)
//-----------------------------------------------------------------------------
// A macro da IMEM se carrega sozinha, por plusarg:
//     xrun ... +IMEM_HEX=<caminho>/neorv32_raw_exe.hex
// Fazer a carga AQUI DENTRO (e nao pelo testbench) torna a simulacao
// independente dos nomes de hierarquia que o Genus escrever no netlist.
//=============================================================================

`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// IMEM: 8 kB = 2048 x 32 (+ linha sobressalente: 12 bits de endereco)
//-----------------------------------------------------------------------------
module sram_8kbyte_1rw_32x2048_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [11:0] addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0
);
    wire [32:0] dout0_33;

    sram_8kbyte_1rw_32x2048_8_beh u_beh (
        .clk0(clk0), .csb0(csb0), .web0(web0), .wmask0(wmask0),
        .spare_wen0(1'b0), .addr0(addr0),
        .din0({1'b0, din0}), .dout0(dout0_33));

    assign dout0 = dout0_33[31:0];

    reg [1023:0] arq;
    initial begin
        if ($value$plusargs("IMEM_HEX=%s", arq)) begin
            $readmemh(arq, u_beh.mem);
            $display("[IMEM] programa: %0s", arq);
            $display("[IMEM] mem[0..2] = %h %h %h", u_beh.mem[0], u_beh.mem[1], u_beh.mem[2]);
        end else begin
            $display("[IMEM] ERRO: falta +IMEM_HEX=<neorv32_raw_exe.hex>.");
            $display("[IMEM] Sem programa a CPU busca X e nada roda.");
        end
    end
endmodule

//-----------------------------------------------------------------------------
// DMEM: 4 kB = 1024 x 32 (+ linha sobressalente: 11 bits de endereco)
//-----------------------------------------------------------------------------
module sram_4kbyte_1rw_32x1024_8 (
    input  wire        clk0,
    input  wire        csb0,
    input  wire        web0,
    input  wire [3:0]  wmask0,
    input  wire [10:0] addr0,
    input  wire [31:0] din0,
    output wire [31:0] dout0
);
    wire [32:0] dout0_33;

    sram_4kbyte_1rw_32x1024_8_beh u_beh (
        .clk0(clk0), .csb0(csb0), .web0(web0), .wmask0(wmask0),
        .spare_wen0(1'b0), .addr0(addr0),
        .din0({1'b0, din0}), .dout0(dout0_33));

    assign dout0 = dout0_33[31:0];
endmodule
