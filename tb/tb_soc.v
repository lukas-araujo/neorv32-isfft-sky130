//=============================================================================
// tb_soc.v
//
// Testbench do SoC convertido (build/neorv32_asic.v) com IMEM/DMEM em macro.
//
// - Carrega o firmware na macro da IMEM (ROM) por $readmemh.
// - Decodifica a UART0 (8N1) e imprime o que o firmware manda.
// - Encerra na linha "#FIM#". PASSA se viu "RESULTADO: OK".
// - AXI4-Lite e SLINK ficam sem escravo por enquanto (a ISFFT entra depois).
//
// Plusargs:
//   +HEX=<arquivo>     imagem do firmware (neorv32_raw_exe.hex)
//   +BAUD=<n>          baud da UART (padrao 115200)
//=============================================================================

`timescale 1ns / 1ps

module tb_soc;

    localparam real PERIODO = 20.0;          // 50 MHz -- casa com CLOCK_FREQUENCY
    localparam real LIMITE_MS = 20.0;        // tempo maximo simulado

    reg clk = 1'b0;
    always #(PERIODO/2.0) clk = ~clk;
    reg rstn = 1'b0;

    wire uart_txd;

    neorv32_asic dut (
        .clk_i(clk), .rstn_i(rstn),
        .uart0_txd_o(uart_txd), .uart0_rxd_i(1'b1),
        // AXI4-Lite: sem escravo ainda
        .m_axi_awaddr(), .m_axi_awprot(), .m_axi_awvalid(), .m_axi_awready(1'b0),
        .m_axi_wdata(), .m_axi_wstrb(), .m_axi_wvalid(), .m_axi_wready(1'b0),
        .m_axi_bresp(2'b00), .m_axi_bvalid(1'b0), .m_axi_bready(),
        .m_axi_araddr(), .m_axi_arprot(), .m_axi_arvalid(), .m_axi_arready(1'b0),
        .m_axi_rdata(32'h0), .m_axi_rresp(2'b00), .m_axi_rvalid(1'b0), .m_axi_rready(),
        // SLINK: sem ISFFT ainda
        .slink_rx_dat_i(32'h0), .slink_rx_val_i(1'b0), .slink_rx_lst_i(1'b0), .slink_rx_rdy_o(),
        .slink_tx_dat_o(), .slink_tx_val_o(), .slink_tx_lst_o(), .slink_tx_rdy_i(1'b0)
    );

    //-------------------------------------------------------------------------
    // O modelo da OpenRAM imprime TODO acesso (VERBOSE = 1): com a CPU
    // buscando instrucao a cada ciclo, sao milhoes de linhas e a simulacao
    // fica presa escrevendo log. Desligado aqui.
    //-------------------------------------------------------------------------
    defparam dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro.VERBOSE = 0;
    defparam dut.neorv32_top_inst.memory_system_neorv32_dmem_enabled_neorv32_dmem_inst.u_sram.u_macro.VERBOSE = 0;

    //-------------------------------------------------------------------------
    // Maior endereco lido da IMEM: mostra se o programa usa a metade de cima
    // da macro de 8 kB (acima de 0x1000)
    reg [31:0] imem_max = 0;
    always @(posedge clk)
        if (dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.req_stb_i &&
            !dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.req_rw_i &&
            dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.req_addr_i[12:0] > imem_max)
            imem_max <= dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.req_addr_i[12:0];

    // Carga do firmware na macro da IMEM
    //-------------------------------------------------------------------------
    reg [1023:0] hex;
    initial begin
        if (!$value$plusargs("HEX=%s", hex)) begin
            $display("[TB] ERRO: falta +HEX=<neorv32_raw_exe.hex>");
            $finish;
        end
        $readmemh(hex, dut.neorv32_top_inst
                           .memory_system_neorv32_imem_enabled_neorv32_imem_inst
                           .u_sram.u_macro.mem);
        $display("[TB] firmware: %0s", hex);
        $display("[TB] IMEM[0..2] = %h %h %h",
            dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro.mem[0],
            dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro.mem[1],
            dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro.mem[2]);
        repeat (10) @(negedge clk);
        rstn = 1'b1;
        $display("[TB] reset liberado em %0t ns", $time);
    end

    //-------------------------------------------------------------------------
    // Receptor UART 8N1
    //-------------------------------------------------------------------------
    integer baud;
    real    tbit;
    reg [7:0] ch;
    reg [8*200-1:0] linha;      // linha atual (para achar marcadores)
    integer n_linha = 0;
    reg viu_ok = 0;
    integer k;

    initial begin
        if (!$value$plusargs("BAUD=%d", baud)) baud = 115200;
        tbit = 1.0e9 / baud;
        linha = 0;
        forever begin
            @(negedge uart_txd);                 // start bit
            #(tbit * 1.5);                       // meio do bit 0
            for (k = 0; k < 8; k = k + 1) begin
                ch[k] = uart_txd;
                #(tbit);
            end
            if (ch == 8'h0A) begin
                $display("[UART] %0s", linha);
                $fflush;                         // mostra o progresso na hora
                if (linha[8*13-1:0] == "RESULTADO: OK") viu_ok = 1;
                if (linha[8*5-1:0] == "#FIM#") begin
                    $display("[TB] maior endereco lido da IMEM: 0x%h (%0s da macro)", imem_max,
                             imem_max >= 32'h1000 ? "metade de CIMA" : "so metade de baixo");
                    $display("[TB] fim em %0.3f ms (%0d ciclos)", $time/1.0e6, $time/PERIODO);
                    if (viu_ok) $display("[TB] PASSOU");
                    else        $display("[TB] FALHOU: nao viu 'RESULTADO: OK'");
                    $finish;
                end
                linha = 0;
            end else if (ch != 8'h0D) begin
                linha = {linha[8*199-1:0], ch};
            end
        end
    end

    //-------------------------------------------------------------------------
    // Vigias
    //-------------------------------------------------------------------------
    initial begin
        #(LIMITE_MS * 1.0e6);
        $display("[TB] FALHOU: tempo limite de %0.1f ms sem '#FIM#'", LIMITE_MS);
        $finish;
    end

    // a CPU tem que buscar instrucao logo depois do reset
    initial begin
        wait (rstn);
        repeat (200) @(posedge clk);
        if (^dut.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.req_addr_i === 1'bx)
            $display("[TB] AVISO: endereco da IMEM em X 200 ciclos apos o reset");
    end

endmodule
