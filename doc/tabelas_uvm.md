# Tabelas da verificação UVM do IP da ISFFT para os slides

Regressão no **Xcelium 26.03** da VM em **28/10/2026**, semente 1. Fonte:
`resultados/2026-10-28_uvm_regressao_2603/reports/`. Detalhes e
decisões no `DIARIO_UVM.md` (sessões 7 a 9). A rodada anterior (30/09,
Xcelium 23.09, 8 testes) está em `resultados/2026-09-30_uvm_regressao/`.

---

## 1. Ficha

| Item | Valor |
|---|---|
| DUT | `isfft_axi_v4`: wrapper AXI + núcleo Spiral + 2 macros OpenRAM (modelo `.v`) |
| RTL | o mesmo `frontend/` que o Genus sintetizou (`isfft_dut.f`: 58 arquivos + 2 macros + referência) |
| Simulador | Cadence Xcelium 26.03 (`xrun -uvm`), UVM **1.1d** (o da Cadence) |
| Cobertura | IMC 26.03: merge das 10 rodadas; `cobertura.ccf` tira da cobertura de código o que não é RTL do chip |
| Relógio | 50 MHz (o do chip) |
| Conferência antes da VM | Verilator 5.052 (aberto), UVM 2020-3.2: 10/10, 12/12 mutações |

(`reports/*_s1.log`: linha `[TESTE] UVM:`; `reports/imc.log`)

## 2. O ambiente

| Peça | O que faz |
|---|---|
| Agente AXI4-Lite | lê/escreve os 7 registradores com atrasos sorteados |
| Agente AXI-Stream de entrada | manda as matrizes com pausas sorteadas (ou sem pausa: teste de vazão) |
| Agente AXI-Stream de saída | sorteia o `tready` (50–100 %) e faz paradas longas |
| RAL | modelo dos registradores; contadores previstos pelo modelo e conferidos com `mirror` |
| Modelo de referência | refaz o commit/rollback da entrada e passa cada matriz pelo **wrapper da etapa 1** (Kria) |
| Scoreboard | checagem **bit a bit** + checagem **numérica** (ISFFT em ponto flutuante) + modelo do `tlast` + épocas de soft reset |
| Asserções | 8 dentro do DUT e das macros (por `bind`, sem tocar no RTL) + protocolo AXI nas interfaces |
| Cobertura funcional | 4 grupos, 54 bins: entrada, saída, registradores, ocupação dos buffers |

## 3. Resultado da regressão

| Teste | Cenário | Palavras bit a bit | Pior erro numérico | Tempo simulado | Resultado |
|---|---|---|---|---|---|
| `fumaca` | 1 matriz | 32 | 0,77 LSB | 7 µs | ✅ |
| `registradores` | reset, R/W, escrita em RO | — | — | 3 µs | ✅ |
| `kria` | 3 matrizes da placa | 96 | 1,48 LSB | 10 µs | ✅ |
| `aleatorio` | 40 matrizes, 5 tipos × 4 amplitudes | 1.280 | 3,14 LSB | 123 µs | ✅ |
| `truncado` | + pacotes truncados (pontas dirigidas) | 1.280 | 2,98 LSB | 123 µs | ✅ |
| `contrapressao` | 60 matrizes, `tready` 50 % + paradas | 1.920 | 3,14 LSB | 183 µs | ✅ |
| `soft_reset` | 2 soft resets: no começo e com o núcleo calculando | 200 (3 épocas) | 2,48 LSB | 44 µs | ✅ |
| `kria_regressao` | o testbench da Kria reescrito em UVM | 1.280 | 2,94 LSB (fora da faixa, informativo) | 187 µs | ✅ |
| `vazao` | 80 matrizes, entrada sem pausa, `tready` 100 % | 2.560 | ≤ 4 LSB | 241 µs | ✅ |
| `estouro` | 40 matrizes ±32.767 (acima da faixa válida) | 1.280 | 40 de 40 estouram (só contado) | 121 µs | ✅ |
| **Total** | **10 testes** | **9.928 palavras** | **≤ 3,14 LSB** dentro da faixa (limite 4) | | **10/10** |

Em todos: 0 erros de dado, 0 de `tlast`, 0 `UVM_ERROR`, 0 `UVM_WARNING`,
0 asserção falhando.

(`reports/regressao.txt` e as linhas `[SB_RESUMO]` de cada log)

## 4. EVM igual à placa

| Matriz | EVM no UVM | Kria (placa) | |
|---|---|---|---|
| Impulso | 3,4122 % | 3,41 % | = |
| Senoide | 0,7822 % | 0,78 % | = |
| Rampa | 0,5965 % | 0,60 % | = |

(`reports/isfft_kria_test_s1.log`, linhas `[KRIA]`) Igual no Xcelium 23.09,
no 26.03, no Verilator e na simulação do chip inteiro (FE-D32).

## 5. Faixa válida da entrada: |re|, |im| ≤ 23.170

O núcleo Spiral **estoura** acima de 32.767/√2 = 23.170: o estágio que
multiplica pelo fator de 45° ((1−j)/√2) da IFFT das linhas não tem bit de
guarda. Medido com o núcleo sozinho (Icarus) e toda componente em ±A:

| Amplitude A | Matrizes que estouraram |
|---|---|
| 16.384 / 22.000 / **23.170** | **0** / 0 / 0 de 200 |
| **23.500** / 24.576 / 28.672 | **47** / 36 / 43 de 200 |
| 32.767 | 186 de 200 (no UVM: 40 de 40) |

(`DIARIO_UVM.md`, 7ª sessão; `reports/isfft_estouro_test_s1.log`)

**Leitura:** o bit a bit contra a etapa 1 passa (é o mesmo núcleo); só o
modelo independente em ponto flutuante viu. Com dado uniforme o estouro
é raro (0,7 % das matrizes cheias) — por isso a 1ª medição (set/2026) não
o achou. Para o sistema OTFS: escalar a matriz para ≤ 23.170 antes do IP.

## 6. Erro numérico: fixo em LSB, não depende do sinal

| Faixa de amplitude da entrada | Pior erro (aleatório) | Pior EVM |
|---|---|---|
| ≤ 64 | 2,83 LSB | 54,1 % |
| 65 – 1.024 | 2,97 LSB | 1,08 % |
| 1.025 – 8.192 | 3,14 LSB | 0,14 % |
| 8.193 – 23.170 | 2,68 LSB | 0,15 % |

(linhas `faixa` de `aleatorio`, `truncado` e `contrapressao`)

**Leitura:** o erro absoluto é ~3 LSB em qualquer amplitude
(arredondamento do ponto fixo do Spiral). O EVM só parece ruim com sinal
pequeno. Por isso o critério é em LSB, não em EVM.

## 7. Cobertura (IMC, merge das 10 rodadas)

| Métrica | 30/09 | **28/10** |
|---|---|---|
| **Funcional** (covergroups) | 94,4 % (51/54) | **100 % (54/54)** |
| **Asserções** | 8/8, 0 falhas | **8/8, 0 falhas** |
| Código — núcleo (`top_isfft`) | 99,6 % | **100 %** (280/280; IFFT e FFT 782/782) |
| Código — wrapper `isfft_axi_v4` | 70,7 % (848/1.200) | **73,5 % (975/1.326)** — com expressões `&`/`\|`/`assign` medidas |
| Código — modelos das macros (OpenRAM) | 57–58 % | fora (não é RTL do chip) |
| Código — asserções ligadas por `bind` | contavam como DUT | fora |

(`reports/cobertura_funcional.txt`, `reports/cobertura_resumo.txt`)

### O que a cobertura achou (e virou teste ou decisão)

| Buraco | Causa | O que foi feito |
|---|---|---|
| espera curta na entrada (0 acertos) | só aparece com entrada a 1 palavra/ciclo e saída livre | teste `vazao`: 77 acertos |
| truncado na 1ª e na 31ª palavra | sorteio uniforme de 1 a 31 | as 2 pontas dirigidas no `truncado` |
| `write_fsm.v:55` (matriz emendada) | o wrapper gasta **33 ciclos por matriz** (1 de folga): nunca emenda | inalcançável no chip; exclusão justificada |
| `reset` do núcleo com 1 transição | o soft reset por tempo caía dentro do reset estendido de 127 ciclos | 2º soft reset por estado, com o núcleo calculando |
| matriz 39 do `vazao`: 4.096 LSB | estouro do núcleo acima de 23.170 | faixa válida + teste `estouro` |

## 8. Cada checagem pega um tipo de defeito (mutações)

12 defeitos plantados no RTL (Verilator, 26/10, ambiente da 8ª sessão):

| Defeito plantado | Quem pegou |
|---|---|
| 5 no wrapper (os mesmos da regressão da Kria) | bit a bit + numérica; asserção em 2 deles |
| `tlast` uma matriz depois | só o modelo de `tlast` |
| rollback quebrado | bit a bit + numérica + watchdog (travava) |
| limpar erro ignorado; soft reset; ID errado | RAL |
| **2 no núcleo Spiral** | **só a checagem numérica** (bit a bit: 0 erros) |
| **Total** | **12/12 detectados** |

**Leitura:** a comparação bit a bit usa a referência da etapa 1, que tem
o **mesmo** núcleo Spiral. Um defeito no núcleo sai igual dos dois lados,
e o bit a bit passa. Só o modelo em ponto flutuante vê — o mesmo motivo
pelo qual só ele viu o estouro (§5).

## 9. Verilator × Xcelium

| | Verilator 5.052 | Xcelium 26.03 |
|---|---|---|
| UVM | 2020-3.2 (IEEE 1800.2) | 1.1d (Cadence) |
| Regressão | 10/10 | 10/10 |
| EVM da Kria | 3,4122 / 0,7822 / 0,5965 % | igual |
| `estouro`: matrizes que estouram | 37 de 40 | 40 de 40 (outro sorteio) |
| Compilação | ~3–9 min (o UVM vira C++; `O0=1` numa sessão de 7 GB) | segundos |
| Cobertura de código / merge | não | sim (IMC) |
| Custo | aberto | licença |

(`DIARIO_UVM.md`, sessões 7 e 8; `reports/`)

Os percentuais de cobertura **por teste** diferem entre os dois: os
estímulos sorteados não são iguais. O que tem de bater — passou/falhou,
EVM, palavras comparadas nos testes determinísticos — bate.
