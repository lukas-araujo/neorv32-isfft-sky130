//=============================================================================
// isfft_tb_top.sv -- topo do testbench UVM do isfft_axi_v4
//
//   clock 50 MHz (o do chip, D7), reset por 20 ciclos
//   DUT : isfft_axi_v4 (com as duas macros OpenRAM, modelo .v da OpenRAM)
//   REF : isfft_axi_wrapper (etapa 1), dirigido pelo modelo de referencia
//   bind: assercoes internas do DUT e das macros
//
// O teste e escolhido por +UVM_TESTNAME=<teste>.
//=============================================================================
`timescale 1ns/1ps

module isfft_tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import isfft_env_pkg::*;
    import isfft_test_pkg::*;

    localparam real PERIODO_NS = 20.0;

    logic aclk = 1'b0;
    logic aresetn = 1'b0;
    always #(PERIODO_NS / 2) aclk = ~aclk;
    initial begin
        repeat (20) @(posedge aclk);
        aresetn <= 1'b1;
    end

    axil_if        axil  (.aclk(aclk), .aresetn(aresetn));
    axis_if        s_ax  (.aclk(aclk), .aresetn(aresetn));   // entrada do DUT
    axis_if        m_ax  (.aclk(aclk), .aresetn(aresetn));   // saida do DUT
    axis_if        r_in  (.aclk(aclk), .aresetn(aresetn));   // entrada da referencia
    axis_if        r_out (.aclk(aclk), .aresetn(aresetn));   // saida da referencia
    isfft_probe_if probe (.aclk(aclk), .aresetn(aresetn));

    //-------------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------------
    isfft_axi_v4 dut (
        .aclk            (aclk),
        .aresetn         (aresetn),
        .s_axi_awaddr    (axil.awaddr),
        .s_axi_awprot    (axil.awprot),
        .s_axi_awvalid   (axil.awvalid),
        .s_axi_awready   (axil.awready),
        .s_axi_wdata     (axil.wdata),
        .s_axi_wstrb     (axil.wstrb),
        .s_axi_wvalid    (axil.wvalid),
        .s_axi_wready    (axil.wready),
        .s_axi_bresp     (axil.bresp),
        .s_axi_bvalid    (axil.bvalid),
        .s_axi_bready    (axil.bready),
        .s_axi_araddr    (axil.araddr),
        .s_axi_arprot    (axil.arprot),
        .s_axi_arvalid   (axil.arvalid),
        .s_axi_arready   (axil.arready),
        .s_axi_rdata     (axil.rdata),
        .s_axi_rresp     (axil.rresp),
        .s_axi_rvalid    (axil.rvalid),
        .s_axi_rready    (axil.rready),
        .s00_axis_tdata  (s_ax.tdata),
        .s00_axis_tkeep  (s_ax.tkeep),
        .s00_axis_tlast  (s_ax.tlast),
        .s00_axis_tvalid (s_ax.tvalid),
        .s00_axis_tready (s_ax.tready),
        .m00_axis_tdata  (m_ax.tdata),
        .m00_axis_tkeep  (m_ax.tkeep),
        .m00_axis_tlast  (m_ax.tlast),
        .m00_axis_tvalid (m_ax.tvalid),
        .m00_axis_tready (m_ax.tready)
    );

    // O modelo da OpenRAM imprime todo acesso com VERBOSE = 1
    defparam dut.u_in_mem.VERBOSE  = 0;
    defparam dut.u_out_mem.VERBOSE = 0;

    //-------------------------------------------------------------------------
    // Referencia: wrapper da etapa 1 (tready de entrada sempre 1; a saida
    // nao olha tready)
    //-------------------------------------------------------------------------
    wire [7:0] r_tstrb;
    isfft_axi_wrapper ref_etapa1 (
        .s00_axis_aclk    (aclk),
        .s00_axis_aresetn (aresetn),
        .s00_axis_tready  (r_in.tready),
        .s00_axis_tdata   (r_in.tdata),
        .s00_axis_tstrb   (8'hFF),
        .s00_axis_tlast   (r_in.tlast),
        .s00_axis_tvalid  (r_in.tvalid),
        .m00_axis_aclk    (aclk),
        .m00_axis_aresetn (aresetn),
        .m00_axis_tvalid  (r_out.tvalid),
        .m00_axis_tdata   (r_out.tdata),
        .m00_axis_tstrb   (r_tstrb),
        .m00_axis_tlast   (r_out.tlast),
        .m00_axis_tready  (r_out.tready)
    );
    assign r_out.tkeep = r_tstrb;
    assign r_in.tkeep  = 8'hFF;

    //-------------------------------------------------------------------------
    // Sonda (caixa-branca) e reset do caminho de dados nas interfaces
    //-------------------------------------------------------------------------
    assign probe.in_used     = dut.in_used;
    assign probe.out_used    = dut.out_used;
    assign probe.ob_n        = dut.ob_n;
    assign probe.in_avail_32 = (dut.in_avail >= 32);
    assign probe.out_free_32 = (dut.out_free >= 32);
    assign probe.dp_rst      = dut.dp_rst;
    assign s_ax.sync_rst     = dut.dp_rst;
    assign m_ax.sync_rst     = dut.dp_rst;
    assign r_in.sync_rst     = 1'b0;
    assign r_out.sync_rst    = 1'b0;

    //-------------------------------------------------------------------------
    // Assercoes internas, sem tocar no RTL
    //-------------------------------------------------------------------------
    bind isfft_axi_v4 isfft_v4_sva u_sva (
        .aclk(aclk), .aresetn(aresetn), .dp_rst(dp_rst),
        .in_used(in_used), .out_used(out_used), .reserved(reserved),
        .ob_n(ob_n), .ob_pend(ob_pend), .out_ovf(out_ovf),
        .core_push(core_push), .core_armado(core_armado),
        .launch_start(launch_start), .launch_active(launch_active));

    bind sram_1rw1r_64x64_wpr2 sram_1rw1r_sva #(.AW(6)) u_sva (
        .clk(clk0), .csb0(csb0), .web0(web0), .csb1(csb1), .addr0(addr0), .addr1(addr1));
    bind sram_1rw1r_64x256 sram_1rw1r_sva #(.AW(8)) u_sva (
        .clk(clk0), .csb0(csb0), .web0(web0), .csb1(csb1), .addr0(addr0), .addr1(addr1));

    //-------------------------------------------------------------------------
    // UVM
    //-------------------------------------------------------------------------
    // Declaracao e criacao separadas: com inicializador, 'cfg' seria uma
    // variavel estatica criada na inicializacao estatica (antes do UVM).
    isfft_env_cfg cfg;
    initial begin
        cfg = isfft_env_cfg::type_id::create("cfg");
        cfg.axil_vif    = axil;
        cfg.in_vif      = s_ax;
        cfg.out_vif     = m_ax;
        cfg.ref_in_vif  = r_in;
        cfg.ref_out_vif = r_out;
        cfg.probe_vif   = probe;
        uvm_config_db#(isfft_env_cfg)::set(null, "uvm_test_top*", "cfg", cfg);
        run_test();
    end

    // Forma de onda so quando pedida (+ONDA): no Xcelium use -access +rwc
    // e o SimVision; aqui fica o VCD para o Verilator/GTKWave.
    initial begin
        if ($test$plusargs("ONDA")) begin
            $dumpfile("isfft_uvm.vcd");
            $dumpvars(0, isfft_tb_top);
        end
    end
endmodule
