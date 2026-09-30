//=============================================================================
// axis_if.sv -- interface AXI4-Stream de 64 bits
//
// Usada duas vezes: entrada (s00_axis, testbench -> DUT) e saida (m00_axis,
// DUT -> testbench). Uma terceira instancia liga o modelo de referencia
// (wrapper da etapa 1).
//
// sync_rst: reset do caminho de dados do DUT (dp_rst = ~aresetn | soft
// reset). Durante o soft reset o DUT zera a FIFO de saida de proposito, e
// o tvalid cai sem handshake -- a regra do AXI nao vale nesse momento.
//=============================================================================
interface axis_if #(parameter int DW = 64) (input logic aclk, input logic aresetn);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    logic [DW-1:0]   tdata;
    logic [DW/8-1:0] tkeep;
    logic            tlast;
    logic            tvalid;
    logic            tready;
    logic            sync_rst;   // ligado pelo topo do tb (0 onde nao se aplica)

    // valid nao cai e dado/last nao mudam enquanto espera o ready
    a_estavel: assert property (@(posedge aclk) disable iff (!aresetn || sync_rst)
        (tvalid && !tready) |=> (tvalid && $stable(tdata) && $stable(tlast)))
        else `uvm_error("SVA", $sformatf("AXI-Stream: tvalid caiu ou tdata/tlast mudou antes do handshake"))

    // sem X no que e transferido
    a_sem_x: assert property (@(posedge aclk) disable iff (!aresetn)
        (tvalid && tready) |-> !$isunknown({tdata, tlast}))
        else `uvm_error("SVA", $sformatf("AXI-Stream: X em tdata/tlast num handshake"))

endinterface
