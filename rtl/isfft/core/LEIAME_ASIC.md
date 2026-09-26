# Núcleo da ISFFT — o que mudou em relação à Kria

Os 58 arquivos vêm do projeto da Kria. **Uma única mudança**, em 10
arquivos, feita para o ASIC (DIARIO, 13ª sessão, D34):

```verilog
// codeBlock40889.v, 40973, 41154, 41237, 41426 (IFFT)
// codeBlock6811.v, 6895, 7076, 7159, 7348     (FFT)
      if (reset == 1) begin
         next <= 0;   // ASIC: frame sync limpo no reset (DIARIO, D34)
```

**Por quê:** o registrador `next` (sincronismo de quadro do Spiral) não
tinha reset e **congelava durante o reset**. No FPGA ele liga em 0; no
silício liga com valor qualquer, e ao fim do reset dispara um `next`
falso que corrompe para sempre os seletores de banco (`inFlip0`/
`outFlip0`) dos blocos de permutação — eles só alternam. Achado na
simulação de portas (a saída da FFT ficava toda em X).

**Prova de que nada mais mudou:** regressão da Kria (40 matrizes, com
parada longa e pacote truncado) com o núcleo original e com o corrigido
— as 1.280 palavras de saída são **idênticas**. EVM continua igual ao da
Kria.

`isfft_axi_v3.v` e o restante do núcleo estão como vieram da Kria.
