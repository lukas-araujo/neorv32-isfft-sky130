//=============================================================================
// isfft_cobertura.svh -- cobertura funcional
//
// Responde "o que os testes EXERCITARAM", nao "se passou". Quatro grupos:
//   cg_ent   entrada: pausas, contrapressao do DUT, posicao do tlast
//   cg_sai   saida: tempo parado sem tready, tlast
//   cg_reg   plano de controle: quais registradores, PKT_MAT, bits do CTRL
//   cg_ocup  caixa-branca (sonda): ocupacao do buffer de entrada, da FIFO
//            de saida e do buffer de pre-busca, amostrada a todo ciclo
//=============================================================================
class isfft_cobertura extends uvm_component;
    `uvm_component_utils(isfft_cobertura)

    uvm_analysis_imp_ent #(axis_item, isfft_cobertura) ent_imp;
    uvm_analysis_imp_sai #(axis_item, isfft_cobertura) sai_imp;
    uvm_analysis_imp_ctl #(axil_item, isfft_cobertura) ctl_imp;

    isfft_env_cfg cfg;

    // valores amostrados
    int unsigned e_ociosos, e_esperas, e_pos;
    bit          e_last;
    int unsigned s_esperas;
    bit          s_last;
    bit          r_write;
    bit [5:0]    r_addr;
    bit [31:0]   r_data;
    int unsigned pos_ent = 0;     // posicao da palavra dentro da matriz (entrada)
    // Contagens dos bins que faltavam em 30/09 (DIARIO_UVM, 7a sessao): no
    // simulador aberto (5.052) so sai a % do grupo; assim o bin aparece no log
    int unsigned n_esp_curta = 0, n_trunc_pos0 = 0, n_trunc_pos30 = 0;
    bit [6:0]    o_in_used;       // copiados da sonda a cada ciclo
    bit [8:0]    o_out_used;
    bit [1:0]    o_ob_n;
    bit          o_in_avail_32, o_out_free_32;

    covergroup cg_ent;
        option.per_instance = 1;
        cp_ociosos: coverpoint e_ociosos {
            bins seguido  = {0};
            bins curta    = {[1:2]};
            bins media    = {[3:10]};
            bins longa    = {[11:$]};
        }
        cp_esperas: coverpoint e_esperas {       // DUT segurou o tready (buffer cheio)
            bins nenhuma  = {0};
            bins curta    = {[1:3]};
            bins longa    = {[4:$]};
        }
        cp_last: coverpoint {e_last, (e_pos == 31)} {
            bins meio_sem_last = {2'b00};
            bins fim_sem_last  = {2'b01};         // pacote com varias matrizes
            bins fim_com_last  = {2'b11};         // fim de pacote certo
            bins truncado      = {2'b10};         // tlast no meio: rollback
        }
        cp_pos_trunc: coverpoint e_pos iff (e_last && e_pos != 31) {
            bins primeira = {0};
            bins meio     = {[1:29]};
            bins penult   = {30};
        }
    endgroup

    covergroup cg_sai;
        option.per_instance = 1;
        cp_esperas: coverpoint s_esperas {
            bins nenhuma = {0};
            bins curta   = {[1:3]};
            bins media   = {[4:50]};
            bins longa   = {[51:$]};
        }
        cp_last: coverpoint s_last;
    endgroup

    covergroup cg_reg;
        option.per_instance = 1;
        cp_acesso: coverpoint {r_write, r_addr} {
            bins le_ctrl    = {7'h00};  bins le_status  = {7'h04};
            bins le_mat_in  = {7'h08};  bins le_mat_out = {7'h0C};
            bins le_err     = {7'h10};  bins le_id      = {7'h14};
            bins le_pkt     = {7'h18};
            bins esc_ctrl   = {7'h40};  bins esc_pkt    = {7'h58};
            bins esc_ro     = {7'h44, 7'h48, 7'h4C, 7'h50, 7'h54};  // escrita ignorada
        }
        cp_pkt_mat: coverpoint r_data[15:0] iff (r_write && r_addr == 6'h18) {
            bins zero = {0};  bins um = {1};  bins dois = {2};
            bins tres_quatro = {[3:4]};  bins grande = {[5:$]};
        }
        cp_ctrl: coverpoint r_data[2:0] iff (r_write && r_addr == 6'h00) {
            bins desliga    = {3'b000};
            bins liga       = {3'b001};
            bins soft_reset = {3'b010, 3'b011};
            bins limpa_err  = {3'b101, 3'b100};
        }
    endgroup

    covergroup cg_ocup;
        option.per_instance = 1;
        cp_in_used: coverpoint o_in_used {
            bins vazio  = {0};
            bins parcial = {[1:31]};
            bins uma    = {32};
            bins mais   = {[33:63]};
            bins cheio  = {64};
        }
        cp_out_used: coverpoint o_out_used {
            bins vazia   = {0};
            bins pouco   = {[1:31]};
            bins metade  = {[32:127]};
            bins muito   = {[128:255]};
            bins cheia   = {256};
        }
        cp_ob_n: coverpoint o_ob_n {
            bins zero = {0}; bins um = {1}; bins dois = {2};
        }
        cp_lanca_com_saida_cheia: coverpoint {o_in_avail_32, o_out_free_32} {
            bins espera_saida = {2'b10};           // matriz pronta, sem espaco na saida
            bins lanca        = {2'b11};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        ent_imp = new("ent_imp", this);
        sai_imp = new("sai_imp", this);
        ctl_imp = new("ctl_imp", this);
        cg_ent  = new();
        cg_sai  = new();
        cg_reg  = new();
        cg_ocup = new();
    endfunction

    function void write_ent(axis_item t);
        e_ociosos = t.ociosos; e_esperas = t.esperas; e_last = t.last; e_pos = pos_ent;
        cg_ent.sample();
        if (e_esperas >= 1 && e_esperas <= 3) n_esp_curta++;
        if (e_last && e_pos == 0)  n_trunc_pos0++;
        if (e_last && e_pos == 30) n_trunc_pos30++;
        pos_ent = (t.last && pos_ent != 31) ? 0 : (pos_ent + 1) % 32;
    endfunction

    function void write_sai(axis_item t);
        s_esperas = t.esperas; s_last = t.last;
        cg_sai.sample();
    endfunction

    function void write_ctl(axil_item t);
        r_write = t.write; r_addr = t.addr; r_data = t.data;
        cg_reg.sample();
        if (t.write && t.addr == 6'h00 && t.data[1]) pos_ent = 0;   // soft reset
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge cfg.probe_vif.aclk);
            if (cfg.probe_vif.aresetn) begin
                o_in_used     = cfg.probe_vif.in_used;
                o_out_used    = cfg.probe_vif.out_used;
                o_ob_n        = cfg.probe_vif.ob_n;
                o_in_avail_32 = cfg.probe_vif.in_avail_32;
                o_out_free_32 = cfg.probe_vif.out_free_32;
                cg_ocup.sample();
            end
        end
    endtask

    // Cobertura da INSTANCIA (get_inst_coverage, com per_instance = 1): ha
    // uma instancia de cada grupo, entao e a mesma do tipo. O Verilator
    // 5.052 devolve 0 em get_coverage() (tipo) -- DIARIO_UVM, 2a sessao.
    function void report_phase(uvm_phase phase);
        `uvm_info("COBERTURA", $sformatf("entrada %.1f%%  saida %.1f%%  registradores %.1f%%  ocupacao %.1f%%",
                  cg_ent.get_inst_coverage(), cg_sai.get_inst_coverage(),
                  cg_reg.get_inst_coverage(), cg_ocup.get_inst_coverage()), UVM_NONE)
        `uvm_info("COBERTURA", $sformatf("acertos: espera curta (1-3) %0d, truncado na 1a palavra %0d, na 31a %0d",
                  n_esp_curta, n_trunc_pos0, n_trunc_pos30), UVM_NONE)
    endfunction
endclass
