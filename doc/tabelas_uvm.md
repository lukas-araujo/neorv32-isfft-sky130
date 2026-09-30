# Tabelas da verificação UVM do IP da ISFFT para os slides

Regressão no **Xcelium** da VM em 30/09/2026, semente 1. Fonte:
`resultados/2026-09-30_uvm_regressao/` (os logs em `reports/`). Detalhes
e decisões no `DIARIO_UVM.md`.

---

## 1. Ficha

| Item | Valor |
|---|---|
| DUT | `isfft_axi_v4`: wrapper AXI + núcleo Spiral + 2 macros OpenRAM (modelo `.v`) |
| RTL | o mesmo `frontend/` que o Genus sintetizou (61 arquivos na lista, `isfft_dut.f`) |
| Simulador | Cadence Xcelium 23.09 (`xrun -uvm`), UVM **1.1d** (o da Cadence) |
| Cobertura | IMC 24.09: merge das 8 rodadas |
| Relógio | 50 MHz (o do chip) |
| Conferência antes da VM | Verilator 5.052 (aberto), UVM 2020-3.2: mesmo resultado |

(`reports/*_s1.log`: linha `[TESTE] UVM:`; `reports/imc.log`)

## 2. O ambiente

| Peça | O que faz |
|---|---|
| Agente AXI4-Lite | lê/escreve os 7 registradores com atrasos sorteados |
| Agente AXI-Stream de entrada | manda as matrizes com pausas sorteadas |
| Agente AXI-Stream de saída | sorteia o `tready` (50–100 %) e faz paradas longas |
| RAL | modelo dos registradores; contadores previstos pelo modelo e conferidos com `mirror` |
| Modelo de referência | refaz o commit/rollback da entrada e passa cada matriz pelo **wrapper da etapa 1** (Kria) |
| Scoreboard | checagem **bit a bit** + checagem **numérica** (ISFFT em ponto flutuante) + modelo do `tlast` |
| Asserções | 8 dentro do DUT e das macros (por `bind`, sem tocar no RTL) + protocolo AXI nas interfaces |
| Cobertura funcional | 4 grupos, 54 bins: entrada, saída, registradores, ocupação dos buffers |

## 3. Resultado da regressão

| Teste | Cenário | Palavras bit a bit | Pior erro numérico | Tempo simulado | Resultado |
|---|---|---|---|---|---|
| `fumaca` | 1 matriz | 32 | 2,79 LSB | 7 µs | ✅ |
| `registradores` | reset, R/W, escrita em RO | — | — | 3 µs | ✅ |
| `kria` | 3 matrizes da placa | 96 | 1,48 LSB | 10 µs | ✅ |
| `aleatorio` | 40 matrizes, 5 tipos × 4 amplitudes | 1.280 | 2,97 LSB | 123 µs | ✅ |
| `truncado` | + pacotes truncados | 1.280 | 2,95 LSB | 123 µs | ✅ |
| `contrapressao` | 60 matrizes, `tready` 50 % + paradas | 1.920 | 2,97 LSB | 183 µs | ✅ |
| `soft_reset` | reset com dado dentro do DUT | 256 (2 épocas) | 2,81 LSB | 29 µs | ✅ |
| `kria_regressao` | o testbench da Kria reescrito em UVM | 1.280 | 2,94 LSB (só informativo) | 187 µs | ✅ |
| **Total** | **8 testes** | **6.144 palavras = 192 matrizes** | **≤ 2,97 LSB** (limite 4) | | **8/8** |

Em todos: 0 erros de dado, 0 de `tlast`, 0 `UVM_ERROR`, 0 `UVM_WARNING`,
0 asserção falhando. Cada teste leva ~1 s de relógio de parede.

(`reports/regressao.txt` e as linhas `[SB_RESUMO]` de cada log)

## 4. EVM igual à placa

| Matriz | EVM no UVM | Kria (placa) | |
|---|---|---|---|
| Impulso | 3,4122 % | 3,41 % | = |
| Senoide | 0,7822 % | 0,78 % | = |
| Rampa | 0,5965 % | 0,60 % | = |

(`reports/isfft_kria_test_s1.log`, linhas `[KRIA]`)

O mesmo número da simulação do chip inteiro (FE-D32), agora medido no IP
sozinho, com modelo em SystemVerilog.

## 5. Erro numérico: fixo em LSB, não depende do sinal

| Faixa de amplitude da entrada | Matrizes | Pior erro | Pior EVM |
|---|---|---|---|
| ≤ 64 | 24 | 2,76 LSB | 17,9 % |
| 65 – 1.024 (inclui as 3 da Kria) | 55 | 2,79 LSB | 3,41 % |
| 1.025 – 8.192 | 48 | 2,97 LSB | 0,43 % |
| 8.193 – 32.767 (+ Kria regressão) | 65 | 2,94 LSB | 0,14 % |

(soma das linhas `faixa` dos testes com dado sorteado)

**Leitura:** o erro absoluto é ~3 LSB em qualquer amplitude
(arredondamento do ponto fixo do Spiral). O EVM só parece ruim com sinal
pequeno. Por isso o critério é em LSB, não em EVM.

## 6. Cobertura (IMC, merge das 8 rodadas)

| Métrica | Resultado |
|---|---|
| **Funcional** (covergroups) | **94,4 %** (51 de 54 bins) |
| ↳ saída, registradores, ocupação | 100 % (6/6, 19/19, 15/15) |
| ↳ entrada | 78,6 % (11/14) — os 3 buracos abaixo |
| **Asserções** | 8 de 8 exercitadas, **0 falhas** |
| **Código — núcleo** (`top_isfft`: FFT, IFFT, FSMs) | **99,6 %** dos itens |
| **Código — wrapper** `isfft_axi_v4` | 70,7 % dos itens (848/1.200) |
| Código — modelos das macros (OpenRAM, não é nosso) | 57–58 % |

(`reports/cobertura_funcional.txt`, `reports/cobertura_resumo.txt`)

### Os 3 bins não cobertos

| Bin | O que é | Por que faltou |
|---|---|---|
| entrada: espera curta (1–3 ciclos) | o DUT segura o `tready` só um pouco | o buffer de entrada só enche quando a saída está travada, e aí a espera é longa (≥ 4 ciclos) |
| pacote truncado na 1ª palavra | `tlast` numa palavra só | o tamanho do truncado é sorteado de 1 a 31: pontas raras |
| pacote truncado na 31ª palavra | `tlast` uma palavra antes da matriz fechar | idem |

## 7. Cada checagem pega um tipo de defeito (mutações)

12 defeitos plantados no RTL (Verilator, 30/09):

| Defeito plantado | Quem pegou |
|---|---|
| 5 no wrapper (os mesmos da regressão da Kria) | bit a bit + numérica; asserção em 2 deles |
| `tlast` uma matriz depois | só o modelo de `tlast` |
| rollback quebrado | bit a bit + numérica + watchdog (travava) |
| limpar erro ignorado; soft reset; ID errado | RAL |
| **2 no núcleo Spiral** | **só a checagem numérica** (bit a bit: 0 erros) |
| **Total** | **12/12 detectados** |

(`DIARIO_UVM.md`, 2ª sessão)

**Leitura:** a comparação bit a bit usa a referência da etapa 1, que tem
o **mesmo** núcleo Spiral. Um defeito no núcleo sai igual dos dois lados,
e o bit a bit passa. Só o modelo em ponto flutuante vê.

## 8. Verilator × Xcelium

| | Verilator 5.052 | Xcelium 23.09 |
|---|---|---|
| UVM | 2020-3.2 (IEEE 1800.2) | 1.1d (Cadence) |
| Regressão | 8/8 | 8/8 |
| EVM da Kria | 3,4122 / 0,7822 / 0,5965 % | igual |
| Compilação | 165 s (o UVM vira C++) | segundos |
| Cobertura de código / merge | não | sim (IMC) |
| Custo | aberto | licença |

(`DIARIO_UVM.md`, 2ª sessão; `reports/`)

Os percentuais de cobertura **por teste** diferem entre os dois: os
estímulos sorteados não são iguais (outro gerador aleatório). O que tem de
bater — passou/falhou, EVM, palavras comparadas — bate.
