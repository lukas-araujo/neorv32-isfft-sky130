//=============================================================================
// tb_stream.v -- conversores stream_32to64 e stream_64to32
//
// Tres bancadas no mesmo arquivo, cada uma com gerador aleatorio de
// valid/ready e um modelo de referencia (vetor de palavras esperadas):
//
//   A. 32 -> 64 : palavras de 32 com 'last' (a maioria em posicao par,
//                 algumas em posicao impar = pacote truncado)
//   B. 64 -> 32 : palavras de 64 com tlast aleatorio
//   C. volta completa 32 -> 64 -> 32: a saida tem que ser IDENTICA a
//      entrada (dado e last), com pacotes de tamanho par
//
// Confere dado, last, e que nada se perde nem se duplica (contagem).
//=============================================================================

`timescale 1ns / 1ps

module tb_stream;

    parameter integer N    = 20000;   // palavras por bancada
    parameter integer SEED = 3;

    reg clk = 0;
    always #5 clk = ~clk;
    reg rstn = 0;
    integer seed;
    integer erros = 0;

    //=========================================================================
    // A. 32 -> 64
    //=========================================================================
    reg  [31:0] a_din;  reg a_vin, a_lin;  wire a_rdy;
    wire [63:0] a_dout; wire a_vout, a_lout; reg a_rin;

    stream_32to64 dut_a (.clk_i(clk), .rstn_i(rstn),
        .s_data_i(a_din), .s_valid_i(a_vin), .s_last_i(a_lin), .s_ready_o(a_rdy),
        .m_data_o(a_dout), .m_valid_o(a_vout), .m_last_o(a_lout), .m_ready_i(a_rin));

    reg [31:0] a_src_d [0:N-1];  reg a_src_l [0:N-1];
    reg [63:0] a_exp_d [0:N-1];  reg a_exp_l [0:N-1];
    integer a_nexp, a_tx = 0, a_rx = 0;

    //=========================================================================
    // B. 64 -> 32
    //=========================================================================
    reg  [63:0] b_din;  reg b_vin, b_lin;  wire b_rdy;
    wire [31:0] b_dout; wire b_vout, b_lout; reg b_rin;

    stream_64to32 dut_b (.clk_i(clk), .rstn_i(rstn),
        .s_data_i(b_din), .s_valid_i(b_vin), .s_last_i(b_lin), .s_ready_o(b_rdy),
        .m_data_o(b_dout), .m_valid_o(b_vout), .m_last_o(b_lout), .m_ready_i(b_rin));

    reg [63:0] b_src_d [0:N-1];  reg b_src_l [0:N-1];
    integer b_tx = 0, b_rx = 0;

    //=========================================================================
    // C. 32 -> 64 -> 32 (volta completa)
    //=========================================================================
    reg  [31:0] c_din;  reg c_vin, c_lin;  wire c_rdy;
    wire [63:0] c_mid;  wire c_vmid, c_lmid, c_rmid;
    wire [31:0] c_dout; wire c_vout, c_lout; reg c_rin;

    stream_32to64 dut_c1 (.clk_i(clk), .rstn_i(rstn),
        .s_data_i(c_din), .s_valid_i(c_vin), .s_last_i(c_lin), .s_ready_o(c_rdy),
        .m_data_o(c_mid), .m_valid_o(c_vmid), .m_last_o(c_lmid), .m_ready_i(c_rmid));
    stream_64to32 dut_c2 (.clk_i(clk), .rstn_i(rstn),
        .s_data_i(c_mid), .s_valid_i(c_vmid), .s_last_i(c_lmid), .s_ready_o(c_rmid),
        .m_data_o(c_dout), .m_valid_o(c_vout), .m_last_o(c_lout), .m_ready_i(c_rin));

    reg [31:0] c_src_d [0:N-1];  reg c_src_l [0:N-1];
    integer c_tx = 0, c_rx = 0;

    //=========================================================================
    // Geracao dos vetores
    //=========================================================================
    integer i, cnt, n_impar = 0;
    initial begin
        seed = SEED;
        // A: pacotes de tamanho aleatorio; ~10% deles com tamanho impar
        cnt = 0;
        for (i = 0; i < N; i = i + 1) begin
            a_src_d[i] = $random(seed);
            cnt = cnt + 1;
            a_src_l[i] = (i == N-1) ||
                         ((cnt % 2 == 0) && (($random(seed) & 15) == 0)) ||
                         ((cnt % 2 == 1) && (($random(seed) & 63) == 0));
            if (a_src_l[i]) begin
                if (cnt % 2) n_impar = n_impar + 1;
                cnt = 0;
            end
        end
        // modelo de A
        a_nexp = 0; cnt = 0;
        for (i = 0; i < N; i = i + 1) begin
            if (cnt == 0) begin
                if (a_src_l[i]) begin
                    a_exp_d[a_nexp] = {32'h0, a_src_d[i]}; a_exp_l[a_nexp] = 1; a_nexp = a_nexp + 1;
                end else cnt = 1;
            end else begin
                a_exp_d[a_nexp] = {a_src_d[i], a_src_d[i-1]}; a_exp_l[a_nexp] = a_src_l[i];
                a_nexp = a_nexp + 1; cnt = 0;
            end
        end
        // B
        for (i = 0; i < N; i = i + 1) begin
            b_src_d[i] = {$random(seed), $random(seed)};
            b_src_l[i] = (($random(seed) & 7) == 0);
        end
        // C: pacotes de tamanho PAR (senao a volta nao e identica por definicao)
        cnt = 0;
        for (i = 0; i < N; i = i + 1) begin
            c_src_d[i] = $random(seed);
            cnt = cnt + 1;
            c_src_l[i] = (cnt % 2 == 0) && ((($random(seed) & 15) == 0) || (i >= N-2));
            if (c_src_l[i]) cnt = 0;
        end
        c_src_l[N-1] = 1;   // N par: fecha o ultimo pacote
    end

    //=========================================================================
    // Estimulo e checagem (entradas mudam na descida, amostragem na subida)
    //
    // A fonte so troca de palavra se o handshake ACONTECEU na subida
    // anterior (flags *_ok). Olhar o ready na descida esta errado: o ready
    // de saida e sorteado de novo nessa mesma descida e o s_ready depende
    // dele -- a fonte trocaria uma palavra que nao foi aceita.
    //=========================================================================
    reg a_ok = 0, b_ok = 0, c_ok = 0;

    always @(negedge clk) begin
        // valid da fonte: 70% do tempo; ready do sorvedouro: 60%, com rajadas
        if (!a_vin || a_ok) begin
            a_vin = (a_tx < N) && (($random(seed) % 10) < 7);
            if (a_vin) begin a_din = a_src_d[a_tx]; a_lin = a_src_l[a_tx]; end
        end
        a_rin = (($random(seed) % 10) < 6);

        if (!b_vin || b_ok) begin
            b_vin = (b_tx < N) && (($random(seed) % 10) < 7);
            if (b_vin) begin b_din = b_src_d[b_tx]; b_lin = b_src_l[b_tx]; end
        end
        b_rin = (($random(seed) % 10) < 6);

        if (!c_vin || c_ok) begin
            c_vin = (c_tx < N) && (($random(seed) % 10) < 7);
            if (c_vin) begin c_din = c_src_d[c_tx]; c_lin = c_src_l[c_tx]; end
        end
        c_rin = (($random(seed) % 10) < 6);
    end

    task erro(input [8*40-1:0] msg);
        begin
            erros = erros + 1;
            if (erros <= 10) $display("[%0t] ERRO %0s", $time, msg);
        end
    endtask

    always @(posedge clk) if (rstn) begin
        a_ok = a_vin && a_rdy;
        b_ok = b_vin && b_rdy;
        c_ok = c_vin && c_rdy;
        // ---- A ----
        if (a_ok) a_tx = a_tx + 1;
        if (a_vout && a_rin) begin
            if (a_rx >= a_nexp) erro("A: palavra a mais");
            else if (a_dout !== a_exp_d[a_rx] || a_lout !== a_exp_l[a_rx]) begin
                erro("A: dado/last errado");
                if (erros <= 10) $display("      #%0d: saiu %h/%b esperado %h/%b",
                    a_rx, a_dout, a_lout, a_exp_d[a_rx], a_exp_l[a_rx]);
            end
            a_rx = a_rx + 1;
        end
        // ---- B ----
        if (b_ok) b_tx = b_tx + 1;
        if (b_vout && b_rin) begin
            if ((b_rx/2) >= N) erro("B: palavra a mais");
            else if (b_dout !== (b_rx % 2 ? b_src_d[b_rx/2][63:32] : b_src_d[b_rx/2][31:0]) ||
                     b_lout !== ((b_rx % 2) ? b_src_l[b_rx/2] : 1'b0)) begin
                erro("B: dado/last errado");
                if (erros <= 10) $display("      #%0d: saiu %h/%b", b_rx, b_dout, b_lout);
            end
            b_rx = b_rx + 1;
        end
        // ---- C ----
        if (c_ok) c_tx = c_tx + 1;
        if (c_vout && c_rin) begin
            if (c_rx >= N) erro("C: palavra a mais");
            else if (c_dout !== c_src_d[c_rx] || c_lout !== c_src_l[c_rx]) begin
                erro("C: volta diferente da entrada");
                if (erros <= 10) $display("      #%0d: saiu %h/%b esperado %h/%b",
                    c_rx, c_dout, c_lout, c_src_d[c_rx], c_src_l[c_rx]);
            end
            c_rx = c_rx + 1;
        end
    end

    initial begin
        a_vin = 0; b_vin = 0; c_vin = 0; a_rin = 0; b_rin = 0; c_rin = 0;
        repeat (3) @(negedge clk);
        rstn = 1;
        wait (a_rx == a_nexp && b_rx == 2*N && c_rx == N);
        repeat (20) @(posedge clk);   // nada pode sair depois do fim
        $display("[TB] A: %0d palavras de 32 -> %0d de 64 (%0d pacotes impares)", N, a_rx, n_impar);
        $display("[TB] B: %0d palavras de 64 -> %0d de 32", N, b_rx);
        $display("[TB] C: %0d palavras de 32, volta completa", c_rx);
        if (a_rx != a_nexp || b_rx != 2*N || c_rx != N) erro("contagem final");
        if (erros == 0) $display("[TB] PASSOU"); else $display("[TB] FALHOU: %0d erros", erros);
        $finish;
    end

    initial begin
        #(N * 100 * 10);
        $display("[TB] FALHOU: travou (A %0d/%0d, B %0d/%0d, C %0d/%0d)",
                 a_rx, a_nexp, b_rx, 2*N, c_rx, N);
        $finish;
    end

endmodule
