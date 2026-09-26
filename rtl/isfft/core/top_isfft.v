module top_isfft (
    input clk,
    input reset,
    
    // Entrada, lembrando que são 2 amostras complexas X e Y por ciclo de clock
    // 16 bits de parte real X0 e 16 bits de parte imaginária X1
    // Entrada é no Domínio de Doppler
    input next_in,
    input [15:0] in_X0, in_X1, in_X2, in_X3,
    
    // Interface de Saída no Domínio Tempo-Frequência e funciona igual a entrada
    output next_out,
    output [15:0] out_Y0, out_Y1, out_Y2, out_Y3
);
    
    // Saídas da IFFT
    wire ifft_next_out;
    wire [15:0] ifft_Y0, ifft_Y1, ifft_Y2, ifft_Y3;
    
    // Sinais da FSM de Escrita
    wire write_en;
    wire [1:0] wr_col_cnt;
    wire [2:0] wr_row_cnt;
    wire wr_bank_sel;
    wire matrix_ready;
    
    // Sinais da FSM de Leitura
    wire fft_next_in;
    wire [2:0] rd_col_cnt;
    wire [1:0] rd_row_pair_cnt;
    wire rd_bank_sel;
    
    // Entradas da FFT saindo do banco de registradores
    reg [15:0] fft_X0, fft_X1, fft_X2, fft_X3;

    // ====================================================================
    //           A MATRIZ DE MEMÓRIA (PING-PONG REGISTER FILE)
    // ====================================================================
    // Matriz 3D: [Banco Ping(0) ou Pong(1)] [Linha 0 a 7] [Coluna 0 a 7]
    // Armazenamos palavras complexas de 32 bits {Real(16), Imag(16)}
    reg [31:0] ping_pong_ram [0:1][0:7][0:7];

    // LÓGICA DE ESCRITA NO BANCO (Acompanha o ritmo das Linhas)
    always @(posedge clk) begin
        if (write_en) begin
            // O col_cnt da FSM vai de 0 a 3, então é multiplicada por 2
            // para acessar as colunas da matriz 0, 2, 4 e 6
            ping_pong_ram[wr_bank_sel][wr_row_cnt][wr_col_cnt * 2]     <= {ifft_Y0, ifft_Y1};
            // + 1 para acessar as colunas da matriz 1, 3, 5 e 7
            ping_pong_ram[wr_bank_sel][wr_row_cnt][wr_col_cnt * 2 + 1] <= {ifft_Y2, ifft_Y3};
        end
    end

    // LÓGICA DE LEITURA NO BANCO (Acompanha o ritmo das Colunas)
    always @(posedge clk) begin
        // O rd_row_pair_cnt vai de 0 a 3, então é multiplicada por 2
        // para acessar as linhas da matriz 0, 2, 4 e 6
        {fft_X0, fft_X1} <= ping_pong_ram[rd_bank_sel][rd_row_pair_cnt * 2][rd_col_cnt];
	// + 1 para acessar as linhas da matriz 1, 3, 5 e 7
        {fft_X2, fft_X3} <= ping_pong_ram[rd_bank_sel][rd_row_pair_cnt * 2 + 1][rd_col_cnt];
    end

    // ====================================================================
    //         INSTANCIAÇÃO DOS MÓDULOS (IP CORES E CONTROLE)
    // ====================================================================

    // Módulo IFFT 1D (Calcula o eixo de Atraso / Delay)
    ifft_1d_top inst_ifft_1d (
        .clk(clk), 
        .reset(reset), 
        .next(next_in), 
        .next_out(ifft_next_out),
        .X0(in_X0), .X1(in_X1), .X2(in_X2), .X3(in_X3),
        .Y0(ifft_Y0), .Y1(ifft_Y1), .Y2(ifft_Y2), .Y3(ifft_Y3)
    );

    // Máquina de Estados de Escrita
    write_fsm inst_write_fsm (
        .clk(clk),
        .reset(reset),
        .ifft_next_out(ifft_next_out),
        .write_en(write_en),
        .col_cnt(wr_col_cnt),
        .row_cnt(wr_row_cnt),
        .bank_sel(wr_bank_sel),
        .matrix_ready(matrix_ready)
    );

    // Máquina de Estados de Leitura
    read_fsm inst_read_fsm (
        .clk(clk),
        .reset(reset),
        .matrix_ready(matrix_ready),
        .fft_next_in(fft_next_in),
        .rd_col_cnt(rd_col_cnt),
        .rd_row_pair_cnt(rd_row_pair_cnt),
        .rd_bank_sel(rd_bank_sel)
    );

    // Módulo FFT 1D (Calcula o eixo Doppler)
    fft_1d_top inst_fft_1d (
        .clk(clk), 
        .reset(reset), 
        .next(fft_next_in), 
        .next_out(next_out),
        .X0(fft_X0), .X1(fft_X1), .X2(fft_X2), .X3(fft_X3),
        .Y0(out_Y0), .Y1(out_Y1), .Y2(out_Y2), .Y3(out_Y3)
    );

endmodule
