//=============================================================================
// axil_if.sv -- interface AXI4-Lite (lado mestre = testbench, escravo = ISFFT)
//
// Os sinais tem os mesmos nomes das portas s_axi_* do isfft_axi_v4, sem o
// prefixo. O driver escreve com atribuicao nao bloqueante logo depois da
// borda de subida; o monitor le logo depois da mesma borda (ve os valores
// de ANTES da borda, que sao os que o DUT amostrou).
//
// Assercoes de protocolo (regras do AXI: "valid nao cai sem handshake e o
// conteudo nao muda enquanto espera"). Valem para os dois lados:
//   - AW, W, AR: mestre = nosso driver  -> pega erro do testbench
//   - B, R     : mestre = o DUT         -> pega erro do RTL
//=============================================================================
interface axil_if #(parameter int AW = 6) (input logic aclk, input logic aresetn);
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    logic [AW-1:0] awaddr;
    logic [2:0]    awprot;
    logic          awvalid;
    logic          awready;
    logic [31:0]   wdata;
    logic [3:0]    wstrb;
    logic          wvalid;
    logic          wready;
    logic [1:0]    bresp;
    logic          bvalid;
    logic          bready;
    logic [AW-1:0] araddr;
    logic [2:0]    arprot;
    logic          arvalid;
    logic          arready;
    logic [31:0]   rdata;
    logic [1:0]    rresp;
    logic          rvalid;
    logic          rready;

    //-------------------------------------------------------------------------
    // Protocolo
    //-------------------------------------------------------------------------
    a_aw_estavel: assert property (@(posedge aclk) disable iff (!aresetn)
        (awvalid && !awready) |=> (awvalid && $stable(awaddr)))
        else `uvm_error("SVA", $sformatf("AXI-Lite: AW mudou/caiu antes do handshake"))

    a_w_estavel: assert property (@(posedge aclk) disable iff (!aresetn)
        (wvalid && !wready) |=> (wvalid && $stable(wdata) && $stable(wstrb)))
        else `uvm_error("SVA", $sformatf("AXI-Lite: W mudou/caiu antes do handshake"))

    a_ar_estavel: assert property (@(posedge aclk) disable iff (!aresetn)
        (arvalid && !arready) |=> (arvalid && $stable(araddr)))
        else `uvm_error("SVA", $sformatf("AXI-Lite: AR mudou/caiu antes do handshake"))

    a_b_estavel: assert property (@(posedge aclk) disable iff (!aresetn)
        (bvalid && !bready) |=> (bvalid && $stable(bresp)))
        else `uvm_error("SVA", $sformatf("AXI-Lite: B (DUT) caiu antes do handshake"))

    a_r_estavel: assert property (@(posedge aclk) disable iff (!aresetn)
        (rvalid && !rready) |=> (rvalid && $stable(rdata) && $stable(rresp)))
        else `uvm_error("SVA", $sformatf("AXI-Lite: R (DUT) mudou/caiu antes do handshake"))

    // O DUT so responde OKAY
    a_resp_okay: assert property (@(posedge aclk) disable iff (!aresetn)
        (bvalid |-> bresp == 2'b00) and (rvalid |-> rresp == 2'b00))
        else `uvm_error("SVA", $sformatf("AXI-Lite: resposta diferente de OKAY"))

endinterface
