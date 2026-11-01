`timescale 1ns/1ps
// =============================================================================
// tb_dft_flush.v -- teste de cadeia (flush) do isfft_axi_v4 com scan
//
// DIARIO_DFT, 1a sessao. Conferencia aberta (Icarus), antes da VM.
//
// O teste de cadeia e o primeiro padrao de qualquer ATPG: com scan_en = 1,
// cada cadeia vira um registrador de deslocamento. Entra um bit aleatorio
// por ciclo em scan_in[c]; L(c) ciclos depois ele tem de sair em
// scan_out[c]. Prova que a cadeia esta inteira, na ordem, e que a celula
// de scan desloca (inclusive as sedfxtp com DE = 0: o mux de SCE vem
// depois do mux de DE).
//
// cadeias.vh (gerado pelo run_dft_aberto.sh a partir da saida do
// costurador) define NCAD e a funcao L(c).
// Saida: "[FLUSH] cadeia c: ok" ou "ERRO", e "[FLUSH] PASSOU"/"FALHOU".
// =============================================================================
module tb_dft_flush;
`include "cadeias.vh"

    reg aclk = 0;
    always #10 aclk = ~aclk;                 // 50 MHz (mesmo do chip)

    reg              scan_en = 1'b1;
    reg  [NCAD-1:0]  scan_in = 0;
    wire [NCAD-1:0]  scan_out;

    // Funcionais parados: em deslocamento o D nao entra (SCE = 1)
    isfft_axi_v4 dut (
        .aclk(aclk), .aresetn(1'b0),
        .s_axi_awaddr(6'd0), .s_axi_awprot(3'd0), .s_axi_awvalid(1'b0), .s_axi_awready(),
        .s_axi_wdata(32'd0), .s_axi_wstrb(4'd0), .s_axi_wvalid(1'b0), .s_axi_wready(),
        .s_axi_bresp(), .s_axi_bvalid(), .s_axi_bready(1'b0),
        .s_axi_araddr(6'd0), .s_axi_arprot(3'd0), .s_axi_arvalid(1'b0), .s_axi_arready(),
        .s_axi_rdata(), .s_axi_rresp(), .s_axi_rvalid(), .s_axi_rready(1'b0),
        .s00_axis_tdata(64'd0), .s00_axis_tkeep(8'd0), .s00_axis_tlast(1'b0),
        .s00_axis_tvalid(1'b0), .s00_axis_tready(),
        .m00_axis_tdata(), .m00_axis_tkeep(), .m00_axis_tlast(), .m00_axis_tvalid(),
        .m00_axis_tready(1'b0),
        .scan_en(scan_en), .scan_in(scan_in), .scan_out(scan_out)
    );
    defparam dut.u_in_mem.VERBOSE  = 0;
    defparam dut.u_out_mem.VERBOSE = 0;

    // Acessos as macros DURANTE o deslocamento: os ponteiros e os csb vem de
    // flip-flops que estao com bits aleatorios passando por eles. A macro
    // nao tem scan; num chip real isso corrompe o conteudo e gasta energia
    // (DIARIO_DFT, 1a sessao). Contado aqui para o diario.
    integer esc_in = 0, esc_out = 0, lei_in = 0, lei_out = 0;
    always @(posedge aclk) if (scan_en) begin
        if (dut.u_in_mem.csb0  === 1'b0) esc_in  = esc_in  + 1;
        if (dut.u_out_mem.csb0 === 1'b0) esc_out = esc_out + 1;
        if (dut.u_in_mem.csb1  === 1'b0) lei_in  = lei_in  + 1;
        if (dut.u_out_mem.csb1 === 1'b0) lei_out = lei_out + 1;
    end

    localparam integer HIST = 2048;          // > maior cadeia
    reg [NCAD-1:0] hist [0:HIST-1];          // o que entrou em cada ciclo
    integer ciclo, c, lmax, erros_c, nconf;
    integer erros [0:NCAD-1];
    integer conf  [0:NCAD-1];
    integer seed = 1;
    reg esperado;

    initial begin
        lmax = 0;
        for (c = 0; c < NCAD; c = c + 1) begin
            if (L(c) > lmax) lmax = L(c);
            erros[c] = 0; conf[c] = 0;
        end
        if (lmax + 1 > HIST) begin $display("[FLUSH] ERRO: aumente HIST"); $finish; end

        for (ciclo = 0; ciclo < lmax + 300; ciclo = ciclo + 1) begin
            // muda a entrada longe da borda de subida
            @(negedge aclk);
            // confere a saida: o bit que entrou L(c) bordas atras
            if (ciclo >= lmax + 1)
            for (c = 0; c < NCAD; c = c + 1) begin
                esperado = hist[(ciclo - L(c)) % HIST][c];
                conf[c] = conf[c] + 1;
                if (scan_out[c] !== esperado) begin
                    if (erros[c] < 3)
                        $display("[FLUSH] cadeia %0d ciclo %0d: saiu %b, esperado %b",
                                 c, ciclo, scan_out[c], esperado);
                    erros[c] = erros[c] + 1;
                end
            end
            scan_in = $random(seed);
            hist[ciclo % HIST] = scan_in;
        end

        erros_c = 0;
        for (c = 0; c < NCAD; c = c + 1) begin
            $display("[FLUSH] cadeia %0d (L = %0d): %0d bits conferidos, %0d erros -> %s",
                     c, L(c), conf[c], erros[c], erros[c] ? "ERRO" : "ok");
            if (erros[c]) erros_c = erros_c + 1;
        end
        $display("[FLUSH] acessos as macros em deslocamento (%0d ciclos): in_mem %0d escritas / %0d leituras, out_mem %0d / %0d",
                 lmax + 300, esc_in, lei_in, esc_out, lei_out);
        if (erros_c == 0) $display("[FLUSH] PASSOU");
        else              $display("[FLUSH] FALHOU: %0d cadeia(s) com erro", erros_c);
        $finish;
    end
endmodule
