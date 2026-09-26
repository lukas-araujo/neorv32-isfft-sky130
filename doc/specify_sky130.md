# Modelos de simulação do sky130 sem `specify`: o que é, por que dá X e como corrigir

> Projeto NEORV32 + ISFFT (sky130). Achado na 13ª sessão do DIARIO.
> Explica o X que travou a simulação pós-síntese do projeto anterior
> (`neorv32_sram_soc`) e as duas formas de corrigir.

---

## 1. Resumo em três linhas

- O arquivo `tech/verilog/sky130_fd_sc_hd.v` (células padrão) tem, para cada
  célula sequencial, um modelo que depende de fios `*_delayed` — e esses fios
  deveriam ser acionados por blocos `specify` que **não existem no arquivo**.
- Resultado: todo flip-flop e latch fica em **X para sempre**, em qualquer
  simulador, com qualquer reset.
- Correção: simular com `-define FUNCTIONAL` (o que o fluxo usa) **ou** ligar
  os fios `*_delayed` com `sim/liga_delayed.py`. **As memórias da OpenRAM não
  têm esse problema.**

---

## 2. As memórias da OpenRAM não são afetadas

Conferido nos 4 modelos (`macros/*/*.v`):

| Modelo | `specify` | fios `*_delayed` |
|---|---|---|
| `sram_8kbyte_1rw_32x2048_8.v` | 0 | 0 |
| `sram_4kbyte_1rw_32x1024_8.v` | 0 | 0 |
| `sram_1rw1r_64x256.v` | 0 | 0 |
| `sram_1rw1r_64x64_wpr2.v` | 0 | 0 |

O modelo da OpenRAM é **comportamental**: registra as entradas em
`always @(posedge clk0)`, escreve e lê em `negedge`, sem primitivas de
célula e sem checagem de tempo. Ele não depende de `specify` para nada, e
funcionou na simulação de portas sem mudança nenhuma.

O que as memórias têm de peculiar é outra coisa, já resolvida no fluxo:
a interface de 33 bits do `.v` das macros de 1 porta contra 32 bits do
`.lib` (adaptador `sram_lib_view_model.v`) e o `VERBOSE = 1` (o
`run_first.tcl` troca para 0).

O problema é **só do arquivo de células padrão** do sky130:

| `sky130_fd_sc_hd.v` | |
|---|---|
| módulos | 1.524 |
| blocos `specify` | **0** |
| fios `*_delayed` declarados | 240 |

---

## 3. Como o modelo de uma célula é organizado

Cada célula vem em **4 variantes**, escolhidas por `` `ifdef ``:

```
`ifdef USE_POWER_PINS          -> com pinos VPWR/VGND/VPB/VNB
    `ifdef FUNCTIONAL          ->   funcional
    `else                      ->   comportamental
`else                          -> sem pinos de alimentação (o netlist do Genus usa esta)
    `ifdef FUNCTIONAL          ->   funcional
    `else                      ->   comportamental   <- o padrão sem nenhum define
`endif
```

### Variante funcional (`FUNCTIONAL`) — `dfrtp`

```verilog
module sky130_fd_sc_hd__dfrtp (Q, CLK, D, RESET_B);
    output Q; input CLK; input D; input RESET_B;
    wire buf_Q; wire RESET;
    not                                     not0 (RESET , RESET_B        );
    sky130_fd_sc_hd__udp_dff$PR `UNIT_DELAY dff0 (buf_Q , D, CLK, RESET  );
    buf                                     buf0 (Q     , buf_Q          );
endmodule
```

A primitiva de flip-flop (`udp_dff$PR`) lê `D`, `CLK` e `RESET` direto das
portas. Simples e correto. `UNIT_DELAY` é uma macro que o usuário define
(`#1` = 1 ns de atraso na saída).

### Variante comportamental (padrão) — `dfrtp`

```verilog
module sky130_fd_sc_hd__dfrtp (Q, CLK, D, RESET_B);
    output Q; input CLK; input D; input RESET_B;
    supply1 VPWR; supply0 VGND; ...
    wire buf_Q; wire RESET;
    reg  notifier;
    wire D_delayed;          // <-- ninguém aciona
    wire RESET_B_delayed;    // <-- ninguém aciona
    wire CLK_delayed;        // <-- ninguém aciona
    wire awake, cond0, cond1;
    not  not0 (RESET, RESET_B_delayed);
    sky130_fd_sc_hd__udp_dff$PR_pp$PG$N dff0 (buf_Q, D_delayed, CLK_delayed,
                                             RESET, notifier, VPWR, VGND);
    assign awake = (VPWR === 1'b1);
    assign cond0 = (awake && (RESET_B_delayed === 1'b1));
    assign cond1 = (awake && (RESET_B === 1'b1));
    buf  buf0 (Q, buf_Q);
endmodule
```

Aqui a primitiva lê `D_delayed`, `CLK_delayed` e `RESET_B_delayed`, não as
portas. `notifier`, `cond0` e `cond1` existem para os checks de tempo.

---

## 4. Quem deveria acionar os fios `*_delayed`: o bloco `specify`

No PDK completo, cada célula comportamental termina com um bloco assim
(forma típica):

```verilog
specify
    (posedge CLK => (Q +: D)) = (0:0:0, 0:0:0);           // atraso CLK->Q (o SDF anota aqui)
    $setuphold (posedge CLK, posedge D, 0:0:0, 0:0:0, notifier,
                cond1, cond1, CLK_delayed, D_delayed);    // <-- cria CLK_delayed e D_delayed
    $recrem    (posedge RESET_B, posedge CLK, 0:0:0, 0:0:0, notifier,
                cond0, cond0, RESET_B_delayed, CLK_delayed);
endspecify
```

Os dois últimos argumentos de `$setuphold`/`$recrem` são os **sinais
atrasados**: o simulador cria cópias de `CLK` e `D` deslocadas no tempo, para
modelar checagens de setup/hold com limites negativos. Sem `specify`, nada
cria essas cópias:

```
D_delayed, CLK_delayed, RESET_B_delayed = Z  (fio sem driver)
udp_dff$PR_pp$PG$N com entradas Z          -> saída X
flip-flop                                   -> X, para sempre
```

O reset não resolve: `RESET` vem de `not0(RESET, RESET_B_delayed)`, e
`RESET_B_delayed` também é Z. **Por isso o gerador de reset do NEORV32
nunca saía de X.**

### O que isso explica no projeto anterior

A simulação pós-síntese do `neorv32_sram_soc` (09/09) ficou em X com 6
hipóteses testadas. O SimVision ("Go to Cause") levou ao `udp_mux_2to1`
dentro de um `sdfrtp`, e a conclusão foi "SCE flutuando". Não era: o `sdfrtp`
também lê `SCD_delayed`/`SCE_delayed`/`D_delayed`, todos em Z. O `avoid` nos
`sdf*` foi mantido (não temos DFT), mas **não teria resolvido**: o `dfrtp`
comum tem o mesmo problema.

### Como verificar se um arquivo de células tem o problema

```bash
F=tech/verilog/sky130_fd_sc_hd.v
grep -c specify   $F    # 0     -> sem blocos specify
grep -c _delayed  $F    # > 0   -> modelos comportamentais dependem deles
```

Se `specify` = 0 e `_delayed` > 0, a variante comportamental **não funciona**
nesse arquivo.

---

## 5. Correção A (a do fluxo): simular com `FUNCTIONAL`

```bash
xrun ... -define FUNCTIONAL -define 'UNIT_DELAY=#1' \
     tech/verilog/primitives.v tech/verilog/sky130_fd_sc_hd.v \
     scripts/restore_nettype.v  <netlist> ...
```

| Detalhe | Por quê |
|---|---|
| `FUNCTIONAL` | Escolhe a variante que lê as portas direto |
| `UNIT_DELAY=#1` | Sem ele a macro fica indefinida e não compila. `#1` põe 1 ns na saída dos flip-flops: sem árvore de clock, evita corrida entre clock e dado |
| Linha 49162 corrigida | Com `FUNCTIONAL`, aparece um bug do próprio PDK: `` `endif SKY130_FD_SC_HD__LPFLOW_BLEEDER_FUNCTIONAL_V `` sem `//`. O pacote já vem corrigido (`sim/monta_vm.sh` faz a troca) |
| Sem `-v` no arquivo de células | O `-v` indexa só o topo de cada `` `ifdef `` (lição do projeto anterior) |
| `restore_nettype.v` depois das células | O arquivo termina blocos com `` `default_nettype none `` |

**Resultado neste projeto:** netlist sai do reset, as 3 matrizes batem com o
RTL, `PASSOU`.

**Limite:** a variante funcional não tem checagem de tempo nem lugar para
anotar SDF. É simulação **lógica** do netlist (reset, X, conectividade), não
de timing.

---

## 6. Correção B (alternativa): ligar os fios `*_delayed` à mão

Mantém a variante comportamental (com `awake`, `cond*`, `notifier`) e faz o
papel que o `specify` faria com atraso zero:

```verilog
wire D_delayed;
assign D_delayed = D;        // sem specify: liga direto
```

**A regra:** ligar só `<ENTRADA>_delayed`, isto é, quando `<ENTRADA>` é porta
de entrada da célula. Das 240 declarações:

| Caso | Quantas | O que fazer |
|---|---|---|
| `D_`, `CLK_`, `RESET_B_`, `SCD_`, `SCE_`, `SET_B_`, `GATE_`, `GATE_N_`, `DE_`, `CLK_N_`, `SLEEP_B_delayed` | 230 | `assign` a partir da entrada |
| `SCE_gate_delayed` (`sdlclkp`) | 2 | **Não tocar**: já é saída de um `nor` dentro da célula (ligar dá erro de driver duplo) |
| `RESET_delayed` (latches `dlrbn/dlrbp/dlrtn/dlrtp`) | 8 | Declarado e não usado; não precisa |

O script faz isso (`sim/liga_delayed.py`):

```bash
python3 sim/liga_delayed.py tech/verilog/sky130_fd_sc_hd.v sky130_fd_sc_hd_ligado.v
# 230 fios <entrada>_delayed ligados
```

e a simulação usa o arquivo ligado **sem** `FUNCTIONAL`:

```bash
xrun ... tech/verilog/primitives.v sky130_fd_sc_hd_ligado.v \
     scripts/restore_nettype.v <netlist> ...
```

**Conferido:** com o arquivo original sem `FUNCTIONAL`, aos 3 µs
`rstn_sys = x` e `uart = x`; com o arquivo ligado, `rstn_sys = 1` e
`uart = 1` (repouso). A simulação inteira com o arquivo ligado está
registrada no DIARIO.

**Limite:** igual à correção A: atraso zero e nenhum check de tempo
dispara (o `notifier` nunca muda). Ela **não** habilita simulação com SDF —
só mostra que o defeito é mesmo a falta de quem acione os fios.

---

## 7. E se um dia precisar de simulação com SDF?

Aí é preciso o modelo com os blocos `specify` de verdade (atrasos
`IOPATH` e checks `$setuphold`/`$recrem`), que o SDF anota. Isso não dá para
escrever à mão para 1.524 módulos. Caminho:

1. Procurar no PDK do notebook um modelo com `specify`:
   ```bash
   grep -rlc "specify" ~/Projects/pdks/sky130A/libs.ref/sky130_fd_sc_hd/verilog/
   ```
   Se algum arquivo tiver contagem > 0, é ele (usar **sem** `FUNCTIONAL`).
2. Se não houver, a alternativa de verdade para timing é **STA** (Tempus, ou
   o OpenSTA do próprio LibreLane) com parasitas do layout — que já é o plano
   (D23). A simulação com SDF não acrescenta muito sobre STA num projeto
   síncrono de um clock só.

---

## 8. Resumo para o slide

| | |
|---|---|
| Sintoma | Netlist inteiro em X; reset não "pega" |
| Causa | `sky130_fd_sc_hd.v` sem `specify` → fios `*_delayed` sem driver |
| Onde | Só nas células padrão; modelos da OpenRAM não usam `specify` |
| Correção usada | `-define FUNCTIONAL -define 'UNIT_DELAY=#1'` (+ 1 linha do PDK) |
| Alternativa | Ligar `<ENTRADA>_delayed = <ENTRADA>` (`sim/liga_delayed.py`) |
| O que NÃO dá | Simulação com SDF com este arquivo — timing fica para o STA |
