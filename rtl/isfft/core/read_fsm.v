// Módulo FSM que conta 32 ciclos de clock para organizar a leitura
// do banco de registrador para entrar na FFT

module read_fsm (
    input clk,
    input reset,
    // Sinal vindo da FSM de Escrita que avisa que tem uma matriz pronta
    input matrix_ready,
    // Sinal de controle indo para a entrada da FFT
    output reg fft_next_in,
    // Sinais de controle indo para o banco de registradores
    output reg [2:0] rd_col_cnt,       // Controla a coluna fixa (0 a 7)
    output reg [1:0] rd_row_pair_cnt,  // Controla qual par de linhas estamos descendo (0 a 3)
    output reg rd_bank_sel             // Seleciona banco 0 ou banco 1 para leitura
);
    
    // Definição dos Estados
    localparam IDLE = 1'b0;
    localparam READING = 1'b1;

    reg state;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            fft_next_in <= 1'b0;
            rd_col_cnt <= 3'd0;
            rd_row_pair_cnt <= 2'd0;
            rd_bank_sel <= 1'b0;       // Começa lendo no banco 0
        end else begin
            case (state)
                IDLE: begin
                    if (matrix_ready == 1'b1) begin
                        state <= READING;
                        fft_next_in <= 1'b1;      // Pulsa o gatilho da FFT
                        rd_col_cnt <= 3'd0;
                        rd_row_pair_cnt <= 2'd0;
                    end
                end

                READING: begin
                    // Ejeta 2 amostras da memória direto para a FFT por ciclo
                    if (rd_row_pair_cnt == 2'd3) begin
                        rd_row_pair_cnt <= 2'd0; // Volta para o topo da próxima coluna
                        
                        if (rd_col_cnt == 3'd7) begin
                            rd_bank_sel <= ~rd_bank_sel; // Troca o banco
                            // Continua com a próxima matriz 
                            if (matrix_ready == 1'b1) begin
                                fft_next_in <= 1'b1;
                                rd_col_cnt <= 3'd0;
                            end else begin
                                fft_next_in <= 1'b0;
                                state <= IDLE;
                            end
                        end else begin
                            rd_col_cnt <= rd_col_cnt + 3'd1; // Vai para a próxima coluna
                            fft_next_in <= 1'b1;             // Gatilho para a nova coluna
                        end
                    end else begin
                        rd_row_pair_cnt <= rd_row_pair_cnt + 2'd1;
                        fft_next_in <= 1'b0; // Abaixa o gatilho durante o meio da coluna
                    end
                end
            endcase
        end
    end
endmodule
