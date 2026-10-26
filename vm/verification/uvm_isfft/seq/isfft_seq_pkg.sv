//=============================================================================
// isfft_seq_pkg.sv -- sequencias
//
// Nivel de palavra (roda no sequenciador AXI-Stream de entrada):
//   isfft_palavras_seq   manda N palavras com pausas sorteadas
// Nivel de cenario (sequencias virtuais, rodam no isfft_vsequencer):
//   isfft_base_vseq      tarefas comuns: configura, manda matriz/pacote,
//                        pacote truncado, soft reset, espera esvaziar,
//                        confere registradores
//   isfft_*_vseq         um cenario por teste
//=============================================================================
package isfft_seq_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axil_pkg::*;
    import axis_pkg::*;
    import isfft_env_pkg::*;

    //=========================================================================
    class isfft_palavras_seq extends uvm_sequence #(axis_item);
        `uvm_object_utils(isfft_palavras_seq)

        bit [63:0] dados[$];
        int        pos_last = -1;    // indice da palavra com tlast (-1: nenhuma)
        // Pausas: chance (%) de pausa antes de cada palavra, e o tamanho
        int unsigned pausa_pct   = 0;
        int unsigned pausa_max   = 2;
        int unsigned longa_pct   = 0;    // chance de uma pausa longa (40 ciclos)

        function new(string name = "isfft_palavras_seq");
            super.new(name);
        endfunction

        task body();
            foreach (dados[i]) begin
                axis_item t = axis_item::type_id::create("t");
                int unsigned d = 0;
                start_item(t);
                if ($urandom_range(99) < pausa_pct) d = $urandom_range(pausa_max, 1);
                if ($urandom_range(99) < longa_pct) d = 40;
                if (!t.randomize() with { delay == d; })
                    `uvm_error("SEQ", "randomize do axis_item falhou")
                t.data = dados[i];
                t.last = (i == pos_last);
                finish_item(t);
            end
        endtask
    endclass

    //=========================================================================
    class isfft_base_vseq extends uvm_sequence;
        `uvm_object_utils(isfft_base_vseq)
        `uvm_declare_p_sequencer(isfft_vsequencer)

        // Pausas na entrada (repassadas a isfft_palavras_seq)
        int unsigned pausa_pct = 0, pausa_max = 2, longa_pct = 0;
        uvm_status_e st;

        function new(string name = "isfft_base_vseq");
            super.new(name);
        endfunction

        // PKT_MAT e enable
        task configura(int pkt_mat, bit enable = 1);
            p_sequencer.regs.PKT_MAT.write(st, pkt_mat, .parent(this));
            p_sequencer.regs.CTRL.write(st, enable, .parent(this));
        endtask

        task manda_palavras(bit [63:0] d[$], int pos_last);
            isfft_palavras_seq s = isfft_palavras_seq::type_id::create("palavras");
            s.dados = d;  s.pos_last = pos_last;
            s.pausa_pct = pausa_pct; s.pausa_max = pausa_max; s.longa_pct = longa_pct;
            s.start(p_sequencer.in_sqr, this);
        endtask

        // Um pacote = n matrizes com tlast na ultima palavra
        task manda_pacote(isfft_matriz m[$]);
            bit [63:0] d[$];
            foreach (m[i])
                for (int k = 0; k < 32; k++) d.push_back(m[i].palavra(k));
            manda_palavras(d, d.size() - 1);
        endtask

        // Pacote truncado: n < 32 palavras com tlast na ultima
        task manda_truncado(int n);
            bit [63:0] d[$];
            for (int k = 0; k < n; k++) d.push_back({32'hDEADBEEF, 32'(k)});
            `uvm_info("VSEQ", $sformatf("pacote truncado de %0d palavras", n), UVM_MEDIUM)
            manda_palavras(d, n - 1);
        endtask

        function isfft_matriz sorteia_matriz();
            isfft_matriz m = isfft_matriz::type_id::create("m");
            if (!m.randomize()) `uvm_error("VSEQ", "randomize da matriz falhou")
            return m;
        endfunction

        task soft_reset(bit enable_depois = 1);
            `uvm_info("VSEQ", "soft reset", UVM_MEDIUM)
            p_sequencer.regs.CTRL.write(st, 32'h2, .parent(this));
            p_sequencer.cfg.espera_clk(5);
            p_sequencer.regs.CTRL.write(st, enable_depois, .parent(this));
        endtask

        // Espera o DUT entregar tudo que foi confirmado na epoca atual
        task espera_esvaziar(int limite_ciclos = 200000);
            int c = 0;
            while (p_sequencer.sb.palavras_epoca() < 32 * p_sequencer.refm.conf_epoca) begin
                p_sequencer.cfg.espera_clk(1);
                if (++c > limite_ciclos) begin
                    `uvm_error("VSEQ", $sformatf("DUT nao esvaziou: %0d de %0d palavras",
                               p_sequencer.sb.palavras_epoca(), 32 * p_sequencer.refm.conf_epoca))
                    return;
                end
            end
            p_sequencer.cfg.espera_clk(20);
        endtask

        // Contadores pelo RAL (valor esperado vem do modelo/scoreboard via
        // predict) + bits do STATUS conferidos a mao
        task confere_registradores();
            uvm_reg_data_t v;
            p_sequencer.regs.ID.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.MAT_IN.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.MAT_OUT.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.ERR_CNT.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.PKT_MAT.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.STATUS.read(st, v, .parent(this));
            if (v[0])  `uvm_error("STATUS", "busy ainda ativo com o DUT vazio")
            if (v[1])  `uvm_error("STATUS", "sobrou matriz na entrada")
            if (v[3])  `uvm_error("STATUS", "sobrou dado na FIFO de saida")
            if (v[9])  `uvm_error("STATUS", "overflow interno")
            if (v[8] != p_sequencer.refm.err_flag)
                `uvm_error("STATUS", $sformatf("erro de tlast = %0b, esperado %0b", v[8], p_sequencer.refm.err_flag))
            `uvm_info("VSEQ", $sformatf("registradores OK: MAT_IN=%0d MAT_OUT=%0d ERR_CNT=%0d STATUS=0x%03h",
                      p_sequencer.regs.MAT_IN.get_mirrored_value(),
                      p_sequencer.regs.MAT_OUT.get_mirrored_value(),
                      p_sequencer.regs.ERR_CNT.get_mirrored_value(), v), UVM_LOW)
        endtask

        task limpa_erros();
            p_sequencer.regs.CTRL.write(st, 32'h5, .parent(this));   // enable + limpa
        endtask
    endclass

    //=========================================================================
    // Fumaca: 1 matriz, sem pausas
    //=========================================================================
    class isfft_fumaca_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_fumaca_vseq)
        function new(string name = "isfft_fumaca_vseq"); super.new(name); endfunction
        task body();
            isfft_matriz m[$];
            configura(1);
            m.push_back(sorteia_matriz());
            manda_pacote(m);
            espera_esvaziar();
            confere_registradores();
        endtask
    endclass

    //=========================================================================
    // Aleatorio: n matrizes em pacotes de PKT_MAT, com pausas; opcionalmente
    // pacotes truncados no meio
    //=========================================================================
    class isfft_aleatorio_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_aleatorio_vseq)
        int n_mat      = 40;
        int pkt_mat    = 0;      // 0 = sorteia 1..4
        int trunc_pct  = 0;      // chance de um pacote truncado antes de cada pacote
        int n_trunc    = 0;      // truncados ja mandados
        function new(string name = "isfft_aleatorio_vseq"); super.new(name); endfunction

        // Tamanho do truncado (DIARIO_UVM, 7a sessao). Sorteio uniforme de
        // 1 a 31 deixava as pontas sem acerto (bins cp_pos_trunc.primeira e
        // .penult: 0 em 8 truncados). Agora: os 2 primeiros sao as pontas
        // (dirigido: tlast na 1a e na 31a palavra) e o resto e sorteado com
        // peso extra nas pontas (1/5 cada).
        function int sorteia_trunc();
            n_trunc++;
            if (n_trunc == 1) return 1;
            if (n_trunc == 2) return 31;
            case ($urandom_range(4, 0))
                0:       return 1;
                1:       return 31;
                default: return $urandom_range(30, 2);
            endcase
        endfunction

        task body();
            int enviadas = 0;
            if (pkt_mat == 0) pkt_mat = $urandom_range(4, 1);
            `uvm_info("VSEQ", $sformatf("%0d matrizes, PKT_MAT=%0d, truncados %0d%%", n_mat, pkt_mat, trunc_pct), UVM_LOW)
            configura(pkt_mat);
            while (enviadas < n_mat) begin
                isfft_matriz m[$];
                if ($urandom_range(99) < trunc_pct) manda_truncado(sorteia_trunc());
                for (int i = 0; i < pkt_mat && enviadas < n_mat; i++) begin
                    m.push_back(sorteia_matriz());
                    enviadas++;
                end
                manda_pacote(m);
            end
            espera_esvaziar();
            confere_registradores();
            if (p_sequencer.refm.err_flag) begin
                limpa_erros();
                confere_registradores();
            end
        endtask
    endclass

    //=========================================================================
    // Soft reset no meio do fluxo (dados dentro do DUT), depois continua
    //=========================================================================
    class isfft_soft_reset_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_soft_reset_vseq)
        function new(string name = "isfft_soft_reset_vseq"); super.new(name); endfunction
        task body();
            isfft_matriz m[$];
            int alvo, c;
            configura(2);
            // 1) Soft reset por TEMPO, logo no comeco: com a semente 1 ele cai
            //    antes de o nucleo sair do reset estendido (127 ciclos), e so
            //    o buffer de entrada tem dado. Fica: "reset dentro do reset".
            for (int i = 0; i < 6; i++) m.push_back(sorteia_matriz());
            fork
                manda_pacote(m);
                begin
                    p_sequencer.cfg.espera_clk($urandom_range(300, 60));
                    soft_reset();
                end
            join
            // As palavras que chegaram depois do reset formam "matrizes"
            // desalinhadas e o fim do pacote pode sair truncado (erro de
            // tlast). O DUT e o modelo contam igual -- faz parte do teste.
            p_sequencer.cfg.espera_clk(50);
            // 2) Soft reset por ESTADO (DIARIO_UVM, 8a sessao): so depois de
            //    o DUT entregar 1 matriz inteira + parte da seguinte -- o
            //    nucleo esta calculando, a FIFO de saida e o buffer de saida
            //    tem dado. Era o caso que o 1) prometia e nao garantia (no
            //    IMC, o reset do nucleo so tinha uma transicao).
            m.delete();
            for (int i = 0; i < 6; i++) m.push_back(sorteia_matriz());
            alvo = 32 + $urandom_range(31, 0);
            fork
                manda_pacote(m);
                begin
                    c = 0;
                    while (p_sequencer.sb.palavras_epoca() < alvo && c < 20000) begin
                        p_sequencer.cfg.espera_clk(1);
                        c++;
                    end
                    if (c >= 20000)
                        `uvm_error("VSEQ", $sformatf("saida nao chegou a %0d palavras para o 2o soft reset", alvo))
                    `uvm_info("VSEQ", $sformatf("2o soft reset com o nucleo trabalhando: %0d palavras ja entregues na epoca",
                                                p_sequencer.sb.palavras_epoca()), UVM_LOW)
                    soft_reset();
                end
            join
            // Depois, um pacote novo, limpo.
            p_sequencer.cfg.espera_clk(50);
            m.delete();
            for (int i = 0; i < 4; i++) m.push_back(sorteia_matriz());
            manda_pacote(m);
            espera_esvaziar();
            confere_registradores();
        endtask
    endclass

    //=========================================================================
    // As 3 matrizes da Kria (processamento_otfs.ipynb): EVM tem que ser o
    // mesmo medido na placa (D32)
    //=========================================================================
    class isfft_kria_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_kria_vseq)
        function new(string name = "isfft_kria_vseq"); super.new(name); endfunction
        task body();
            isfft_matriz m[$];
            isfft_tipo_e tipos[3] = '{MAT_KRIA_IMPULSO, MAT_KRIA_SENOIDE, MAT_KRIA_RAMPA};
            configura(3);
            foreach (tipos[i]) begin
                isfft_matriz x = isfft_matriz::type_id::create("kria");
                x.tipo = tipos[i];
                x.preenche();
                m.push_back(x);
            end
            manda_pacote(m);
            espera_esvaziar();
            confere_registradores();
        endtask
    endclass

    //=========================================================================
    // Estouro (U23): n matrizes MAT_SINAIS (+-lim em toda componente) com
    // lim acima da faixa valida. Mostra o limite do nucleo; o bit a bit
    // contra a etapa 1 continua cobrado.
    //=========================================================================
    class isfft_estouro_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_estouro_vseq)
        int n_mat = 40;
        function new(string name = "isfft_estouro_vseq"); super.new(name); endfunction
        task body();
            isfft_matriz m[$];
            configura(4);
            for (int i = 0; i < n_mat; i++) begin
                isfft_matriz x = isfft_matriz::type_id::create("sinais");
                x.tipo = MAT_SINAIS;  x.amp = AMP_FORA;
                x.preenche();
                m.push_back(x);
                if (m.size() == 4) begin manda_pacote(m); m.delete(); end
            end
            if (m.size() != 0) manda_pacote(m);
            espera_esvaziar();
            confere_registradores();
        endtask
    endclass

    //=========================================================================
    // O tb_isfft_axi_v3 da Kria reescrito em UVM: 40 matrizes de dado
    // aleatorio cheio, PKT_MAT = 4, tready ~75% com parada longa, pacote
    // truncado de 20 palavras no meio, e limpeza de erro no fim
    //=========================================================================
    class isfft_kria_regressao_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_kria_regressao_vseq)
        function new(string name = "isfft_kria_regressao_vseq"); super.new(name); endfunction
        task body();
            isfft_matriz m[$];
            configura(4);
            for (int p = 0; p < 10; p++) begin
                if (p == 5) manda_truncado(20);
                m.delete();
                for (int i = 0; i < 4; i++) begin
                    isfft_matriz x = isfft_matriz::type_id::create("x");
                    // Dado cheio de 16 bits, como o tb da Kria: fora da faixa
                    // valida (U23). Aqui o numerico ja era so informativo.
                    x.tipo = MAT_ALEATORIA; x.amp = AMP_FORA; x.preenche();
                    m.push_back(x);
                end
                manda_pacote(m);
            end
            espera_esvaziar();
            confere_registradores();
            limpa_erros();
            confere_registradores();
        endtask
    endclass

    //=========================================================================
    // Acesso a registradores: valores de reset (sequencia pronta do UVM) e
    // escrita/leitura do PKT_MAT
    //=========================================================================
    class isfft_registradores_vseq extends isfft_base_vseq;
        `uvm_object_utils(isfft_registradores_vseq)
        function new(string name = "isfft_registradores_vseq"); super.new(name); endfunction
        int valores_pkt[5] = '{0, 1, 2, 16'hFFFF, 16'h00A5};

        task body();
            uvm_reg_hw_reset_seq rst = uvm_reg_hw_reset_seq::type_id::create("hw_reset");
            rst.model = p_sequencer.regs;
            rst.start(null, this);

            foreach (valores_pkt[i]) begin
                p_sequencer.regs.PKT_MAT.write(st, valores_pkt[i], .parent(this));
                p_sequencer.regs.PKT_MAT.mirror(st, UVM_CHECK, .parent(this));
            end
            p_sequencer.regs.PKT_MAT.write(st, 1, .parent(this));

            p_sequencer.regs.CTRL.write(st, 32'h1, .parent(this));
            p_sequencer.regs.CTRL.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.CTRL.write(st, 32'h0, .parent(this));
            p_sequencer.regs.CTRL.mirror(st, UVM_CHECK, .parent(this));

            // Escrita direta (sem RAL) nos registradores somente leitura: o
            // DUT tem que ignorar. O predictor ve a escrita e, como os campos
            // sao RO, o espelho continua no valor certo.
            foreach (ro_end[i]) escreve_direto(ro_end[i], 32'hFFFF_FFFF);
            p_sequencer.regs.MAT_IN.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.MAT_OUT.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.ERR_CNT.mirror(st, UVM_CHECK, .parent(this));
            p_sequencer.regs.ID.mirror(st, UVM_CHECK, .parent(this));
        endtask

        bit [5:0] ro_end[5] = '{6'h04, 6'h08, 6'h0C, 6'h10, 6'h14};

        task escreve_direto(bit [5:0] addr, bit [31:0] data);
            axil_item t = axil_item::type_id::create("direto");
            start_item(t, -1, p_sequencer.axil_sqr);
            if (!t.randomize() with { write == 1; addr == local::addr; })
                `uvm_error("VSEQ", "randomize falhou")
            t.data = data;
            finish_item(t);
        endtask
    endclass

endpackage
