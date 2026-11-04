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

## 2026-11-02 — 2ª sessão: ✅ bloco 1 (Genus com scan) passou de primeira

Rodado pelo Lukas na VM; fonte: trecho final do `genus.log` colado no chat
(os relatórios completos chegam pelo `sim/traz_dft.sh`).

| Item | Resultado | Linha do log |
|---|---|---|
| `connect_scan_chains` | "Configuring 16 chains for 12552 scan f/f"; cadeias 0–7 com 785, 8–15 com 784; domínio `aclk`, borda de subida | `connect_scan_chains` |
| Portas criadas | 32 (`DFT-130`: `scan_in_0..15`, `scan_out_0..15`) + `scan_en` | Message Summary |
| `check_dft_rules` (pós) | **0 violações**; 12.552 registradores passam; **100 %** com scan; 0 fora por escolha | `check_dft_rules` |
| `syn_opt` | área final **974.796** (`area_down`); TNS 0; transição máx. 5.263 → 0 | tabelas do `syn_opt` |
| `add_tieoffs` | `conb_1` nos `1'b0`/`1'b1` | `UTUI-207` |
| `write_do_lec` | dofile composto (RTL → `fv_map` → revisado) **com as restrições de DFT** | `CFM-2`, `CFM-655` |
| `write_dft_atpg` | `modus_work/runmodus.atpg.tcl` **e** `run_fullscan_sim` (simulação dos padrões) | fim do log |
| `ungroup` + netlist achatado | sem erro (o bloco 2b tem netlist) | — |

### Conferência do `run_first_dft.tcl` (depois do `exit`)

| Item | Resultado |
|---|---|
| Módulos não resolvidos / vazios | 0 / 0 |
| Regras de DFT (pré): relógio / set-reset assíncrono / total | 0 / 0 / **0**; 1 domínio de relógio de teste; 100 % com scan |
| Cadeias (`_scan_chains.rpt`) | 16: `cadeia_0..7` com 785, `cadeia_8..15` com 784 |
| Fora das cadeias | 0 (reprovados, preservados, segmentos, *lockup*) |
| Células de scan no netlist | **12.551 `sdfxtp_1` + 1 `sdfxtp_2`; 0 `sedfxtp`** |
| Flip-flops comuns | 0 |
| Instâncias / sequenciais | 35.962 / 12.554 (12.552 flip-flops + 2 macros) |
| Área (`_qor.rpt`) | 974.848,7 µm² |
| Slack de setup | **+4.479 ps** |
| `modus_work/` | `runmodus.atpg.tcl`, `run_fullscan_sim`, `run_fullscan_sim_sdf`, `isfft_axi_v4.FULLSCAN.pinassign`, `isfft_axi_v4.test_netlist.v` (5 MB) |

**O Genus não usou o `sedfxtp`.** Os 9.8xx flip-flops com enable viraram
`sdfxtp` + mux na frente (`D = DE ? D : Q`), não a célula de scan com
enable embutido. Funciona igual: em deslocamento o mux de scan, dentro da
célula, ignora o `D`. Se custou área, o `_gates.rpt` vai dizer (contar
`mux2` aqui × síntese do chip).

### 🐛 "portas de teste: 0" na conferência

**Sintoma:** a linha de conferência contou 0 portas de teste, com o log
dizendo 32 (`DFT-130`) e as cadeias ligadas de `scan_in_N` a `scan_out_N`.
**Causa:** o `grep` procurava `input scan_...`; o Genus declara as portas em
lista (`input aclk, ..., scan_in_0, ...`).
**Resolvi com:** contar os nomes `scan_(in|out)_N` distintos no cabeçalho do
módulo (esperado 32).
**Tempo gasto:** 2 min. **Vira slide?** Não.

**Flip-flops: Yosys 12.559 × Genus 12.552.** O Genus otimizou 7 a mais; a
previsão das cadeias (~785) bateu.

| Aviso | O que é | Efeito |
|---|---|---|
| `DFT-325` | as células de clock gating (`sdlclkp`) estão evitadas, e "a DFT às vezes precisa delas" | nenhum: o IP não tem clock gating, e o Genus não precisou de nenhuma |
| `CFM-655` | o dofile do LEC prende as portas de teste (`scan_en = 0`) | é o que se quer: com `scan_en = 0` o netlist tem de ser o RTL |
| `TUI-32` | um atributo vai ficar obsoleto na próxima versão | nenhum agora; descobrir qual quando o `genus.log` inteiro chegar |

A área de 974.796 µm² inclui as 2 macros (449.871 µm² no `.lib`). A
comparação justa com o IP sem scan fica para quando chegar o
`_area_hier.rpt` (o `u_isfft` da síntese do chip tem 448.030 µm² de
lógica, `doc/tabelas_sintese.md`).

### ✅ Bloco 2a — LEC: RTL sem scan ≡ netlist com scan

Fonte: fim do `reports/isfft_dft_lec_run.log` colado no chat (Conformal
**26.10-s200**). Dofile composto do Genus, com as restrições de DFT
(`CFM-655`).

| Etapa | Resultado |
|---|---|
| `fv_map` → netlist com scan (plana) | **Equivalent** |
| RTL → `fv_map` (hierárquica, `run_hier_compare`) | **Equivalent**, 129 pares de módulos |
| Não-equivalentes / abortados / desconhecidos | **0 / 0 / 0** |
| `analyze_results` | LEC **PASS**, Flatten **PASS**, Hierarchical **PASS** |
| Fase sequencial | 12.552 flip-flops, 0 inconsistências (`sequential_phase`) |
| Constante / fusão sequencial | 516 / 163 pontos, 0 inconsistências (otimizações do Genus aceitas) |
| Tempo | 582 s (comparação 334 s, datapath 206 s); 591 MB |

Avisos "críticos" do log: `RTL5.3` (8), `RTL13` (5), `RTL7.10a` (2) — leitura
do RTL do Spiral (`case` redimensionado, laço `for` que nunca entra,
comparação de larguras diferentes); os mesmos do LEC do chip, sem efeito.
O "No of compare points = 595" do fim do log é da última comparação da
corrida hierárquica (um módulo), não do IP inteiro.

**Leitura:** com `scan_en = 0` o mux de scan vira fio; o LEC prova que os
32 portas novas e a troca de 9.8xx `edfxtp` por `sdfxtp` + mux não mudaram
nenhuma função.
**Vira slide?** Sim, junto do LEC do chip: "inserir scan não muda o circuito".

### ✅ Bloco 2b — regressão da Kria no netlist do Genus com scan (`scan_en = 0`)

Fonte: saída do `xrun` colada no chat (Xcelium **26.03-s005**), netlist
achatado `deliverables/isfft_dft_flat.v`.

| Item | Resultado |
|---|---|
| Referência (wrapper da etapa 1) | 1.280 palavras |
| Pacote truncado | injetado (20 palavras com `tlast`) |
| Veredito | **`PASSOU: 40 matrizes identicas a referencia, tlast e registradores OK`** |
| Tempo simulado / real | 118,35 µs / **10 s** (Icarus na nuvem, scan de mentira: 341 s) |

Avisos: só `DLCPTH` (o `cds.lib` da instalação nova aponta para pastas VHDL
que não existem; o mesmo da etapa 9 do GDSII). Nenhum erro.

**A conferência fecha por dois caminhos independentes:** o LEC (2a) prova a
equivalência formal; a simulação (2b) roda o mesmo teste que validou a Kria,
o RTL e o netlist sem scan.

### 🐛 Bloco 3 — Modus sem licença (`TDA-011`): licença 25.1, Modus 26.1

**Sintoma:** `modus -file runmodus.atpg.tcl` abre ("Starting Modus DFT
Software Solution Tcl UI") e para na hora:
`ERROR (TDA-011): Failed to obtain a license to run Modus Tcl User Interface.
Attempted to check out ... Modus_common_ui (1) ... CDS_LIC_FILE=5280@192.168.2.250`.
**Investigação (Lukas, na VM):**

| Comando | Resultado |
|---|---|
| `lmstat -a` (servidor) | `Modus_common_ui`, `modus_atpg`, `modus_atpg_mcpu`, `Modus_DFT_Opt`: **95 emitidas, 0 em uso** (não é fila) |
| `lmstat -i Modus_common_ui` | **v25.1**, 95, `cdslmd`, expira 31-mai-2027 |
| `lmdiag -n Modus_common_ui` | servidor `licserver.ibti.org.br`; flutuante 1-jun-2026 a 31-mai-2027; "This license can be checked out" (testado na v25.1) |
| `ls -d /tools/cadence/*MODUS*` | só `MODUS261` |

**Causa:** licença FlexNet é um **teto de versão**: a v25.1 vale para o Modus
≤ 25.1. O Modus da VM é o **26.1** (atualização de out/2026, DIARIO_UVM 6ª
sessão) e pede a v26.1. O Conformal 26.1 e o Xcelium 26.03 pegam licença:
as deles foram atualizadas; a do Modus, não. O `lmdiag` diz que pode retirar
porque testa na versão da própria licença.
**Resolvi com:** não se resolve daqui. Depende do administrador da VM:
instalar o Modus 25.1 (a licença 25.1 está válida, 95 livres) ou atualizar a
licença para 26.1. Com o 25.1 instalado, basta trocar `MODUS261` no PATH do
bloco 3. Alternativa oferecida ao Lukas: ATPG aberto na nuvem para ver o
conceito (circuito com os flip-flops cortados = combinacional).
**Tempo gasto:** ~15 min.
**Vira slide?** Sim: "ferramenta instalada ≠ ferramenta licenciada — e a
licença tem versão".

**Etapa 4 de graça:** o `run_fullscan_sim` já existe; entrou como bloco 4
do `run_first_dft.tcl` (rodar depois do 3).

**Vira slide?** Sim: "12.552 flip-flops, 100 % com scan, 16 cadeias de 785".

| # | Decisão | Status | Motivo |
|---|---|---|---|
| T12 | Bloco 4 = `run_fullscan_sim` escrito pelo Genus | ✅ | Sai de graça e fecha o ciclo: os padrões do Modus simulados no netlist |

---

## 2026-11-03 — 4ª sessão: Modus 25.1 instalado na VM

O Prof. Gilmar avisou que a VM foi consertada. `ls -d /tools/cadence/*MODUS*`
(Lukas): **`MODUS251`** e `MODUS261` — o administrador instalou o 25.1 ao lado,
que casa com a licença v25.1 (2ª sessão).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| T15 | `run_first_dft.tcl` com `MODUS251` no PATH (só ele; o resto do PATH igual ao `CLAUDE.md`) | ✅ | Licença `Modus_common_ui` v25.1; o 26.1 dá `TDA-011`. Registrado também no `CLAUDE.md` |

O bloco 3 volta a ser o caminho principal; o bloco 5 (modo de teste na mão,
T13) fica como complemento.

### ✅ Bloco 3 — ATPG no Modus 25.1: 170 padrões, 99,65 % de cobertura

Fonte: saída do `run_first_dft.tcl` (bloco 3) colada no chat; Modus
**25.12-s004_1** (`MODUS251`). Licenças `Modus_common_ui` e `modus_atpg`
retiradas sem erro. Fluxo inteiro ~40 s; `create_logic_tests` 15 s.

| Comando | Resultado |
|---|---|
| `build_model` | ok; `TLM-140`: `sram_1rw1r_64x64_wpr2` sem rede interna → `TIEX` nas saídas; `TEI-010` [Severe]: `sram_1rw1r_64x256` "indefinido" → caixa-preta (efeito igual ao planejado, T6; ver abaixo) |
| `build_testmode FULLSCAN` | **16 cadeias controláveis e observáveis** (`TTM-357`); 99,66 % de lógica ativa, 0,34 % inativa |
| `verify_test_structures` | 16 × "controllable and observable" (`TSV-378`); maior cadeia 785 = 100 % da média; 12.552 bits |
| `build_faultmodel` | *stuck-at* (`-includedynamic no`) |
| `create_logic_tests` | **170 padrões simulados, 169 efetivos; ATCov 99,65 % (modo de teste) / 99,30 % (global); 996 falhas não testadas** |
| `write_toggle_gram` | `TBM-099`: comutação no deslocamento > 30 % |
| `write_vectors` (Verilog, paralelo) | 12.552 medidas, todas nas saídas de scan (0 nas saídas primárias) |
| `commit_tests` | testes 1 a 170 gravados |

**A curva de cobertura (`TDA-220`):**

| Padrões | Falhas detectadas no trecho | Cobertura (modo de teste) | Não testadas |
|---|---|---|---|
| 1 (teste de cadeia) | 87.905 | **25,71 %** | 253.966 |
| 16 | 196.355 | 83,15 % | 57.405 |
| 32 | 20.246 | 89,07 % | 37.150 |
| 64 | 6.736 | 93,55 % | 21.846 |
| 96 | 4.834 | 96,61 % | 11.366 |
| 128 | 3.564 | 98,97 % | 3.294 |
| 167 | 1.414 | 99,64 % | 1.020 |
| 174 (169 efetivos) | 0 | **99,65 %** | **996** |

Total de falhas: **341.871** no modo de teste (343.063 no global) — número
exato na 5ª sessão.

**Leituras:**
1. **O teste de cadeia sozinho cobre 25,7 %**: as falhas do próprio caminho de
   scan (SCD/SCE, mux de scan, Q). É o E1 da 3ª sessão em escala: o
   deslocamento vê o "trem", não a lógica.
2. **Retorno decrescente:** o padrão 16 levou 196 mil falhas; o 168, 4. As
   fáceis caem primeiro; as difíceis pedem um padrão quase só para elas.
3. **T6 confirmada:** perde-se pouco em volta das macros (996 falhas, ~0,3 %):
   o que entra e sai delas passa por flip-flops de scan.
4. **Rapidez:** 15 s para 170 padrões em ~342 mil falhas — é o scan que
   transforma o problema sequencial em combinacional.

**Avisos:**

| Aviso | O que é | Efeito |
|---|---|---|
| `TEI-010` [Severe] `sram_1rw1r_64x256` indefinido | as **duas** macros (o resumo mostra só a 1ª ocorrência, "Count 2"; ver 5ª sessão) | nenhum: é a caixa-preta planejada (T6) |
| `TLM-140` `TIEX` nas saídas da 64×64 | saída sem rede interna = fonte de X | é a caixa-preta funcionando |
| `TBM-099` comutação > 30 % no deslocamento | consumo alto no testador | o lado de potência da DFT (como os acessos espúrios às macros, 1ª sessão); fora do escopo (T10) |
| `TBM-109` X nos padrões | estados desconhecidos (macros) preenchidos aleatoriamente para a conta de comutação | só afeta a estimativa de comutação |
| `TVE-103` sem *offset* de teste para `aclk` | o Modus usou 8 ns | só na temporização dos vetores |

**Vira slide?** Sim, os dois: a curva de cobertura e "1 padrão = 25 %".

### ✅ Bloco 4 — os 170 padrões do Modus simulados no netlist (Xcelium)

Fonte: fim da saída do `run_fullscan_sim` colada no chat (Xcelium 26.03-s005,
`testresults/verilog/VER.FULLSCAN.isfft_axi_v4_atpg.mainsim.v`).

| Arquivo de vetores | Testes | Comparações | Divergências |
|---|---|---|---|
| teste de cadeia | 1 | 12.552 (1 por flip-flop) | 0 |
| lógica (`...data.logic.ex1.ts2.verilog`) | 169 | 2.143.560 | 0 |
| **Total (`TVE-209`)** | **170 / 170** | **2.156.112** | **0** |

855 ciclos, 68,4 µs simulados, 9 s reais. O formato é **paralelo**
(`-scanformat parallel`, do `runmodus.atpg.tcl` do Genus): o simulador
carrega/lê as cadeias de uma vez, sem os 785 ciclos de deslocamento por
padrão (em série seriam ~170 × 785 ≈ 133 mil ciclos). O deslocamento em si
está provado à parte: `verify_test_structures` (bloco 3), flush na nuvem
(1ª sessão) e o arquivo do teste de cadeia.

**Vira slide?** Sim: "170 padrões, 2,16 milhões de comparações, 0 erros".

### Escopo da frente fechado (T10)

| Etapa | Prova |
|---|---|
| 1. Síntese com scan | 12.552 flip-flops, 100 % com scan, 16 cadeias, slack +4,48 ns |
| 2a. LEC RTL ≡ netlist com scan | PASS, 0 não-equivalentes |
| 2b. Kria no netlist com scan | PASSOU, 40 matrizes |
| 3. ATPG *stuck-at* | 170 padrões, **99,65 %** (modo de teste) / 99,30 % (global), 996 falhas não testadas |
| 4. Padrões simulados | 170/170, 2.156.112 comparações, 0 divergências |

O bloco 5 (modo de teste na mão, T13) fica como material opcional para a
aula: mostra um padrão por dentro (carga, captura, descarga, falha) — o que
o Modus fez 170 vezes. Rodá-lo na VM exige o mapa do netlist do Genus
(`traz_dft.sh` + `sim/run_dft_modo_teste.sh`).

---

## 2026-11-04 — 5ª sessão: os resultados completos no git; números exatos

O Lukas copiou a pasta da VM e rodou `bash sim/traz_dft.sh … scan`:
**`resultados/2026-11-02_dft_scan/`** (4,1 MB; a data é a do netlist do
Genus). A síntese do chip (`backend/synthesis/`) não mudou desde a etapa 9
do layout (arquivo mais novo de 26/10 18:00, já em
`resultados/2026-10-26_layout_etapa9/`) — o `traz_vm.sh` não precisou rodar.
Os números abaixo substituem os que vinham dos trechos colados no chat.

### Cobertura exata (`modus/log_create_logic_tests_*`)

| | #Faults | #Tested | #Possibly | #Redund | #Untested | %TCov | **%ATCov** |
|---|---|---|---|---|---|---|---|
| Modo de teste FULLSCAN | 341.871 | 340.510 | 214 | 151 | **996** | 99,60 | **99,65** |
| Global | 343.063 | 340.510 | 214 | 151 | 2.188 | 99,26 | 99,30 |

- **TCov** = testadas ÷ todas; **ATCov** (ajustada) = testadas ÷ (todas −
  redundantes). As 151 **redundantes** são falhas que não mudam nenhuma saída
  em circuito nenhum (lógica sem efeito) — não há padrão que as detecte, e
  elas não indicam defeito do teste.
- **Possibly** (214): o padrão produz X no circuito com falha (perto das
  macros caixa-preta): talvez detecte, talvez não.
- **Global − modo de teste = 1.192 falhas inativas** (`build_faultmodel`:
  "Total Static 343063 / Active 341871 / Inactive 1192"): pontos que o modo
  FULLSCAN não usa (0,34 % de lógica inativa, `THM-814`) — PI estáticas
  ativas só 47 % (portas paradas no teste, como `scan_en` fixa na captura).

### Modelo do Modus (`log_build_model_*`, `TLM-055`)

| Item | Valor |
|---|---|
| Blocos (hierárquico / achatado) | 422.058 / 174.384 |
| Entradas / saídas primárias | 153 / 132 (as do IP + `scan_en` + 16 `scan_in` / 16 `scan_out`) |
| Redes amarradas | 14 em 0, 14 em 1, **128 em X** |
| Flip-flops (borda de subida) | 12.552 |
| MUX2 | 12.579 (os muxes de scan dentro das `sdfxtp` + 27 da lógica) |
| RAMs / latches | 0 / 0 |

**As 128 redes em X = os `dout0[63:0]` das duas macros** (porta 0 só escreve;
saída sem uso). Com as macros caixa-preta, o Modus põe `TIEX` nelas (`TLM-140`).

### 🔍 `TEI-010` não era só da 64×256

O resumo de mensagens do Modus mostra **só a 1ª ocorrência** de cada código,
com a contagem ao lado ("2 WARNING (TEI-010) … `sram_1rw1r_64x256`"). No log
completo há as duas: `sram_1rw1r_64x256` **e** `sram_1rw1r_64x64_wpr2` "is
undefined … defined as a black box" — e o mesmo com o `TLM-140`. O
`macros_caixa_preta.v` (módulo só com portas) é lido, e o Modus chama módulo
sem conteúdo de "indefinido". Resultado: exatamente o planejado (T6).
**Lição:** "Count" no resumo do Modus = ocorrências do mesmo código, não da
mesma instância.

### Custo do scan em área (Genus, mesma biblioteca e mesmo RTL)

| | IP no chip, sem scan (`2026-09-29_sintese_layout`, `u_isfft`) | IP com scan (`isfft_dft_area_hier.rpt`) | Diferença |
|---|---|---|---|
| Área total (com as 2 macros, 449.871 µm²) | 897.901 µm² | 974.849 µm² | +76.948 µm² (**+8,6 %**) |
| Só lógica | 448.030 µm² | 524.977 µm² | **+17,2 %** |
| Instâncias | 36.375 | 35.962 | −413 |
| Sequencial (scan) | — | 329.808 µm² (12.552 `sdfxtp`, 33,8 %) | |

O custo vem da célula: `sdfxtp_1` tem um mux embutido. **Menos** instâncias
com scan: os 9.8xx flip-flops com enable (`edfxtp`, que o Genus usou no chip)
viraram `sdfxtp` com a recirculação do enable feita na lógica em volta
(só 1 `mux2_1` e 26 `mux2i_1` no netlist: o Genus fundiu o mux do enable com
portas que já existiam). O SDC do IP isolado (atrasos de E/S de 6 ns nas
portas AXI) não é o mesmo contexto do chip; o slack (+4,48 ns) não se compara.

**Vira slide?** Sim: "scan = +17 % de lógica, 99,65 % de cobertura".

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
| T12 | Bloco 4 = `run_fullscan_sim` do Genus | ✅ | 2026-11-02 |

---

## Pendências abertas

- [x] ~~VM: bloco 1 (Genus)~~ — passou (2ª sessão)
- [x] ~~VM: bloco 2a (LEC)~~ — PASS (2ª sessão)
- [x] ~~VM: bloco 2b (Kria no netlist com scan)~~ — PASSOU, 10 s (2ª sessão)
- [x] ~~VM: bloco 3 (Modus)~~ — 170 padrões, 99,65 % (4ª sessão)
- [x] ~~VM: bloco 4 (`run_fullscan_sim`)~~ — 170/170, 0 divergências (4ª sessão)
- [x] ~~`traz_dft.sh … scan`~~ — `resultados/2026-11-02_dft_scan/` (5ª sessão)
- [ ] (opcional) Bloco 5, modo de teste na mão: mapa do netlist do Genus (`bash sim/run_dft_modo_teste.sh`) + VM
- [x] ~~Comparar área com a síntese sem DFT~~ — +17,2 % de lógica (5ª sessão)
- [x] ~~Confirmar T10~~ — Lukas (01/11): "a ideia da DFT é só testar como funciona e ver no Modus as coisas funcionando; um teste básico já é suficiente" → etapas 1–3
- [ ] (fora do escopo, T10) Etapas 5–7: *shadow logic*, proteção do `csb`, transição, compressão
