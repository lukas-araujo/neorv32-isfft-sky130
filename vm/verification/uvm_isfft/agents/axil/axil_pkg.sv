//=============================================================================
// axil_pkg.sv -- agente AXI4-Lite (mestre) para o plano de controle da ISFFT
//
// Componentes:
//   axil_item         transacao (leitura ou escrita de 1 registrador)
//   axil_sequencer    typedef de uvm_sequencer
//   axil_driver       dirige AW/W (em paralelo, com atrasos sorteados), B, AR, R
//   axil_monitor      publica cada transacao COMPLETA (no handshake de B ou R)
//   axil_agent        junta os tres; passivo = so monitor
//   axil_reg_adapter  converte uvm_reg_bus_op <-> axil_item (RAL)
//=============================================================================
package axil_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    //=========================================================================
    class axil_item extends uvm_sequence_item;
        rand bit        write;
        rand bit [5:0]  addr;
        rand bit [31:0] data;         // escrita: dado; leitura: preenchido pelo driver
        bit      [3:0]  strb = 4'hF;  // o RAL ajusta pelo byte enable
        bit      [1:0]  resp;

        // Atrasos em ciclos: AW e W chegam em momentos diferentes (o escravo
        // precisa aceitar os dois em qualquer ordem) e o bready/rready demora.
        rand int unsigned aw_delay;
        rand int unsigned w_delay;
        rand int unsigned resp_delay;

        constraint c_addr  { addr[1:0] == 2'b00; }
        constraint c_delay { aw_delay   <= 3;
                             w_delay    <= 3;
                             resp_delay <= 2; }

        `uvm_object_utils(axil_item)

        function new(string name = "axil_item");
            super.new(name);
        endfunction

        virtual function string convert2string();
            return $sformatf("%s addr=0x%02h data=0x%08h strb=%b resp=%0d",
                             write ? "ESCRITA" : "LEITURA", addr, data, strb, resp);
        endfunction

        virtual function void do_copy(uvm_object rhs);
            axil_item t;
            super.do_copy(rhs);
            $cast(t, rhs);
            write = t.write; addr = t.addr; data = t.data; strb = t.strb; resp = t.resp;
            aw_delay = t.aw_delay; w_delay = t.w_delay; resp_delay = t.resp_delay;
        endfunction
    endclass

    typedef uvm_sequencer #(axil_item) axil_sequencer;

    //=========================================================================
    class axil_driver extends uvm_driver #(axil_item);
        `uvm_component_utils(axil_driver)
        virtual axil_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axil_driver sem virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            vif.awvalid <= 1'b0; vif.awaddr <= '0; vif.awprot <= '0;
            vif.wvalid  <= 1'b0; vif.wdata  <= '0; vif.wstrb  <= '0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0; vif.araddr <= '0; vif.arprot <= '0;
            vif.rready  <= 1'b0;
            @(posedge vif.aclk iff vif.aresetn);
            forever begin
                seq_item_port.get_next_item(req);
                if (req.write) escreve(req);
                else           le(req);
                seq_item_port.item_done();
            end
        endtask

        // Handshake: quem espera le o ready logo depois da borda -- o valor
        // de antes da borda, o mesmo que o DUT usou.
        task escreve(axil_item t);
            fork
                begin
                    repeat (t.aw_delay) @(posedge vif.aclk);
                    vif.awaddr <= t.addr; vif.awvalid <= 1'b1;
                    do @(posedge vif.aclk); while (!vif.awready);
                    vif.awvalid <= 1'b0;
                end
                begin
                    repeat (t.w_delay) @(posedge vif.aclk);
                    vif.wdata <= t.data; vif.wstrb <= t.strb; vif.wvalid <= 1'b1;
                    do @(posedge vif.aclk); while (!vif.wready);
                    vif.wvalid <= 1'b0;
                end
            join
            repeat (t.resp_delay) @(posedge vif.aclk);
            vif.bready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.bvalid);
            t.resp = vif.bresp;
            vif.bready <= 1'b0;
        endtask

        task le(axil_item t);
            repeat (t.aw_delay) @(posedge vif.aclk);
            vif.araddr <= t.addr; vif.arvalid <= 1'b1;
            do @(posedge vif.aclk); while (!vif.arready);
            vif.arvalid <= 1'b0;
            repeat (t.resp_delay) @(posedge vif.aclk);
            vif.rready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.rvalid);
            t.data = vif.rdata;
            t.resp = vif.rresp;
            vif.rready <= 1'b0;
        endtask
    endclass

    //=========================================================================
    class axil_monitor extends uvm_monitor;
        `uvm_component_utils(axil_monitor)
        virtual axil_if vif;
        uvm_analysis_port #(axil_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axil_if)::get(this, "", "vif", vif))
                `uvm_fatal("NOVIF", "axil_monitor sem virtual interface")
        endfunction

        task run_phase(uvm_phase phase);
            bit [5:0]  aw_q[$], ar_q[$];
            bit [35:0] w_q[$];              // {strb, data}
            forever begin
                @(posedge vif.aclk);
                if (!vif.aresetn) begin
                    aw_q.delete(); w_q.delete(); ar_q.delete();
                    continue;
                end
                if (vif.awvalid && vif.awready) aw_q.push_back(vif.awaddr);
                if (vif.wvalid  && vif.wready)  w_q.push_back({vif.wstrb, vif.wdata});
                if (vif.arvalid && vif.arready) ar_q.push_back(vif.araddr);

                if (vif.bvalid && vif.bready) begin
                    axil_item t = axil_item::type_id::create("mon_wr");
                    bit [35:0] w;
                    if (aw_q.size() == 0 || w_q.size() == 0)
                        `uvm_error("AXIL_MON", "B sem AW/W correspondente")
                    else begin
                        w = w_q.pop_front();
                        t.write = 1'b1;
                        t.addr  = aw_q.pop_front();
                        t.data  = w[31:0];
                        t.strb  = w[35:32];
                        t.resp  = vif.bresp;
                        `uvm_info("AXIL_MON", t.convert2string(), UVM_HIGH)
                        ap.write(t);
                    end
                end
                if (vif.rvalid && vif.rready) begin
                    axil_item t = axil_item::type_id::create("mon_rd");
                    if (ar_q.size() == 0)
                        `uvm_error("AXIL_MON", "R sem AR correspondente")
                    else begin
                        t.write = 1'b0;
                        t.addr  = ar_q.pop_front();
                        t.data  = vif.rdata;
                        t.resp  = vif.rresp;
                        `uvm_info("AXIL_MON", t.convert2string(), UVM_HIGH)
                        ap.write(t);
                    end
                end
            end
        endtask
    endclass

    //=========================================================================
    class axil_agent extends uvm_agent;
        `uvm_component_utils(axil_agent)
        axil_sequencer sqr;
        axil_driver    drv;
        axil_monitor   mon;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = axil_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = axil_sequencer::type_id::create("sqr", this);
                drv = axil_driver::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass

    //=========================================================================
    // Adaptador do RAL: o driver devolve o dado da leitura no proprio item
    // (provides_responses = 0).
    //=========================================================================
    class axil_reg_adapter extends uvm_reg_adapter;
        `uvm_object_utils(axil_reg_adapter)

        function new(string name = "axil_reg_adapter");
            super.new(name);
            supports_byte_enable = 1;
            provides_responses   = 0;
        endfunction

        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            axil_item t = axil_item::type_id::create("ral_item");
            if (!t.randomize() with { write == (rw.kind == UVM_WRITE); addr == rw.addr[5:0]; })
                `uvm_error("ADAPTER", "randomize do axil_item falhou")
            t.data = (rw.kind == UVM_WRITE) ? rw.data[31:0] : 32'h0;
            t.strb = (rw.kind == UVM_WRITE && rw.byte_en != 0) ? rw.byte_en[3:0] : 4'hF;
            return t;
        endfunction

        virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
            axil_item t;
            if (!$cast(t, bus_item)) begin
                `uvm_fatal("ADAPTER", "item nao e axil_item")
                return;
            end
            rw.kind    = t.write ? UVM_WRITE : UVM_READ;
            rw.addr    = t.addr;
            rw.data    = t.data;
            rw.byte_en = t.strb;
            rw.status  = (t.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
        endfunction
    endclass

endpackage
