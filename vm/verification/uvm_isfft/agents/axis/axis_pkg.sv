//=============================================================================
// axis_pkg.sv -- agente AXI4-Stream de 64 bits
//
// O mesmo agente faz os dois papeis, escolhidos no axis_cfg:
//   AXIS_MESTRE    (entrada do DUT)  driver manda palavras com pausas sorteadas
//   AXIS_ESCRAVO   (saida do DUT)    driver so controla o tready
// O monitor e o mesmo nos dois: publica cada palavra transferida, com
// quantos ciclos o canal ficou parado antes dela (sem valid / sem ready).
//=============================================================================
package axis_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum { AXIS_MESTRE, AXIS_ESCRAVO } axis_papel_e;

    //=========================================================================
    // Configuracao do agente (tambem usada em tempo de simulacao: o teste
    // muda ready_pct ou pede uma parada longa com para_ready())
    //=========================================================================
    class axis_cfg extends uvm_object;
        `uvm_object_utils(axis_cfg)
        uvm_active_passive_enum ativo = UVM_ACTIVE;
        axis_papel_e            papel = AXIS_MESTRE;

        // so no ESCRAVO: chance (%) de tready = 1 em cada ciclo
        int unsigned ready_pct   = 100;
        // so no ESCRAVO: ciclos restantes de tready = 0 forcado
        int unsigned parada_ciclos = 0;

        function new(string name = "axis_cfg");
            super.new(name);
        endfunction

        function void para_ready(int unsigned ciclos);
            parada_ciclos = ciclos;
        endfunction
    endclass

    //=========================================================================
    class axis_item extends uvm_sequence_item;
        rand bit [63:0]   data;
        rand bit          last;
        rand int unsigned delay;      // mestre: ciclos sem tvalid antes da palavra
        bit      [7:0]    keep = 8'hFF;

        // preenchidos pelo monitor
        int unsigned ociosos;         // ciclos sem tvalid antes desta palavra
        int unsigned esperas;         // ciclos com tvalid e sem tready

        constraint c_delay { delay <= 64; }

        `uvm_object_utils(axis_item)

        function new(string name = "axis_item");
            super.new(name);
        endfunction

        virtual function string convert2string();
            return $sformatf("data=%016h last=%0b keep=%02h ociosos=%0d esperas=%0d",
                             data, last, keep, ociosos, esperas);
        endfunction

        virtual function void do_copy(uvm_object rhs);
            axis_item t;
            super.do_copy(rhs);
            $cast(t, rhs);
            data = t.data; last = t.last; delay = t.delay; keep = t.keep;
            ociosos = t.ociosos; esperas = t.esperas;
        endfunction
    endclass

    typedef uvm_sequencer #(axis_item) axis_sequencer;

    //=========================================================================
    class axis_driver extends uvm_driver #(axis_item);
        `uvm_component_utils(axis_driver)
        virtual axis_if vif;
        axis_cfg        cfg;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axis_driver sem virtual interface")
            if (!uvm_config_db#(axis_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "axis_driver sem axis_cfg")
        endfunction

        task run_phase(uvm_phase phase);
            if (cfg.papel == AXIS_MESTRE) mestre();
            else                          escravo();
        endtask

        task mestre();
            vif.tvalid <= 1'b0; vif.tdata <= '0; vif.tlast <= 1'b0; vif.tkeep <= '1;
            @(posedge vif.aclk iff vif.aresetn);
            forever begin
                seq_item_port.get_next_item(req);
                repeat (req.delay) @(posedge vif.aclk);
                vif.tdata  <= req.data;
                vif.tlast  <= req.last;
                vif.tkeep  <= req.keep;
                vif.tvalid <= 1'b1;
                do @(posedge vif.aclk); while (!vif.tready);
                // Se a proxima palavra vier sem pausa, o tvalid <= 1 dela
                // sobrescreve este no mesmo instante: fluxo continuo.
                vif.tvalid <= 1'b0;
                vif.tlast  <= 1'b0;
                seq_item_port.item_done();
            end
        endtask

        task escravo();
            vif.tready <= 1'b0;
            forever begin
                @(posedge vif.aclk);
                if (cfg.parada_ciclos > 0) begin
                    cfg.parada_ciclos--;
                    vif.tready <= 1'b0;
                end else
                    vif.tready <= ($urandom_range(99) < cfg.ready_pct);
            end
        endtask
    endclass

    //=========================================================================
    class axis_monitor extends uvm_monitor;
        `uvm_component_utils(axis_monitor)
        virtual axis_if vif;
        uvm_analysis_port #(axis_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axis_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axis_monitor sem virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            int unsigned ociosos = 0, esperas = 0;
            forever begin
                @(posedge vif.aclk);
                if (!vif.aresetn) begin
                    ociosos = 0; esperas = 0;
                    continue;
                end
                if (vif.tvalid && vif.tready) begin
                    axis_item t = axis_item::type_id::create("mon");
                    t.data    = vif.tdata;
                    t.last    = vif.tlast;
                    t.keep    = vif.tkeep;
                    t.ociosos = ociosos;
                    t.esperas = esperas;
                    `uvm_info(get_full_name(), t.convert2string(), UVM_DEBUG)
                    ap.write(t);
                    ociosos = 0; esperas = 0;
                end
                else if (vif.tvalid) esperas++;
                else                 ociosos++;
            end
        endtask
    endclass

    //=========================================================================
    class axis_agent extends uvm_agent;
        `uvm_component_utils(axis_agent)
        axis_cfg       cfg;
        axis_sequencer sqr;
        axis_driver    drv;
        axis_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(axis_cfg)::get(this, "", "cfg", cfg))
                `uvm_fatal("NOCFG", "axis_agent sem axis_cfg")
            mon = axis_monitor::type_id::create("mon", this);
            if (cfg.ativo == UVM_ACTIVE) begin
                // O escravo nao recebe itens (so controla o tready), mas o
                // uvm_driver exige a porta ligada: o sequenciador fica ocioso
                drv = axis_driver::type_id::create("drv", this);
                sqr = axis_sequencer::type_id::create("sqr", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (cfg.ativo == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

endpackage
