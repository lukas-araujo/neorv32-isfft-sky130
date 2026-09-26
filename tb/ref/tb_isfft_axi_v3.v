`timescale 1 ns / 1 ps
// =============================================================================
// tb_isfft_axi_v3
//
// Fase 1: alimenta o wrapper VALIDADO da etapa 1 (isfft_axi_wrapper) com N_MAT
//         matrizes contiguas e tready sempre 1. A saida vira a referencia.
// Fase 2: alimenta o wrapper NOVO com as mesmas matrizes, com pausas aleatorias
//         em tvalid e tready, uma parada longa do tready e um pacote truncado
//         (tlast no meio de uma matriz) injetado no meio do fluxo.
// Verifica: saida palavra a palavra, posicao do tlast, MAT_IN, MAT_OUT,
//           ERR_CNT, flag de erro e limpeza de erro.
//
// Precisa dos fontes: isfft_axi_v3.v, isfft_axi_wrapper.v (etapa 1),
//                     top_isfft.v, write_fsm.v, read_fsm.v, ifft/fft do Spiral.
// =============================================================================
module tb_isfft_axi_v3;

    parameter integer N_MAT   = 40;   // multiplo de PKT_MAT
    parameter integer PKT_MAT = 4;
    parameter integer SEED    = 7;

    localparam integer NW = N_MAT * 32;

    reg clk = 1'b0;
    always #5 clk = ~clk;              // 100 MHz
    reg rstn = 1'b0;

    integer seed;
    integer errors = 0;
    integer i, k;

    reg [63:0] stim    [0:NW-1];
    reg [63:0] ref_out [0:NW-1];
    integer    ref_cnt = 0;

    // =========================================================================
    // Referencia: wrapper da etapa 1
    // =========================================================================
    reg  [63:0] r_s_tdata  = 64'd0;
    reg         r_s_tvalid = 1'b0;
    reg         r_s_tlast  = 1'b0;
    wire        r_s_tready;
    wire [63:0] r_m_tdata;
    wire        r_m_tvalid, r_m_tlast;
    wire [7:0]  r_m_tstrb;

    isfft_axi_wrapper ref_dut (
        .s00_axis_aclk(clk), .s00_axis_aresetn(rstn),
        .s00_axis_tready(r_s_tready), .s00_axis_tdata(r_s_tdata),
        .s00_axis_tstrb(8'hFF), .s00_axis_tlast(r_s_tlast), .s00_axis_tvalid(r_s_tvalid),
        .m00_axis_aclk(clk), .m00_axis_aresetn(rstn),
        .m00_axis_tvalid(r_m_tvalid), .m00_axis_tdata(r_m_tdata),
        .m00_axis_tstrb(r_m_tstrb), .m00_axis_tlast(r_m_tlast), .m00_axis_tready(1'b1)
    );

    always @(posedge clk) begin
        if (rstn && r_m_tvalid && ref_cnt < NW) begin
            ref_out[ref_cnt] <= r_m_tdata;
            ref_cnt <= ref_cnt + 1;
        end
    end

    // =========================================================================
    // DUT: wrapper novo
    // =========================================================================
    reg  [5:0]  awaddr = 0;  reg awvalid = 0; wire awready;
    reg  [31:0] wdata  = 0;  reg [3:0] wstrb = 0; reg wvalid = 0; wire wready;
    wire [1:0]  bresp;       wire bvalid; reg bready = 0;
    reg  [5:0]  araddr = 0;  reg arvalid = 0; wire arready;
    wire [31:0] rdata;       wire [1:0] rresp; wire rvalid; reg rready = 0;

    reg  [63:0] d_s_tdata  = 64'd0;
    reg         d_s_tvalid = 1'b0;
    reg         d_s_tlast  = 1'b0;
    wire        d_s_tready;
    wire [63:0] d_m_tdata;
    wire [7:0]  d_m_tkeep;
    wire        d_m_tvalid, d_m_tlast;
    reg         d_m_tready = 1'b0;

    isfft_axi_v3 dut (
        .aclk(clk), .aresetn(rstn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(wstrb), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(bready),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(rready),
        .s00_axis_tdata(d_s_tdata), .s00_axis_tkeep(8'hFF), .s00_axis_tlast(d_s_tlast),
        .s00_axis_tvalid(d_s_tvalid), .s00_axis_tready(d_s_tready),
        .m00_axis_tdata(d_m_tdata), .m00_axis_tkeep(d_m_tkeep), .m00_axis_tlast(d_m_tlast),
        .m00_axis_tvalid(d_m_tvalid), .m00_axis_tready(d_m_tready)
    );

    // =========================================================================
    // Tarefas AXI4-Lite
    // =========================================================================
    task axil_write(input [5:0] addr, input [31:0] data);
        reg aw_done, w_done;
        begin
            @(negedge clk);
            awaddr = addr; awvalid = 1'b1;
            wdata  = data; wstrb = 4'hF; wvalid = 1'b1;
            bready = 1'b1;
            aw_done = 1'b0; w_done = 1'b0;
            while (!(aw_done && w_done)) begin
                @(posedge clk);
                if (awvalid && awready) aw_done = 1'b1;
                if (wvalid  && wready)  w_done  = 1'b1;
                @(negedge clk);
                if (aw_done) awvalid = 1'b0;
                if (w_done)  wvalid  = 1'b0;
            end
            while (!bvalid) @(negedge clk);
            @(negedge clk);
            bready = 1'b0;
        end
    endtask

    task axil_read(input [5:0] addr, output [31:0] data);
        begin
            @(negedge clk);
            araddr = addr; arvalid = 1'b1; rready = 1'b1;
            @(posedge clk);
            while (!arready) @(posedge clk);
            @(negedge clk);
            arvalid = 1'b0;
            while (!rvalid) @(negedge clk);
            data = rdata;
            @(negedge clk);
            rready = 1'b0;
        end
    endtask

    // =========================================================================
    // Monitor da saida do DUT
    // =========================================================================
    integer out_idx  = 0;
    reg     check_on = 1'b0;

    always @(posedge clk) begin
        if (check_on && d_m_tvalid && d_m_tready) begin
            if (out_idx >= NW) begin
                $display("ERRO: palavra extra na saida (%0d)", out_idx);
                errors = errors + 1;
            end else begin
                if (d_m_tdata !== ref_out[out_idx]) begin
                    if (errors < 10)
                        $display("ERRO dado: palavra %0d (matriz %0d) esperado %h obtido %h",
                                 out_idx, out_idx/32, ref_out[out_idx], d_m_tdata);
                    errors = errors + 1;
                end
                if (d_m_tlast !== (((out_idx + 1) % (PKT_MAT*32)) == 0)) begin
                    if (errors < 10)
                        $display("ERRO tlast: palavra %0d tlast=%b", out_idx, d_m_tlast);
                    errors = errors + 1;
                end
            end
            out_idx = out_idx + 1;
        end
    end

    // tready aleatorio (~75%) com uma parada longa
    integer cyc = 0;
    always @(negedge clk) begin
        if (!check_on) begin
            cyc = 0;
            d_m_tready = 1'b0;
        end else begin
            cyc = cyc + 1;
        end
        if (!check_on)
            d_m_tready = 1'b0;
        else if (cyc > 1500 && cyc < 6500) // parada longa: enche a FIFO e forca backpressure
            d_m_tready = 1'b0;
        else
            d_m_tready = (({$random(seed)} % 4) != 0);
    end

    // =========================================================================
    // Envio de uma palavra no DUT com pausa aleatoria antes
    // =========================================================================
    task dut_send(input [63:0] data, input last);
        integer gap;
        begin
            gap = {$random(seed)} % 3;
            if (({$random(seed)} % 20) == 0) gap = 40;   // pausa grande ocasional
            while (gap > 0) begin
                @(negedge clk);
                d_s_tvalid = 1'b0;
                gap = gap - 1;
            end
            @(negedge clk);
            d_s_tdata = data; d_s_tlast = last; d_s_tvalid = 1'b1;
            @(posedge clk);
            while (!d_s_tready) @(posedge clk);
            @(negedge clk);
            d_s_tvalid = 1'b0; d_s_tlast = 1'b0;
        end
    endtask

    // =========================================================================
    // Sequencia principal
    // =========================================================================
    reg [31:0] rv;
    integer timeout;

    initial begin
        seed = SEED;
        for (i = 0; i < NW; i = i + 1)
            stim[i] = {$random(seed), $random(seed)};

        repeat (20) @(posedge clk);
        rstn = 1'b1;
        repeat (10) @(posedge clk);

        // ---------------- Fase 1: referencia ----------------
        $display("Fase 1: gerando referencia com o wrapper da etapa 1...");
        for (i = 0; i < NW; i = i + 1) begin
            @(negedge clk);
            r_s_tdata  = stim[i];
            r_s_tvalid = 1'b1;
            r_s_tlast  = (i == NW-1);
        end
        @(negedge clk);
        r_s_tvalid = 1'b0; r_s_tlast = 1'b0;

        timeout = 0;
        while (ref_cnt < NW && timeout < 100000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        if (ref_cnt < NW) begin
            $display("FALHA: referencia gerou so %0d de %0d palavras", ref_cnt, NW);
            $finish;
        end
        $display("  referencia: %0d palavras", ref_cnt);

        // ---------------- Fase 2: DUT ----------------
        $display("Fase 2: wrapper novo com pausas aleatorias...");
        axil_read(6'h14, rv);
        if (rv !== 32'h15FF0300) begin
            $display("ERRO: ID = %h", rv); errors = errors + 1;
        end
        axil_write(6'h18, PKT_MAT);
        axil_write(6'h00, 32'h1);          // enable
        check_on = 1'b1;

        for (i = 0; i < NW; i = i + 1) begin
            // pacote truncado injetado antes da matriz N_MAT/2
            if (i == (N_MAT/2)*32) begin
                $display("  injetando pacote truncado (20 palavras com tlast)");
                for (k = 0; k < 20; k = k + 1)
                    dut_send(64'hDEADBEEF_00000000 | k, (k == 19));
            end
            dut_send(stim[i], (((i + 1) % (PKT_MAT*32)) == 0));
        end

        timeout = 0;
        while (out_idx < NW && timeout < 400000) begin
            @(posedge clk); timeout = timeout + 1;
        end
        repeat (200) @(posedge clk);

        if (out_idx != NW) begin
            $display("ERRO: saida teve %0d palavras, esperado %0d", out_idx, NW);
            errors = errors + 1;
        end

        axil_read(6'h08, rv);
        if (rv != N_MAT) begin $display("ERRO: MAT_IN = %0d", rv); errors = errors + 1; end
        axil_read(6'h0C, rv);
        if (rv != N_MAT) begin $display("ERRO: MAT_OUT = %0d", rv); errors = errors + 1; end
        axil_read(6'h10, rv);
        if (rv != 1) begin $display("ERRO: ERR_CNT = %0d (esperado 1)", rv); errors = errors + 1; end
        axil_read(6'h04, rv);
        if (rv[8] !== 1'b1) begin $display("ERRO: flag de erro tlast nao setada"); errors = errors + 1; end
        if (rv[9] !== 1'b0) begin $display("ERRO: overflow interno!"); errors = errors + 1; end
        if (rv[0] !== 1'b0) begin $display("ERRO: busy ainda ativo"); errors = errors + 1; end

        axil_write(6'h00, 32'h5);          // enable + limpa erros
        axil_read(6'h04, rv);
        if (rv[8] !== 1'b0) begin $display("ERRO: flag nao limpou"); errors = errors + 1; end
        axil_read(6'h10, rv);
        if (rv != 0) begin $display("ERRO: ERR_CNT nao zerou"); errors = errors + 1; end

        if (errors == 0)
            $display("PASSOU: %0d matrizes identicas a referencia, tlast e registradores OK", N_MAT);
        else
            $display("FALHOU: %0d erros", errors);
        $finish;
    end

endmodule
