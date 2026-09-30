//=============================================================================
// isfft_regs.svh -- modelo de registradores (RAL) do isfft_axi_v4
//
// Mapa (cabecalho do isfft_axi_v4.v):
//   0x00 CTRL    R/W  [0] enable  [1] soft reset (nivel)  [2] limpa erros (pulso)
//   0x04 STATUS  RO   [0] busy [1] matriz na entrada [2] FIFO cheia
//                     [3] FIFO com dados [8] erro tlast [9] overflow interno
//   0x08 MAT_IN  RO   matrizes confirmadas na entrada
//   0x0C MAT_OUT RO   matrizes entregues na saida
//   0x10 ERR_CNT RO   erros de tlast (pacote truncado)
//   0x14 ID      RO   0x15FF0300
//   0x18 PKT_MAT R/W  [15:0] matrizes por pacote de saida (0 = 1)
//
// Os contadores (MAT_IN, MAT_OUT, ERR_CNT) nao mudam por escrita: quem
// atualiza o valor esperado deles no RAL e o modelo de referencia e o
// scoreboard, com predict(). Um mirror(UVM_CHECK) depois compara com o DUT.
// STATUS muda sozinho a todo ciclo: volatil e sem checagem automatica (os
// bits que importam sao conferidos a mao nas sequencias).
//=============================================================================

class isfft_reg_ctrl extends uvm_reg;
    `uvm_object_utils(isfft_reg_ctrl)
    rand uvm_reg_field enable;
    rand uvm_reg_field soft_rst;
    rand uvm_reg_field clr_err;
    function new(string name = "CTRL");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
        enable   = uvm_reg_field::type_id::create("enable");
        soft_rst = uvm_reg_field::type_id::create("soft_rst");
        clr_err  = uvm_reg_field::type_id::create("clr_err");
        //                parent size lsb access  volatile reset has_rst rand indiv
        enable.configure  (this, 1,  0,  "RW",   0,       0,    1,      1,   0);
        soft_rst.configure(this, 1,  1,  "RW",   0,       0,    1,      1,   0);
        clr_err.configure (this, 1,  2,  "WO",   0,       0,    1,      1,   0);
        clr_err.set_compare(UVM_NO_CHECK);   // pulso: sempre le 0
    endfunction
endclass

class isfft_reg_status extends uvm_reg;
    `uvm_object_utils(isfft_reg_status)
    uvm_reg_field busy, in_mat, out_cheia, out_dados, err_tlast, err_ovf;
    function new(string name = "STATUS");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
        busy      = uvm_reg_field::type_id::create("busy");
        in_mat    = uvm_reg_field::type_id::create("in_mat");
        out_cheia = uvm_reg_field::type_id::create("out_cheia");
        out_dados = uvm_reg_field::type_id::create("out_dados");
        err_tlast = uvm_reg_field::type_id::create("err_tlast");
        err_ovf   = uvm_reg_field::type_id::create("err_ovf");
        busy.configure     (this, 1, 0, "RO", 1, 0, 1, 0, 0);
        in_mat.configure   (this, 1, 1, "RO", 1, 0, 1, 0, 0);
        out_cheia.configure(this, 1, 2, "RO", 1, 0, 1, 0, 0);
        out_dados.configure(this, 1, 3, "RO", 1, 0, 1, 0, 0);
        err_tlast.configure(this, 1, 8, "RO", 1, 0, 1, 0, 0);
        err_ovf.configure  (this, 1, 9, "RO", 1, 0, 1, 0, 0);
        // volatil e sem checagem automatica (nem o hw_reset compara): os
        // bits sao conferidos a mao nas sequencias
        busy.set_compare(UVM_NO_CHECK);   in_mat.set_compare(UVM_NO_CHECK);
        out_cheia.set_compare(UVM_NO_CHECK); out_dados.set_compare(UVM_NO_CHECK);
        err_tlast.set_compare(UVM_NO_CHECK); err_ovf.set_compare(UVM_NO_CHECK);
    endfunction
endclass

// Registrador de 32 bits somente leitura (contadores e ID)
class isfft_reg_ro32 extends uvm_reg;
    `uvm_object_utils(isfft_reg_ro32)
    uvm_reg_field valor;
    uvm_reg_data_t reset_val = 0;
    function new(string name = "RO32");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
        valor = uvm_reg_field::type_id::create("valor");
        valor.configure(this, 32, 0, "RO", 0, reset_val, 1, 0, 1);
    endfunction
endclass

class isfft_reg_pkt_mat extends uvm_reg;
    `uvm_object_utils(isfft_reg_pkt_mat)
    rand uvm_reg_field pkt_mat;
    function new(string name = "PKT_MAT");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction
    virtual function void build();
        pkt_mat = uvm_reg_field::type_id::create("pkt_mat");
        pkt_mat.configure(this, 16, 0, "RW", 0, 1, 1, 1, 0);
    endfunction
endclass

class isfft_reg_block extends uvm_reg_block;
    `uvm_object_utils(isfft_reg_block)
    rand isfft_reg_ctrl    CTRL;
    isfft_reg_status       STATUS;
    isfft_reg_ro32         MAT_IN, MAT_OUT, ERR_CNT, ID;
    rand isfft_reg_pkt_mat PKT_MAT;

    function new(string name = "isfft_regs");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        default_map = create_map("map", 'h0, 4, UVM_LITTLE_ENDIAN);

        CTRL    = isfft_reg_ctrl::type_id::create("CTRL");
        STATUS  = isfft_reg_status::type_id::create("STATUS");
        MAT_IN  = isfft_reg_ro32::type_id::create("MAT_IN");
        MAT_OUT = isfft_reg_ro32::type_id::create("MAT_OUT");
        ERR_CNT = isfft_reg_ro32::type_id::create("ERR_CNT");
        ID      = isfft_reg_ro32::type_id::create("ID");
        ID.reset_val = 32'h15FF0300;
        PKT_MAT = isfft_reg_pkt_mat::type_id::create("PKT_MAT");

        CTRL.configure(this);    CTRL.build();
        STATUS.configure(this);  STATUS.build();
        MAT_IN.configure(this);  MAT_IN.build();
        MAT_OUT.configure(this); MAT_OUT.build();
        ERR_CNT.configure(this); ERR_CNT.build();
        ID.configure(this);      ID.build();
        PKT_MAT.configure(this); PKT_MAT.build();

        default_map.add_reg(CTRL,    'h00, "RW");
        default_map.add_reg(STATUS,  'h04, "RO");
        default_map.add_reg(MAT_IN,  'h08, "RO");
        default_map.add_reg(MAT_OUT, 'h0C, "RO");
        default_map.add_reg(ERR_CNT, 'h10, "RO");
        default_map.add_reg(ID,      'h14, "RO");
        default_map.add_reg(PKT_MAT, 'h18, "RW");
        lock_model();
    endfunction
endclass
