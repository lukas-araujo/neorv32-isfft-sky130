//=============================================================================
// isfft_sva.sv -- sonda e assercoes internas do isfft_axi_v4
//
// Falha de assercao vira `uvm_error: conta no resumo do UVM e o teste FALHA
// (com $error ela so seria impressa).
//
// isfft_probe_if   : sinais internos que a cobertura amostra (caixa-branca).
//                    Ligada no topo do tb por referencia hierarquica.
// isfft_v4_sva     : invariantes do wrapper, ligado por 'bind' (nao mexe no RTL)
// sram_1rw1r_sva   : a regra que a macro da OpenRAM so AVISA com $display
//                    (ler e escrever o mesmo endereco no mesmo ciclo) vira
//                    erro de assercao. Ligado por 'bind' no MODULO da macro:
//                    vale para as duas instancias, sem depender de nomes.
//=============================================================================
interface isfft_probe_if (input logic aclk, input logic aresetn);
    logic [6:0] in_used;       // palavras no buffer de entrada (0..64)
    logic [8:0] out_used;      // palavras na FIFO de saida (0..256)
    logic [1:0] ob_n;          // palavras no buffer de pre-busca (0..2)
    logic       in_avail_32;   // ha matriz confirmada esperando o nucleo
    logic       out_free_32;   // ha espaco reservavel para 1 matriz na saida
    logic       dp_rst;        // reset do caminho de dados (inclui soft reset)
endinterface

module isfft_v4_sva (
    input logic        aclk,
    input logic        aresetn,
    input logic        dp_rst,
    input logic [6:0]  in_used,
    input logic [8:0]  out_used,
    input logic [9:0]  reserved,
    input logic [1:0]  ob_n,
    input logic        ob_pend,
    input logic        out_ovf,
    input logic        core_push,
    input logic        core_armado,
    input logic        launch_start,
    input logic        launch_active
);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // A reserva de espaco garante que o nucleo nunca empurra com a FIFO cheia
    a_sem_overflow: assert property (@(posedge aclk) disable iff (dp_rst)
        !out_ovf)
        else `uvm_error("SVA", $sformatf("SVA: nucleo empurrou palavra com a FIFO de saida cheia"))

    a_in_used: assert property (@(posedge aclk) disable iff (dp_rst)
        in_used <= 7'd64)
        else `uvm_error("SVA", $sformatf("SVA: buffer de entrada passou de 64 (in_used=%0d)", in_used))

    // Ocupacao + reserva nunca passa da capacidade
    a_reserva: assert property (@(posedge aclk) disable iff (dp_rst)
        ({1'b0, out_used} + reserved) <= 10'd256)
        else `uvm_error("SVA", $sformatf("SVA: out_used (%0d) + reservado (%0d) > 256", out_used, reserved))

    // Pre-busca: buffer de 2 palavras, contando a que esta a caminho
    a_prebusca: assert property (@(posedge aclk) disable iff (dp_rst)
        (ob_n + ob_pend) <= 3'd2)
        else `uvm_error("SVA", $sformatf("SVA: pre-busca com %0d palavras (max 2)", {1'b0, ob_n} + ob_pend))

    // Saida do nucleo so e aceita depois da primeira matriz (core_armado, D34)
    a_armado: assert property (@(posedge aclk) disable iff (dp_rst)
        core_push |-> core_armado)
        else `uvm_error("SVA", $sformatf("SVA: nucleo entregou palavra antes de receber matriz"))

    // O liberador so dispara com o nucleo parado
    a_lanca: assert property (@(posedge aclk) disable iff (dp_rst)
        launch_start |-> !launch_active)
        else `uvm_error("SVA", $sformatf("SVA: liberador disparou com matriz em andamento"))
endmodule

module sram_1rw1r_sva #(parameter int AW = 6) (
    input logic          clk,
    input logic          csb0,
    input logic          web0,
    input logic          csb1,
    input logic [AW-1:0] addr0,
    input logic [AW-1:0] addr1
);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    a_sem_conflito: assert property (@(posedge clk)
        !(!csb0 && !web0 && !csb1 && (addr0 == addr1)))
        else `uvm_error("SVA", $sformatf("SVA: macro %m escreveu e leu o endereco %0d no mesmo ciclo", addr0))
endmodule
