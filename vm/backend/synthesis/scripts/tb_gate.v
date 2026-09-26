//=============================================================================
// tb_gate.v -- testbench do chip para a VM (Xcelium)
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// O MESMO testbench roda duas vezes (ver run_first.tcl):
//   0) RTL      : frontend/*.v com +define+SRAM_LIB_VIEW
//   2) netlist  : deliverables/<design>.v + celulas sky130
// As duas usam os mesmos modelos de memoria (sram_lib_view_model.v), entao
// a unica diferenca entre elas e o circuito sob teste.
//
//-----------------------------------------------------------------------------
// O QUE ELE VERIFICA
//-----------------------------------------------------------------------------
//   1. saida da UART nunca em X/Z depois do reset (X vindo de estado nao
//      inicializado e o problema tipico de simulacao de portas)
//   2. cada linha "CHK <m> 0x<soma>" do firmware isfft_evm e IGUAL a soma
//      da simulacao RTL (arquivo +CHK_FILE). A soma cobre as 64 palavras
//      que chegaram na DMEM: soma igual = saida da ISFFT igual a do RTL,
//      e o RTL ja deu EVM igual ao da Kria (D32)
//   3. o firmware termina com "RESULTADO: OK" (ID da ISFFT, contadores,
//      sem erro de tlast, DMA sem erro)
//
// NAO ha referencia hierarquica para dentro do chip: nada aqui depende
// dos nomes que o Genus der para instancias e redes.
//
//-----------------------------------------------------------------------------
// PLUSARGS
//-----------------------------------------------------------------------------
//   +IMEM_HEX=<arq>   programa (lido pelo modelo da IMEM, ver
//                     sram_lib_view_model.v)            -- obrigatorio
//   +CHK_FILE=<arq>   somas esperadas, 1 por linha, hex -- isfft_evm
//   +BAUD=<n>         baud da UART do firmware (isfft_evm: 1000000,
//                     padrao; hello: 115200)
//   +LIMITE_MS=<n>    tempo simulado maximo (padrao 10 ms)
//=============================================================================

`timescale 1ns / 1ps

module tb_gate;

    localparam real PERIODO = 20.0;          // 50 MHz (casa com o SDC)

    reg clk  = 1'b0;
    reg rstn = 1'b0;
    always #(PERIODO/2.0) clk = ~clk;

    wire uart_txd;

    //-------------------------------------------------------------------------
    // Chip: RTL ou netlist, mesmo nome e mesmas portas
    //-------------------------------------------------------------------------
    asic_top dut (
        .clk_i       (clk),
        .rstn_i      (rstn),
        .uart0_txd_o (uart_txd),
        .uart0_rxd_i (1'b1)
    );

    //-------------------------------------------------------------------------
    // Reset: 10 ciclos, liberado na descida do clock
    //-------------------------------------------------------------------------
    integer ciclos = 0;
    initial begin
        repeat (10) @(negedge clk);
        rstn = 1'b1;
        $display("[TB] reset liberado em %0t ns", $time);
    end
    always @(posedge clk) if (rstn) ciclos <= ciclos + 1;

    integer erros = 0;

    //-------------------------------------------------------------------------
    // 1. UART em X/Z depois do reset
    //-------------------------------------------------------------------------
    reg avisou_x = 1'b0;
    always @(posedge clk) begin
        if (rstn && ciclos > 20 && (uart_txd !== 1'b0) && (uart_txd !== 1'b1) && !avisou_x) begin
            avisou_x = 1'b1;
            erros = erros + 1;
            $display("[TB] ERRO: uart0_txd_o = %b no ciclo %0d -- X/Z vindo de estado nao inicializado", uart_txd, ciclos);
        end
    end

    //-------------------------------------------------------------------------
    // Somas esperadas (da simulacao RTL)
    //-------------------------------------------------------------------------
    reg  [31:0]  chk_esp [0:15];
    integer      n_esp = 0, k;
    reg  [1023:0] arq;

    initial begin
        for (k = 0; k < 16; k = k + 1) chk_esp[k] = 32'hxxxxxxxx;
        if ($value$plusargs("CHK_FILE=%s", arq)) begin
            $readmemh(arq, chk_esp);
            for (k = 0; k < 16; k = k + 1) if (chk_esp[k] !== 32'hxxxxxxxx) n_esp = k + 1;
            $display("[TB] %0d somas esperadas em %0s", n_esp, arq);
        end
    end

    //-------------------------------------------------------------------------
    // UART: decodifica linhas; 2. CHK; 3. RESULTADO
    //-------------------------------------------------------------------------
    integer   baud, m, n_chk = 0;
    real      tbit;
    reg [7:0] ch;
    reg [8*200-1:0] linha;
    reg [31:0] soma;
    reg        viu_ok = 1'b0;
    integer    i;

    initial begin
        if (!$value$plusargs("BAUD=%d", baud)) baud = 1000000;
        tbit  = 1.0e9 / baud;
        linha = 0;
        wait (rstn);
        forever begin
            @(negedge uart_txd);
            #(tbit * 1.5);
            for (i = 0; i < 8; i = i + 1) begin ch[i] = uart_txd; #(tbit); end
            if (ch == 8'h0A) begin
                $display("[UART] %0s", linha);
                // Espaco no inicio do formato: 'linha' tem zeros a esquerda
                // (bytes nao usados), que o Xcelium le como espaco. Sem o
                // espaco, o $sscanf do Xcelium nunca casa (o Icarus ignora).
                if ($sscanf(linha, " CHK %d 0x%h", m, soma) == 2) begin
                    n_chk = n_chk + 1;
                    if (m >= n_esp)
                        $display("[TB] matriz %0d: soma 0x%h (sem valor esperado)", m, soma);
                    else if (soma !== chk_esp[m]) begin
                        erros = erros + 1;
                        $display("[TB] ERRO matriz %0d: soma 0x%h, RTL 0x%h", m, soma, chk_esp[m]);
                    end else
                        $display("[TB] matriz %0d: soma = RTL (0x%h)", m, soma);
                end
                if (linha[8*13-1:0] == "RESULTADO: OK") viu_ok = 1'b1;
                if (linha[8*5-1:0]  == "#FIM#") fim;
                linha = 0;
            end else if (ch != 8'h0D)
                linha = {linha[8*199-1:0], ch};
            $fflush();
        end
    end

    task fim;
        begin
            if (n_esp != 0 && n_chk != n_esp) begin
                erros = erros + 1;
                $display("[TB] ERRO: %0d CHK recebidos, %0d esperados", n_chk, n_esp);
            end
            $display("[TB] fim em %0.3f ms (%0d ciclos)", $time/1.0e6, ciclos);
            if (viu_ok && erros == 0) $display("[TB] PASSOU");
            else                      $display("[TB] FALHOU (%0d erros, RESULTADO OK = %0d)", erros, viu_ok);
            $finish;
        end
    endtask

    //-------------------------------------------------------------------------
    // Limite de tempo
    //-------------------------------------------------------------------------
    real limite_ms;
    integer lim;
    initial begin
        if ($value$plusargs("LIMITE_MS=%d", lim)) limite_ms = lim; else limite_ms = 10.0;
        #(limite_ms * 1.0e6);
        $display("[TB] FALHOU: tempo limite de %0.1f ms (%0d ciclos, %0d CHK)", limite_ms, ciclos, n_chk);
        $finish;
    end

endmodule
