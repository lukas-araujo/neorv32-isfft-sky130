//=============================================================================
// tb_top.v -- chip inteiro (asic_top): firmware + DMA + SLINK + ISFFT
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Referencia: uma instancia da isfft_axi_v3 -- o RTL da Kria, com as
// memorias em flip-flop -- alimentada com exatamente as palavras de 64 bits
// que a ISFFT do chip (isfft_axi_v4, memorias em macro) aceitou. Verifica o
// ENCANAMENTO novo -- DMA, SLINK, conversores 32<->64, ponte AXI, janela de
// endereco -- e a v4 lado a lado com a v3 (D21). A matematica e verificada
// pelo EVM (run_tb_evm.sh).
//
// Checagens:
//   1. saida da ISFFT do chip == saida da referencia, palavra a palavra
//   2. o firmware imprime "CHK <m> <soma>" com a soma do que CHEGOU NA DMEM;
//      o testbench calcula a mesma soma sobre a saida da referencia e compara
//      -> prova que os dados atravessaram SLINK + DMA ate a memoria intactos
//   3. "RESULTADO: OK" do firmware (ID, contadores, sem erro de tlast)
//
//   4. (opcional) "DUMP <m> <endereco>" do firmware: copia as 64 palavras
//      da DMEM a partir do endereco para <DUMP>/saida_<m>.hex (EVM, evm.py)
//
// Plusargs: +HEX=<neorv32_raw_exe.hex>  [+BAUD=115200]  [+DUMP=<pasta>]
//=============================================================================

`timescale 1ns / 1ps

module tb_top;

    localparam real PERIODO   = 20.0;     // 50 MHz
    localparam real LIMITE_MS = 30.0;
    localparam integer MAXW   = 4096;     // palavras de 64 bits guardadas

    reg clk = 1'b0;
    always #(PERIODO/2.0) clk = ~clk;
    reg rstn = 1'b0;

    wire uart_txd;

    asic_top dut (.clk_i(clk), .rstn_i(rstn), .uart0_txd_o(uart_txd), .uart0_rxd_i(1'b1));

    // caminhos longos, uma vez so
    `define IMEM dut.u_cpu.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro
    `define DMEM dut.u_cpu.neorv32_top_inst.memory_system_neorv32_dmem_enabled_neorv32_dmem_inst.u_sram.u_macro

    defparam `IMEM.VERBOSE = 0;
    defparam `DMEM.VERBOSE = 0;
    defparam dut.u_isfft.u_in_mem.VERBOSE  = 0;
    defparam dut.u_isfft.u_out_mem.VERBOSE = 0;

    //-------------------------------------------------------------------------
    // Firmware
    //-------------------------------------------------------------------------
    reg [1023:0] hex;
    initial begin
        if (!$value$plusargs("HEX=%s", hex)) begin
            $display("[TB] ERRO: falta +HEX=<neorv32_raw_exe.hex>");
            $finish;
        end
        $readmemh(hex, `IMEM.mem);
        $display("[TB] firmware: %0s", hex);
        repeat (10) @(negedge clk);
        rstn = 1'b1;
    end

    integer erros = 0;

    //-------------------------------------------------------------------------
    // Referencia: isfft_axi_v3 alimentada com o que a ISFFT do chip aceitou
    //-------------------------------------------------------------------------
    reg  [63:0] fila_d [0:MAXW-1];
    reg         fila_l [0:MAXW-1];
    integer     n_push = 0, n_pop = 0;

    reg  [5:0]  r_awaddr = 0;  reg r_awvalid = 0;  wire r_awready;
    reg  [31:0] r_wdata  = 0;  reg r_wvalid  = 0;  wire r_wready;
    wire [1:0]  r_bresp;       wire r_bvalid;
    wire [63:0] r_out;         wire r_out_val, r_out_lst;
    wire        r_in_rdy;
    wire [31:0] r_rdata;       wire r_rvalid;  wire [1:0] r_rresp;  wire r_arready;

    isfft_axi_v3 u_ref (
        .aclk(clk), .aresetn(rstn),
        .s_axi_awaddr(r_awaddr), .s_axi_awprot(3'b0), .s_axi_awvalid(r_awvalid), .s_axi_awready(r_awready),
        .s_axi_wdata(r_wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(r_wvalid), .s_axi_wready(r_wready),
        .s_axi_bresp(r_bresp), .s_axi_bvalid(r_bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(6'h0), .s_axi_arprot(3'b0), .s_axi_arvalid(1'b0), .s_axi_arready(r_arready),
        .s_axi_rdata(r_rdata), .s_axi_rresp(r_rresp), .s_axi_rvalid(r_rvalid), .s_axi_rready(1'b1),
        .s00_axis_tdata(fila_d[n_pop % MAXW]), .s00_axis_tkeep(8'hFF),
        .s00_axis_tlast(fila_l[n_pop % MAXW]),
        .s00_axis_tvalid(n_pop < n_push), .s00_axis_tready(r_in_rdy),
        .m00_axis_tdata(r_out), .m00_axis_tkeep(), .m00_axis_tlast(r_out_lst),
        .m00_axis_tvalid(r_out_val), .m00_axis_tready(1'b1)
    );

    // liga a referencia (CTRL.enable = 1) logo apos o reset
    initial begin
        wait (rstn);
        @(negedge clk);
        r_awaddr = 6'h00; r_wdata = 32'h1; r_awvalid = 1; r_wvalid = 1;
        @(posedge clk); while (!(r_awready && r_wready)) @(posedge clk);
        @(negedge clk);
        r_awvalid = 0; r_wvalid = 0;
    end

    // entrada da ISFFT do chip -> fila da referencia
    always @(posedge clk) if (rstn) begin
        if (dut.in_val && dut.in_rdy) begin
            fila_d[n_push % MAXW] <= dut.in_dat;
            fila_l[n_push % MAXW] <= dut.in_lst;
            n_push <= n_push + 1;
        end
        if ((n_pop < n_push) && r_in_rdy) n_pop <= n_pop + 1;
    end

    //-------------------------------------------------------------------------
    // Saidas: chip x referencia, palavra a palavra; soma por matriz
    //-------------------------------------------------------------------------
    reg [63:0] ref_d [0:MAXW-1];
    reg        ref_l [0:MAXW-1];
    reg [63:0] chip_d [0:MAXW-1];
    reg        chip_l [0:MAXW-1];
    integer    n_ref = 0, n_dut = 0, n_cmp = 0;
    reg [31:0] soma_ref [0:15];
    reg [31:0] s_acc = 0;
    integer    m_ref = 0;

    always @(posedge clk) if (rstn) begin
        if (r_out_val) begin
            ref_d[n_ref % MAXW] = r_out;
            ref_l[n_ref % MAXW] = r_out_lst;
            n_ref = n_ref + 1;
            // mesma soma do firmware: [31:0] primeiro, depois [63:32]
            s_acc = {s_acc[30:0], s_acc[31]} ^ r_out[31:0];
            s_acc = {s_acc[30:0], s_acc[31]} ^ r_out[63:32];
            if (r_out_lst) begin
                soma_ref[m_ref] = s_acc;
                m_ref = m_ref + 1;
                s_acc = 0;
            end
        end
        // A referencia recebe cada palavra 1 ciclo DEPOIS do chip (passa pela
        // fila do testbench), entao o chip pode sair na frente. Guarda as
        // duas saidas e compara pelo indice quando as duas existem.
        if (dut.out_val && dut.out_rdy) begin
            chip_d[n_dut % MAXW] = dut.out_dat;
            chip_l[n_dut % MAXW] = dut.out_lst;
            n_dut = n_dut + 1;
        end
        while (n_cmp < n_dut && n_cmp < n_ref) begin
            if (chip_d[n_cmp % MAXW] !== ref_d[n_cmp % MAXW] || chip_l[n_cmp % MAXW] !== ref_l[n_cmp % MAXW]) begin
                erros = erros + 1;
                if (erros <= 10)
                    $display("[TB] ERRO saida #%0d: chip %h/%b ref %h/%b", n_cmp,
                             chip_d[n_cmp % MAXW], chip_l[n_cmp % MAXW], ref_d[n_cmp % MAXW], ref_l[n_cmp % MAXW]);
            end
            n_cmp = n_cmp + 1;
        end
    end

    //-------------------------------------------------------------------------
    // UART + comparacao do CHK
    //-------------------------------------------------------------------------
    integer baud, k, m_fw;
    real    tbit;
    reg [7:0] ch;
    reg [8*200-1:0] linha;
    reg [31:0] soma_fw;
    reg viu_ok = 0;
    integer n_chk = 0;
    reg [1023:0] dump_dir;
    reg [31:0]   dump_adr;
    integer      fd, j, n_dump = 0;

    initial begin
        if (!$value$plusargs("BAUD=%d", baud)) baud = 115200;
        tbit = 1.0e9 / baud;
        linha = 0;
        forever begin
            @(negedge uart_txd);
            #(tbit * 1.5);
            for (k = 0; k < 8; k = k + 1) begin ch[k] = uart_txd; #(tbit); end
            if (ch == 8'h0A) begin
                $display("[UART] %0s", linha); $fflush;
                if ($sscanf(linha, "CHK %d 0x%h", m_fw, soma_fw) == 2) begin
                    n_chk = n_chk + 1;
                    if (m_fw >= m_ref) begin
                        erros = erros + 1;
                        $display("[TB] ERRO: firmware relatou a matriz %0d antes da referencia", m_fw);
                    end else if (soma_fw !== soma_ref[m_fw]) begin
                        erros = erros + 1;
                        $display("[TB] ERRO CHK matriz %0d: DMEM 0x%h  referencia 0x%h", m_fw, soma_fw, soma_ref[m_fw]);
                    end else
                        $display("[TB] matriz %0d: soma na DMEM = referencia (0x%h)", m_fw, soma_fw);
                end
                if ($sscanf(linha, "DUMP %d 0x%h", m_fw, dump_adr) == 2 &&
                    $value$plusargs("DUMP=%s", dump_dir)) begin
                    // DMEM em 0x8000_0000; indice da macro = endereco da palavra
                    fd = $fopen($sformatf("%0s/saida_%0d.hex", dump_dir, m_fw), "w");
                    for (j = 0; j < 64; j = j + 1)
                        $fdisplay(fd, "%h", `DMEM.mem[((dump_adr - 32'h8000_0000) >> 2) + j][31:0]);
                    $fclose(fd);
                    n_dump = n_dump + 1;
                    $display("[TB] matriz %0d: 64 palavras da DMEM (0x%h) -> saida_%0d.hex", m_fw, dump_adr, m_fw);
                end
                if (linha[8*13-1:0] == "RESULTADO: OK") viu_ok = 1;
                if (linha[8*5-1:0] == "#FIM#") begin
                    $display("[TB] palavras de 64 bits: entrada %0d, saida chip %0d, ref %0d, comparadas %0d",
                             n_push, n_dut, n_ref, n_cmp);
                    if (n_dut != n_ref || n_cmp != n_dut) begin erros = erros + 1; $display("[TB] ERRO: contagens diferentes"); end
                    if (n_chk == 0)     begin erros = erros + 1; $display("[TB] ERRO: nenhum CHK"); end
                    $display("[TB] fim em %0.3f ms", $time/1.0e6);
                    if (viu_ok && erros == 0) $display("[TB] PASSOU");
                    else                      $display("[TB] FALHOU (%0d erros, ok=%0d)", erros, viu_ok);
                    $finish;
                end
                linha = 0;
            end else if (ch != 8'h0D) linha = {linha[8*199-1:0], ch};
        end
    end

    // +DEBUG: estado do caminho de dados a cada 20 mil ciclos
    initial if ($test$plusargs("DEBUG")) forever begin
        #(20000 * PERIODO);
        $display("[TB] t=%0.2f ms  in %0d  saida chip %0d ref %0d | tx_val %b tx_rdy %b in_val %b in_rdy %b out_val %b out_rdy %b rx_val %b rx_rdy %b",
                 $time/1.0e6, n_push, n_dut, n_ref, dut.tx_val, dut.tx_rdy, dut.in_val, dut.in_rdy,
                 dut.out_val, dut.out_rdy, dut.rx_val, dut.rx_rdy);
        $fflush;
    end

    initial begin
        #(LIMITE_MS * 1.0e6);
        $display("[TB] FALHOU: tempo limite (entrada %0d, chip %0d, ref %0d)", n_push, n_dut, n_ref);
        $finish;
    end

endmodule
