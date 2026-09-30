# Tabelas da síntese (Genus) para os slides

Rodada **para o layout** de 29/09/2026 (a que virou o netlist do layout,
L14/L20). Fonte de cada número entre parênteses; todos os arquivos estão em
`resultados/2026-09-29_sintese_layout/`. Área em µm²; 1 mm² = 10⁶ µm².

---

## 1. Ficha da rodada

| Item | Valor |
|---|---|
| Ferramenta | Cadence Genus 22.16 (VM goku) |
| Topo | `asic_top` (NEORV32 + ISFFT + conversores 32↔64) |
| Biblioteca | `sky130_fd_sc_hd`, corner **TT 25 °C 1,80 V** + `.lib` das 4 macros OpenRAM |
| Modelo de fio | *wireload* (sem posicionamento) |
| Relógio | `clk_i`, **20 ns = 50 MHz** |
| Tempo de síntese | 599 s (~10 min), 2,5 GB de memória |

(`_qor.rpt`, `_drc.rpt`)

## 2. Resultado em uma tabela

| Métrica | Valor |
|---|---|
| Área total | **1,913 mm²** (1.912.951,6 µm²) |
| Macros SRAM (4) | 1,183 mm² — **61,8 %** |
| Lógica em células padrão | 0,730 mm² — 38,2 % |
| Instâncias | 60.026 (19.823 flip-flops + 4 macros, 40.199 combinacionais) |
| Folga de setup (pior caminho) | **+2,41 ns**, 0 caminhos violando |
| Regras de projeto (transição, capacitância, fanout) | 0 violações |
| Módulos não resolvidos / vazios | 0 / 0 |

(`_qor.rpt`, `_gates.rpt`, `_drc.rpt`, `_unresolved.rpt`)

## 3. Onde está a área

| Bloco | Área (µm²) | % do chip | O que é |
|---|---|---|---|
| **Macros SRAM** | **1.182.837,6** | **61,8 %** | |
| ↳ IMEM 8 kB (1rw 32×2048) | 448.827,0 | 23,5 % | programa |
| ↳ `out_mem` (1rw1r 64×256) | 296.939,1 | 15,5 % | FIFO de saída da ISFFT |
| ↳ DMEM 4 kB (1rw 32×1024) | 284.139,2 | 14,9 % | dados |
| ↳ `in_mem` (1rw1r 64×64) | 152.932,3 | 8,0 % | buffer de entrada da ISFFT |
| **Lógica da ISFFT** | **448.029,7** | **23,4 %** | |
| ↳ ping-pong + registradores do `top_isfft` | 149.015,4 | 7,8 % | memória de transposição em flip-flop (FE-D26) |
| ↳ IFFT 1D (Spiral, linhas) | 141.104,1 | 7,4 % | |
| ↳ FFT 1D (Spiral, colunas) | 138.333,9 | 7,2 % | |
| ↳ wrapper `isfft_axi_v4` (AXI-Lite, buffers, pré-busca) | 18.891,9 | 1,0 % | |
| ↳ FSMs de leitura/escrita | 684,4 | 0,04 % | |
| **Lógica do NEORV32** | **275.798,3** | **14,4 %** | |
| ↳ FIFOs do SLINK (2 × 64 × 37 bits) | 147.332,5 | 7,7 % | precisam caber uma matriz (FE-D19) |
| ↳ CPU rv32imc | 97.058,1 | 5,1 % | banco de registradores = 45.920,3 (47 % da CPU) |
| ↳ DMA | 17.242,8 | 0,9 % | |
| ↳ UART0 | 4.140,2 | 0,2 % | |
| ↳ resto (barramentos, SYSINFO, ponte XBUS→AXI, reset/clock) | 10.024,6 | 0,5 % | |
| **Conversores 32↔64** | 6.204,7 | 0,3 % | |

(`_area_hier.rpt` e `_gates.rpt`; "resto" e "ping-pong + registradores" são
diferenças entre linhas do relatório. Os 81 µm² que faltam para fechar a
lógica são células no próprio `asic_top`.)

**Leitura para o slide:** as memórias dominam o chip. Somando as macros
(61,8 %) com as memórias que ficaram em flip-flop (FIFOs do SLINK 7,7 %,
ping-pong 7,8 %, banco de registradores 2,4 %), **quase 80 % da área é
memória**; a matemática da ISFFT (FFT + IFFT) é 14,6 %.

## 4. Composição por tipo de célula

| Tipo | Instâncias | Área (µm²) | % da área |
|---|---|---|---|
| Macros (modelo de tempo) | 4 | 1.182.837,6 | 61,8 % |
| Sequenciais (flip-flops) | 19.823 | 408.324,1 | 21,3 % |
| Lógica combinacional | 38.130 | 313.424,3 | 16,4 % |
| Inversores | 2.000 | 7.775,0 | 0,4 % |
| Buffers | 69 | 590,6 | 0,03 % |
| **Total** | **60.026** | **1.912.951,6** | 100 % |

(`_gates.rpt`, tabela final)

| Célula mais usada | Instâncias | Área (µm²) | Por quê |
|---|---|---|---|
| `a22o` (AND-OR 2-2) | 17.773 | 155.783 | multiplexador de leitura das memórias em flip-flop |
| `dfxtp` (flip-flop sem reset) | 17.600 | 352.339 | os bits dessas memórias (não precisam de reset) |
| `a22oi` | 7.292 | 54.743 | idem, versão invertida |
| `dfrtp` (flip-flop com reset) | 2.128 | 53.292 | registradores de controle |
| `fa` (somador completo) | 1.321 | 26.445 | somadores do Spiral e da CPU |

(`_gates.rpt`, somando as forças `_1`, `_2`, `_4` de cada célula)

**Leitura:** 89 % dos flip-flops são **sem reset** e 62 % das células
combinacionais são `a22o`/`a22oi`. É a assinatura de memória
construída com flip-flops: um bit guardado + um mux para ler.

Buffers só 69: sem posicionamento, a síntese não enxerga fio longo nem
fanout real (o relógio tem 19.829 cargas numa rede ideal). O layout
colocou **12.930 buffers** no reparo pós-posicionamento (`DIARIO_GDSII`,
15ª sessão).

## 5. Temporização

### Orçamento do pior caminho

| Parcela | ps |
|---|---|
| Período | 20.000 |
| − incerteza de relógio (setup) | 2.000 |
| − setup do flip-flop | 126 |
| = tempo disponível para o dado | 17.874 |
| − atraso do dado (CK→Q + lógica) | 15.464 |
| **= folga** | **+2.410** |

(`_timing.rpt`, Path 1; a latência de 1.000 ps entra nos dois lados e se
cancela)

### O caminho

| Item | Valor |
|---|---|
| Início | registrador do controle da CPU (`neorv32_cpu_control`), fanout 53 |
| Fim | registrador do multiplicador/divisor (`neorv32_cpu_alu_muldiv`, bit 63) |
| O que tem no meio | **subtração de 32 bits em *ripple carry***: 32 somadores completos `fa_1` em cadeia, ~391 ps cada = **12,5 ns** dos 15,5 ns |
| Passa por macro ou pela ISFFT? | não — o gargalo é a CPU |

(`_timing.rpt`)

### Os 10 piores caminhos

| # | Destino | Folga |
|---|---|---|
| 1 | multiplicador/divisor, bit 63 | +2.410 ps |
| 2–10 | banco de registradores, bit 30 (9 registradores diferentes) | +2.418 ps |

(`_timing_top10.rpt`) Todos na CPU, todos com ~2,4 ns de sobra: a ISFFT e
as macros têm folga maior que isso.

### Restrições (SDC)

| Restrição | Valor |
|---|---|
| Relógio | 20 ns (50 MHz), ciclo de trabalho 50 % |
| Incerteza | 2 ns em setup e em hold |
| Latência (estimada, sem árvore) | 1 ns; `clk_i` e `rstn_i` como redes ideais |
| Atraso de entrada / saída (UART) | 6 ns (30 % do período) |
| `rstn_i` | caminho falso (assíncrono) |

(`deliverables/neorv32_isfft_soc.sdc`, `_timing_lint.rpt`: 0 relógio sem
forma de onda, 0 laço combinacional; só avisos esperados sobre `rstn_i`)

## 6. A síntese está certa? (verificação)

| Pergunta | Ferramenta | Resposta |
|---|---|---|
| O netlist é o mesmo circuito do RTL? | Conformal LEC | **PASS**: 19.828 pontos equivalentes (1 saída + 19.823 flip-flops + 4 macros), 0 não-equivalentes, 0 abortados; 169/169 módulos |
| O netlist funciona? | Xcelium, portas com o firmware das 3 matrizes | **PASSOU**: as 3 somas = RTL (`0xeb88508e`, `0xba7fc58e`, `0xb29c0211`), 188.195 ciclos (RTL: 188.194) |
| A matemática está certa? | simulação RTL + modelo numpy | EVM 3,41 / 0,78 / 0,60 % = Kria (FE-D32) |

(`logs/neorv32_isfft_soc_lec_genus_run.log.gz`, `logs/xrun_postsyn.log`,
`logs/xrun_rtl.log`)

## 7. As três rodadas

| | 26/09 front-end | 27/09 para o layout | 29/09 para o layout (final) |
|---|---|---|---|
| Mudança | — | `.lib` 33 bits (L1) + células de constante `conb_1` (L2) | + evita as 53 células proibidas no layout (L20) |
| Área (µm²) | 1.912.962,9 | 1.913.000,4 (+37,5 = 10 `conb_1`) | **1.912.951,6** (−48,8) |
| Instâncias | 60.028 | 60.038 | **60.026** |
| Folga de setup | +2.410,4 ps | +2.410,4 ps | +2.410,4 ps |
| `conb_1` / células proibidas | 0 / 227 | 10 / 227 | **10 / 0** |
| Tempo | 597 s | 601 s | 599 s |

(`_qor.rpt` de cada pasta em `resultados/`; `conb_1` e células proibidas
contadas no netlist de cada rodada, com a lista `tech/sky130/drc_exclude.cells`)

**Leitura:** as três correções pedidas pelo layout não custaram nada em
área nem em tempo — a folga é a mesma até o décimo de ps.

## 8. O que **não** vai para o slide (e por quê)

| Número | Valor no relatório | Por que não vale |
|---|---|---|
| Potência total | 2.767 W | O `.lib` das macros da OpenRAM (modelo analítico) tem potência interna fora de escala. Registradores + lógica: ~50 mW, sem atividade de simulação (*vectorless*) — só ordem de grandeza |
| Área de fio | 0 | *Wireload* no modo `top`: a área de fio só existe depois do layout |
| Folga de hold | — | Relógio ideal: hold só faz sentido depois da árvore de relógio (etapa 5 do layout) |

(`_power.rpt`, `_qor.rpt`)
