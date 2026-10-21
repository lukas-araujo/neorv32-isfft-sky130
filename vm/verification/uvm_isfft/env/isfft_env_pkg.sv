//=============================================================================
// isfft_env_pkg.sv -- ambiente UVM do isfft_axi_v4
//
//                 +------------------------- isfft_env --------------------------+
//                 |                                                              |
//   vseq -> vsqr -+-> RAL (isfft_reg_block) -> axil_agt ---- AXI4-Lite ---+      |
//                 |                               | mon                   |      |
//                 |                               +-> predictor (RAL)     v      |
//                 |                               +-> ref_model  +-----------+   |
//                 |                               +-> scoreboard |           |   |
//                 +-> in_agt (mestre) ---- AXI-Stream entrada -->|    DUT    |   |
//                 |      | mon -> ref_model (monta matrizes,     | isfft_v4  |   |
//                 |      |        commit/rollback, epoca)        |           |   |
//                 |      |          | dirige o wrapper da        +-----------+   |
//                 |      |          v etapa 1 (ref_in/ref_out)         |         |
//                 |      |       esperado --> scoreboard <-- mon <- out_agt      |
//                 |      +--> cobertura <------------------------------+         |
//                 +--------------------------------------------------------------+
//
// Duas checagens independentes em cada matriz:
//   1. bit a bit contra o wrapper da etapa 1 (a referencia da regressao da
//      Kria) -- pega erro no wrapper novo (buffers, macros, pre-busca);
//   2. numerica contra a ISFFT em ponto flutuante (erro em LSB e EVM) --
//      pega erro na matematica, que a checagem 1 nao ve (o nucleo e o mesmo
//      nos dois lados).
//=============================================================================
package isfft_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axil_pkg::*;
    import axis_pkg::*;

    `include "isfft_regs.svh"
    `include "isfft_matriz.svh"

    `uvm_analysis_imp_decl(_ent)
    `uvm_analysis_imp_decl(_sai)
    `uvm_analysis_imp_decl(_ctl)
    `uvm_analysis_imp_decl(_esp)

    //=========================================================================
    // Configuracao do ambiente
    //=========================================================================
    class isfft_env_cfg extends uvm_object;
        `uvm_object_utils(isfft_env_cfg)

        virtual axil_if        axil_vif;
        virtual axis_if        in_vif, out_vif;         // DUT
        virtual axis_if        ref_in_vif, ref_out_vif; // wrapper da etapa 1
        virtual isfft_probe_if probe_vif;

        axis_cfg in_cfg, out_cfg;

        // Checagem numerica. Limites MEDIDOS (DIARIO_UVM, 1a sessao): em 600
        // matrizes de todas as faixas, erro max 3,19 LSB e medio <= 1,03 LSB,
        // sem depender da amplitude (arredondamento do ponto fixo). EVM nao
        // serve de limite geral: com sinal pequeno ele passa de 50% mesmo com
        // o circuito certo. O EVM e cobrado so no teste da Kria (= placa).
        bit  checa_numerico   = 1;
        real erro_max_lsb     = 4.0;   // maior |erro| por elemento (LSB)
        real erro_medio_lsb   = 1.5;   // media de |erro| na matriz (LSB)

        function new(string name = "isfft_env_cfg");
            super.new(name);
            in_cfg  = axis_cfg::type_id::create("in_cfg");
            out_cfg = axis_cfg::type_id::create("out_cfg");
            in_cfg.papel  = AXIS_MESTRE;
            out_cfg.papel = AXIS_ESCRAVO;
        endfunction

        task espera_clk(int n);
            repeat (n) @(posedge in_vif.aclk);
        endtask
    endclass

    //=========================================================================
    // Uma matriz: entrada (32 palavras) e saida esperada (32 palavras)
    //=========================================================================
    class isfft_mat_txn extends uvm_object;
        `uvm_object_utils(isfft_mat_txn)
        bit [63:0] ent[32];
        bit [63:0] sai[32];
        int        epoca;
        int        indice;
        function new(string name = "isfft_mat_txn");
            super.new(name);
        endfunction
    endclass

    //=========================================================================
    // Modelo de referencia
    //
    // Recebe as palavras que ENTRARAM no DUT (monitor) e reproduz as regras
    // do buffer de entrada: commit a cada 32 palavras; tlast antes da 32a
    // descarta a matriz parcial (rollback) e conta erro. Cada matriz
    // confirmada passa pelo wrapper da etapa 1 (32 palavras seguidas, como
    // no tb da Kria) e a saida vira o esperado.
    //
    // Epoca: cada escrita de soft reset (CTRL[1] = 1) comeca uma epoca nova.
    // O que estava dentro do DUT se perde de proposito; o scoreboard aceita
    // perder o FIM de uma epoca, nunca o meio.
    //=========================================================================
    class isfft_ref_model extends uvm_component;
        `uvm_component_utils(isfft_ref_model)

        uvm_analysis_imp_ent #(axis_item, isfft_ref_model) ent_imp;
        uvm_analysis_imp_ctl #(axil_item, isfft_ref_model) ctl_imp;
        uvm_analysis_port    #(isfft_mat_txn)              ap;

        isfft_env_cfg   cfg;
        isfft_reg_block regs;

        bit [63:0]    parcial[$];
        isfft_mat_txn fila[$];
        int epoca        = 0;
        int conf_epoca   = 0;   // matrizes confirmadas nesta epoca (= MAT_IN)
        int conf_total   = 0;
        int truncados    = 0;
        int err_cnt      = 0;   // espelho do ERR_CNT
        bit err_flag     = 0;   // espelho do STATUS[8]

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ent_imp = new("ent_imp", this);
            ctl_imp = new("ctl_imp", this);
            ap      = new("ap", this);
        endfunction

        function void write_ent(axis_item t);
            if (t.last && parcial.size() != 31) begin
                `uvm_info("REF", $sformatf("pacote truncado com %0d palavras: descartado (rollback)",
                                           parcial.size() + 1), UVM_MEDIUM)
                parcial.delete();
                truncados++;
                err_cnt++;
                err_flag = 1;
                void'(regs.ERR_CNT.predict(err_cnt));
                return;
            end
            parcial.push_back(t.data);
            if (parcial.size() == 32) begin
                isfft_mat_txn m = isfft_mat_txn::type_id::create("mat");
                foreach (m.ent[k]) m.ent[k] = parcial[k];
                m.epoca  = epoca;
                m.indice = conf_epoca;
                fila.push_back(m);
                parcial.delete();
                conf_epoca++;
                conf_total++;
                void'(regs.MAT_IN.predict(conf_epoca));
            end
        endfunction

        function void write_ctl(axil_item t);
            if (!(t.write && t.addr == 6'h00 && t.strb[0])) return;
            if (t.data[1]) begin
                epoca++;
                `uvm_info("REF", $sformatf("soft reset: epoca %0d (descarta %0d palavras parciais)",
                                           epoca, parcial.size()), UVM_MEDIUM)
                parcial.delete();
                conf_epoca = 0;
                void'(regs.MAT_IN.predict(0));
            end
            if (t.data[2]) begin
                err_cnt  = 0;
                err_flag = 0;
                void'(regs.ERR_CNT.predict(0));
            end
        endfunction

        task run_phase(uvm_phase phase);
            cfg.ref_in_vif.tvalid  <= 1'b0;
            cfg.ref_in_vif.tdata   <= '0;
            cfg.ref_in_vif.tlast   <= 1'b0;
            cfg.ref_out_vif.tready <= 1'b1;
            forever begin
                wait (fila.size() > 0);
                phase.raise_objection(this, "modelo de referencia com matriz pendente");
                while (fila.size() > 0) begin
                    isfft_mat_txn m = fila.pop_front();
                    calcula(m);
                    ap.write(m);
                end
                phase.drop_objection(this);
            end
        endtask

        // 32 palavras seguidas no wrapper da etapa 1; ele nao tem tready
        // (sempre 1) e a saida nao espera ninguem.
        task calcula(isfft_mat_txn m);
            int n = 0, t = 0;
            @(posedge cfg.ref_in_vif.aclk);
            fork
                begin
                    for (int k = 0; k < 32; k++) begin
                        cfg.ref_in_vif.tdata  <= m.ent[k];
                        cfg.ref_in_vif.tlast  <= (k == 31);
                        cfg.ref_in_vif.tvalid <= 1'b1;
                        @(posedge cfg.ref_in_vif.aclk);
                    end
                    cfg.ref_in_vif.tvalid <= 1'b0;
                    cfg.ref_in_vif.tlast  <= 1'b0;
                end
                begin
                    while (n < 32) begin
                        @(posedge cfg.ref_out_vif.aclk);
                        if (cfg.ref_out_vif.tvalid) begin
                            m.sai[n] = cfg.ref_out_vif.tdata;
                            n++;
                        end
                        if (++t > 5000)
                            `uvm_fatal("REF", "wrapper da etapa 1 nao devolveu 32 palavras")
                    end
                end
            join
        endtask
    endclass

    //=========================================================================
    // Scoreboard
    //=========================================================================
    class isfft_epoca;
        axis_item     act[$];       // palavras do DUT ainda nao comparadas
        isfft_mat_txn esp[$];       // matrizes esperadas desta epoca
        int           n_cmp = 0;    // palavras ja comparadas
        bit [63:0]    mat_act[32];  // matriz em comparacao (para a checagem numerica)
    endclass

    class isfft_scoreboard extends uvm_component;
        `uvm_component_utils(isfft_scoreboard)

        uvm_analysis_imp_sai #(axis_item, isfft_scoreboard)     sai_imp;
        uvm_analysis_imp_esp #(isfft_mat_txn, isfft_scoreboard) esp_imp;
        uvm_analysis_imp_ctl #(axil_item, isfft_scoreboard)     ctl_imp;

        isfft_env_cfg   cfg;
        isfft_reg_block regs;

        isfft_epoca ep[$];
        int epoca = 0;
        // modelo do tlast e do MAT_OUT (epoca atual)
        int wcnt = 0, pkt_cnt = 0, mat_out = 0;

        // resultados
        int  n_palavras = 0, n_matrizes = 0, n_erros_dado = 0, n_erros_last = 0;
        int  n_num = 0, n_erros_num = 0;
        int  n_fora = 0, n_estouro_fora = 0;   // entrada fora da faixa valida (U23)
        real evm_lista[$];             // uma por matriz, na ordem
        isfft_mat_txn sai_lista[$];    // entrada + saida REAL do DUT, na ordem
        int  amp_lista[$];
        real pior_erro[isfft_amp_e];   // maior |erro| (LSB) por faixa de amplitude
        real pior_evm[isfft_amp_e];    // maior EVM (%) por faixa
        int  n_faixa[isfft_amp_e];

        function new(string name, uvm_component parent);
            super.new(name, parent);
            sai_imp = new("sai_imp", this);
            esp_imp = new("esp_imp", this);
            ctl_imp = new("ctl_imp", this);
        endfunction

        function void build_phase(uvm_phase phase);
            isfft_epoca e0 = new();
            super.build_phase(phase);
            ep.push_back(e0);
        endfunction

        function void write_ctl(axil_item t);
            isfft_epoca e;
            if (!(t.write && t.addr == 6'h00 && t.strb[0] && t.data[1])) return;
            epoca++;
            e = new();
            ep.push_back(e);
            wcnt = 0; pkt_cnt = 0; mat_out = 0;
            void'(regs.MAT_OUT.predict(0));
        endfunction

        function void write_sai(axis_item t);
            int  pkt_eff = regs.PKT_MAT.pkt_mat.get_mirrored_value();
            bit  last_esp;
            if (pkt_eff == 0) pkt_eff = 1;
            last_esp = (wcnt == 31) && (pkt_cnt >= pkt_eff - 1);
            if (t.last !== last_esp) begin
                n_erros_last++;
                `uvm_error("SB_TLAST", $sformatf("palavra %0d da matriz %0d (epoca %0d): tlast=%0b, esperado %0b (PKT_MAT=%0d)",
                                                 wcnt, mat_out, epoca, t.last, last_esp, pkt_eff))
            end
            if (t.keep !== 8'hFF)
                `uvm_error("SB_TKEEP", $sformatf("tkeep=%02h", t.keep))
            if (wcnt == 31) begin
                pkt_cnt = last_esp ? 0 : pkt_cnt + 1;
                mat_out++;
                void'(regs.MAT_OUT.predict(mat_out));
            end
            wcnt = (wcnt + 1) % 32;
            ep[epoca].act.push_back(t);
            compara(epoca);
        endfunction

        function void write_esp(isfft_mat_txn m);
            ep[m.epoca].esp.push_back(m);
            compara(m.epoca);
        endfunction

        function void compara(int e);
            isfft_epoca   x = ep[e];
            isfft_mat_txn m;
            axis_item     t;
            int k;
            while (x.act.size() > 0 && (x.n_cmp / 32) < x.esp.size()) begin
                m = x.esp[x.n_cmp / 32];
                k = x.n_cmp % 32;
                t = x.act.pop_front();
                if (t.data !== m.sai[k]) begin
                    n_erros_dado++;
                    if (n_erros_dado <= 10)
                        `uvm_error("SB_DADO", $sformatf("epoca %0d matriz %0d palavra %0d: DUT %016h, referencia %016h",
                                                        e, m.indice, k, t.data, m.sai[k]))
                end
                x.mat_act[k] = t.data;
                x.n_cmp++;
                n_palavras++;
                if (k == 31) begin
                    n_matrizes++;
                    checa_numerico(m, x.mat_act);
                end
            end
        endfunction

        function isfft_amp_e faixa(int a);
            if (a <= isfft_matriz::limite(AMP_BAIXA)) return AMP_BAIXA;
            if (a <= isfft_matriz::limite(AMP_MEDIA)) return AMP_MEDIA;
            if (a <= isfft_matriz::limite(AMP_ALTA))  return AMP_ALTA;
            if (a <= isfft_matriz::limite(AMP_CHEIA)) return AMP_CHEIA;
            return AMP_FORA;
        endfunction

        function void checa_numerico(isfft_mat_txn m, bit [63:0] y[32]);
            real evm, emax, emed;
            int  a = isfft_modelo::amplitude(m.ent);
            isfft_amp_e f = faixa(a);
            isfft_mat_txn r = isfft_mat_txn::type_id::create("real");
            r.ent = m.ent;  r.sai = y;  r.epoca = m.epoca;  r.indice = m.indice;
            sai_lista.push_back(r);
            isfft_modelo::avalia(m.ent, y, evm, emax, emed);
            evm_lista.push_back(evm);
            amp_lista.push_back(a);
            if (!n_faixa.exists(f)) begin n_faixa[f] = 0; pior_erro[f] = 0.0; pior_evm[f] = 0.0; end
            n_faixa[f]++;
            if (emax > pior_erro[f]) pior_erro[f] = emax;
            if (evm > pior_evm[f])   pior_evm[f]  = evm;
            `uvm_info("SB_NUM", $sformatf("matriz %0d: amplitude %0d  EVM %.4f%%  erro max %.2f LSB  medio %.2f",
                                          n_matrizes - 1, a, evm, emax, emed), UVM_HIGH)
            if (!cfg.checa_numerico) return;
            // Fora da faixa valida (U23): o nucleo pode estourar por projeto.
            // Bit a bit continua cobrado (compara); o numerico so e contado.
            if (f == AMP_FORA) begin
                n_fora++;
                if (emax > cfg.erro_max_lsb || emed > cfg.erro_medio_lsb) n_estouro_fora++;
                return;
            end
            n_num++;
            if (emax > cfg.erro_max_lsb || emed > cfg.erro_medio_lsb) begin
                n_erros_num++;
                if (n_erros_num <= 10)
                    `uvm_error("SB_NUM", $sformatf("matriz %0d (amplitude %0d): erro max %.2f LSB (limite %.2f), medio %.2f (limite %.2f), EVM %.4f%%",
                                                   n_matrizes - 1, a, emax, cfg.erro_max_lsb, emed, cfg.erro_medio_lsb, evm))
            end
        endfunction

        // Palavras que o DUT entregou na epoca atual (para a sequencia saber
        // quando terminou)
        function int palavras_epoca();
            return ep[epoca].n_cmp + ep[epoca].act.size();
        endfunction

        function void check_phase(uvm_phase phase);
            foreach (ep[e]) begin
                int esp = ep[e].esp.size() * 32;
                compara(e);
                if (ep[e].act.size() != 0)
                    `uvm_error("SB_FIM", $sformatf("epoca %0d: %0d palavras do DUT sem esperado (DUT entregou a mais)",
                                                   e, ep[e].act.size()))
                if (e == epoca) begin
                    if (ep[e].n_cmp != esp)
                        `uvm_error("SB_FIM", $sformatf("epoca %0d: DUT entregou %0d de %0d palavras esperadas",
                                                       e, ep[e].n_cmp, esp))
                end else if (ep[e].n_cmp < esp)
                    `uvm_info("SB_FIM", $sformatf("epoca %0d: %0d palavras perdidas no soft reset (permitido)",
                                                  e, esp - ep[e].n_cmp), UVM_LOW)
            end
        endfunction

        function void report_phase(uvm_phase phase);
            isfft_amp_e f;
            `uvm_info("SB_RESUMO", $sformatf("%0d matrizes / %0d palavras comparadas bit a bit; %0d erros de dado, %0d de tlast; %0d epocas",
                                             n_matrizes, n_palavras, n_erros_dado, n_erros_last, epoca + 1), UVM_NONE)
            `uvm_info("SB_RESUMO", $sformatf("checagem numerica: %0d matrizes, %0d fora do limite (erro max <= %.1f LSB, medio <= %.1f LSB)",
                                             n_num, n_erros_num, cfg.erro_max_lsb, cfg.erro_medio_lsb), UVM_NONE)
            if (n_fora > 0)
                `uvm_info("SB_RESUMO", $sformatf("fora da faixa valida (|re|,|im| > %0d, U23): %0d matrizes, %0d estouraram (so contado)",
                                                 isfft_matriz::FAIXA_MAX, n_fora, n_estouro_fora), UVM_NONE)
            if (n_faixa.first(f))
                do
                    `uvm_info("SB_RESUMO", $sformatf("  faixa %-9s: %4d matrizes  pior erro %.2f LSB  pior EVM %.4f%%",
                                                     f.name(), n_faixa[f], pior_erro[f], pior_evm[f]), UVM_NONE)
                while (n_faixa.next(f));
        endfunction
    endclass

    `include "isfft_cobertura.svh"

    //=========================================================================
    // Sequenciador virtual: da as sequencias acesso a tudo que elas usam
    //=========================================================================
    class isfft_vsequencer extends uvm_sequencer;
        `uvm_component_utils(isfft_vsequencer)
        axis_sequencer   in_sqr;
        axil_sequencer   axil_sqr;   // acesso direto, sem RAL
        isfft_reg_block  regs;
        isfft_env_cfg    cfg;
        isfft_ref_model  refm;
        isfft_scoreboard sb;
        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction
    endclass

    //=========================================================================
    class isfft_env extends uvm_env;
        `uvm_component_utils(isfft_env)

        isfft_env_cfg    cfg;
        axil_agent       axil_agt;
        axis_agent       in_agt, out_agt;
        isfft_reg_block  regs;
        axil_reg_adapter adapter;
        uvm_reg_predictor #(axil_item) predictor;
        isfft_ref_model  refm;
        isfft_scoreboard sb;
        isfft_cobertura  cov;
        isfft_vsequencer vsqr;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(isfft_env_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "isfft_env sem isfft_env_cfg")

            uvm_config_db#(virtual axil_if)::set(this, "axil_agt*", "vif", cfg.axil_vif);
            uvm_config_db#(virtual axis_if)::set(this, "in_agt*",   "vif", cfg.in_vif);
            uvm_config_db#(virtual axis_if)::set(this, "out_agt*",  "vif", cfg.out_vif);
            uvm_config_db#(axis_cfg)::set(this, "in_agt*",  "cfg", cfg.in_cfg);
            uvm_config_db#(axis_cfg)::set(this, "out_agt*", "cfg", cfg.out_cfg);

            axil_agt = axil_agent::type_id::create("axil_agt", this);
            in_agt   = axis_agent::type_id::create("in_agt", this);
            out_agt  = axis_agent::type_id::create("out_agt", this);

            regs = isfft_reg_block::type_id::create("regs");
            regs.build();
            regs.reset();
            adapter   = axil_reg_adapter::type_id::create("adapter");
            predictor = uvm_reg_predictor#(axil_item)::type_id::create("predictor", this);

            refm = isfft_ref_model::type_id::create("refm", this);
            sb   = isfft_scoreboard::type_id::create("sb", this);
            cov  = isfft_cobertura::type_id::create("cov", this);
            vsqr = isfft_vsequencer::type_id::create("vsqr", this);
            refm.cfg = cfg;  refm.regs = regs;
            sb.cfg   = cfg;  sb.regs   = regs;
            cov.cfg  = cfg;
        endfunction

        function void connect_phase(uvm_phase phase);
            // RAL: acesso pelo agente AXI-Lite; espelho atualizado pelo que o
            // monitor VE no barramento (predicao explicita)
            regs.default_map.set_sequencer(axil_agt.sqr, adapter);
            regs.default_map.set_auto_predict(0);
            predictor.map     = regs.default_map;
            predictor.adapter = adapter;
            axil_agt.mon.ap.connect(predictor.bus_in);

            in_agt.mon.ap.connect(refm.ent_imp);
            in_agt.mon.ap.connect(cov.ent_imp);
            axil_agt.mon.ap.connect(refm.ctl_imp);
            axil_agt.mon.ap.connect(sb.ctl_imp);
            axil_agt.mon.ap.connect(cov.ctl_imp);
            out_agt.mon.ap.connect(sb.sai_imp);
            out_agt.mon.ap.connect(cov.sai_imp);
            refm.ap.connect(sb.esp_imp);

            vsqr.in_sqr   = in_agt.sqr;
            vsqr.axil_sqr = axil_agt.sqr;
            vsqr.regs   = regs;
            vsqr.cfg    = cfg;
            vsqr.refm   = refm;
            vsqr.sb     = sb;
        endfunction
    endclass

endpackage
