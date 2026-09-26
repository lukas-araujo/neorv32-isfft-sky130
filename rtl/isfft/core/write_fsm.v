// Módulo FSM que conta 32 ciclos de clock para organizar a escrita
// da saída da IFFT nos bancos de registradores

module write_fsm (
    input clk,
    input reset,
    input ifft_next_out,       // Sinal vindo da IFFT
    // Sinais de controle indo para o banco de registradores
    output reg write_en,       // Habilita a escrita nos registradores
    output reg [1:0] col_cnt,  // Controla qual par de colunas estamos escrevendo (0, 2, 4 ou 6)
    output reg [2:0] row_cnt,  // Controla a linha (0 a 7)
    output reg bank_sel,       // Sinais de controle indo para o banco de registradores
    output reg matrix_ready    // Flag avisando a FSM de Leitura que a matriz está pronta
);

    // Definição dos estados
    localparam IDLE = 1'b0;
    localparam WRITING = 1'b1;

    reg state;

    always @(posedge clk) begin
        if (reset) begin
            state        <= IDLE;
            write_en     <= 0;
            col_cnt      <= 0;
            row_cnt      <= 0;
            bank_sel     <= 0;      // Começa gravando no banco 0
            matrix_ready <= 0;
        end else begin
            matrix_ready <= 1'b0; 

            case (state)
                IDLE: begin
                    if (ifft_next_out == 1'b1) begin
                    	// A IFFT avisou que no próximo ciclo de clock os dados chegam
                        state    <= WRITING;
                        write_en <= 1'b1;
                        col_cnt  <= 2'd0;
                        row_cnt  <= 3'd0;
                    end else begin
                        write_en <= 1'b0;
                    end
                end

                WRITING: begin
                    if (col_cnt == 2'd3) begin
                    	// Terminamos uma linha inteira (4 ciclos)
                        col_cnt <= 2'd0; // Reseta a coluna para a próxima linha
                        if (row_cnt == 3'd7) begin
                            // Terminamos a última linha da matriz
                            bank_sel <= ~bank_sel;     // Inverte o banco de registradores
                            matrix_ready <= 1'b1;      // Avisa a FSM de leitura
                            // Avalia se a IFFT já está mandando a próxima matriz emendada
                            if (ifft_next_out == 1'b1) begin
                                row_cnt <= 3'd0; // Continua para próxima matriz
                            end else begin
                                state <= IDLE;    // Fica ocioso aguardando
                                write_en <= 1'b0;
                            end
                        end else begin
                            // Vai para a próxima linha da mesma matriz
                            row_cnt <= row_cnt + 3'd1;
                        end
                    end else begin
                        // Avança para o próximo par de colunas da mesma linha
                        col_cnt <= col_cnt + 2'd1;
                    end
                end
            endcase
        end
    end
endmodule
