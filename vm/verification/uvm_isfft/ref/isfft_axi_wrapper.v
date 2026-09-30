`timescale 1 ns / 1 ps

module isfft_axi_wrapper #
(
    parameter integer C_S00_AXIS_TDATA_WIDTH    = 64,
    parameter integer C_M00_AXIS_TDATA_WIDTH    = 64,
    parameter integer C_M00_AXIS_START_COUNT    = 32
)
(
    input wire  s00_axis_aclk,
    input wire  s00_axis_aresetn,
    output wire  s00_axis_tready,
    input wire [C_S00_AXIS_TDATA_WIDTH-1 : 0] s00_axis_tdata,
    input wire [(C_S00_AXIS_TDATA_WIDTH/8)-1 : 0] s00_axis_tstrb,
    input wire  s00_axis_tlast,
    input wire  s00_axis_tvalid,

    input wire  m00_axis_aclk,
    input wire  m00_axis_aresetn,
    output wire  m00_axis_tvalid,
    output wire [C_M00_AXIS_TDATA_WIDTH-1 : 0] m00_axis_tdata,
    output wire [(C_M00_AXIS_TDATA_WIDTH/8)-1 : 0] m00_axis_tstrb,
    output wire  m00_axis_tlast,
    input wire  m00_axis_tready
);

    reg [1:0] in_count = 0;
    // É necessário ter um ciclo de clock de atraso para o primeiro dado
    reg [C_S00_AXIS_TDATA_WIDTH-1:0] tdata_delay;
    
    // Deixa o axi sempre pronto para receber
    assign s00_axis_tready = 1'b1;

    always @(posedge s00_axis_aclk) begin
        if (~s00_axis_aresetn) begin
            in_count <= 2'b00;
            tdata_delay <= 0;
        end else if (s00_axis_tvalid && s00_axis_tready) begin
            // Conta de 0 a 3 repetidamente
            in_count <= in_count + 1; 
            // Segura o dado por 1 clock
            tdata_delay <= s00_axis_tdata;
        end
    end

    // O pulso next_in é disparado quando o AXI manda tvalid
    wire isfft_next_in = (s00_axis_tvalid && (in_count == 2'd0));


    wire [15:0] saida_y0, saida_y1, saida_y2, saida_y3;
    wire isfft_next_out;

    top_isfft inst_isfft_matriz (
        .clk      (s00_axis_aclk),
        .reset    (~s00_axis_aresetn), 
        .next_in  (isfft_next_in),
        .in_X0    (tdata_delay[15:0]),
        .in_X1    (tdata_delay[31:16]),
        .in_X2    (tdata_delay[47:32]),
        .in_X3    (tdata_delay[63:48]),
        .next_out (isfft_next_out),
        .out_Y0   (saida_y0),
        .out_Y1   (saida_y1),
        .out_Y2   (saida_y2),
        .out_Y3   (saida_y3)
    );


    reg [3:0] out_valid_sr; 
    reg [4:0] tlast_counter; 
    
    always @(posedge m00_axis_aclk) begin
        if (~m00_axis_aresetn) begin
            out_valid_sr  <= 4'b0000;
            tlast_counter <= 5'd0;
        end else begin
            if (isfft_next_out) begin
                out_valid_sr <= 4'b1111; 
            end else begin
                out_valid_sr <= {1'b0, out_valid_sr[3:1]};
            end

            if (m00_axis_tvalid && m00_axis_tready) begin
                tlast_counter <= tlast_counter + 1; 
            end
        end
    end

    // Empacota a saída 
    assign m00_axis_tdata = {saida_y3, saida_y2, saida_y1, saida_y0};
    
    // tvalid com atraso de 1 clock
    assign m00_axis_tvalid = out_valid_sr[0];

    // Finaliza o pacote no ciclo 31
    assign m00_axis_tlast = (m00_axis_tvalid && (tlast_counter == 5'd31));
    
    assign m00_axis_tstrb = 8'hFF;
    
endmodule
