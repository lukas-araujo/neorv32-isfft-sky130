//=============================================================================
// tb_mem_equiv.v
//
// Equivalencia: IMEM/DMEM com macro OpenRAM  x  IMEM/DMEM original do NEORV32.
//
// A referencia (ref_mem) e o VHDL OFICIAL do NEORV32 convertido para Verilog
// pelo proprio GHDL (ghdl synth) -- nao e um modelo escrito a mao. Os dois
// recebem exatamente o mesmo estimulo e sao comparados em todo ciclo.
//
// Defines de compilacao (escolhidos pelo sim/run_tb_mem.sh):
//   DUT_DMEM          DUT = neorv32_dmem
//   DUT_IMEM          DUT = neorv32_imem (INITROM = 0, RAM)
//   DUT_IMEM_ROM      DUT = neorv32_imem (INITROM = 1, ROM)
//   ROM_HEX="arq"     imagem da ROM, a mesma que o VHDL de referencia usa
//   ROM_WORDS=n       tamanho da imagem em palavras
//   MEM_AWIDTH=n      largura do endereco em bytes (12 = 4 kB DMEM, 13 = 8 kB IMEM)
//
// Fases:
//   1. (RAM) escreve todas as palavras com dado aleatorio nos dois
//      (ROM) carrega a imagem na macro por $readmemh
//   2. N_ACC acessos aleatorios seguindo o protocolo do NEORV32
//      (1 requisicao pendente por vez; pausas aleatorias entre elas)
//   3. rajada: requisicao em TODO ciclo, sem esperar o ack
//
// Comparacao em toda borda de subida:
//   - ack e err identicos
//   - em resposta de leitura: bytes HABILITADOS identicos e sem X
//     (a macro le a palavra inteira; o VHDL so os bytes habilitados)
//   - fora de resposta de leitura: dado identico nos 32 bits (deve ser 0)
//=============================================================================

`timescale 1ns / 1ps

module tb_mem_equiv;

    parameter integer N_ACC = 20000;
    parameter integer SEED  = 1;

`ifdef DUT_IMEM_ROM
    localparam ROM = 1;
`else
    localparam ROM = 0;
`endif
`ifndef MEM_AWIDTH
  `define MEM_AWIDTH 12
`endif
`ifndef ROM_WORDS
  `define ROM_WORDS 1024
`endif
    localparam integer AW    = `MEM_AWIDTH;
    localparam integer WORDS = 1 << (AW - 2);

    reg clk = 1'b0;
    always #10 clk = ~clk;            // 50 MHz
    reg rstn = 1'b0;

    reg  [31:0] addr = 0, wdata = 0;
    reg  [3:0]  ben  = 0;
    reg         stb  = 0, rw = 0;

    wire [31:0] d_data, r_data;
    wire        d_ack, r_ack, d_err, r_err;

    //-------------------------------------------------------------------------
    // DUT
    //-------------------------------------------------------------------------
`ifdef DUT_DMEM
    neorv32_dmem #(.AWIDTH(AW), .OUTREG(0)) dut (
`elsif DUT_IMEM_ROM
    neorv32_imem #(.AWIDTH(AW), .INITROM(1), .OUTREG(0)) dut (
`else
    neorv32_imem #(.AWIDTH(AW), .INITROM(0), .OUTREG(0)) dut (
`endif
        .clk_i(clk), .rstn_i(rstn),
        .req_addr_i(addr), .req_data_i(wdata), .req_ben_i(ben),
        .req_stb_i(stb), .req_rw_i(rw),
        .rsp_data_o(d_data), .rsp_ack_o(d_ack), .rsp_err_o(d_err));

    //-------------------------------------------------------------------------
    // Referencia: VHDL oficial convertido pelo GHDL (generics fixados no synth)
    //-------------------------------------------------------------------------
    ref_mem u_ref (
        .clk_i(clk), .rstn_i(rstn),
        .req_addr_i(addr), .req_data_i(wdata), .req_ben_i(ben),
        .req_stb_i(stb), .req_rw_i(rw),
        .rsp_data_o(r_data), .rsp_ack_o(r_ack), .rsp_err_o(r_err));

    //-------------------------------------------------------------------------
    // Rastreia a requisicao do ciclo anterior (resposta vem 1 ciclo depois)
    //-------------------------------------------------------------------------
    reg        prev_rd = 0;
    reg [3:0]  prev_ben = 0;
    integer    errors = 0, n_rd = 0, n_wr = 0, n_wr_parcial = 0, n_rd_parcial = 0;
    integer    n_cmp_bytes = 0;
    reg [31:0] mask;
    integer    k;

    always @(posedge clk) begin
        if (rstn) begin
            if (d_ack !== r_ack || d_err !== r_err) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[%0t] ERRO handshake: ack dut=%b ref=%b  err dut=%b ref=%b",
                             $time, d_ack, r_ack, d_err, r_err);
            end
            if (prev_rd) begin
                mask = {{8{prev_ben[3]}}, {8{prev_ben[2]}}, {8{prev_ben[1]}}, {8{prev_ben[0]}}};
                if (((d_data & mask) !== (r_data & mask)) || (^(d_data & mask) === 1'bx)) begin
                    errors = errors + 1;
                    if (errors <= 10)
                        $display("[%0t] ERRO leitura: ben=%b dut=%h ref=%h",
                                 $time, prev_ben, d_data, r_data);
                end
                for (k = 0; k < 4; k = k + 1) if (prev_ben[k]) n_cmp_bytes = n_cmp_bytes + 1;
            end else if (d_data !== r_data) begin
                errors = errors + 1;
                if (errors <= 10)
                    $display("[%0t] ERRO dado fora de leitura: dut=%h ref=%h", $time, d_data, r_data);
            end
        end
        prev_rd  <= stb & ~rw;
        prev_ben <= ben;
    end

    //-------------------------------------------------------------------------
    // Tarefas de acesso (dirigem as entradas na borda de descida)
    //
    // 'seed' e declarada ANTES da tarefa que a usa: o Icarus do OSS CAD
    // Suite exige declaracao antes do uso (o do Ubuntu tolerava).
    //-------------------------------------------------------------------------
    integer seed;

    task pulso(input [31:0] a, input [31:0] d, input [3:0] b, input w);
        begin
            @(negedge clk);
            addr = a; wdata = d; ben = b; rw = w; stb = 1'b1;
            @(negedge clk);
            stb = 1'b0;
            addr = $random(seed); wdata = $random(seed);   // barramento "sujo" fora do strobe
            ben = $random(seed); rw = $random(seed);
        end
    endtask

    integer i, pausa;
    reg [31:0] a;
    reg [3:0]  b;
    reg        w;

    function [31:0] endereco_valido(input dummy);
        reg [31:0] r;
        begin
            r = $random(seed);
            if (ROM) r = (r % `ROM_WORDS);          // ROM: so dentro da imagem
            else     r = r & (WORDS - 1);
            r = r << 2;
            // bits altos aleatorios em parte dos acessos: a memoria deve ignora-los
            if (($random(seed) & 3) == 0) r = r | ($random(seed) & ~((32'd1 << AW) - 1));
            endereco_valido = r;
        end
    endfunction

    initial begin
        seed = SEED;
`ifdef DUT_IMEM_ROM
        $readmemh(`ROM_HEX, dut.u_sram.u_macro.mem);
`endif
        repeat (4) @(negedge clk);
        rstn = 1'b1;

        // ---------------- Fase 1: preenche a RAM ----------------
        if (!ROM) begin
            for (i = 0; i < WORDS; i = i + 1)
                pulso(i << 2, $random(seed), 4'hF, 1'b1);
            $display("[TB] fase 1: %0d palavras escritas (AWIDTH %0d)", WORDS, AW);
        end

        // ---------------- Fase 2: acessos aleatorios -------------
        for (i = 0; i < N_ACC; i = i + 1) begin
            a = endereco_valido(0);
            w = ($random(seed) & 1);
            b = $random(seed);
            if (!w && b == 0) b = 4'hF;       // leitura sem byte habilitado nao tem o que comparar
            if (w) begin
                n_wr = n_wr + 1;
                if (b != 4'hF) n_wr_parcial = n_wr_parcial + 1;
            end else begin
                n_rd = n_rd + 1;
                if (b != 4'hF) n_rd_parcial = n_rd_parcial + 1;
            end
            pulso(a, $random(seed), b, w);
            pausa = $random(seed) & 3;         // 0..3 ciclos a mais entre requisicoes
            repeat (pausa) @(negedge clk);
        end
        $display("[TB] fase 2: %0d leituras (%0d parciais), %0d escritas (%0d parciais)",
                 n_rd, n_rd_parcial, n_wr, n_wr_parcial);

        // ---------------- Fase 3: rajada, strobe em todo ciclo ----
        @(negedge clk);
        for (i = 0; i < 2000; i = i + 1) begin
            addr = endereco_valido(0); wdata = $random(seed);
            rw = $random(seed); ben = $random(seed);
            if (!rw && ben == 0) ben = 4'hF;
            stb = 1'b1;
            @(negedge clk);
        end
        stb = 1'b0;
        $display("[TB] fase 3: 2000 acessos em rajada");

        repeat (5) @(negedge clk);
        $display("[TB] bytes comparados em leituras: %0d", n_cmp_bytes);
        if (errors == 0) $display("[TB] PASSOU");
        else             $display("[TB] FALHOU: %0d erros", errors);
        $finish;
    end

endmodule
