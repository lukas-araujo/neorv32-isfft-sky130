`timescale 1 ns / 1 ps
// =============================================================================
// isfft_axi_v4 - isfft_axi_v3 com in_mem e out_mem em macro OpenRAM (ASIC)
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130). Decisao D26 do DIARIO.
//
// O QUE MUDOU EM RELACAO A v3 (o resto e copia fiel -- diff mostra):
//   1. in_mem (64 x 64)  -> macro sram_1rw1r_64x64_wpr2 (H)
//      Escrita pela porta 0, leitura pela porta 1. A leitura da macro chega
//      1 ciclo DEPOIS da leitura registrada da v3, entao o dado passa pelo
//      mesmo registrador core_x e o next_in do nucleo e atrasado 1 ciclo:
//      o nucleo ve exatamente a mesma sequencia (next_in, dado) da v3.
//   2. out_mem (256 x 64) -> macro sram_1rw1r_64x256 (F)
//      A v3 lia de forma ASSINCRONA (tdata = out_mem[rd_ptr]). A macro so
//      tem leitura sincrona, entao entra uma PRE-BUSCA: um buffer de saida
//      de 2 palavras em registrador, abastecido pela porta 1. tdata sai de
//      registrador. Ocupacao total (out_used, cheio, reserva) nao muda.
//   3. reset do nucleo Spiral estendido por 127 ciclos (core_rst): varre
//      as cadeias de 'next' sem reset antes de o nucleo comecar; a
//      primeira matriz so e entregue depois disso.
//   4. next_out do nucleo so e aceito depois da primeira matriz entregue
//      (core_armado): o Spiral gera next_out por registradores sem reset,
//      que no silicio ligam com valor qualquer. Sem isto, pulsos falsos
//      logo apos o reset empurrariam lixo na FIFO de saida.
//   Nada muda no plano de controle, no mapa de registradores nem no ID.
//
// Leitura e escrita nunca acontecem no mesmo endereco no mesmo ciclo
// (a leitura so pega palavra ja confirmada/escrita; ver comentarios).
//
// Tamanhos fixos pelas macros: IN_AW = 6, OUT_AW = 8.
//
// ---------------------------------------------------------------------------
// Texto original da v3:
//
// isfft_axi_v3 - Wrapper da ISFFT 8x8 com plano de controle AXI4-Lite
//
//  S00_AXIS -> [buffer de entrada] -> [liberador] -> top_isfft -> [FIFO saida] -> M00_AXIS
//
//  - A entrada so e "confirmada" (commit) a cada 32 palavras. Se chegar tlast
//    no meio de uma matriz, as palavras parciais sao descartadas (rollback).
//  - O liberador so entrega uma matriz ao nucleo quando ha 32 palavras
//    confirmadas E espaco reservado para 32 palavras na FIFO de saida.
//    Assim o nucleo sempre recebe 32 palavras contiguas e nunca perde saida.
//  - A saida respeita tready. tlast a cada PKT_MAT matrizes.
//
//  Mapa de registradores (offset):
//   0x00 CTRL    R/W  [0] enable  [1] soft reset (nivel)  [2] limpa erros (W1, auto-limpa)
//   0x04 STATUS  RO   [0] busy  [1] ha matriz na entrada  [2] FIFO saida cheia
//                     [3] FIFO saida com dados  [8] erro tlast  [9] overflow interno
//   0x08 MAT_IN  RO   matrizes confirmadas na entrada
//   0x0C MAT_OUT RO   matrizes entregues na saida
//   0x10 ERR_CNT RO   numero de erros de tlast
//   0x14 ID      RO   0x15FF0300
//   0x18 PKT_MAT R/W  matrizes por pacote de saida (tlast). 0 = 1. Mudar com enable=0.
// =============================================================================
module isfft_axi_v4 #
(
    parameter integer IN_AW              = 6,   // buffer de entrada: 2^6 = 64 palavras (minimo 6)
    parameter integer OUT_AW             = 8,   // FIFO de saida: 2^8 = 256 palavras (minimo 6)
    parameter integer C_S_AXI_ADDR_WIDTH = 6
)
(
    (* X_INTERFACE_INFO = "xilinx.com:signal:clock:1.0 aclk CLK" *)
    (* X_INTERFACE_PARAMETER = "ASSOCIATED_BUSIF s_axi:s00_axis:m00_axis, ASSOCIATED_RESET aresetn" *)
    input  wire        aclk,
    (* X_INTERFACE_INFO = "xilinx.com:signal:reset:1.0 aresetn RST" *)
    (* X_INTERFACE_PARAMETER = "POLARITY ACTIVE_LOW" *)
    input  wire        aresetn,

    // ---------------- AXI4-Lite (controle) ----------------
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_awaddr,
    input  wire [2:0]  s_axi_awprot,
    input  wire        s_axi_awvalid,
    output wire        s_axi_awready,
    input  wire [31:0] s_axi_wdata,
    input  wire [3:0]  s_axi_wstrb,
    input  wire        s_axi_wvalid,
    output wire        s_axi_wready,
    output wire [1:0]  s_axi_bresp,
    output reg         s_axi_bvalid,
    input  wire        s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] s_axi_araddr,
    input  wire [2:0]  s_axi_arprot,
    input  wire        s_axi_arvalid,
    output wire        s_axi_arready,
    output reg  [31:0] s_axi_rdata,
    output wire [1:0]  s_axi_rresp,
    output reg         s_axi_rvalid,
    input  wire        s_axi_rready,

    // ---------------- AXI4-Stream entrada ----------------
    input  wire [63:0] s00_axis_tdata,
    input  wire [7:0]  s00_axis_tkeep,
    input  wire        s00_axis_tlast,
    input  wire        s00_axis_tvalid,
    output wire        s00_axis_tready,

    // ---------------- AXI4-Stream saida ----------------
    output wire [63:0] m00_axis_tdata,
    output wire [7:0]  m00_axis_tkeep,
    output wire        m00_axis_tlast,
    output wire        m00_axis_tvalid,
    input  wire        m00_axis_tready
);

    localparam integer IN_DEPTH  = 1 << IN_AW;
    localparam integer OUT_DEPTH = 1 << OUT_AW;

    // As macros tem tamanho fixo: outro valor para a elaboracao.
    generate
        if (IN_AW != 6) begin : g_erro_in_aw
            ERRO_isfft_axi_v4_macro_in_mem_so_suporta_IN_AW_6 u_erro ();
        end
        if (OUT_AW != 8) begin : g_erro_out_aw
            ERRO_isfft_axi_v4_macro_out_mem_so_suporta_OUT_AW_8 u_erro ();
        end
    endgenerate

    // =========================================================================
    // Registradores de controle
    // =========================================================================
    reg        ctrl_enable;
    reg        ctrl_soft_rst;
    reg        clr_err;          // pulso de 1 ciclo
    reg [15:0] pkt_mat;

    wire dp_rst = ~aresetn | ctrl_soft_rst;   // reset do caminho de dados

    // -------------------------------------------------------------------------
    // v4: reset ESTENDIDO do nucleo Spiral (127 ciclos alem do dp_rst)
    //
    // O Spiral encadeia o 'next' por registradores de deslocamento SEM reset
    // (shiftRegFIFO); cada FFT 1D tem 41 ciclos de latencia. Com reset curto
    // (o do chip dura 10 ciclos), o next_out da IFFT ainda carrega o valor
    // de power-up quando o reset acaba: dispara write_fsm/read_fsm e o next
    // da FFT, e os seletores de banco dos blocos de permutacao (inFlip0/
    // outFlip0, que so alternam: ~X = X) ficam corrompidos para sempre.
    // Segurando o reset do nucleo por 127 ciclos com next_in = 0, toda a
    // cadeia e varrida com zeros antes de o nucleo sair do reset -- no
    // silicio e na simulacao de portas. (No RTL nada disso aparece: 'if (X)'
    // conta como falso.) Achado na simulacao de portas -- DIARIO, 13a sessao.
    // -------------------------------------------------------------------------
    reg  [6:0] core_rst_cnt;
    always @(posedge aclk) begin
        if (dp_rst)                    core_rst_cnt <= 7'd127;
        else if (core_rst_cnt != 7'd0) core_rst_cnt <= core_rst_cnt - 1'b1;
    end
    wire core_rst = dp_rst | (core_rst_cnt != 7'd0);

    // =========================================================================
    // Buffer de entrada com commit a cada 32 palavras
    // =========================================================================
    reg [IN_AW:0] in_wr_ptr;     // proxima escrita
    reg [IN_AW:0] in_wr_commit;  // fim da ultima matriz completa
    reg [IN_AW:0] in_rd_ptr;
    reg [4:0]     in_wcnt;       // posicao da palavra dentro da matriz (0..31)

    wire [IN_AW:0] in_used  = in_wr_ptr    - in_rd_ptr;
    wire [IN_AW:0] in_avail = in_wr_commit - in_rd_ptr;

    assign s00_axis_tready = ~dp_rst & (in_used != IN_DEPTH);

    wire in_hs       = s00_axis_tvalid & s00_axis_tready;
    wire in_last_err = in_hs & s00_axis_tlast & (in_wcnt != 5'd31);
    wire in_commit   = in_hs & (in_wcnt == 5'd31);

    // in_mem: macro 1rw1r 64 x 64. Porta 0 so escreve; porta 1 so le.
    // Conflito impossivel: a leitura so pega palavra ja confirmada, e a
    // escrita so ocorre com in_used < 64, entao in_wr_ptr != in_rd_ptr
    // (modulo 64) sempre que as duas portas estao ativas.
    wire [63:0] in_rdata;
    wire        in_rd_en;              // definido no liberador

    sram_1rw1r_64x64_wpr2 u_in_mem (
        .clk0  (aclk),
        .csb0  (~in_hs),
        .web0  (1'b0),
        .addr0 (in_wr_ptr[IN_AW-1:0]),
        .din0  (s00_axis_tdata),
        .dout0 (),
        .clk1  (aclk),
        .csb1  (~in_rd_en),
        .addr1 (in_rd_ptr[IN_AW-1:0]),
        .dout1 (in_rdata)
    );

    always @(posedge aclk) begin
        if (dp_rst) begin
            in_wr_ptr    <= 0;
            in_wr_commit <= 0;
            in_wcnt      <= 5'd0;
        end else if (in_hs) begin
            if (in_last_err) begin
                // tlast no meio da matriz: descarta as palavras parciais
                in_wr_ptr <= in_wr_commit;
                in_wcnt   <= 5'd0;
            end else begin
                in_wr_ptr <= in_wr_ptr + 1'b1;
                in_wcnt   <= in_wcnt + 1'b1;          // 31 -> 0 naturalmente
                if (in_wcnt == 5'd31)
                    in_wr_commit <= in_wr_ptr + 1'b1;
            end
        end
    end

    // =========================================================================
    // FIFO de saida + reserva de espaco
    // =========================================================================
    reg [OUT_AW:0]   out_wr_ptr;
    reg [OUT_AW:0]   out_rd_ptr;   // palavras ENTREGUES na saida (como na v3)
    reg [OUT_AW+1:0] reserved;   // palavras prometidas ao nucleo e ainda nao escritas

    wire [OUT_AW:0]   out_used = out_wr_ptr - out_rd_ptr;
    wire [OUT_AW+1:0] out_free = OUT_DEPTH - out_used - reserved;
    wire              out_full = (out_used == OUT_DEPTH);

    // =========================================================================
    // Liberador: entrega 32 palavras contiguas ao nucleo
    // (mesma temporizacao do wrapper validado na etapa 1: next_in junto
    //  com a palavra 0 da linha e dados registrados 1 ciclo depois)
    // =========================================================================
    reg        launch_active;
    reg [4:0]  launch_cnt;
    reg [63:0] core_x;

    wire launch_start = ~core_rst & ctrl_enable & ~launch_active &
                        (in_avail >= 32) & (out_free >= 32);

    always @(posedge aclk) begin
        if (dp_rst) begin
            launch_active <= 1'b0;
            launch_cnt    <= 5'd0;
            in_rd_ptr     <= 0;
        end else if (launch_start) begin
            launch_active <= 1'b1;
            launch_cnt    <= 5'd0;
        end else if (launch_active) begin
            in_rd_ptr  <= in_rd_ptr + 1'b1;
            launch_cnt <= launch_cnt + 1'b1;
            if (launch_cnt == 5'd31)
                launch_active <= 1'b0;
        end
    end

    // v3: core_x <= in_mem[in_rd_ptr] no ciclo em que launch_active = 1.
    // v4: o endereco vai para a macro nesse ciclo; o dado sai da macro no
    //     ciclo seguinte e so entao e registrado em core_x (+1 ciclo).
    assign in_rd_en = launch_active;

    reg in_rd_v;                      // leitura da macro chegando neste ciclo
    always @(posedge aclk) begin
        if (dp_rst) in_rd_v <= 1'b0;
        else        in_rd_v <= in_rd_en;
    end

    always @(posedge aclk) begin
        if (in_rd_v)
            core_x <= in_rdata;
    end

    // next_in atrasado 1 ciclo junto com o dado: o nucleo ve a mesma
    // sequencia da v3, so que 1 ciclo depois.
    reg core_next_in;
    always @(posedge aclk) begin
        if (dp_rst) core_next_in <= 1'b0;
        else        core_next_in <= launch_active & (launch_cnt[1:0] == 2'd0);
    end

    // =========================================================================
    // Nucleo ISFFT (inalterado; reset estendido -- core_rst)
    // =========================================================================
    wire [15:0] core_y0, core_y1, core_y2, core_y3;
    wire        core_next_out;

    top_isfft inst_isfft_matriz (
        .clk      (aclk),
        .reset    (core_rst),
        .next_in  (core_next_in),
        .in_X0    (core_x[15:0]),
        .in_X1    (core_x[31:16]),
        .in_X2    (core_x[47:32]),
        .in_X3    (core_x[63:48]),
        .next_out (core_next_out),
        .out_Y0   (core_y0),
        .out_Y1   (core_y1),
        .out_Y2   (core_y2),
        .out_Y3   (core_y3)
    );

    // Captura da saida do nucleo (mesma logica da etapa 1)
    //
    // v4: next_out so vale DEPOIS da primeira matriz entregue ao nucleo.
    // O Spiral gera next_out por registradores de deslocamento SEM reset
    // (shiftRegFIFO). No FPGA eles ligam em 0; no silicio ligam com valor
    // qualquer, e ate o next_in (0 no reset) varrer a cadeia podem sair
    // pulsos falsos de next_out -- lixo empurrado na FIFO de saida logo
    // apos o reset. Na simulacao de portas isso aparece como X que
    // contamina out_valid_sr, a FIFO, o SLINK e a CPU. (No RTL nao
    // aparece: 'if (X)' conta como falso.) Achado na simulacao de portas
    // da nuvem -- ver DIARIO, 13a sessao.
    reg core_armado;
    always @(posedge aclk) begin
        if (dp_rst)            core_armado <= 1'b0;
        else if (launch_start) core_armado <= 1'b1;
    end

    reg [3:0] out_valid_sr;
    always @(posedge aclk) begin
        if (dp_rst)
            out_valid_sr <= 4'b0000;
        else if (core_next_out & core_armado)
            out_valid_sr <= 4'b1111;
        else
            out_valid_sr <= {1'b0, out_valid_sr[3:1]};
    end

    wire        core_push = out_valid_sr[0];
    wire [63:0] core_y    = {core_y3, core_y2, core_y1, core_y0};
    wire        out_ovf   = core_push & out_full;   // nao deve ocorrer (reserva)

    // -------------------------------------------------------------------------
    // out_mem: macro 1rw1r 256 x 64 + pre-busca (buffer de saida de 2 palavras)
    //
    //   out_wr_ptr  : proxima escrita na macro (nucleo)
    //   ram_rd_ptr  : proxima palavra a BUSCAR na macro
    //   out_rd_ptr  : palavras ENTREGUES no AXIS (define out_used, igual a v3)
    //
    //   macro --(porta 1, 1 ciclo)--> ob_q0 / ob_q1 --> m00_axis
    //
    // Conflito impossivel: busca so com ram_cnt != 0 (ram_rd_ptr != out_wr_ptr);
    // ram_cnt = 256 exigiria out_used >= 256, e ai out_full bloqueia a escrita.
    // -------------------------------------------------------------------------
    reg  [OUT_AW:0] ram_rd_ptr;
    wire [OUT_AW:0] ram_cnt = out_wr_ptr - ram_rd_ptr;   // palavras ainda so na macro

    reg  [63:0] ob_q0, ob_q1;          // q0 = cabeca (vai para tdata)
    reg  [1:0]  ob_n;                  // palavras no buffer (0..2)
    reg         ob_pend;               // busca emitida no ciclo anterior: dado chegando
    wire [63:0] out_rdata;

    assign m00_axis_tvalid = (ob_n != 2'd0);
    assign m00_axis_tdata  = ob_q0;
    assign m00_axis_tkeep  = 8'hFF;
    wire   out_hs          = m00_axis_tvalid & m00_axis_tready;

    // Busca se ha palavra na macro e lugar no buffer contando o que ja esta
    // a caminho. A saida no mesmo ciclo libera lugar (vazao de 1 palavra/ciclo).
    wire [1:0] ob_ocup  = ob_n + ob_pend;              // nunca passa de 2
    wire       ob_fetch = ~dp_rst & (ram_cnt != 0) &
                          ((ob_ocup != 2'd2) | out_hs);

    sram_1rw1r_64x256 u_out_mem (
        .clk0  (aclk),
        .csb0  (~(core_push & ~out_full)),
        .web0  (1'b0),
        .addr0 (out_wr_ptr[OUT_AW-1:0]),
        .din0  (core_y),
        .dout0 (),
        .clk1  (aclk),
        .csb1  (~ob_fetch),
        .addr1 (ram_rd_ptr[OUT_AW-1:0]),
        .dout1 (out_rdata)
    );

    always @(posedge aclk) begin
        if (dp_rst) begin
            ram_rd_ptr <= 0;
            ob_pend    <= 1'b0;
            ob_n       <= 2'd0;
        end else begin
            if (ob_fetch) ram_rd_ptr <= ram_rd_ptr + 1'b1;
            ob_pend <= ob_fetch;
            ob_n    <= ob_n + ob_pend - out_hs;
        end
    end

    // Dados do buffer (sem reset: so valem com ob_n)
    always @(posedge aclk) begin
        case ({ob_pend, out_hs})
            2'b10: begin                          // chega sem sair
                if (ob_n == 2'd0) ob_q0 <= out_rdata;
                else              ob_q1 <= out_rdata;
            end
            2'b01: ob_q0 <= ob_q1;                // sai sem chegar
            2'b11: begin                          // sai e chega
                if (ob_n == 2'd1) ob_q0 <= out_rdata;
                else begin        ob_q0 <= ob_q1; ob_q1 <= out_rdata; end
            end
            default: ;
        endcase
    end

    always @(posedge aclk) begin
        if (dp_rst) begin
            out_wr_ptr <= 0;
            out_rd_ptr <= 0;
            reserved   <= 0;
        end else begin
            if (core_push & ~out_full) out_wr_ptr <= out_wr_ptr + 1'b1;
            if (out_hs)                out_rd_ptr <= out_rd_ptr + 1'b1;

            case ({launch_start, core_push & (reserved != 0)})
                2'b10: reserved <= reserved + 32;
                2'b01: reserved <= reserved - 1'b1;
                2'b11: reserved <= reserved + 31;
                default: ;
            endcase
        end
    end

    // =========================================================================
    // tlast de saida e contadores
    // =========================================================================
    reg  [4:0]  out_wcnt;
    reg  [15:0] out_pkt_cnt;
    wire [15:0] pkt_eff = (pkt_mat == 16'd0) ? 16'd1 : pkt_mat;

    assign m00_axis_tlast = m00_axis_tvalid & (out_wcnt == 5'd31) &
                            (out_pkt_cnt >= pkt_eff - 1'b1);

    reg [31:0] mat_in_cnt, mat_out_cnt, err_cnt;
    reg        err_tlast, err_ovf;

    always @(posedge aclk) begin
        if (dp_rst) begin
            out_wcnt    <= 5'd0;
            out_pkt_cnt <= 16'd0;
            mat_in_cnt  <= 32'd0;
            mat_out_cnt <= 32'd0;
        end else begin
            if (in_commit)
                mat_in_cnt <= mat_in_cnt + 1'b1;
            if (out_hs) begin
                out_wcnt <= out_wcnt + 1'b1;
                if (out_wcnt == 5'd31) begin
                    mat_out_cnt <= mat_out_cnt + 1'b1;
                    out_pkt_cnt <= m00_axis_tlast ? 16'd0 : out_pkt_cnt + 1'b1;
                end
            end
        end
    end

    always @(posedge aclk) begin
        if (~aresetn | clr_err) begin
            err_cnt   <= 32'd0;
            err_tlast <= 1'b0;
            err_ovf   <= 1'b0;
        end else begin
            if (in_last_err) begin
                err_cnt   <= err_cnt + 1'b1;
                err_tlast <= 1'b1;
            end
            if (out_ovf)
                err_ovf <= 1'b1;
        end
    end

    wire [31:0] status = { 22'd0,
                           err_ovf,              // [9]
                           err_tlast,            // [8]
                           4'd0,
                           (out_used != 0),      // [3]
                           out_full,             // [2]
                           (in_avail >= 32),     // [1]
                           (launch_active | (reserved != 0)) }; // [0]

    // =========================================================================
    // Escravo AXI4-Lite
    // =========================================================================
    reg [C_S_AXI_ADDR_WIDTH-1:0] aw_addr;
    reg        aw_q, w_q;
    reg [31:0] w_data;
    reg [3:0]  w_strb;

    assign s_axi_awready = ~aw_q;
    assign s_axi_wready  = ~w_q;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = ~s_axi_rvalid;
    assign s_axi_rresp   = 2'b00;

    always @(posedge aclk) begin
        if (~aresetn) begin
            aw_q          <= 1'b0;
            w_q           <= 1'b0;
            aw_addr       <= 0;
            w_data        <= 32'd0;
            w_strb        <= 4'd0;
            s_axi_bvalid  <= 1'b0;
            ctrl_enable   <= 1'b0;
            ctrl_soft_rst <= 1'b0;
            clr_err       <= 1'b0;
            pkt_mat       <= 16'd1;
        end else begin
            clr_err <= 1'b0;

            if (s_axi_awvalid & ~aw_q) begin
                aw_q    <= 1'b1;
                aw_addr <= s_axi_awaddr;
            end
            if (s_axi_wvalid & ~w_q) begin
                w_q    <= 1'b1;
                w_data <= s_axi_wdata;
                w_strb <= s_axi_wstrb;
            end

            if (aw_q & w_q & ~s_axi_bvalid) begin
                aw_q         <= 1'b0;
                w_q          <= 1'b0;
                s_axi_bvalid <= 1'b1;
                case (aw_addr[5:0])
                    6'h00: if (w_strb[0]) begin
                        ctrl_enable   <= w_data[0];
                        ctrl_soft_rst <= w_data[1];
                        clr_err       <= w_data[2];
                    end
                    6'h18: begin
                        if (w_strb[0]) pkt_mat[7:0]  <= w_data[7:0];
                        if (w_strb[1]) pkt_mat[15:8] <= w_data[15:8];
                    end
                    default: ;
                endcase
            end

            if (s_axi_bvalid & s_axi_bready)
                s_axi_bvalid <= 1'b0;
        end
    end

    always @(posedge aclk) begin
        if (~aresetn) begin
            s_axi_rvalid <= 1'b0;
            s_axi_rdata  <= 32'd0;
        end else if (s_axi_arvalid & ~s_axi_rvalid) begin
            s_axi_rvalid <= 1'b1;
            case (s_axi_araddr[5:0])
                6'h00:   s_axi_rdata <= {29'd0, 1'b0, ctrl_soft_rst, ctrl_enable};
                6'h04:   s_axi_rdata <= status;
                6'h08:   s_axi_rdata <= mat_in_cnt;
                6'h0C:   s_axi_rdata <= mat_out_cnt;
                6'h10:   s_axi_rdata <= err_cnt;
                6'h14:   s_axi_rdata <= 32'h15FF0300;
                6'h18:   s_axi_rdata <= {16'd0, pkt_mat};
                default: s_axi_rdata <= 32'd0;
            endcase
        end else if (s_axi_rvalid & s_axi_rready) begin
            s_axi_rvalid <= 1'b0;
        end
    end

endmodule