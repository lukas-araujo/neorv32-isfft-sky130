`timescale 1ns/1ps
// =============================================================================
// tb_isfft_modo_teste.v -- o IP da ISFFT em MODO DE TESTE, no netlist com scan
//
// DIARIO_DFT, 3a sessao (T13). Ideia do Prof. Gilmar: sem o Modus (licenca,
// bloco 3), fazer "na mao", em simulacao, o que um padrao de ATPG faz:
// carregar um estado pelas cadeias (scan_en = 1), dar UM pulso de captura
// (scan_en = 0), descarregar e comparar com o esperado.
//
// Testes:
//   A. Integridade das cadeias: carrega 12.5xx bits aleatorios e descarrega
//      -- tem de voltar tudo igual (e o 1o padrao de qualquer ATPG).
//   B. OBSERVAR: o IP trabalha no modo normal (registradores pelo AXI-Lite,
//      3 matrizes pela entrada) e depois o estado interno e lido PELAS
//      CADEIAS: contadores e registradores aparecem nos pinos scan_out.
//   C. CONTROLAR: um estado e escrito PELAS CADEIAS (PKT_MAT, MAT_IN) e lido
//      pelo barramento AXI-Lite, no modo normal.
//   D. PADRAO DE CAPTURA (o que o ATPG gera): estado carregado de modo que,
//      com uma palavra entrando, a matriz feche; um pulso de captura;
//      descarga: mat_in_cnt 0xFF -> 0x100 (o carry anda 8 bits), in_wcnt
//      31 -> 0, ponteiros 0 -> 1.
//   E. FALHA: stuck-at-0 no pino D de mat_in_cnt[8] (`PINO_FALHA, do mapa).
//      E1: o teste A (so deslocamento) NAO a ve -- o pino D nao esta no
//          caminho de scan;
//      E2: o padrao D a ve: o bit 8 sai 0 em vez de 1 -> "falha detectada".
//      E a diferenca entre teste de cadeia e teste de logica.
//
// mapa_cadeias.vh: gerado por sim/dft/mapa_cadeias.py a partir do NETLIST
// (cadeia e posicao de cada bit; o pino da falha). Netlist do Genus: portas
// scan_in_<i>/scan_out_<i>. Netlist de conferencia (sim/dft/dft_costura.py):
// barramentos -- compilar com -define SCAN_BARRAMENTO.
//
// Saida: "[MT] <teste>: PASSOU/FALHOU ..." e "[MT] RESULTADO: TUDO OK".
// =============================================================================
module tb_isfft_modo_teste;
`include "mapa_cadeias.vh"

    reg aclk = 0;
    always #10 aclk = ~aclk;                 // 50 MHz

    reg         aresetn = 1'b0;
    reg  [5:0]  awaddr = 0, araddr = 0;
    reg         awvalid = 0, wvalid = 0, arvalid = 0;
    reg  [31:0] wdata = 0;
    wire        awready, wready, bvalid, arready, rvalid;
    wire [1:0]  bresp, rresp;
    wire [31:0] rdata;
    reg  [63:0] s_tdata = 0;
    reg         s_tlast = 0, s_tvalid = 0;
    wire        s_tready;
    wire [63:0] m_tdata;
    wire [7:0]  m_tkeep;
    wire        m_tlast, m_tvalid;
    reg         m_tready = 1'b1;

    reg         scan_en = 1'b0;
    reg  [15:0] si = 0;
    wire [15:0] so;

    isfft_axi_v4 dut (
        .aclk(aclk), .aresetn(aresetn),
        .s_axi_awaddr(awaddr), .s_axi_awprot(3'd0), .s_axi_awvalid(awvalid), .s_axi_awready(awready),
        .s_axi_wdata(wdata), .s_axi_wstrb(4'hF), .s_axi_wvalid(wvalid), .s_axi_wready(wready),
        .s_axi_bresp(bresp), .s_axi_bvalid(bvalid), .s_axi_bready(1'b1),
        .s_axi_araddr(araddr), .s_axi_arprot(3'd0), .s_axi_arvalid(arvalid), .s_axi_arready(arready),
        .s_axi_rdata(rdata), .s_axi_rresp(rresp), .s_axi_rvalid(rvalid), .s_axi_rready(1'b1),
        .s00_axis_tdata(s_tdata), .s00_axis_tkeep(8'hFF), .s00_axis_tlast(s_tlast),
        .s00_axis_tvalid(s_tvalid), .s00_axis_tready(s_tready),
        .m00_axis_tdata(m_tdata), .m00_axis_tkeep(m_tkeep), .m00_axis_tlast(m_tlast),
        .m00_axis_tvalid(m_tvalid), .m00_axis_tready(m_tready),
`ifdef SCAN_BARRAMENTO
        .scan_en(scan_en), .scan_in(si), .scan_out(so)
`else
        .scan_en(scan_en),
        .scan_in_0(si[0]),   .scan_in_1(si[1]),   .scan_in_2(si[2]),   .scan_in_3(si[3]),
        .scan_in_4(si[4]),   .scan_in_5(si[5]),   .scan_in_6(si[6]),   .scan_in_7(si[7]),
        .scan_in_8(si[8]),   .scan_in_9(si[9]),   .scan_in_10(si[10]), .scan_in_11(si[11]),
        .scan_in_12(si[12]), .scan_in_13(si[13]), .scan_in_14(si[14]), .scan_in_15(si[15]),
        .scan_out_0(so[0]),   .scan_out_1(so[1]),   .scan_out_2(so[2]),   .scan_out_3(so[3]),
        .scan_out_4(so[4]),   .scan_out_5(so[5]),   .scan_out_6(so[6]),   .scan_out_7(so[7]),
        .scan_out_8(so[8]),   .scan_out_9(so[9]),   .scan_out_10(so[10]), .scan_out_11(so[11]),
        .scan_out_12(so[12]), .scan_out_13(so[13]), .scan_out_14(so[14]), .scan_out_15(so[15])
`endif
    );
    defparam dut.u_in_mem.VERBOSE  = 0;
    defparam dut.u_out_mem.VERBOSE = 0;

    // -------------------------------------------------------------------------
    // Imagens das cadeias: carga[c][p] = bit que vai para a posicao p da
    // cadeia c; lido[c][p] = o que saiu dela na descarga
    // -------------------------------------------------------------------------
    localparam integer LMAXA = 1024;
    reg carga [0:15][0:LMAXA-1];
    reg lido  [0:15][0:LMAXA-1];
    integer lmax, c, p, k, erros, total_erros, seed;

    // Registradores pelo numero (as funcoes <reg>_C/_P vem do mapa)
    localparam R_MAT_IN = 0, R_MAT_OUT = 1, R_ERR = 2, R_PKT = 3, R_WCNT = 4,
               R_WPTR = 5, R_WCOMMIT = 6, R_RPTR = 7, R_EN = 8, R_SRST = 9;
    function integer CC(input integer r, input integer i);
        case (r)
            R_MAT_IN: CC = mat_in_cnt_C(i);   R_MAT_OUT: CC = mat_out_cnt_C(i);
            R_ERR:    CC = err_cnt_C(i);      R_PKT:     CC = pkt_mat_C(i);
            R_WCNT:   CC = in_wcnt_C(i);      R_WPTR:    CC = in_wr_ptr_C(i);
            R_WCOMMIT:CC = in_wr_commit_C(i); R_RPTR:    CC = in_rd_ptr_C(i);
            R_EN:     CC = ctrl_enable_C(i);  R_SRST:    CC = ctrl_soft_rst_C(i);
            default:  CC = -1;
        endcase
    endfunction
    function integer PP(input integer r, input integer i);
        case (r)
            R_MAT_IN: PP = mat_in_cnt_P(i);   R_MAT_OUT: PP = mat_out_cnt_P(i);
            R_ERR:    PP = err_cnt_P(i);      R_PKT:     PP = pkt_mat_P(i);
            R_WCNT:   PP = in_wcnt_P(i);      R_WPTR:    PP = in_wr_ptr_P(i);
            R_WCOMMIT:PP = in_wr_commit_P(i); R_RPTR:    PP = in_rd_ptr_P(i);
            R_EN:     PP = ctrl_enable_P(i);  R_SRST:    PP = ctrl_soft_rst_P(i);
            default:  PP = -1;
        endcase
    endfunction

    task zera_carga;
        begin
            for (c = 0; c < 16; c = c + 1)
                for (p = 0; p < LMAXA; p = p + 1) carga[c][p] = 1'b0;
        end
    endtask

    task poe(input integer r, input integer larg, input [31:0] v);
        integer i;
        begin
            for (i = 0; i < larg; i = i + 1) carga[CC(r, i)][PP(r, i)] = v[i];
        end
    endtask

    function [31:0] le(input integer r, input integer larg);
        integer i;
        begin
            le = 32'd0;
            for (i = 0; i < larg; i = i + 1) le[i] = lido[CC(r, i)][PP(r, i)];
        end
    endfunction

    // -------------------------------------------------------------------------
    // Deslocamento: lmax ciclos com scan_en = 1. Carrega 'carga' e, ao mesmo
    // tempo, descarrega o estado anterior em 'lido' (como o testador faz:
    // o padrao seguinte entra enquanto a resposta do anterior sai).
    // Cadeias mais curtas: os primeiros (lmax - L) bits caem fora.
    // Entradas mudam na borda de descida; scan_out e lido nela tambem.
    // fica = 1: termina com scan_en = 1, para emendar outro deslocamento sem
    // nenhuma borda com scan_en = 0 no meio -- essa borda seria uma CAPTURA
    // e trocaria o estado carregado pela resposta da logica (3a sessao: foi
    // o que reprovou a 1a versao do teste A).
    // -------------------------------------------------------------------------
    task desloca(input integer fica);
        begin
            if (!scan_en) @(negedge aclk);   // emendado: ja estamos na descida certa
            scan_en  = 1'b1;
            s_tvalid = 1'b0; arvalid = 1'b0; awvalid = 1'b0; wvalid = 1'b0;
            for (k = 0; k < lmax; k = k + 1) begin
                if (k > 0) @(negedge aclk);
                for (c = 0; c < NCAD; c = c + 1) begin
                    if (k < L(c)) lido[c][L(c) - 1 - k] = so[c];
                    si[c] = (lmax - 1 - k < L(c)) ? carga[c][lmax - 1 - k] : 1'b0;
                end
            end
            @(negedge aclk);                 // a ultima borda de subida ja deslocou
            if (!fica) scan_en = 1'b0;
            si = 16'd0;
        end
    endtask

    // Um pulso de captura (scan_en = 0 desde a descida anterior)
    task captura;
        begin
            @(posedge aclk);
            @(negedge aclk);
        end
    endtask

    // -------------------------------------------------------------------------
    // Modo normal: AXI-Lite e AXI-Stream
    // -------------------------------------------------------------------------
    task axi_escreve(input [5:0] a, input [31:0] d);
        begin
            @(negedge aclk); awaddr = a; wdata = d; awvalid = 1; wvalid = 1;
            @(negedge aclk); awvalid = 0; wvalid = 0;
            while (!bvalid) @(negedge aclk);
            @(negedge aclk);
        end
    endtask

    task axi_le(input [5:0] a, output [31:0] d);
        begin
            @(negedge aclk); araddr = a; arvalid = 1;
            @(negedge aclk); arvalid = 0;
            while (!rvalid) @(negedge aclk);
            d = rdata;
            @(negedge aclk);
        end
    endtask

    task manda_palavras(input integer n);
        integer i;
        begin
            i = 0;
            while (i < n) begin
                @(negedge aclk);
                s_tvalid = 1'b1;
                s_tdata  = {$random(seed), $random(seed)} & 64'h3FFF3FFF3FFF3FFF;
                s_tlast  = (i % 32) == 31;
                if (s_tready) i = i + 1;
            end
            @(negedge aclk); s_tvalid = 1'b0; s_tlast = 1'b0;
        end
    endtask

    task confere(input [8*24-1:0] nome, input [31:0] obtido, input [31:0] esperado);
        begin
            if (obtido === esperado)
                $display("[MT]     %0s = 0x%0h  (esperado 0x%0h) ok", nome, obtido, esperado);
            else begin
                $display("[MT]     %0s = 0x%0h  (esperado 0x%0h) ERRO", nome, obtido, esperado);
                erros = erros + 1;
            end
        end
    endtask

    task resultado(input [8*64-1:0] nome);
        begin
            $display("[MT] %0s: %s (%0d erro(s))", nome, erros ? "FALHOU" : "PASSOU", erros);
            total_erros = total_erros + erros;
            erros = 0;
        end
    endtask

    // Padrao D: carga, captura, descarga; devolve os erros em 'erros'
    task padrao_d;
        begin
            zera_carga;
            poe(R_MAT_IN, 32, 32'h0000_00FF);
            poe(R_WCNT,    5, 5'd31);
            desloca(0);                       // carrega
            aresetn  = 1'b1;                  // entradas da captura
            s_tvalid = 1'b1; s_tlast = 1'b0; s_tdata = 64'h0123_4567_89AB_CDEF;
            captura;
            s_tvalid = 1'b0;
            zera_carga;
            desloca(0);                       // descarrega
            confere("mat_in_cnt",   le(R_MAT_IN, 32),  32'h0000_0100);
            confere("in_wcnt",      le(R_WCNT, 5),     32'd0);
            confere("in_wr_ptr",    le(R_WPTR, 7),     32'd1);
            confere("in_wr_commit", le(R_WCOMMIT, 7),  32'd1);
            confere("err_cnt",      le(R_ERR, 32),     32'd0);
        end
    endtask

    reg [31:0] v;

    initial begin
        seed = 7; erros = 0; total_erros = 0;
        lmax = 0;
        for (c = 0; c < NCAD; c = c + 1) if (L(c) > lmax) lmax = L(c);
        $display("[MT] %0d cadeias, maior com %0d flip-flops", NCAD, lmax);

        // ---------------- A. integridade das cadeias ----------------
        for (c = 0; c < 16; c = c + 1)
            for (p = 0; p < LMAXA; p = p + 1) carga[c][p] = $random(seed);
        desloca(1);                           // carrega aleatorio
        zera_carga;
        desloca(0);                           // descarrega (e zera), emendado
        for (c = 0; c < 16; c = c + 1)
            for (p = 0; p < LMAXA; p = p + 1) carga[c][p] = 0;
        // compara com a carga aleatoria de novo (mesma semente)
        seed = 7;
        for (c = 0; c < 16; c = c + 1)
            for (p = 0; p < LMAXA; p = p + 1) begin
                v[0] = $random(seed);
                if (c < NCAD && p < L(c) && lido[c][p] !== v[0]) erros = erros + 1;
            end
        $display("[MT]     %0d bits carregados e descarregados", lmax * NCAD);
        resultado("A. integridade das cadeias");

        // ---------------- B. observar pelo scan ----------------
        seed = 11;
        aresetn = 1'b0;
        repeat (20) @(negedge aclk);
        aresetn = 1'b1;
        axi_escreve(6'h18, 32'd5);            // PKT_MAT = 5
        axi_escreve(6'h00, 32'd1);            // CTRL: enable
        manda_palavras(96);                   // 3 matrizes
        repeat (50) @(negedge aclk);
        zera_carga;
        desloca(0);                           // descarrega o estado do modo normal
        confere("mat_in_cnt",   le(R_MAT_IN, 32), 32'd3);
        confere("pkt_mat",      le(R_PKT, 16),    32'd5);
        confere("ctrl_enable",  le(R_EN, 1),      32'd1);
        confere("in_wr_ptr",    le(R_WPTR, 7),    32'd96);
        confere("in_wr_commit", le(R_WCOMMIT, 7), 32'd96);
        confere("in_wcnt",      le(R_WCNT, 5),    32'd0);
        resultado("B. observar: estado lido pelas cadeias");

        // ---------------- C. controlar pelo scan ----------------
        zera_carga;
        poe(R_PKT,    16, 16'hBEEF);
        poe(R_MAT_IN, 32, 32'h1234_5678);
        desloca(0);                           // escreve pelo scan
        aresetn = 1'b1;
        axi_le(6'h18, v); confere("PKT_MAT (AXI)", v, 32'h0000_BEEF);
        axi_le(6'h08, v); confere("MAT_IN (AXI)",  v, 32'h1234_5678);
        resultado("C. controlar: escrito pelas cadeias, lido no AXI");

        // ---------------- D. padrao de captura ----------------
        padrao_d;
        resultado("D. padrao de captura (carga, 1 pulso, descarga)");

        // ---------------- E. falha stuck-at-0 em mat_in_cnt[8].D ----------------
        force `PINO_FALHA = 1'b0;
        $display("[MT] falha injetada: stuck-at-0 no pino D de mat_in_cnt[8]");
        erros = 0;
        // E1: o deslocamento puro nao passa pelo pino D -> nenhum erro esperado
        begin : e1
            integer s2, e1_erros;
            s2 = 13; e1_erros = 0;
            for (c = 0; c < 16; c = c + 1)
                for (p = 0; p < LMAXA; p = p + 1) carga[c][p] = $random(s2);
            desloca(1); zera_carga; desloca(0);
            s2 = 13;
            for (c = 0; c < 16; c = c + 1)
                for (p = 0; p < LMAXA; p = p + 1) begin
                    v[0] = $random(s2);
                    if (c < NCAD && p < L(c) && lido[c][p] !== v[0]) e1_erros = e1_erros + 1;
                end
            if (e1_erros == 0)
                $display("[MT] E1. teste de cadeia com a falha: passou -- NAO enxerga a falha (esperado: o pino D nao esta no caminho de scan)");
            else begin
                $display("[MT] E1. teste de cadeia com a falha: %0d erros (inesperado)", e1_erros);
                total_erros = total_erros + 1;
            end
        end
        // E2: o padrao D tem de reprovar no bit 8
        padrao_d;
        if (erros > 0 && le(R_MAT_IN, 32) === 32'h0000_0000) begin
            $display("[MT] E2. padrao de captura com a falha: mat_in_cnt = 0x0 em vez de 0x100 -> FALHA DETECTADA");
            erros = 0;
        end else if (erros > 0) begin
            $display("[MT] E2. padrao de captura com a falha: reprovou (mat_in_cnt = 0x%0h) -> FALHA DETECTADA", le(R_MAT_IN, 32));
            erros = 0;
        end else begin
            $display("[MT] E2. padrao de captura com a falha: passou -> falha NAO detectada (ERRO do teste)");
            total_erros = total_erros + 1;
        end
        release `PINO_FALHA;

        if (total_erros == 0) $display("[MT] RESULTADO: TUDO OK");
        else                  $display("[MT] RESULTADO: FALHOU (%0d)", total_erros);
        $finish;
    end
endmodule
