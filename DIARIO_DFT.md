# DIÁRIO DFT — scan e ATPG no IP da ISFFT (`isfft_axi_v4`)

Diário de bordo da frente de **DFT** (*design for test*): síntese com
**scan** do IP da ISFFT no **Genus** e geração de padrões de teste
(**ATPG**) no **Modus**, na VM.

Continua o `DIARIO.md` (front-end, sessões 1–15). A tarefa nasceu na 15ª
sessão de lá (FE-D39), com a lista "Levar para a síntese com DFT".
Decisões de lá são citadas como **FE-Dn**; do back-end, **Ln**; do UVM,
**Un**. Decisões deste diário são **Tn** (T de teste).

| Diário | Trabalho | Prefixo | Situação |
|---|---|---|---|
| `DIARIO.md` | Front-end | D (citado como FE-D) | ✅ fechado |
| `DIARIO_GDSII.md` | Back-end até o GDSII | L | ▶ outro chat |
| `DIARIO_UVM.md` | UVM no IP da ISFFT | U | ▶ outro chat |
| `DIARIO_DFT.md` | DFT no IP da ISFFT | **T** | ▶ este |

---

## Como usar este diário

Mesmo modelo dos outros:

```
### 🐛 <título curto>
**Sintoma:** o que apareceu (mensagem, log, comportamento).
**Causa:** por que quebrou, quando eu descobrir.
**Resolvi com:** o que funcionou.
**Tempo gasto:** aproximado.
**Vira slide?** sim/não — e por quê.
```

Decisões entram na tabela da sessão **e** no índice no fim: ✅ adotada ·
🟡 proposta (aguarda confirmação) · ❌ descartada. Pelo combinado L52
(`CLAUDE.md`), escolha de projeto o Claude decide e registra como ✅ com o
motivo; o que depende do Lukas (rodar na VM, o que ele quer aprender) é
perguntado.

---

## Caminhos

| O quê | Onde |
|---|---|
| Repositório | `github.com/lukas-araujo/neorv32-isfft-sky130` (privado); notebook: `~/Projects/neorv32-isfft-sky130` |
| Frente na VM (fonte de verdade, pasta dona) | `vm/backend/dft_isfft/` |
| Conferência aberta (notebook/nuvem) | `sim/run_dft_aberto.sh`, `sim/dft/` |
| Resultados da VM → repositório | `bash sim/traz_dft.sh <pasta copiada da VM> <etapa>` → `resultados/<data>_dft_<etapa>/` |
| Monta a pasta da VM | `bash sim/monta_vm.sh` (copia tudo o que está em `vm/`) |
| Na VM | `/prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc/backend/dft_isfft/` |
| Script da VM | `.../backend/dft_isfft/scripts/run_first_dft.tcl` |

---

## Plano da frente

> Resumo do que a frente faz e por quê. Detalhes nas sessões datadas.

### Objetivo

Levar o IP da ISFFT (`isfft_axi_v4`, o mesmo RTL que o Genus sintetizou no
chip e que o UVM verificou) a um netlist **testável**: todos os
flip-flops em cadeias de scan, padrões de ATPG gerados e a **cobertura de
falhas medida**, com o custo (área, timing) comparado com a síntese sem
DFT.

**O que se aprende:** o UVM pergunta "o projeto está certo?"; a DFT
pergunta "este chip *fabricado* saiu certo?". Um defeito de fabricação
(um fio curto com o terra, um transistor aberto) é modelado como **falha**
(*stuck-at-0/1*, transição lenta), e o teste de produção precisa
**controlar** e **observar** cada nó por poucos pinos. O scan transforma
os 12.559 flip-flops em registradores de deslocamento: dá para escrever e
ler o estado inteiro do circuito, e o problema sequencial vira
combinacional.

### O DUT do ponto de vista do teste

| Característica | No IP | Consequência para a DFT |
|---|---|---|
| Flip-flops | **12.559** (Yosys): 9.812 com enable (`edfxtp`), 2.747 simples (`dfxtp`) | 16 cadeias de ~785 (T5) |
| Relógio | 1 (`aclk`), borda de subida, sem clock gating | sem *lockup latch*, sem relógio de teste à parte |
| Reset | **todos síncronos** (66 blocos `always`, todos só `posedge clk`) | nenhum controle de reset em modo de teste (T3) |
| Latches | nenhum | — |
| Memórias | 2 macros OpenRAM (`in_mem` 64×64, `out_mem` 64×256) | **caixa-preta** para o ATPG: perda de cobertura em volta (T6) |
| Flip-flops sem reset (Spiral, `core_x`, `ob_q*`) | muitos | indiferente para scan: o estado inicial vem pela cadeia |

### Células de scan do sky130

24 células no `.lib` TT, todas com grupo `test_cell` (é por ele que o
Genus reconhece `SCD`/`SCE`). As que interessam:

| Comum | Scan | `next_state` da célula de scan (`.lib`) |
|---|---|---|
| `dfxtp` | `sdfxtp` | `(D & !SCE) \| (SCD & SCE)` |
| `edfxtp` (enable) | `sedfxtp` | `(D&DE&!SCE) \| (IQ&!DE&!SCE) \| (SCD&SCE)` |

No `sedfxtp` o mux de scan vem **depois** do mux de enable (modelo
funcional: `mux(SCE: SCD, mux(DE: D, Q))`): em deslocamento o flip-flop
anda mesmo com `DE = 0`. Sem isso, cada flip-flop com enable precisaria
de lógica extra para entrar na cadeia.

### Fluxo

| # | Etapa | Ferramenta | Onde | Passou quando |
|---|---|---|---|---|
| 0 | Conferência aberta: scan "de mentira" + Icarus | Yosys · Icarus | nuvem/notebook | regressão da Kria com `scan_en = 0`; flush das cadeias; mutação detectada |
| 1 | Síntese com scan (16 cadeias) | **Genus** | VM | 0 violações de DFT; 12.5xx flip-flops de scan; 16 cadeias |
| 2a | RTL sem scan ≡ netlist com scan | **Conformal** | VM | 0 não-equivalentes (com `scan_en = 0`) |
| 2b | Regressão da Kria no netlist do Genus | **Xcelium** | VM | `PASSOU` (40 matrizes) |
| 3 | ATPG *stuck-at* | **Modus** | VM | cadeias passam no teste de estrutura; cobertura medida |
| 4 | Simulação dos padrões do ATPG | Xcelium | VM | padrões passam no netlist |
| 5 | Reduzir a perda em volta das macros (*shadow logic* / pontos de teste) | Genus · Modus | VM | cobertura antes × depois |
| 6 | Falhas de transição (*at-speed*, LOC) | Modus | VM | cobertura de transição |
| 7 | Compressão (o chip tem 4 pinos) | Genus · Modus | VM | mesma cobertura com menos pinos de teste |

Etapas 5–7 ficaram **fora** (T10, Lukas em 01/11: um teste básico basta —
ver o fluxo funcionando no Modus). Ficam na tabela como registro do que
viria depois (observabilidade, defeitos de atraso, custo de pino).

### Fora de escopo

- **DFT no chip inteiro.** A frente é só do IP (FE-D39). O netlist com
  scan **não** entra no layout (o GDS do chip é o da síntese sem DFT).
- **MBIST das macros.** Teste de memória por BIST precisa de modelos da
  memória que a OpenRAM não gera; as macros ficam caixa-preta.
- **JTAG / IEEE 1149.1**: só faz sentido no nível do chip.

---

## 2026-11-01 — 1ª sessão: abertura da frente, medição do IP e conferência aberta

**Pedido do Lukas:** "vamos abrir a frente de DFT". Repositório no commit
`6e308e7` (fim da etapa 11 do GDSII) + o push do Lukas com os resultados da
etapa 12 do layout (`resultados/2026-11-01_1717_12_layout_chip/`, da outra
frente — não lido aqui).

### O que o FE previa × o que o RTL mostra

A 15ª sessão do `DIARIO.md` deixou 5 cuidados. Conferidos no RTL e no `.lib`:

| Cuidado (FE 15ª sessão) | Conferido | Fonte |
|---|---|---|
| 1. Liberar as células de scan (o `tech.tcl` as evita) | ✅ procede; é a única mudança de tecnologia (T2) | `vm/backend/synthesis/scripts/common/tech.tcl` |
| 2. SDC novo (portas do IP, não do chip) | ✅ procede (T4) | `isfft_axi_v4.v`, portas |
| 3. Macros caixa-preta perdem controle/observação em volta | ✅ procede; medir antes de remediar (T6) | — |
| 4. Portas de teste criadas pelo Genus; Modus na VM? | ✅ `MODUS261` está no PATH da VM | `CLAUDE.md` |
| 5. Reset interno (`core_rst`, `dp_rst`) "tende a precisar de controle em modo de teste" | ❌ **não precisa**: todo reset do IP é **síncrono**. Reset síncrono é só mais uma entrada do `D`; o ATPG o controla pela cadeia como qualquer dado. O que exige controle em teste é reset **assíncrono** gerado por lógica (ele mudaria o estado no meio do deslocamento) | `grep` dos 66 `always` do IP: todos `@(posedge clk)`/`@(posedge aclk)` |

**Vira slide?** Sim: "reset síncrono não atrapalha o scan; o assíncrono
sim — e este IP não tem nenhum".

### Medição do IP (Yosys, mesmas células evitadas do chip)

`sim/run_dft_aberto.sh`, passo 1 (`sim/build_dft/yosys.log`):

| Item | Valor |
|---|---|
| Flip-flops | **12.559** |
| ↳ `sky130_fd_sc_hd__edfxtp_1` (com enable) | 9.812 |
| ↳ `sky130_fd_sc_hd__dfxtp_1` | 2.747 |
| ↳ com reset/set assíncrono | **0** |
| Macros | 2 (`in_mem`, `out_mem`) |
| Tempo da síntese | 25 s |

(O Genus vai dar outro número exato — otimiza diferente —, mas a ordem de
grandeza decide as cadeias.)

### A biblioteca para o Modus (T7)

O Modus monta o modelo do circuito (`build_model`) a partir do netlist e de
uma **biblioteca Verilog estrutural** das células. O `sky130_fd_sc_hd.v`
tem dois modelos por célula, e o padrão (comportamental) depende de fios
`*_delayed` que só um bloco `specify` acionaria — o arquivo não tem
nenhum (`doc/specify_sky130.md`: era o X do projeto anterior). Na simulação
isso se resolve com `-define FUNCTIONAL`; para o Modus, o arquivo vai
**já resolvido**:

```bash
iverilog -E -DFUNCTIONAL -DUNIT_DELAY= -o sky130_fd_sc_hd_atpg.v primitives.v sky130_fd_sc_hd.v
```

| Item | Valor |
|---|---|
| Módulos / UDPs | 603 / 23 |
| `_delayed`, `specify`, `notifier`, `` `ifdef `` fora de comentário | **0** |
| `vm/backend/dft_isfft/modus/sky130_fd_sc_hd_atpg.v.gz` | 32 kB (1,17 MB descompactado; texto muito repetitivo) |

As macros entram por `modus/macros_caixa_preta.v`: só as portas, sem corpo.
O modelo da OpenRAM (`reg [..] mem`, `always @(negedge)`) não é estrutural.

**Risco registrado:** o modelo funcional das células usa **UDPs**
(`sky130_fd_sc_hd__udp_dff$P`, `udp_mux_2to1`...). O Modus aceita UDP em
biblioteca de células, mas é a primeira vez com o sky130 aqui; se o
`build_model` reclamar, é o primeiro lugar a olhar.

### Conferência aberta (T8): scan "de mentira" + Icarus

Antes de mandar para a VM, provar com ferramentas abertas o que o Genus
vai assumir. `sim/dft/dft_costura.py` faz uma inserção de scan
simplificada no netlist do Yosys (`dfxtp → sdfxtp`, `edfxtp → sedfxtp`,
flip-flops em ordem de nome, 16 cadeias, portas `scan_en`/`scan_in`/
`scan_out`). **Não é o netlist do ATPG** — é só a prova de conceito.

`bash sim/run_dft_aberto.sh` (Yosys 0.70 via `yowasp-yosys`, Icarus 12.0).
Fontes: `sim/build_dft/*.log` (fora do git; o script refaz).

| Passo | O que prova | Resultado | Tempo |
|---|---|---|---|
| 2. Kria no netlist **sem** scan | a base está certa (netlist do Yosys = RTL) | `PASSOU: 40 matrizes identicas a referencia, tlast e registradores OK` | 284 s |
| 3. Costura | todos os flip-flops entram | 12.559 (2.747 `sdfxtp` + 9.812 `sedfxtp`); cadeias 15 × 785 + 1 × 784 | < 1 s |
| 4. Kria no netlist **com** scan, `scan_en = 0` | o mux de scan é transparente | `PASSOU` (mesma mensagem) | 341 s |
| 5. Flush das 16 cadeias | as células de scan do sky130 deslocam, inclusive `sedfxtp` com `DE = 0` | **16/16**, 299 bits conferidos por cadeia, 0 erros | ~1 min |
| 6. Mutação: `SCE = 0` no 393º flip-flop da cadeia 0 (só a versão certa passou antes) | o flush enxerga cadeia quebrada | detectada **só na cadeia 0**: a partir do ciclo 786 sai `x` | ~1 min |

(O tempo a mais do passo 4: 12.559 muxes de scan a mais para o Icarus avaliar.)

### 🐛 O costurador gerava Verilog inválido

**Sintoma:** `isfft_scan.v:176001: syntax error ... Invalid module instantiation`.
**Causa:** identificador escapado do Verilog (`\inst.perm.inFlip0 `) só termina
num **espaço**. O `.strip()` do Python tirou o espaço, e `.SCD(\inst...inFlip0)`
virou um nome que engole o `)`.
**Resolvi com:** o nome do `Q` volta sempre com um espaço no fim.
**Tempo gasto:** 10 min.
**Vira slide?** Não.

### 🔍 As macros trabalham durante o deslocamento

Contado no flush (`tb_dft_flush.v`, 1.085 ciclos com `scan_en = 1`):

| Macro | Escritas | Leituras | Por quê |
|---|---|---|---|
| `in_mem` | 0 | **454** | `csb1 = ~launch_active`: `launch_active` é um flip-flop, e bits aleatórios passam por ele. Escrita = 0 porque `csb0 = ~(tvalid & tready)` depende da porta `s00_axis_tvalid`, parada em 0 |
| `out_mem` | **352** | 0 | `csb0` vem do `out_valid_sr[0]` (flip-flop); leitura = 0 porque `ob_fetch` tem `~dp_rst` e o tb segurou `aresetn = 0` |

A macro não tem scan nem sabe que o resto do circuito está em modo de teste:
cada bit que passa pelos flip-flops de controle vira um acesso. No silício
isso **corrompe o conteúdo** e **gasta energia** no deslocamento. Para o ATPG
com a macro caixa-preta tanto faz (ela já é X). Num teste que precise da
memória (ou num chip sensível a consumo no teste), a solução padrão é prender
o `csb` em 1 com `scan_en` (proteção de memória em deslocamento). Mexe no
RTL (front-end fechado) ou entra como lógica de teste no Genus; fica para a
etapa 5, junto com a *shadow logic* (T11).
**Vira slide?** Sim: "a memória não sabe que está em teste".

### O que ainda não foi conferido (só a VM responde)

| Ponto | Por quê |
|---|---|
| Sintaxe dos comandos de DFT do Genus 22.1 (`define_shift_enable`, `define_scan_chain`, `connect_scan_chains`, `write_dft_atpg`) | primeira rodada de DFT nesta VM; os frágeis estão em `catch` com mensagem |
| Se o Genus mapeia `edfxtp` em `sedfxtp` ou em `sdfxtp` + mux | escolha da ferramenta; a contagem sai no bloco 1 |
| `write_do_lec` com DFT prende `scan_en = 0` no revisado | conferir no `.do` antes de rodar o 2a |
| Nome e conteúdo do script do Modus que o `write_dft_atpg` escreve | o bloco 3 lista a pasta antes de rodar |
| Modus aceita os UDPs da biblioteca do sky130 | ver "Risco registrado" acima |

### Arquivos da frente

| Arquivo | O quê |
|---|---|
| `vm/backend/dft_isfft/scripts/run_first_dft.tcl` | blocos 1 (Genus), 2a (LEC), 2b (Kria no netlist com scan), 3 (Modus) |
| `vm/backend/dft_isfft/scripts/isfft_dft.tcl` | síntese com scan: lê o `path.tcl`/`tech.tcl` do chip (só leitura), libera o scan, sinais de teste, regras, 16 cadeias, relatórios, LEC, `write_dft_atpg` |
| `vm/backend/dft_isfft/constraints/isfft_dft.sdc` | 50 MHz, modo funcional (`scan_en = 0` por *case analysis*) |
| `vm/backend/dft_isfft/modus/sky130_fd_sc_hd_atpg.v.gz` | biblioteca das células para o Modus (T7) |
| `vm/backend/dft_isfft/modus/macros_caixa_preta.v` | as 2 macros só com portas (T6) |
| `vm/backend/dft_isfft/tb/tb_isfft_dft.v` | o tb da Kria com o DUT = netlist com scan (bloco 2b) |
| `vm/backend/dft_isfft/LEIAME.md` | como rodar na VM |
| `sim/run_dft_aberto.sh` | conferência aberta (passos 1–7) |
| `sim/dft/dft_costura.py`, `sim/dft/tb_dft_flush.v` | scan de mentira e teste de cadeia |
| `sim/traz_dft.sh` | traz os resultados da VM para `resultados/<data>_dft_<etapa>/` |

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| T1 | Scan completo (todos os flip-flops), estilo *muxed scan* | ✅ | É a única célula de scan que o sky130 tem; scan parcial só se justifica com área apertada, e aqui o objetivo é aprender o fluxo completo |
| T2 | Reaproveitar `path.tcl` e `tech.tcl` da síntese do chip (só leitura) e mudar **uma** coisa: `avoid false` em `sdf*`/`sedf*` | ✅ | Mesmas bibliotecas, mesmas células proibidas no layout (L20); a comparação com/sem DFT fica justa e a diferença cabe numa linha |
| T3 | Sem `test_mode` na 1ª rodada | ✅ | Não há reset assíncrono, clock gating nem latch no IP. `test_mode` volta se a *shadow logic* (T6/etapa 5) precisar |
| T4 | SDC do IP: 50 MHz, `aresetn` com atraso de entrada (síncrono, não *false path*), `scan_en = 0` por *case analysis* | ✅ | A síntese otimiza o modo funcional; o caminho de deslocamento é fio curto (o hold dele é assunto de layout) |
| T5 | 16 cadeias (~785 flip-flops cada), portas `scan_in_<i>`/`scan_out_<i>` | ✅ | Tempo de teste ∝ comprimento da cadeia: 16 cadeias = 16× menos ciclos por padrão que 1 cadeia. No IP portas não custam; no chip (4 pinos) não caberiam — gancho para a compressão (etapa 7) |
| T6 | Macros como caixa-preta no ATPG, **sem** *shadow logic* na 1ª rodada | ✅ | Primeiro medir a perda; remediar depois e comparar (é o que vira aula). Hipótese: perda pequena, porque o que entra e sai das macros passa por flip-flops de scan (`core_x`, `ob_q*`, ponteiros) — perdem-se os fios entre esses flip-flops e os pinos da macro |
| T7 | Biblioteca do Modus = `sky130_fd_sc_hd.v` pré-processado com `FUNCTIONAL` (`iverilog -E`), versionado como `.v.gz` | ✅ | O modelo padrão depende de `specify` que não existe; o Modus não precisa saber disso. Gerado por script, não à mão |
| T8 | Conferência aberta antes da VM: Yosys + scan de mentira + Icarus (Kria com `scan_en = 0`, flush, mutação) | ✅ | Mesma regra das outras frentes (`CLAUDE.md`): conferir o que der com ferramentas abertas |
| T9 | A frente DFT também é dona de `sim/run_dft_*.sh`, `sim/dft/` e `sim/traz_dft.sh` | ✅ | Como o UVM com `sim/run_uvm_*.sh`/`traz_uvm.sh`; o `traz_vm.sh` é do GDSII e só olha `backend/synthesis/` |
| T10 | Roteiro em 7 etapas (tabela "Fluxo"); 5–7 conforme o Lukas quiser | 🟡 | Depende do que o Lukas quer aprender e do tempo |
| T11 | Proteção das macros no deslocamento (`csb` preso com `scan_en`) fica para a etapa 5, junto com a *shadow logic* | ✅ | Não muda o ATPG com a macro caixa-preta; exige mexer no RTL ou lógica de teste — melhor decidir com a cobertura medida |

---

### Escopo confirmado (Lukas, 01/11, depois do commit `72caba5`)

"A ideia da DFT é só testar como funciona e ver no Modus as coisas
funcionando. Um teste básico já é suficiente." → **T10 ✅: etapas 1–3**
(Genus com scan, LEC + Kria no netlist, ATPG *stuck-at* no Modus); a 4
(simular os padrões) só se sair de graça; 5–7 fora.

---

## Índice de decisões

| # | Resumo | Status | Data |
|---|---|---|---|
| T1 | Scan completo, *muxed scan* | ✅ | 2026-11-01 |
| T2 | `tech.tcl` do chip + scan liberado | ✅ | 2026-11-01 |
| T3 | Sem `test_mode` (nada assíncrono) | ✅ | 2026-11-01 |
| T4 | SDC do IP, `scan_en = 0` por *case analysis* | ✅ | 2026-11-01 |
| T5 | 16 cadeias | ✅ | 2026-11-01 |
| T6 | Macros caixa-preta, sem *shadow logic* (1ª rodada) | ✅ | 2026-11-01 |
| T7 | Biblioteca do Modus pré-processada com `FUNCTIONAL` | ✅ | 2026-11-01 |
| T8 | Conferência aberta antes da VM | ✅ | 2026-11-01 |
| T9 | Pastas da frente: `vm/backend/dft_isfft/`, `sim/run_dft_*.sh`, `sim/dft/`, `sim/traz_dft.sh` | ✅ | 2026-11-01 |
| T10 | ~~Roteiro de 7 etapas~~ → escopo **básico**: etapas 1–3 (4 opcional); 5–7 fora | ✅ (Lukas) | 2026-11-01 |
| T11 | Proteção das macros no deslocamento → etapa 5 (fora do escopo, T10; fica como achado) | ✅ | 2026-11-01 |

---

## Pendências abertas

- [ ] VM: `bash sim/monta_vm.sh` → copiar → bloco 1 (Genus) do `run_first_dft.tcl` → `traz_dft.sh … scan`
- [ ] VM: blocos 2a (LEC) e 2b (Kria no netlist com scan)
- [ ] VM: bloco 3 (Modus) — conferir o nome do script que o `write_dft_atpg` escreve
- [ ] Bloco 4 (simulação dos padrões): preparar depois de ver a saída do bloco 3
- [ ] Comparar área/timing com a síntese sem DFT (o IP sozinho: rodar o mesmo script sem scan? ou ler o `u_isfft` do `_area_hier.rpt` do chip)
- [x] ~~Confirmar T10~~ — Lukas (01/11): "a ideia da DFT é só testar como funciona e ver no Modus as coisas funcionando; um teste básico já é suficiente" → etapas 1–3
- [ ] (fora do escopo, T10) Etapas 5–7: *shadow logic*, proteção do `csb`, transição, compressão
