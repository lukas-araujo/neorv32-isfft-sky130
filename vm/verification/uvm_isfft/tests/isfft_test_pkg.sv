//=============================================================================
// isfft_test_pkg.sv -- testes
//
//   isfft_fumaca_test          1 matriz, sem pausa, tready sempre 1
//   isfft_registradores_test   reset dos registradores (UVM), R/W, escrita em RO
//   isfft_aleatorio_test       40 matrizes, pausas na entrada, tready 75%
//   isfft_contrapressao_test   paradas longas do tready: enche a FIFO de saida
//   isfft_truncado_test        pacotes truncados (rollback) + limpeza de erro
//   isfft_soft_reset_test      soft reset com dados dentro do DUT
//   isfft_kria_test            3 matrizes da Kria: EVM = placa (D32)
//   isfft_kria_regressao_test  o tb_isfft_axi_v3 da Kria, em UVM
//
// Cada teste termina com uma linha "TESTE PASSOU" ou "TESTE FALHOU" (o
// run_first_uvm.tcl procura por ela).
//=============================================================================
package isfft_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axis_pkg::*;
    import isfft_env_pkg::*;
    import isfft_seq_pkg::*;

    //=========================================================================
    class isfft_base_test extends uvm_test;
        `uvm_component_utils(isfft_base_test)
        isfft_env     env;
        isfft_env_cfg cfg;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(isfft_env_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "o topo nao passou isfft_env_cfg")
            ajusta_cfg();
            // Chaves de linha de comando (valem para qualquer teste)
            if ($test$plusargs("SEM_CHECA_NUM")) cfg.checa_numerico = 0;
            uvm_config_db#(isfft_env_cfg)::set(this, "env", "cfg", cfg);
            env = isfft_env::type_id::create("env", this);
            // Depois de 20 erros o UVM encerra o teste: um defeito que erra a
            // todo ciclo (ex.: assercao) nao trava a regressao. Muda com
            // +UVM_MAX_QUIT_COUNT=<n>,YES
            uvm_report_server::get_server().set_max_quit_count(20);
            // Sem set_timeout do UVM (a unidade depende do timescale do
            // uvm_pkg em cada simulador): os limites sao em CICLOS, nas
            // sequencias (espera_esvaziar) e no modelo de referencia.
        endfunction

        // Os testes filhos mudam o que precisam aqui
        virtual function void ajusta_cfg();
        endfunction

        virtual function isfft_base_vseq cria_vseq();
            return isfft_fumaca_vseq::type_id::create("vseq");
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            `uvm_info("TESTE", $sformatf("UVM: %s", uvm_revision_string()), UVM_NONE)
            if (uvm_report_enabled(UVM_MEDIUM)) this.print();
        endfunction

        // Watchdog em CICLOS (+WATCHDOG=<ciclos>): um defeito pode travar o
        // handshake para sempre (ex.: entrada cheia sem matriz completa).
        // O teste mais longo da regressao usa ~23 mil ciclos.
        int unsigned watchdog = 500000;

        task run_phase(uvm_phase phase);
            isfft_base_vseq vseq = cria_vseq();
            void'($value$plusargs("WATCHDOG=%d", watchdog));
            phase.raise_objection(this);
            @(posedge cfg.in_vif.aclk iff cfg.in_vif.aresetn);
            cfg.espera_clk(5);
            fork
                vseq.start(env.vsqr);
                estimulo_paralelo();
                begin
                    cfg.espera_clk(watchdog);
                    `uvm_fatal("WATCHDOG", $sformatf("teste passou de %0d ciclos: DUT ou sequencia travados", watchdog))
                end
            join_any
            disable fork;
            phase.drop_objection(this);
        endtask

        // Algo que roda junto com a sequencia (ex.: paradas do tready)
        virtual task estimulo_paralelo();
            wait (0);
        endtask

        function void report_phase(uvm_phase phase);
            uvm_report_server rs = uvm_report_server::get_server();
            int erros = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
            if (erros == 0)
                `uvm_info("TESTE", $sformatf("TESTE PASSOU: %s", get_type_name()), UVM_NONE)
            else
                `uvm_info("TESTE", $sformatf("TESTE FALHOU: %s (%0d erros)", get_type_name(), erros), UVM_NONE)
        endfunction
    endclass

    //=========================================================================
    class isfft_fumaca_test extends isfft_base_test;
        `uvm_component_utils(isfft_fumaca_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void ajusta_cfg();
            cfg.out_cfg.ready_pct = 100;
        endfunction
    endclass

    //=========================================================================
    class isfft_registradores_test extends isfft_base_test;
        `uvm_component_utils(isfft_registradores_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function isfft_base_vseq cria_vseq();
            return isfft_registradores_vseq::type_id::create("vseq");
        endfunction
    endclass

    //=========================================================================
    class isfft_aleatorio_test extends isfft_base_test;
        `uvm_component_utils(isfft_aleatorio_test)
        int n_mat = 40, trunc_pct = 0;
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void ajusta_cfg();
            cfg.out_cfg.ready_pct = 75;
        endfunction
        virtual function isfft_base_vseq cria_vseq();
            isfft_aleatorio_vseq v = isfft_aleatorio_vseq::type_id::create("vseq");
            void'($value$plusargs("N_MAT=%d", n_mat));
            v.n_mat = n_mat;  v.trunc_pct = trunc_pct;
            v.pausa_pct = 30; v.pausa_max = 3; v.longa_pct = 3;
            return v;
        endfunction
    endclass

    //=========================================================================
    class isfft_contrapressao_test extends isfft_aleatorio_test;
        `uvm_component_utils(isfft_contrapressao_test)
        function new(string name, uvm_component parent); super.new(name, parent); n_mat = 60; endfunction
        virtual function void ajusta_cfg();
            cfg.out_cfg.ready_pct = 50;
        endfunction
        // A cada 1000-3000 ciclos, tready em 0 por 500-4000 ciclos: a FIFO de
        // saida (256) enche, o liberador para, o buffer de entrada (64) enche
        // e o DUT segura a entrada
        virtual task estimulo_paralelo();
            forever begin
                cfg.espera_clk($urandom_range(3000, 1000));
                cfg.out_cfg.para_ready($urandom_range(4000, 500));
            end
        endtask
    endclass

    //=========================================================================
    class isfft_truncado_test extends isfft_aleatorio_test;
        `uvm_component_utils(isfft_truncado_test)
        function new(string name, uvm_component parent); super.new(name, parent); trunc_pct = 25; endfunction
    endclass

    //=========================================================================
    class isfft_soft_reset_test extends isfft_base_test;
        `uvm_component_utils(isfft_soft_reset_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void ajusta_cfg();
            cfg.out_cfg.ready_pct = 60;
        endfunction
        virtual function isfft_base_vseq cria_vseq();
            isfft_soft_reset_vseq v = isfft_soft_reset_vseq::type_id::create("vseq");
            v.pausa_pct = 20; v.pausa_max = 3;
            return v;
        endfunction
    endclass

    //=========================================================================
    class isfft_kria_test extends isfft_base_test;
        `uvm_component_utils(isfft_kria_test)
        real evm_kria[3] = '{3.41, 0.78, 0.60};
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function isfft_base_vseq cria_vseq();
            return isfft_kria_vseq::type_id::create("vseq");
        endfunction
        // EVM como no notebook da Kria (evm.py): referencia calculada sobre a
        // matriz IDEAL, antes de truncar para int16. Na senoide isso pesa:
        // contra a entrada ja truncada o EVM seria ~0,69% (DIARIO_UVM).
        function void check_phase(uvm_phase phase);
            isfft_tipo_e tipos[3] = '{MAT_KRIA_IMPULSO, MAT_KRIA_SENOIDE, MAT_KRIA_RAMPA};
            real xr[64], xi[64], evm, emax, emed, d;
            if (env.sb.sai_lista.size() != 3) begin
                `uvm_error("KRIA", $sformatf("%0d matrizes na saida, esperado 3", env.sb.sai_lista.size()))
                return;
            end
            foreach (tipos[i]) begin
                isfft_matriz m = isfft_matriz::type_id::create("kria");
                m.tipo = tipos[i];
                m.preenche();
                m.ideal(xr, xi);
                isfft_modelo::avalia_real(xr, xi, env.sb.sai_lista[i].sai, evm, emax, emed);
                d = evm - evm_kria[i];
                if (d < 0) d = -d;
                if (d < 0.005)
                    `uvm_info("KRIA", $sformatf("matriz %0d (%s): EVM %.4f%%  Kria %.2f%%  = Kria  (entrada truncada: %.4f%%)",
                              i + 1, tipos[i].name(), evm, evm_kria[i], env.sb.evm_lista[i]), UVM_NONE)
                else
                    `uvm_error("KRIA", $sformatf("matriz %0d (%s): EVM %.4f%%  Kria %.2f%%  DIFERENTE",
                               i + 1, tipos[i].name(), evm, evm_kria[i]))
            end
        endfunction
    endclass

    //=========================================================================
    class isfft_kria_regressao_test extends isfft_base_test;
        `uvm_component_utils(isfft_kria_regressao_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction
        virtual function void ajusta_cfg();
            cfg.out_cfg.ready_pct = 75;
            // dado aleatorio de 16 bits cheios: so a comparacao bit a bit
            // (a Kria tambem nao media EVM nesse teste)
            cfg.checa_numerico = 0;
        endfunction
        virtual function isfft_base_vseq cria_vseq();
            isfft_kria_regressao_vseq v = isfft_kria_regressao_vseq::type_id::create("vseq");
            v.pausa_pct = 50; v.pausa_max = 2; v.longa_pct = 5;
            return v;
        endfunction
        // parada longa do tready entre 1500 e 6500 ciclos, como no tb original
        virtual task estimulo_paralelo();
            cfg.espera_clk(1500);
            cfg.out_cfg.para_ready(5000);
            wait (0);
        endtask
    endclass

endpackage
