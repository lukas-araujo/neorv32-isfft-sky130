# DIÁRIO GDSII — NEORV32 + ISFFT: do netlist ao layout (SkyWater 130 nm)

Diário de bordo do **back-end** do SoC NEORV32 + ISFFT: ressíntese para o
layout, floorplan, posicionamento, CTS, roteamento, DRC, LVS e GDSII.

Continua o `DIARIO.md` (front-end, sessões 1–15, decisões D1–D39), que
fica **congelado**: só recebe correções. Decisões de lá são citadas como
**FE-Dn** (ex.: FE-D17). Decisões deste diário são **Ln** (L de layout).

| Diário | Trabalho | Prefixo das decisões | Situação |
|---|---|---|---|
| `DIARIO.md` | Front-end: macros, RTL, síntese, LEC, pós-síntese | D (citado aqui como FE-D) | ✅ fechado |
| `DIARIO_GDSII.md` | Back-end até o GDSII | **L** | ▶ este |
| `DIARIO_UVM.md` | UVM no IP da ISFFT | U | ⏳ outro chat |
| `DIARIO_DFT.md` | Síntese com DFT no IP da ISFFT | T | ⏳ outro chat |

---

## Como usar este diário

Mesmo modelo do `DIARIO.md`:

```
### 🐛 <título curto>
**Sintoma:** o que apareceu (mensagem, log, comportamento).
**Causa:** por que quebrou, quando eu descobrir.
**Resolvi com:** o que funcionou.
**Tempo gasto:** aproximado.
**Vira slide?** sim/não — e por quê.
```

Decisões entram na tabela da sessão **e** no índice no fim do arquivo:
✅ adotada · 🟡 proposta (aguarda confirmação) · ❌ descartada.

---

## Caminhos

| O quê | Onde |
|---|---|
| Repositório | `github.com/lukas-araujo/neorv32-isfft-sky130` (privado) |
| Projeto (notebook) | `~/Projects/asic` → passa a ser o clone do repositório |
| Pasta da VM (goku, aluno12) | `neorv32_isfft_soc/` (montada por `sim/monta_vm.sh`, FE-D36) |
| Macros (5 vistas cada) | `asic/macros/<nome>/` |
| Netlist do Genus (front-end) | `neorv32_isfft_soc/backend/synthesis/deliverables/neorv32_isfft_soc.v` |
| LibreLane | 3.0.14 via Nix, clone em `~/Projects/librelane` (L11) |
| PDK do layout | sky130 `8afc8346…` em `~/Projects/pdks/librelane` (L10) |
| PDK da OpenRAM | sky130 `e8294524` (2022.07.29) em `~/Projects/pdks` |

---

## Ponto de partida (herdado do front-end)

| Item | Valor | Fonte |
|---|---|---|
| Área total (Genus) | 1.912.963 µm² | `_qor.rpt` |
| 4 macros | 1.182.838 µm² (62%) | FE 14ª sessão |
| Lógica em células | 730.125 µm² | idem |
| Slack a 50 MHz | +2.410 ps, 0 violações | `_timing.rpt` |
| Células / sequenciais | 60.028 / 19.827 | `_qor.rpt` |
| LEC | 169/169 módulos, 19.828 pontos, PASS | FE-D38 |
| Pós-síntese (Xcelium) | somas = RTL, `PASSOU` | FE-D37 |
| EVM | 3,41 / 0,78 / 0,60 % = Kria | FE-D32 |

| Macro | Instância | Tamanho (LEF, µm) | Área (µm²) |
|---|---|---|---|
| `sram_8kbyte_1rw_32x2048_8` | IMEM | 810,845 × 553,53 | 448.827 |
| `sram_4kbyte_1rw_32x1024_8` | DMEM | 808,845 × 351,29 | 284.139 |
| `sram_1rw1r_64x256` | `out_mem` | 747,12 × 397,445 | 296.939 |
| `sram_1rw1r_64x64_wpr2` | `in_mem` | 735,8 × 207,845 | 152.932 |

---

## 2026-09-26 (1ª sessão) — Análise dos pacotes e plano do layout

Recebidos: `DIARIO.md`, `asic_completo.tar.xz` (projeto do notebook com as
4 macros completas, inclusive `.gds`) e `neorv32_isfft_soc.tar.xz` (pasta da
VM com netlist, SDC, SDF, relatórios e LEC). Nada faltando para o layout.

### 🔑 Achado 1: os 33 bits (FE-D17) bloqueiam os dois caminhos

Tanto o Yosys (caixa-preta da macro) quanto o OpenROAD (timing) leem o
`.lib`. Hoje:

| View | `din0`/`dout0` | `spare_wen0` |
|---|---|---|
| `.v` | 33 | sim |
| `.lef` / `.gds` | 33 | sim |
| `.lib` | **32** | **não** |

**Proposta (L1):** patch no `.lib` das duas macros de 1 porta, por script:
tipo `data` com 33 bits, `pin(din0[32:0])`, `pin(dout0[32:0])` e um
`pin(spare_wen0)` copiado do `web0`. As três views passam a concordar e o
`-define SRAM_LIB_VIEW` (e o `sram_lib_view_model.v` da pós-síntese) deixam
de existir.

### 🔑 Achado 2: o netlist do Genus não tem células de amarração

```
grep -oE "1'b[01]" neorv32_isfft_soc.v | wc -l    ->  6
grep -c conb neorv32_isfft_soc.v                  ->  0
```

`.web0(1'b0)` nas duas 1rw1r, `{1'b0, addr_i}` nas duas 1rw (linha
sobressalente) e dois `.D(1'b1)`. Com a interface de 33 bits entram mais
`spare_wen0` e `din0[32]`. Constante no layout precisa de célula
(`sky130_fd_sc_hd__conb_1`). Resto do netlist limpo: 0 `assign`, 200
módulos, só células comuns (nenhuma `sdf*`, `lpflow*`, `probe*`).

**Proposta (L2):** inserir tie cells no Genus na rodada para o layout.

### 🔑 Achado 3: onde ficam os pinos das macros

| Macro | Pinos de sinal | Canal necessário |
|---|---|---|
| IMEM / DMEM (1rw) | **embaixo**: `din0`, `dout0`, `wmask0`, `spare_wen0`; **esquerda**: `addr0` (8–9 bits), `csb0`, `web0`, `clk0`; **direita**: 4 bits de `dout0` | embaixo e dos dois lados |
| `in_mem` / `out_mem` (1rw1r) | **embaixo** = porta 0 (escrita): `din0`, `dout0`, `addr0`, `clk0`; **em cima** = porta 1 (leitura): `dout1`, `addr1`, `clk1`; `csb0`/`web0` à esquerda, `csb1` à direita | **em cima e embaixo** |

Alimentação (as 4 iguais): anel `vccd1`/`vssd1` em **met3** (lados
horizontais) e **met4** (lados verticais), `SHAPE ABUTMENT`. OBS de met1 a
met4. Consequências:
- **met5 livre** sobre as macros: as tiras horizontais da PDN passam por
  cima e descem até o anel em met4 nos lados verticais.
- As tiras verticais de met4 do núcleo param no halo da macro.
- Redes de alimentação do chip = `vccd1`/`vssd1` (nomes das macros); as
  células padrão (`VPWR`/`VGND`) ligam nelas por conexão global.

### 🔑 Achado 4: o DRC do chip não pode entrar no GDS das macros

Magic no GDS completo somaria ~1,2 milhão de erros das bitcells de 1 porta
da foundry (394.613 + 782.645, causa conhecida — FE 2ª sessão de 19/09).

**Proposta (L3):** DRC e LVS do chip com as macros como **caixa-preta**
(vista LEF/abstract); DRC/LVS de cada macro documentado à parte (já está
no `DIARIO.md`).

### Decisão em aberto: qual netlist vai para o layout

| | A — netlist do Genus no LibreLane | B — LibreLane sintetiza o RTL (Yosys) |
|---|---|---|
| Como | LibreLane só **elabora** o netlist (`SYNTH_ELABORATE_ONLY`, a confirmar na versão instalada) | Fluxo padrão do LibreLane |
| História | "o netlist que passou no LEC é o que virou layout" (fluxo híbrido combinado, OR-D1) | Cadence vira ramo paralelo |
| Custo | Rodada na VM: `.lib` 33 bits, sem `SRAM_LIB_VIEW`, tie cells; refazer Genus + pós-síntese + LEC (~40 min) | Simulação de portas do netlist final no Icarus (~43 min) para recuperar a prova |
| Recomendação | ✅ | |

Em paralelo com A: floorplan + PDN no notebook com o netlist atual (1 bit a
menos não muda o floorplan).

### Floorplan inicial (a testar)

Die **2,0 × 1,5 mm** (3,0 mm²). Descontando macros (1,18 mm²) e
halos/canais: ~1,5 mm² para 0,73 mm² de lógica → densidade ~47%.

```
┌──────────────────────────────────────────────────────┐
│ ┌───────────────┐                ┌────────────────┐  │  ← leitura out_mem → conversor → SLINK RX
│ │ IMEM 8 kB     │                │ out_mem 64×256 │  │
│ │ 811 × 554     │   lógica da    │ 747 × 397      │  │
│ └───── ▼ ───────┘   CPU e DMA    └───── ▼ ────────┘  │  ← escrita vinda do núcleo
│   canal comum (~60 µm)          núcleo da ISFFT      │
│ ┌───── ▲ ───────┐   (espelhado)  (Spiral, ping-pong) │
│ │ DMEM 4 kB     │                ┌───── ▲ ────────┐  │  ← leitura para o núcleo
│ │ 809 × 351     │                │ in_mem 64×64   │  │
│ └───────────────┘                └───── ▼ ────────┘  │  ← escrita vinda do conversor
│   SLINK (FIFOs 147k µm²), conversores 32↔64          │
└──────────────────────────────────────────────────────┘
```

- DMEM espelhada na vertical (MX): IMEM e DMEM dividem um canal de pinos.
- ISFFT de baixo para cima: `in_mem` → núcleo → `out_mem`, cada porta
  virada para quem a usa.
- ~~Sem padring~~: o chip leva padring (6ª sessão, L6).

### Etapas

| # | Etapa | Onde |
|---|---|---|
| 1 | `.lib` de 33 bits + rodada "para layout" (Genus, LEC, pós-síntese) | notebook + VM |
| 2 | LibreLane até floorplan + PDN | notebook |
| 3 | Posicionamento, CTS, roteamento | notebook |
| 4 | DRC, LVS, GDSII (macros como caixa-preta) | notebook |
| 5 | Timing pós-layout × +2,4 ns do Genus | notebook |

### Organização entre chats: repositório git

Três chats vão mexer na pasta da VM: este (ressíntese), UVM e DFT. Cada
chat roda num ambiente isolado; nenhum vê os arquivos do outro. Um Projeto
do Claude compartilha contexto de leitura, não uma pasta de trabalho.

**Decisão do Lukas: git** (L8). Repositório `neorv32-isfft-sky130`,
privado. Regras (detalhe no `README.md`):
- Um diário por frente; cada frente é **dona** de pastas e só lê as outras.
- `vm/backend/synthesis/` (este chat), `vm/backend/dft_isfft/` (DFT),
  `vm/verification/uvm_isfft/` (UVM).
- `sim/monta_vm.sh` agora copia **tudo** o que está em `vm/`: frente nova
  cria a subpasta e não mexe no script compartilhado. `TECH_SRC` passou a
  ter padrão (`tech/sky130/`, cópia das células do PDK no repositório).
- Resultados da VM entram em `resultados/<data>_<etapa>/`. O primeiro:
  `resultados/2026-09-26_sintese_fe/` (relatórios, netlist, SDC, dofile do
  LEC, logs e o `neorv32_asic.v` exato que foi sintetizado).
- GDS das macros guardados como `.gds.gz` (61 → 7,9 MB na de 8 kB);
  `macros/descompacta_gds.sh` recupera os `.gds`, que ficam fora do git.

Conferência: `sim/monta_vm.sh` rodado no repositório → pasta **idêntica**
à que rodou na VM (RTL, `tech/`, scripts), exceto o `run_first.tcl`: o da
VM é a cópia de trabalho (comentários enxutos, bloco do LEC ativo). O do
repositório é a versão documentada; na VM só se comenta/descomenta blocos.

### 🐛 `.gitignore` não aceita comentário no fim da linha

**Sintoma:** nenhum ainda — pego no teste antes do primeiro commit.
**Causa:** `build/   # comentario` vira o padrão `build/   # comentario`;
só é comentário a linha que **começa** com `#`.
**Resolvi com:** comentários em linhas próprias; testado num repositório
descartável (`.gds`, `build/`, `*.elf`, `*.sdf`, `layout/runs/` ignorados;
`.gds.gz` não).
**Vira slide?** Não.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L1 | `.lib` das macros 1rw com 33 bits + `spare_wen0` (patch por script) | 🟡 | Única forma de as três views concordarem; necessário nos dois caminhos |
| L2 | Tie cells (`conb_1`) inseridas no Genus | 🟡 | 6 constantes literais no netlist, 0 células de amarração |
| L3 | DRC/LVS do chip com macros como caixa-preta | 🟡 | ~1,2 milhão de erros conhecidos dentro das macros |
| L4 | Netlist do layout = Genus (caminho A) | 🟡 | Mantém a cadeia LEC → layout |
| L5 | Floorplan inicial 2,0 × 1,5 mm, macros como no desenho | 🟡 | A validar na etapa 2 |
| L6 | Sem padring; 4 pinos na borda | 🟡 | Tapeout fora de escopo |
| L7 | Diário próprio do back-end, decisões com prefixo L; `DIARIO.md` congelado | ✅ | Pedido do Lukas |
| L8 | Repositório git como fonte única; uma pasta dona por frente; `monta_vm.sh` genérico | ✅ | Decisão do Lukas; chats não compartilham arquivos |

---

## 2026-09-26 (2ª sessão) — Rodada "para o layout": `.lib` de 33 bits e tie cells

**Decisão do Lukas: caminho A** (L4 ✅): o netlist do Genus vai para o
LibreLane. Esta sessão prepara a ressíntese na VM.

### L1 — `.lib` das macros de 1 porta com 33 bits

Script `macros/lib_33bits.py` (idempotente, `--check` só confere). No
próprio `.lib` de `macros/<m>/`; o original fica no histórico do git.

| Mudança | Antes | Depois |
|---|---|---|
| `type (data)` | `bit_width 32`, `bit_from 31` | 33, 32 |
| `memory()` | `word_width 32` | 33 |
| barramentos | `pin(din0[31:0])`, `pin(dout0[31:0])` | `[32:0]` (bit 32 herda capacitância e arcos) |
| `spare_wen0` | não existia | cópia do `pin(web0)`: mesma capacitância, mesmo setup/hold contra `clk0` |

**Por que copiar do `web0`:** o `spare_wen0` é a habilitação de escrita da
coluna sobressalente, controlado pela mesma lógica de entrada que o
`web0`. O `.lib` é de modelo analítico (setup 0,103 ns em todos os pinos),
então não há número "mais certo" para inventar.

Consequências no projeto:
- `rtl/mem/sram4k_1rw.v` e `sram8k_1rw.v`: **ramo `SRAM_LIB_VIEW`
  removido**. Com o `.lib` novo ele instanciaria portas que não existem.
  Interface única de 33 bits, bit 32 e `spare_wen0` em 0.
- `sram_lib_view_model.v` **apagado**. O que ele fazia além de converter
  32↔33 (carregar o programa pela `+IMEM_HEX`) foi para o
  `imem_sim_model.v`. A DMEM passa a usar o `.v` da OpenRAM direto.
- `-define SRAM_LIB_VIEW` retirado de: script do Genus, dofile do LEC
  escrito à mão, blocos 0 e 2 do `run_first.tcl`, `sim/run_gls_yosys.sh`.
  O dofile que o Genus escreve herda os defines do `read_hdl`, então sai
  sem ele sozinho.

### L2 — Tie cells no Genus

`add_tieoffs -high conb_1 -low conb_1 -max_fanout 1 -all` depois do
`syn_opt`, dentro de um `catch`: é a primeira vez com a `conb_1` (célula
de duas saídas) no Genus. Se falhar, a síntese não morre (o
`-abort_on_error` pegaria), a mensagem aparece no log e o netlist sai com
as constantes soltas. A conferência do bloco 1 agora mostra:

```
--- constantes soltas no netlist (esperado: 0) e celulas conb_1 (esperado: > 0) ---
--- macros de 1 porta com 33 bits (esperado: 2 linhas com spare_wen0) ---
```

`conb_1` no `.lib` do sky130: `HI` = "1", `LO` = "0", área 3,75 µm², sem
`dont_use`.

### Conferência na nuvem (antes da VM)

| Bancada | Resultado |
|---|---|
| `python3 macros/lib_33bits.py --check` | ok nas 2 macros |
| `sim/monta_vm.sh` | pasta montada, 99 arquivos, 66 RTL |
| `MODO=rtl sim/run_gls_yosys.sh` (RTL de 33 bits + `imem_sim_model.v` + `tb_gate`) | ✅ **somas = RTL**, 188.194 ciclos — igual ao front-end |
| Síntese Yosys com o `.lib` novo | 4 macros, 0 células evitadas, **0 constantes soltas** (`hilomap` → `conb_1`), **`spare_wen0` ligado nas 2** |
| Simulação de portas (Yosys + Icarus, `FUNCTIONAL`) | ✅ **3 somas = RTL**, contadores 3/3/0, `RESULTADO: OK`, 188.195 ciclos (igual ao front-end); 38 min |

O Yosys lê o `.lib` só como caixa-preta (`read_liberty -lib`): prova que a
interface casa, não que o Genus aceita o arquivo. Essa prova é o bloco 1
na VM.

### Na VM, na ordem

1. Montar a pasta: `bash sim/monta_vm.sh` (notebook, depois do
   `git pull` e do `sim/convert.sh`). Substituir a pasta da VM inteira.
2. Bloco 1 (Genus). Conferir: 4 macros, 0 evitadas, **0 constantes soltas,
   `conb_1` > 0, `spare_wen0` nas 2 macros**, slack positivo.
3. Bloco 2 (pós-síntese): somas = RTL (`0xeb88508e`, `0xba7fc58e`,
   `0xb29c0211`) e `[TB] PASSOU`.
4. Bloco 3a (LEC): 0 non-equivalent. Esperado: as `conb_1` novas não criam
   ponto de comparação (são constantes nos dois lados).
5. Trazer de volta para `resultados/2026-09-2x_sintese_layout/`: `reports/`,
   `deliverables/` (sem o `.sdf`) e os logs do Genus, do Xcelium e do LEC.

Comparar com a rodada do front-end: área (+ as `conb_1`), slack,
contagem de células. Diferença grande = investigar antes do layout.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L1 | `.lib` 1rw com 33 bits + `spare_wen0` (`macros/lib_33bits.py`) | ✅ | Feito; Yosys liga os 33 bits e o `spare_wen0` |
| L2 | Tie cells `conb_1` no Genus (`add_tieoffs`, com `catch`) | 🟡 | Falta rodar no Genus |
| L4 | Netlist do layout = Genus (caminho A) | ✅ | Decisão do Lukas |
| L9 | `SRAM_LIB_VIEW` extinto; `imem_sim_model.v` substitui o adaptador | ✅ | Interface única de 33 bits em RTL, netlist, `.v`, `.lib`, `.lef` |

---

## 2026-09-27 (3ª sessão) — Máquina, PDK e instalação do LibreLane

### Notebook (Linux-Batata)

| | |
|---|---|
| Sistema | Ubuntu 24.04.5 LTS, kernel 7.0.0-34 |
| CPU | Intel Core i7-1165G7: 4 núcleos / 8 threads |
| Memória | 32 GB |
| Disco | 3 TB |

32 GB bastam para 60 mil células + 4 macros (o GDS final vai passar de
100 MB, a maior parte das macros). Com 4 núcleos, o roteamento detalhado
é a etapa mais longa: esperar dezenas de minutos por rodada.

**Nada do layout está instalado** (LibreLane, OpenROAD, Magic, Netgen,
KLayout). O `DIARIO.md` do projeto OpenRAM citava LibreLane no notebook,
mas não chegou a ser instalado.

### O PDK: dois, e cada um no seu lugar (L10)

```
$ ciel ls --pdk sky130
In /home/lukas/Projects/pdks/ciel/sky130/versions:
└── e8294524e5f67c533c5d0c3afa0bcc5b2a5fa066 (2022.07.29) (enabled)
```

| PDK | Versão | Usado por |
|---|---|---|
| `~/Projects/pdks` | open_pdks `e8294524` (**29/07/2022**) | OpenRAM (as 4 macros), `tech/sky130/` (a `.lib` que o Genus usou) |
| LibreLane 3.0.14 | sky130 `8afc8346…` (fixado em `librelane/pdk_hashes.yaml`) | Layout: células, regras de DRC, LVS, PDN |

Decisão: **o LibreLane usa o PDK dele, numa `PDK_ROOT` separada**
(`~/Projects/pdks/librelane`). Motivos:
- O LibreLane 3 espera arquivos e configurações de uma versão recente;
  forçar o PDK de 2022 é pedir erro difícil de achar.
- Pasta separada deixa claro qual PDK é de quem. (Primeiro escrevi que o
  LibreLane trocaria a versão **habilitada** e quebraria a OpenRAM.
  Conferido no código, `librelane/flows/cli.py`: ele só faz `ciel.fetch`
  da versão fixada e usa a pasta dela direto, **sem `enable`**. Não
  quebraria; a separação é por organização. A `PDK_ROOT` vem da opção
  `--pdk-root` ou da variável de ambiente `PDK_ROOT`; sem nenhuma, vai
  para `~/.ciel`.)
- As macros são autocontidas (GDS + LEF próprios); a célula padrão
  `sky130_fd_sc_hd` tem os mesmos nomes nas duas versões, então o netlist
  do Genus liga nas células do PDK novo.

Consequência a registrar no relatório: o timing do Genus usou a `.lib`
de 2022; o do layout (OpenSTA) vai usar a do PDK novo. Diferença pequena
esperada; comparar os dois números sabendo disso.

### LibreLane: versão e instalação (L11)

- Versão: **3.0.14** (tag estável mais recente; `main` de 06/09/2026).
- Instalação: **Nix** (recomendada pela documentação para Linux). Traz
  LibreLane + OpenROAD + Yosys + Magic + Netgen + KLayout nas versões que
  o LibreLane testa. Clone em `~/Projects/librelane` (fora deste
  repositório), na tag `3.0.14`.
- Terminal **sem** o venv `microelectronics` e sem o `env_openram.sh`
  (o venv pode esconder o Python do Nix; o `env_openram.sh` mexe no PATH).

### ✅ `SYNTH_ELABORATE_ONLY` existe — e não amarra constantes

Conferido no código do LibreLane 3.0.14
(`librelane/scripts/pyosys/synthesize.py`): com
`SYNTH_ELABORATE_ONLY = true` o Yosys faz só `proc`, `flatten`
(opcional), `splitnets`, `opt_clean` e escreve o netlist. **Não roda
`hilomap`.** Ou seja, as constantes que viessem soltas do Genus iriam
soltas para o layout. Confirma que as células de amarração tinham que
vir do Genus (L2).

### ✅ LibreLane instalado: smoke test passou

**Tropeço no caminho:** o Nix já existia no notebook (2.34.7, da época da
OpenRAM), mas o `/etc/nix/nix.conf` tinha só `experimental-features`,
**sem o cache da FOSSi**. Sem ele o `nix-shell` compilaria OpenROAD,
Magic e KLayout do zero (horas). Pego antes de começar a baixar:

```bash
sudo tee -a /etc/nix/nix.conf <<'EOF2'
extra-substituters = https://nix-cache.fossi-foundation.org
extra-trusted-public-keys = nix-cache.fossi-foundation.org:3+K59iFwXqKsL7BNu6Guy0v+uTlwsxYQxjspXzqLYQs=
EOF2
sudo systemctl restart nix-daemon
nix config show | grep -E "substituters|trusted-public-keys"   # conferir
```

Com o cache: 214 pacotes baixados (792 MB, 4,6 GB descompactados) e só
10 derivações pequenas construídas (ambientes Python e scripts do shell).
Como reconhecer: `copying path ... from 'https://nix-cache.fossi-foundation.org'`
é bom; muitos `building '...openroad...drv'` é o cache faltando.

| Ferramenta (do `nix-shell`) | Versão |
|---|---|
| LibreLane | 3.0.14 |
| OpenROAD | 2026-02-17 |
| Yosys | 0.62 (com plugins: ghdl, slang, eqy, sby) |
| Magic | 8.3.623 |
| Netgen | 1.5.316 |
| KLayout | 0.30.7 |
| Verilator / Icarus / GHDL | 5.044 / s20250103 / 5.1.1 |
| ciel | 2.4.0 |

`librelane --smoke-test` (PDK baixado em
`~/Projects/pdks/librelane/ciel/sky130/versions/8afc8346…`): 80 etapas
do fluxo `Classic` em ~1 min, **Antenna, LVS e DRC: Passed**.

Avisos do smoke test, todos esperados num projeto de exemplo:
- `STA-1140 library ... already exists`: o OpenSTA lê a mesma `.lib` mais
  de uma vez (por corner). Inofensivo.
- `RSZ-0020 found 2 floating nets`: do projeto de exemplo, não do fluxo.
- `DRT-0349 LEF58_ENCLOSURE with no CUTCLASS`: regra do tech LEF que o
  roteador não usa. Conhecido no sky130.
- `VSRC_LOC_FILES` não definido: queda de tensão (IR drop) sem pontos de
  alimentação reais. Só importa com padring. Para nós: sem padring (L6),
  o número de IR drop é indicativo.

**Como entrar no ambiente daqui para frente** (terminal sem venv):

```bash
nix-shell ~/Projects/librelane/shell.nix
export PDK_ROOT=$HOME/Projects/pdks/librelane
```

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L10 | Layout com o PDK fixado pelo LibreLane (`8afc8346`) em `PDK_ROOT` separada; OpenRAM segue com o de 2022 | ✅ | LibreLane 3 com o PDK que ele testa; cada PDK na sua pasta |
| L11 | LibreLane 3.0.14 via Nix, clone em `~/Projects/librelane` | ✅ | Instalado; smoke test passou (Antenna, LVS, DRC) |
| L12 | `CLAUDE.md` no repositório: regras de trabalho e de git para qualquer chat | ✅ | Pedido do Lukas: o próximo chat precisa saber como o git funciona |

---

## 2026-09-27 (4ª sessão) — Resultados da VM chegam pelo git

**Pedido do Lukas:** mandar os resultados da VM pelo repositório, não
como anexo no chat.

`sim/traz_vm.sh <pasta_da_vm> <etapa>` (roda no notebook, na raiz do
repositório):
- aceita a pasta do projeto inteira ou só `backend/synthesis/`;
- copia `reports/*.rpt`, `deliverables/*.v|.sdc|.do` e os logs (Genus,
  Xcelium RTL e pós-síntese, LEC); **não** copia `.sdf`, `xcelium.d/`,
  `work/fv*`;
- compacta o que passa de 500 kB (netlist 8 MB → ~0,9 MB);
- nomeia `resultados/<data do netlist>_<etapa>/` e recusa sobrescrever;
- imprime um resumo (slack, área, células) e os comandos de git.

Testado com a pasta da rodada do front-end: 19 arquivos, 2,0 MB, resumo
com slack +2410,4 ps e 1.912.963 µm² (iguais ao `_qor.rpt`).

**Fluxo:** VM → copia a pasta para o notebook → `traz_vm.sh` →
`git push` → o chat faz `git pull` e lê de `resultados/`. Regra no
`CLAUDE.md` e no `README.md`.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L13 | Resultados da VM entram pelo git, via `sim/traz_vm.sh` | ✅ | Pedido do Lukas; histórico no repositório, sem anexo |

---

## 2026-09-27 (5ª sessão) — ✅ Rodada para o layout na VM: tudo passou

Resultados em `resultados/2026-09-27_sintese_layout/` (commit `7fd0940`
do Lukas, primeira rodada trazida pelo `sim/traz_vm.sh`). Comparação com
`resultados/2026-09-26_sintese_fe/`.

### Síntese (Genus, bloco 1) — `_qor.rpt`, `_gates.rpt`, `genus.log`

| | Front-end (26/09) | Para o layout (27/09) | Diferença |
|---|---|---|---|
| Slack a 50 MHz | +2.410,4 ps, 0 violações | **+2.410,4 ps**, 0 violações | nenhuma |
| Caminho crítico | controle → `muldiv` (`n12685_q_reg[63]`) | o mesmo | nenhuma |
| Área total | 1.912.962,854 µm² | **1.913.000,390 µm²** | **+37,536 = 10 × 3,7536 (`conb_1`)** |
| Células | 60.028 (19.827 seq., 40.201 comb.) | 60.038 (19.827 / 40.211) | +10 combinacionais |
| Não resolvidos / vazios | 0 / 0 | 0 / 0 | |
| Macros | 4, 1 instância cada | 4, 1 instância cada, mesmas áreas | |
| Células evitadas | 0 | 0 | |
| DRC (transição, capacitância, fanout) | sem violações | sem violações | |
| Tempo | 597 s | 601 s | |

**L2 funcionou de primeira.** O `add_tieoffs` com a `conb_1` (célula de
duas saídas) foi aceito sem erro; o `genus.log` mostra, módulo a módulo,
"Connecting all 1'b0/1'b1 ... tielo_cell is ... conb_1, tiehi_cell is
... conb_1". No netlist:

```
constantes soltas (1'b0 / 1'b1):  0      (eram 6)
sky130_fd_sc_hd__conb_1:          10
```

Onde entraram as 10 (área por bloco, `_area_hier.rpt`):

| Bloco | `conb_1` | Para quê |
|---|---|---|
| DMEM (`sram4k_1rw`) | 3 | bit 11 do endereço (linha sobressalente), `din0[32]`, `spare_wen0` |
| IMEM (`sram8k_1rw`) | 3 | idem |
| ISFFT (`isfft_axi_v4`) | 2 | `web0` das duas 1rw1r (porta 0 só escreve) |
| `neorv32_cpu_control` | 1 | `D = 1` de um flip-flop |
| `neorv32_sys_reset` | 1 | `D = 1` do gerador de reset |

`-max_fanout 1`: **uma `conb_1` por pino** que recebe constante (nas
memórias, `logic_0_1_net`, `_2_net` e `_3_net` são três redes de três
células). É o que o layout quer: cada célula fica ao lado do pino que
alimenta, sem fio de constante atravessando o chip.

**L1 funcionou.** As duas macros de 1 porta saem do Genus já com a
interface do LEF:

```
sram_4kbyte_1rw_32x1024_8 u_macro(.din0 ({logic_0_2_net, wdata_i}),
     .addr0 ({logic_0_1_net, addr_i}), ... .spare_wen0 (logic_0_3_net),
     .dout0 ({dout_33[32], rdata_o}));
```

O Genus leu o `.lib` corrigido sem reclamar (nenhum erro de biblioteca no
log; áreas das macros iguais às de antes).

### Simulações (Xcelium, blocos 0 e 2) — `xrun_rtl.log`, `xrun_postsyn.log`

| | RTL (bloco 0) | Pós-síntese (bloco 2) |
|---|---|---|
| Programa carregado (`imem_sim_model.v`) | `mem[0..2] = 0f14020f3 080001217 0ffc20213` | igual |
| Somas | `0xeb88508e`, `0xba7fc58e`, `0xb29c0211` = RTL | **iguais** |
| Firmware | `RESULTADO: OK` | `RESULTADO: OK` |
| Ciclos | 188.194 | 188.195 (atraso unitário, como antes) |
| Veredito | `[TB] PASSOU` | `[TB] PASSOU` |
| Tempo | 7 s | 32 s |

Avisos: 8 `SYSFMW` (linhas da UART que não são `CHK`, conhecidos) e, na
pós-síntese, 1.000 `NODNTW` do PDK + 1 `MXWARN` (limite de avisos). Os
mesmos da rodada anterior. Primeira vez que o **bloco 0** (RTL no Xcelium)
rodou na VM: confirma o `imem_sim_model.v` também no Xcelium.

### LEC (Conformal, bloco 3a) — `*_lec_genus_run.log`

| Etapa | Resultado |
|---|---|
| `fv_map` → netlist final (plana) | **19.828 pontos equivalentes** (1 saída, 19.823 flip-flops, 4 caixas-pretas); 0 não-equivalentes, 0 abortados, 0 não comparados → **PASS** |
| RTL → `fv_map` (hierárquica) | **169/169 módulos equivalentes** |
| Tempo da etapa hierárquica | 1.043 s (antes 1.480 s) |

Mesmos 19.828 pontos da rodada anterior: as `conb_1` são constantes nos
dois lados e não viram ponto de comparação, como previsto.

### 🐛 `origin/main` não existe no clone da sessão

**Sintoma:** `git log HEAD..origin/main` → `unknown revision`;
`git rebase origin/main` → `invalid upstream`.
**Causa:** o clone da sessão é raso e de um ramo só; `git fetch origin main`
grava em `FETCH_HEAD`, não cria `refs/remotes/origin/main`. O comando que
eu tinha escrito no `CLAUDE.md` (`git rebase origin/main`) não funcionava
aqui.
**Resolvi com:** `git pull --rebase origin main` no `CLAUDE.md`.
**Vira slide?** Não.

### Ajuste no `sim/traz_vm.sh`

Veio um `xrun.log` além do `xrun_postsyn.log`. Achei que era duplicata;
**conferido com `diff`, não é**: é o log que o próprio xrun grava na
pasta da simulação, com o mesmo conteúdo **mais a linha de comando
completa** (`-define FUNCTIONAL`, `UNIT_DELAY`, todos os arquivos). Vale
guardar — é a receita exata da rodada. Como `sim_rtl/` e `sim_postsyn/`
têm um `xrun.log` cada, o script agora traz os dois renomeados:
`xrun_rtl_comando.log` e `xrun_postsyn_comando.log`. O desta rodada foi
renomeado para `xrun_postsyn_comando.log` (o do bloco 0 não veio: o
script antigo só pegava um dos dois, e o da pasta de trabalho foi
sobrescrito pela ordem de cópia).

### Estado

O netlist `resultados/2026-09-27_sintese_layout/deliverables/neorv32_isfft_soc.v.gz`
é **o netlist do layout**: 33 bits nas macros de 1 porta, constantes em
`conb_1`, equivalente ao RTL (LEC) e funcionando (pós-síntese = RTL = EVM
da Kria). Próximo: `layout/` com o LibreLane.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L2 | Tie cells `conb_1` no Genus | ✅ | 0 constantes soltas, 10 `conb_1`, LEC PASS |
| L14 | Netlist do layout = `resultados/2026-09-27_sintese_layout/deliverables/neorv32_isfft_soc.v.gz` | ✅ | Passou síntese, pós-síntese e LEC com a interface do LEF |

---

## 2026-09-27 (6ª sessão) — Padring: o que o LibreLane e o sky130 oferecem

**Decisão do Lukas: chip completo, com padring** (L6 revista).

### O que existe (conferido no código, não na documentação)

**LibreLane 3.0.14 tem um fluxo `Chip`** (`librelane/flows/chip.py`):
é o `Classic` com o posicionamento de pinos trocado por
`OpenROAD.PadRing` (os pads viram os terminais do chip) e com 5 etapas a
mais no fim: antena no KLayout, **seal ring**, **preenchimento
(filler)** e **checagem de densidade**. O anel é montado pelo
`scripts/openroad/common/pad_cfg.tcl`: soma as larguras dos pads de cada
lado, distribui o espaço que sobra e encaixa cantos e fillers.

**O sky130 do LibreLane não traz a configuração do anel.** O
`config.tcl` do PDK (open_pdks `8afc8346`, `sky130/openlane/config.tcl`)
só lista as células de I/O (`GPIO_PADS_LEF`, `GPIO_PADS_VERILOG`);
nenhuma das variáveis que o `PadRing` pede (`PAD_CELL_LIBRARY`,
`PAD_SITE_NAME`, `PAD_CORNER`, `PAD_FILLERS`, `PAD_LEFS`...). O fluxo
`Chip` foi montado para PDKs que as trazem (IHP, GF180). **Mas o
LibreLane prevê o caso:** `PAD_FAKE_SITES` existe "se o LEF não incluir
as definições de site dos pads". Ou seja: dá para declarar tudo no nosso
`config.json`. Caminho pouco trilhado no sky130 — espere tropeços.

(Tentei baixar o PDK aqui na nuvem com o `ciel`: `403`, o GitHub Pages
e as *releases* são bloqueados. O `config.tcl` veio do **clone do
open_pdks** no commit `8afc8346`, que é a mesma versão.)

### As células de I/O do sky130 (`sky130_ef_io`, wrappers da Efabless sobre o `sky130_fd_io`)

| Célula | Para quê | Tamanho |
|---|---|---|
| `sky130_ef_io__gpiov2_pad_wrapped` | pino digital (entrada/saída) | 80 × 200 µm (`top_gpiov2`) |
| `sky130_ef_io__vccd_lvc_clamped_pad` / `vssd_lvc_clamped_pad` | alimentação do núcleo 1,8 V | 75 × ~200 µm |
| `sky130_ef_io__vddio_hvc_clamped_pad` / `vssio_hvc_clamped_pad` | alimentação dos pads 3,3 V | 75 × 200 µm |
| `sky130_ef_io__vdda_hvc_clamped_pad` / `vssa_hvc_clamped_pad` | domínio analógico do anel | 75 × 200 µm |
| `sky130_ef_io__corner_pad` | canto | ~200 × 200 µm |
| `sky130_ef_io__com_bus_slice_{1,5,10,20}um` | filler: continua os barramentos do anel | 1–20 µm × 200 µm |

**O `gpiov2` não é um buffer simples: tem 39 pinos.** Além de `PAD`,
`IN` e `OUT`: modo do driver (`DM[2:0]`), `OE_N`, `INP_DIS`,
`VTRIP_SEL`, `SLOW`, `IB_MODE_SEL`, `ANALOG_*`, e pinos no **domínio de
3,3 V** (`ENABLE_H`, `HLD_H_N`, `ENABLE_INP_H`, `ENABLE_VDDA_H`...) que
não podem ser ligados a sinal de 1,8 V — no Caravel eles vêm das saídas
`TIE_HI_ESD`/`TIE_LO_ESD` do próprio pad. Cada um dos 4 pinos do chip
precisa ser **configurado** (entrada: `clk_i`, `rstn_i`, `uart0_rxd_i`;
saída: `uart0_txd_o`).

**Anel mínimo:** 4 cantos + 4 `gpiov2` + 6 de alimentação (núcleo, I/O,
analógico; VDD e VSS de cada) ≈ **14 células**. O resto do perímetro é
filler. Com 200 µm de pad de cada lado (mais o seal ring), o die cresce
de 2,0 × 1,5 mm para **~2,45 × 1,95 mm** mantendo o mesmo núcleo.

### Proposta: layout em dois níveis (L15)

| Nível | O quê | Fluxo | Sai |
|---|---|---|---|
| 1 — núcleo | `asic_top` (netlist do Genus + 4 macros) | `Classic` | GDS + LEF de um bloco, DRC/LVS limpos |
| 2 — chip | `chip_top`: padring + núcleo como macro | `Chip` | GDS final com pads, seal ring, filler, densidade |

Por quê:
- O nível 1 é **exatamente** o que já estava planejado — nada se perde.
- Tropeço nos pads (o caminho incerto) não trava o núcleo: o número de
  área, timing e DRC/LVS do núcleo sai antes.
- Rodadas do nível 2 são rápidas: só pads e poucas ligações; o núcleo já
  está roteado.
- É como o Caravel é feito: o bloco do usuário fechado primeiro, o chip
  com o padframe depois.

O `chip_top.v` (pads + instância do núcleo + ligações de configuração
dos `gpiov2`) é **Verilog estrutural escrito à mão** — o Genus não entra
aqui. Verificação: simulação com os modelos Verilog dos pads + netlist do
núcleo, mesmo `tb_gate` (a UART tem que passar pelo pad).

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L6 | ~~Sem padring~~ → **chip completo, com padring** | ✅ | Decisão do Lukas |
| L15 | Dois níveis: núcleo (`Classic`) → chip com padring (`Chip`) | ✅ | Núcleo sai primeiro; padring (caminho incerto no sky130) não trava o resto |
| L16 | Padring com `sky130_ef_io` declarado no nosso config (`PAD_*`, `PAD_FAKE_SITES`) | 🟡 | O PDK do LibreLane não traz a configuração para o sky130 |

---

## 2026-09-27 (7ª sessão) — Roteiro até o GDSII final

**L15 confirmada pelo Lukas** (dois níveis). Antes de começar, o roteiro
com ferramenta, critério de "passou" e a imagem que cada etapa rende.
Versão de slide: `doc/tabela_backend.png` (`doc/gera_tabela_backend.py`;
para atualizar a situação, mude a última coluna e rode de novo). A tabela
geral (`doc/tabela_fluxo.png`) foi atualizada: 6–8 feitas, back-end em 3
linhas (núcleo, DRC/LVS do núcleo, chip).

| # | Etapa | Ferramenta | Passou quando | Imagem |
|---|---|---|---|---|
| 0 | Netlist para o layout | Genus · Conformal · Xcelium | ✅ 5ª sessão | tabela antes × depois |
| **Nível 1** | **núcleo `asic_top`, fluxo `Classic`** | | | |
| 1 | Leitura do netlist (`SYNTH_ELABORATE_ONLY`) | Yosys (no LibreLane) | 4 macros, 0 módulos não resolvidos, 0 constantes soltas | — |
| 2 | Floorplan: die, macros (posição + orientação + halo), pinos | OpenROAD | macros sem sobreposição, pinos das macros virados para a lógica | planta com as 4 macros |
| 3 | PDN (met4/met5 + ligação nos anéis das macros) | OpenROAD `pdngen` | nenhuma célula ou macro sem alimentação | malha de alimentação |
| 4 | Posicionamento global + detalhado, correção de fanout/transição | OpenROAD (RePlAce, OpenDP, `repair_design`) | 0 células fora de linha; densidade < ~60% | mapa de densidade |
| 5 | Árvore de clock (~19.800 flip-flops) | OpenROAD (TritonCTS) | skew baixo; slack ainda positivo | árvore de clock |
| 6 | Roteamento global e detalhado | OpenROAD (FastRoute, TritonRoute) | 0 violações de roteamento (DRV) | congestionamento + fios |
| 7 | Extração de parasitas + STA | OpenRCX · OpenSTA | slack ≥ 0 a 50 MHz (Genus: +2,4 ns) | slack Genus × layout |
| 8 | DRC, LVS, antena (macros como caixa-preta, L3) | Magic · KLayout · Netgen | DRC 0 e LVS limpo na lógica | tabela de checagens |
| 9 | Netlist do layout ≡ netlist do Genus; simulação do netlist final | Conformal · Xcelium (VM) | LEC PASS; somas = RTL | PASS |
| **Nível 2** | **chip `chip_top`, fluxo `Chip`** | | | |
| 10 | `chip_top.v`: pads `sky130_ef_io` + configuração + núcleo | Verilog · Icarus | UART sai pelo pad; `tb_gate` PASSOU | mapa dos pads |
| 11 | Padring, núcleo como macro, seal ring, preenchimento | LibreLane `Chip` (OpenROAD, KLayout) | anel fechado; núcleo alimentado pelos pads | chip inteiro |
| 12 | DRC, LVS, densidade → GDSII | Magic · KLayout · Netgen | DRC/LVS limpos fora das células da foundry; densidade ok | imagem final do GDS |

Se der tempo (FE-D23): STA com SPEF no Tempus, potência no Joules com
atividade da simulação, mapa de queda de tensão (IR drop).

**Imagens:** o LibreLane grava uma rodada por etapa em
`layout/runs/<RUN>/NN-<etapa>/`, com o `.odb` e o `.def` daquele momento.
Qualquer etapa abre no OpenROAD com GUI (`openroad -gui`) ou no KLayout,
e o fluxo já renderiza o GDS final em PNG (`KLayout.Render`). Plano: um
script em `layout/` que gera as imagens das etapas 2–6 automaticamente
(OpenROAD `save_image` em modo sem tela), para os slides saírem iguais a
cada rodada.

---

## 2026-09-27 (8ª sessão) — `layout/nucleo/`: uma etapa por script, com GUI e imagem

**Pedido do Lukas:** rodar uma parte de cada vez, cada parte num arquivo
próprio, com a GUI abrindo para ver o que aconteceu e a imagem salva em
`resultados/`.

### Como o LibreLane roda por partes (conferido no código 3.0.14)

- `--from <etapa>` / `--to <etapa>` limitam o trecho
  (`librelane/flows/sequential.py`).
- Com `--run-tag` de uma rodada que já existe, ele **continua** nela: as
  pastas novas seguem a numeração (`NN-<etapa>`) e o estado inicial é o
  `state_out.json` mais recente (`flows/flow.py`).
- **Cuidado:** "mais recente" é por data de modificação. Se a etapa 2 for
  refeita depois da 3, ela pegaria o estado do fim da 3. Por isso os
  scripts passam `--with-initial-state` com o `state_out.json` da **etapa
  anterior** (a pasta de maior número daquela etapa). Refazer uma etapa
  nunca parte de um estado errado.
- Pasta de cada etapa: `<NN>-<id em minúsculas, "." → "-">`, ex.
  `3-openroad-floorplan` (`slugify` em `common/misc.py`).

### Etapas 1–3 do fluxo `Classic`

| Script | Trecho (`--from` → `--to`) | Imagens |
|---|---|---|
| `01_leitura.sh` | início → `OpenROAD.STAPrePNR` (rodada nova) | — (texto + métricas) |
| `02_floorplan.sh` | `OpenROAD.Floorplan` → `OpenROAD.TapEndcapInsertion` | planta inteira; zoom no halo da IMEM |
| `03_pdn.sh` | `Odb.AddPDNObstructions` → `Odb.RemovePDNObstructions` | malha met4/met5; zoom no anel da IMEM; canto do anel do núcleo |

GUI: `openroad -gui tcl/imagem.tcl` no `.odb` do fim da etapa. O Tcl
liga/desliga camadas (`gui::set_display_controls`), salva com `save_image
-width 2400 [-area ...]` e deixa a janela aberta. `SEM_GUI=1` usa
`QT_QPA_PLATFORM=offscreen` e fecha sozinho. Comandos conferidos no
`src/gui/README.md` do OpenROAD.

### O `config.json` do núcleo (L17)

| Item | Valor | Por quê |
|---|---|---|
| Entrada | netlist do Genus (L14), `SYNTH_ELABORATE_ONLY`, `RUN_LINTER: false` | Não ressintetizar; lint do Verilator não faz sentido em netlist de portas |
| Clock | `clk_i`, 20 ns; I/O 30 % (6 ns) | Igual ao SDC do Genus |
| SDC | `nucleo.sdc` = `base.sdc` do LibreLane + false path em `rstn_i` | Mesma intenção do Genus; clock propagado depois do CTS |
| Macros no STA | `.lib` (`STA_MACRO_PRIORITIZE_NL: false`) | Não há netlist de portas das macros (o `.v` da OpenRAM é comportamental) |
| GDS das macros | `.gds.gz` direto do `macros/` | O `Classic` aceita GDS compactado (documentação do LibreLane) |
| Die / núcleo | 2000 × 1500 µm / margem de 40 µm | L5; espaço para o anel do núcleo e os pinos |
| Alimentação | `vccd1`/`vssd1` (nomes das macros), `PDN_CORE_RING: true`, `PDN_MACRO_CONNECTIONS` para as 4 | O anel do núcleo é onde o nível 2 (padring) vai ligar |
| Halo das macros | 15 µm | Tira as linhas de célula em volta das macros |
| DRC | `MAGIC_DRC_USE_GDS: false` | L3: DRC com as macros como caixa-preta (o padrão é `true`) |

Posição das macros (canto inferior esquerdo, µm) e orientação:

| Macro | Instância (depois de achatar) | Posição | Orientação | Por quê |
|---|---|---|---|---|
| IMEM 8 kB | `u_cpu.neorv32_top_inst.memory_system_neorv32_imem_enabled_neorv32_imem_inst.u_sram.u_macro` | (60, 886) | `FN` (espelhada em x) | pinos da esquerda vão para a direita, virados para a lógica |
| DMEM 4 kB | `...dmem_enabled_neorv32_dmem_inst.u_sram.u_macro` | (60, 464) | `S` (girada 180°) | pinos de baixo sobem: IMEM e DMEM dividem o canal de 70 µm |
| `out_mem` | `u_isfft.u_out_mem` | (1192, 1002) | `N` | 60 µm livres em cima para a porta de leitura |
| `in_mem` | `u_isfft.u_in_mem` | (1204, 100) | `N` | 60 µm livres embaixo para a porta de escrita |

**Nomes conferidos antes de rodar:** reproduzi aqui o passo de
"só elaborar" do LibreLane (`proc; flatten -noscopeinfo; setattr -set
keep 1; splitnets; opt_clean -purge`, mesmos comandos de
`scripts/pyosys/synthesize.py`) com o Yosys sobre o netlist do Genus:
**0 problemas** no `check`, lógica **730.162,784 µm²** (= 1.913.000,390 −
1.182.837,6 das macros) e os 4 nomes acima.

**Ainda não conferido (só rodando):** se a posição do `MACROS` é o canto
do retângulo **depois** da orientação ou a origem antes dela. A imagem da
etapa 2 responde.

### Testado aqui com LibreLane e OpenROAD "de mentira"

Scripts que só registram os argumentos e criam as pastas de etapa:
retomada com `--with-initial-state` certo nas etapas 2 e 3, refazer a 2
depois da 3 pega o estado da etapa 1, métricas e imagens na pasta de
resultados certa.

### 🐛 `set -e` + `[ -f x ] && comando` no fim de um bloco

**Sintoma:** no teste, o `01_leitura.sh` parava logo depois de imprimir o
resumo, sem salvar as métricas.
**Causa:** `[ -f relatorio ] && grep ...` como último comando do bloco
`{ ... } | tee`: com o arquivo ausente o teste dá falso, o bloco retorna
1, o `pipefail` repassa e o `set -e` encerra o script.
**Resolvi com:** `if [ -f ... ]; then ...; fi`.
**Vira slide?** Não.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L17 | `config.json` do núcleo como na tabela acima | 🟡 | A validar pelas imagens das etapas 2 e 3 |
| L18 | Uma etapa por script, retomando com `--with-initial-state`; imagens em `resultados/<rodada>_layout_nucleo/` | ✅ | Pedido do Lukas |

---

## 2026-09-27 (9ª sessão) — 🐛 Etapa 1 parou: 25.960 `assign` no netlist

Primeira rodada de verdade no notebook (`2026-09-27_1630`). Logs em
`resultados/2026-09-27_1630_layout_nucleo/logs_1644.tar.gz` (primeira
vez com o `junta_logs.sh`).

### 🐛 `Checker.NetlistAssignStatements`: assign statement found in netlist

**Sintoma:** o fluxo parou na etapa 5 (`05-checker-netlistassignstatements`).
`error.log` com **25.960** linhas `asic_top.nl.v:NNNNNN: assign statement
found in netlist`. Exemplo do que o Yosys escreveu:
```
assign \u_isfft.inst_isfft_matriz.inst_ifft_1d.stage0.X1[4] = \u_isfft.core_x[20] ;
```
**Causa:** o netlist do Genus é **hierárquico** (200 módulos, 0 `assign`).
O LibreLane, no modo `SYNTH_ELABORATE_ONLY`, achata a hierarquia e marca
**todo fio com `keep`** (`setattr -set keep 1`, em
`scripts/pyosys/synthesize.py`). Ao achatar, cada porta de submódulo liga
dois nomes do mesmo fio (o de fora e o de dentro); com `keep` o
`opt_clean` não pode fundi-los, e o Yosys escreve a ligação como
`assign`. O OpenROAD não lida bem com `assign` no netlist, por isso o
LibreLane barra.
**Erro meu:** na 8ª sessão reproduzi exatamente esse passo aqui e o
`flat.v` já tinha 25.960 `assign` — conferi o "0 problems" do `check` e
não os `assign`. A checagem do LibreLane que vem logo depois teria me
mostrado.
**Resolvi com (L19):** achatar **antes** do LibreLane, sem `keep`:
```
flatten -noscopeinfo  ->  splitnets  ->  opt_clean -purge
```
- só `flatten` + `opt_clean -purge`: 25.960 → **39** `assign` (os que
  sobram ligam **bits** de vetores diferentes; o `opt_clean` só funde fio
  inteiro);
- com `splitnets` antes (1 bit por fio): **0 `assign`**, área igual
  (730.162,784 µm²), mesmos nomes das 4 macros;
- o passo do LibreLane sobre esse netlist (com `keep`) continua com **0
  `assign`** e 0 avisos de fio sem driver (os `UNCONNECTED_HIER_Z...
  no driver` do log da rodada somem).
**Tempo gasto:** ~40 min.
**Vira slide?** Sim: "netlist hierárquico × plano: o que o P&R espera
receber" — e a lição de conferir o que o **próximo** passo checa.

### Prova de que o achatamento não mudou o circuito

A prova formal pelo `equiv_*` do Yosys não fecha com células como
caixa-preta (127 pontos não provados, do outro lado dos flip-flops). Para
**esta** transformação (só funde nomes de fio), a prova certa é de
**ligação**: as instâncias são as mesmas nos dois lados (mesmos nomes),
então basta mostrar que cada pino está na mesma rede.

`layout/nucleo/compara_ligacoes.py`: os dois netlists achatados e
separados bit a bit; do lado do Genus os `assign` restantes dizem quais
nomes são o mesmo fio (union-find); passa se existe uma correspondência
**1:1** entre as redes que explica todos os pinos.

```
antes: 2562 assigns, 247493 pinos | depois: 0 assigns, 247493 pinos
assigns com concatenacao: 1267
pinos so num dos lados: 0
redes comparadas: 62153 | erros: 0
RESULTADO: IGUAIS (mesma ligacao em todos os pinos)
```

(Primeira versão do comparador acusou 16.082 erros falsos: tratava
`assign {a,b,c} = {x,y,z}` como uma ligação só. Com as concatenações
separadas bit a bit, 0.)

A prova **lógica** completa continua sendo a da etapa 9: Conformal LEC
entre o netlist do Genus e o netlist final do layout — ela cobre este
passo também.

### O que mudou no `01_leitura.sh`

1. Descompacta o netlist do Genus em `entrada/asic_top_genus.v`.
2. Achata com o Yosys do `nix-shell` → `entrada/asic_top.v` (o que o
   `config.json` lê).
3. Roda o `compara_ligacoes.py` e **para** se não der `IGUAIS`.
4. Segue para o LibreLane como antes. O resultado da comparação vai para
   o `01_leitura.txt`.

Testado aqui (Yosys de verdade, LibreLane simulado): ~50 s a mais.

Alternativa considerada: o Genus escrever o netlist já plano (`ungroup
-all -flatten` antes do `write_hdl`). Também resolve, mas pede outra
rodada na VM (síntese + LEC), muda os nomes das instâncias (e o
`config.json`) e perde a área por bloco no relatório. Fica como opção se
o achatamento no notebook causar outro problema.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L19 | Achatar o netlist do Genus com o Yosys (sem `keep`) antes do LibreLane; conferir ligação pino a pino | ✅ | 0 `assign`; mesma ligação em 247.493 pinos; sem nova rodada na VM |

---

## 2026-09-27 (10ª sessão) — ✅ Etapa 1 passou; o que os números dizem

Rodada `2026-09-27_1932` (commit `aaa5dd4` do Lukas):
`resultados/2026-09-27_1932_layout_nucleo/01_leitura.txt` e
`01_leitura_metricas.json` (76 métricas).

| Item | Resultado | Fonte |
|---|---|---|
| Achatamento (L19) | 2.562 → 0 `assign`; 247.493 pinos, 62.153 redes, 0 erros | `01_leitura.txt` |
| Checagens da síntese | `Found and reported 0 problems`; `synthesis__check_error__count` 0 | idem + métricas |
| Células não mapeadas | `design__instance_unmapped__count` 0 | métricas |
| Instâncias | `design__instance__count` 60.038 (= Genus) | métricas |

Três números **pareciam** errados. Investigados:

### 1. Área: 35.614 µm² em vez de ~730.163 — só contagem

O Yosys do LibreLane calcula a área com a biblioteca **já filtrada para
síntese**. O PDK tem duas listas (open_pdks `8afc8346`,
`sky130/openlane/sky130_fd_sc_hd/`):

| Lista | Variável no LibreLane | Células | Efeito |
|---|---|---|---|
| `no_synth.cells` | `SYNTH_EXCLUDED_CELL_FILE` | 199 (141 de força `_1`, buffers de clock, decaps...) | o **Yosys** não escolhe na síntese. **Válidas no layout** |
| `drc_exclude.cells` | `PNR_EXCLUDED_CELL_FILE` | 53 | proibidas na síntese **e no layout** |

O Genus usou muito `_1` (17.601 `dfxtp_1`, 17.676 `a22o_1`...): 57.093
instâncias em células da `no_synth`. Conferido: a área das células **fora**
das duas listas soma exatamente **35.614,2 µm²** — o número do LibreLane.
**Não é problema**; para relatório, a área certa segue sendo a nossa
(730.162,784 µm²).

### 2. 🐛 Células proibidas no layout: 227 instâncias

**Sintoma:** das 53 células da `drc_exclude.cells`, o netlist usa 5:

| Célula | Instâncias |
|---|---|
| `sky130_fd_sc_hd__and2_0` | 169 |
| `sky130_fd_sc_hd__or2_0` | 35 |
| `sky130_fd_sc_hd__o21ai_0` | 12 |
| `sky130_fd_sc_hd__a2111oi_0` | 8 |
| `sky130_fd_sc_hd__a21boi_0` | 3 |

**Causa:** o Genus só evitava as células que **nós** listamos no
`tech.tcl` (scan, `lpflow`, `probe`, spare). As regras do layout do PDK
não chegavam na síntese. O arquivo não diz o motivo de cada célula; o nome
da lista indica problema de DRC no desenho. As 5 têm os mesmos pinos e a
mesma função das versões `_1`.
**Não trava as etapas 2 e 3** (floorplan e PDN não mexem nas células).
Trava a partir do posicionamento (etapa 4).
**Resolvi com (L20, 🟡):**
- `tech/sky130/drc_exclude.cells`: cópia da lista do PDK do LibreLane;
- `tech.tcl`: lê a lista e marca `avoid` em todas (o `monta_vm.sh` leva
  o arquivo para `tech/` da VM);
- `01_leitura.sh`: conta as células proibidas no netlist e mostra
  (esperado 0). Conferido no netlist atual: acusa as 227.
- **Falta:** rodar de novo na VM (blocos 1, 2, 3a) → novo netlist →
  refazer a etapa 1 do layout.
**Vira slide?** Sim: "a síntese precisa conhecer as regras do layout" —
e a diferença entre as duas listas do PDK.

### 3. Timing sem fios: −47 ns de slack (TT) — não conclusivo

`timing__setup__ws` −47,35 ns (TT), −86,12 ns (SS), −28,81 ns (FF);
6.800 caminhos violando; 61.483 violações de transição e 1.710 de fanout.
Nesta etapa o netlist ainda está como o Genus entregou: no Genus o clock e
o reset eram **redes ideais** (sem buffer, `set_ideal_net` no SDC) e o
Genus não tinha o limite de fanout 10 nem a transição máxima do
LibreLane. Aqui não há árvore de clock nem buffers nas redes de fanout
alto, então as transições (e os atrasos) explodem. Quem conserta é o
`RepairDesignPostGPL` (etapa 4) e o CTS (etapa 5). **O número que vale é
o depois do CTS.** A confirmar com o relatório de STA desta rodada
(`junta_logs.sh`), para ver o pior caminho.

A potência (`power__total` 75.787.760 W) é o `.lib` das macros com
`internal_power` fora de escala (FE 14ª sessão). Ignorar.

### Para o slide

`doc/tabela_etapa1.png` (`doc/gera_tabela_etapa1.py`): entrada, achatamento,
checagens, células proibidas (Corrigir), timing (Informativo).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L20 | Genus evita as células da `drc_exclude.cells` do PDK do LibreLane; `01_leitura.sh` confere | 🟡 | 227 instâncias proibidas no layout; falta rodar na VM |

---

## 2026-09-29 (11ª sessão) — Forma de registrar e a GUI do Conformal

**Pedido do Lukas:** não gerar mais imagens de tabela; os resultados de
cada etapa ficam como **tabelas no diário**. As imagens do layout que os
scripts salvam da GUI do OpenROAD continuam. Regra no `CLAUDE.md`. Os
geradores já feitos (`doc/gera_tabela_*.py`) ficam no repositório, mas não
serão mais atualizados.

**Pergunta: a GUI do Conformal LEC mostra algo relevante?**

| Situação | GUI ajuda? | Por quê |
|---|---|---|
| LEC deu PASS (nosso caso até agora) | Não | O relatório já diz tudo: pontos comparados, equivalentes, não-equivalentes (0), abortados (0), não mapeados, caixas-pretas |
| Pontos **não-equivalentes** | Sim | *Diagnosis*: vetor de teste que mostra a diferença e o cone de lógica dos dois lados em esquemático, lado a lado |
| Pontos **não mapeados** (ex.: flip-flop podado ou renomeado) | Sim | *Mapping Manager*: lista o que não casou e sugere correspondência por nome |
| Abortados | Às vezes | Mostra o cone grande demais; em geral resolve-se no dofile (`analyze_datapath`, particionar) |

Para relatório e slide basta o texto do relatório (a tabela da 5ª sessão:
19.828 pontos, 169/169 módulos, PASS). Abrir: `lec -xl` sem `-nogui`, ou
no prompt do Conformal digitar `gui`. Vale abrir **se** o LEC da etapa 9
(netlist do Genus × netlist do layout) falhar.

---

## 2026-09-30 (12ª sessão) — ✅ Síntese com L20 na VM: 0 células proibidas

Resultados em `resultados/2026-09-29_sintese_layout/` (commit `7049416`
do Lukas). Comparação com a rodada de 27/09 (`2026-09-27_sintese_layout`).

### Síntese (Genus, bloco 1)

| | 27/09 | 29/09 (com L20) | Fonte |
|---|---|---|---|
| `avoid` da `drc_exclude.cells` | — | 53 células marcadas | `genus.log`, linha 327 |
| Slack de setup a 50 MHz | +2.410,4 ps | **+2.410,4 ps** (mesmo caminho: controle → `muldiv`) | `_qor.rpt`, `_timing.rpt` |
| Área total | 1.913.000,390 µm² | **1.912.951,593 µm²** (−48,797) | `_qor.rpt` |
| Instâncias (seq. / comb.) | 60.038 (19.827 / 40.211) | **60.026** (19.827 / 40.199) | `_qor.rpt` |
| Macros | 4, mesmas áreas | 4, mesmas áreas | `_gates.rpt` |
| Módulos não resolvidos | 0 | 0 | `_unresolved.rpt` |
| DRC (transição, capacitância, fanout) | sem violações | sem violações | `_drc.rpt` |
| `add_tieoffs` | ok | ok (nenhum `!!! FALHOU`) | `genus.log` |

### Netlist (`deliverables/neorv32_isfft_soc.v.gz`)

| Conferência | Esperado | Resultado |
|---|---|---|
| Células da `drc_exclude.cells` | 0 | **0** (eram 227) |
| Constantes soltas (`1'b0`/`1'b1`) | 0 | 0 |
| `conb_1` | 10 | 10 |
| `spare_wen0` ligado | 2 | 2 |
| `assign` | 0 | 0 |

As `_0` sumiram e o Genus usou as versões `_1` e outras combinações:
`and2_1` 407, `or2_1` 125, `o21ai_1` 471, `a21boi_1` 63, `a2111oi_1` 2.
Área **menor** (−48,8 µm²) e 12 instâncias a menos: com as `_0` proibidas
o mapeamento escolheu outras células, e o total saiu ligeiramente melhor.

### Simulações (Xcelium) e LEC (Conformal)

| Bancada | Resultado | Fonte |
|---|---|---|
| RTL (bloco 0) | somas = RTL (`0xeb88508e`, `0xba7fc58e`, `0xb29c0211`), `RESULTADO: OK`, 188.194 ciclos, `PASSOU` | `xrun_rtl.log` |
| Pós-síntese (bloco 2) | mesmas somas, `RESULTADO: OK`, 188.195 ciclos, `PASSOU` | `xrun_postsyn.log` |
| LEC plano (`fv_map` → netlist) | 19.828 pontos equivalentes (1 saída, 19.823 flip-flops, 4 caixas-pretas); 0 não-equivalentes, 0 abortados, 0 não comparados; **PASS** | `*_lec_genus_run.log` |
| LEC hierárquico (RTL → `fv_map`) | **169/169 módulos equivalentes**; 1.039 s | idem |

### Consequência para o layout

**O netlist do layout passa a ser o de 29/09** (L14 atualizada). O
`01_leitura.sh` já aponta para ele. A rodada `2026-09-27_1932` (netlist de
27/09) fica só como registro: é preciso **refazer a etapa 1** (rodada
nova) antes das etapas 2 e 3.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L20 | Genus evita `drc_exclude.cells` | ✅ | 0 células proibidas; slack igual; LEC e pós-síntese passaram |
| L14 | Netlist do layout = `resultados/2026-09-29_sintese_layout/deliverables/neorv32_isfft_soc.v.gz` | ✅ (atualizada) | Substitui o de 27/09 |

---

## 2026-09-30 (13ª sessão) — Etapa 1 com o netlist novo; 🐛 etapa 2 parou no LEF das macros

Rodada `2026-09-30_0934`. Logs em
`resultados/2026-09-30_0934_layout_nucleo/logs_0940.tar.gz`.

### Etapa 1 (netlist de 29/09) — passou

| Conferência | Resultado | Fonte |
|---|---|---|
| Achatamento (L19) | 2.562 → 0 `assign`; 247.457 pinos, 62.141 redes, 0 erros; IGUAIS | `01_leitura.txt` |
| Células proibidas no layout (L20) | **0** | idem |
| Checagens da síntese | 0 problemas | idem |
| Área contada pelo Yosys do LibreLane | 35.467,77 µm² (só as células fora da `no_synth`; ver 10ª sessão) | idem |

### 🐛 Etapa 2: `[ERROR ODB-0292] LEF data ... is discarded due to errors`

**Sintoma:** `09-openroad-floorplan` parou ao ler o LEF da primeira macro:
```
[WARNING ODB-0205] The LEF UNITS DATABASE MICRON convert factor (2000) is greater
                   than the database units per micron (1000) of the current technology.
[INFO ODB-0227] LEF file: .../sram_8kbyte_1rw_32x2048_8.lef, created 1 library cells
[ERROR ODB-0292] LEF data from .../sram_8kbyte_1rw_32x2048_8.lef is discarded due to errors
Error: floorplan.tcl, 18 ODB-0292
```
**Causa:** a OpenRAM escreve os LEF com `UNITS DATABASE MICRONS 2000`
(resolução de 0,0005 µm). O tech LEF do sky130 usa **1000** (0,001 µm). O
OpenROAD guarda tudo na resolução da tecnologia e **recusa** LEF de macro
com resolução mais fina. As 4 macros tinham 2000; a de 8 kB só foi a
primeira a ser lida.
**Resolvi com (L21):** `macros/lef_unidades.py` — confere que toda
coordenada tem no máximo 3 casas e cai na grade de fabricação do sky130
(0,005 µm), e troca 2000 por 1000. As coordenadas estão em µm no arquivo:
**nenhum número muda**, só a resolução declarada.

| Macro | Coordenadas conferidas | Fora da grade |
|---|---|---|
| `sram_8kbyte_1rw_32x2048_8` | 863 | 0 |
| `sram_4kbyte_1rw_32x1024_8` | 859 | 0 |
| `sram_1rw1r_64x256` | 1.815 | 0 |
| `sram_1rw1r_64x64_wpr2` | 1.783 | 0 |

**A observar:** o GDS das macros também vem da OpenRAM; se o `Magic.StreamOut`
ou o `KLayout.StreamOut` reclamarem de unidade na etapa 8, a causa é a
mesma.
**Vira slide?** Sim, junto com os 33 bits (L1): "a macro gerada não
casa com a tecnologia em três lugares — `.lib` 32 × 33 bits, LEF com
resolução 2000, células de SRAM que o DRC de lógica não entende".

**Para continuar:** `git pull` e rodar só o `02_floorplan.sh` (a etapa 1
desta rodada vale; o 02 recomeça do estado do fim dela).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L21 | LEF das 4 macros com `DATABASE MICRONS 1000` (`macros/lef_unidades.py`) | ✅ | OpenROAD recusa LEF mais fino que a tecnologia; coordenadas todas na grade de 0,005 µm |

---

## 2026-09-30 (14ª sessão) — ✅ Etapas 2 (floorplan) e 3 (PDN) passaram

Rodada `2026-09-30_0934`, depois da L21. Fontes: `02_floorplan_metricas.json`,
`03_pdn_metricas.json` e `logs_0954.tar.gz` (passos `10-openroad-floorplan`,
`14-odb-manualmacroplacement`, `15-openroad-cutrows`,
`16-openroad-tapendcapinsertion`, `18-openroad-generatepdn`), todos em
`resultados/2026-09-30_0934_layout_nucleo/`. Tamanho das macros: `SIZE` dos
LEF em `macros/`.

### Etapa 2 — floorplan

| Item | Valor | Fonte |
|---|---|---|
| Die | 0,0 – 2000 × 1500 µm (3,00 mm²) | `IFP-0100` |
| Núcleo | (40,020; 40,800) – (1959,600; 1457,920) µm = 2.720.275 µm² | `IFP-0101/0102` |
| Ajuste do canto do núcleo | (40; 40) → (40,020; 40,800): múltiplo do sítio (0,46 µm) e da altura da linha (2,72 µm) | `IFP-0028` (aviso esperado) |
| Linhas de células | 521 linhas × 4.173 sítios `unithd` → cortadas pelas 4 macros + halo em **1.124 linhas / 1.108.096 sítios** (51 % dos sítios sobram) | `IFP-0001`, `ODB-0303` |
| Tap cells / endcaps | 20.139 / 1.042 | `TAP-0005/0004` |
| Tie cells novas | 0 (as 10 `conb_1` vêm do Genus, L2) | `IFP-0030` |
| Área das instâncias | 1.912.951,64 µm² (60.026 instâncias) — igual ao Genus (1.912.951,593) | `IFP-0103/0105` |
| Utilização efetiva (tudo / só células padrão) | 0,703 / **0,491** | `IFP-0104`; métrica `design__instance__utilization__stdcell` |
| Depois das taps | 82.413 instâncias, 1.946.587,65 µm² (macros 1.182.837,65) | tabela "Cell type report" do log |

**Macros** (x0,y0 = canto do config; extensão = x0 + largura do LEF):

| Macro | Instância | Orient. | x (µm) | y (µm) | Pinos de sinal no LEF (N) | Para onde ficam virados |
|---|---|---|---|---|---|---|
| IMEM `sram_8kbyte_1rw_32x2048_8` 810,845 × 553,53 | `…imem…u_macro` | FN | 60 – 870,8 | 886 – 1439,5 | 70 embaixo, 12 esq., 4 dir. | 70 para **baixo** (canal IMEM/DMEM); FN espelha em x: os 12 vão para a **direita** (lógica) ✅ |
| DMEM `sram_4kbyte_1rw_32x1024_8` 808,845 × 351,29 | `…dmem…u_macro` | S | 60 – 868,8 | 464 – 815,3 | 70 embaixo, 11 esq., 4 dir. | S gira 180°: 70 para **cima** (canal), 11 para a **direita** ✅ |
| out_mem `sram_1rw1r_64x256` 747,12 × 397,445 | `u_isfft.u_out_mem` | N | 1192 – 1939,1 | 1002 – 1399,4 | `din0`/`dout0` embaixo, `dout1` em cima | `din0` (usado) para o centro ✅; `dout1` (usado) para a borda de cima ⚠️ |
| in_mem `sram_1rw1r_64x64_wpr2` 735,8 × 207,845 | `u_isfft.u_in_mem` | N | 1204 – 1939,8 | 100 – 307,8 | idem | `dout1` (usado) para o centro ✅; `din0` (usado) para a borda de baixo ⚠️ |

| Espaço entre macros e bordas (descontado o halo de 15 µm) | Largura | Uso |
|---|---|---|
| Canal IMEM ↔ DMEM | 815,3 → 886 = 70,7 µm; **40,7 µm** de linhas | os 140 pinos das duas macros da CPU |
| Acima da out_mem | 1457,9 − 1399,4 − 15 = **43,5 µm** | 64 fios do `dout1` dão a volta por aqui |
| Abaixo da in_mem | 100 − 15 − 40,8 = **44,2 µm** | 64 fios do `din0` dão a volta por aqui |
| Direita das memórias da ISFFT | **4,8 µm** (in_mem) / **5,5 µm** (out_mem) | tira fina, só um pedaço de linha — ver PDN-0110 abaixo |
| Esquerda da IMEM/DMEM | 4,98 µm | idem, sem aviso |
| Acima da IMEM | 1457,9 − 1439,5 − 15 = 3,4 µm | idem |

⚠️ **As memórias da ISFFT usam as duas portas**, e a OpenRAM põe a porta 0
(`din0`) embaixo e a porta 1 (`dout1`) em cima (RTL: `rtl/isfft/isfft_axi_v4.v`,
linhas 174 e 352). Seja qual for a orientação, **um barramento de 64 bits fica
de costas para a lógica**. Os ~44 µm até a borda servem de canal. Não é erro;
é para olhar a congestão na etapa 6 (roteamento).
**Vira slide?** Sim: "orientar macro = ler o LEF": onde ficam os pinos e para
onde apontam, com a planta ao lado.

### Etapa 3 — PDN

| Item | Valor | Fonte |
|---|---|---|
| Grades inseridas | `stdcell_grid` + 1 grade `macro` para cada uma das 4 macros | `PDN-0001` |
| Tiras met4 (vertical) / met5 (horizontal) | 1,6 µm de largura, 1,7 µm entre VDD e GND, passo 153,6 / 153,18 µm | `config.json` do passo 18 (padrão do LibreLane) |
| Anel do núcleo | met4/met5, 1,6 µm, afastado 6 µm do núcleo | idem (`PDN_CORE_RING`, L17) |
| Pinos de alimentação das macros | `vccd1`/`vssd1` em met3 + met4 (anel em volta de cada macro) | LEF |
| Conectividade | "All shapes on net vccd1 are connected." e o mesmo para `vssd1` | `PSM-0040` |
| Violações da grade | 0 (`vccd1-grid-errors.rpt` e `vssd1-grid-errors.rpt` vazios) | métrica `design__power_grid_violation__count` |
| Avisos | **6 × `PDN-0110`** "No via inserted between met4 and met5" | log do passo 18 |

### 🐛 Os 6 avisos `PDN-0110` — tiras finas que o floorplan deixou

**Sintoma:**

| Rede | x (µm) | y (µm) | Tira met5 (y = 40,8 + 16,65 + k × 153,18) | Sobre qual macro |
|---|---|---|---|---|
| vccd1 | 1955,98 – 1956,78 | 209,83 / 1128,91 / 1282,09 | k = 1, 7, 8 | in_mem / out_mem / out_mem |
| vssd1 | 1957,82 – 1958,62 | 213,13 / 1132,21 / 1285,39 | idem (tira de GND ao lado) | idem |

Nada ficou solto (PSM-0040; 0 violações da grade).

**Causa** (vista no zoom `imagens/antes_L23/03_pdn_zoom_pdn0110.png`, janela
x 1926–1987 µm, y 190–231 µm):

| O que aparece no zoom | x medido (µm) | Conclusão |
|---|---|---|
| Borda direita da in_mem | ≈ 1939,8 | igual à conta (1204 + 735,8) |
| Coluna de endcaps (`…Left_10xx` e `…Right_1xx`) | ≈ 1954,9 – 1959,7 | a tira de 4,8 µm entre o halo e a borda do núcleo virou "linhas" que só têm um endcap de começo e um de fim, sem lugar para célula nenhuma |
| Duas tiras met4 **estreitas** (VDD e GND) | 1955,98 – 1956,78 e 1957,82 – 1958,62 | o pdngen pôs met4 de 0,8 µm para alimentar os trilhos met1 dessas linhas isoladas; exatamente o x dos avisos |
| Tiras met5 (1,6 µm) cruzando essas met4 | y ≈ 210,6 e 214,0 | cruzam, mas uma via4 precisa de met4 mais larga que 0,8 µm (corte 0,8 µm + borda) → "No via inserted" |
| Anel do núcleo (met4) | ≈ 1965,6 – 1967,2 e 1968,9 – 1970,5 | 1959,6 + 6 µm de afastamento, como o config manda |

Resumo: a macro + halo parava **4,8–5,5 µm antes da borda do núcleo**; ali
sobravam linhas de célula inúteis (só endcaps), e o pdngen tentou
alimentá-las com met4 fina demais para ter via. Elas ficaram ligadas pelas
pontas, pelos trilhos met1 — por isso o PSM diz "connected". Do lado esquerdo
(4,98 µm) e acima da IMEM (3,4 µm) sobravam tiras iguais; lá não houve aviso
porque nenhuma met4 estreita caiu embaixo de uma met5, mas a tira inútil
existia do mesmo jeito.
**Resolvi com (L23):** mover as macros para que o halo **alcance** a borda do
núcleo nos lados em que elas encostam. A regra: a sobra entre o halo e a borda
tem que ser 0 ou larga o bastante para linhas de verdade, nunca poucos µm.

| Macro | Antes (x, y) | Depois (x, y) | Halo agora vai até | Borda do núcleo |
|---|---|---|---|---|
| IMEM | (60; 886) | (55; 890) | esq. 40,0 / topo 1458,5 | 40,02 / 1457,92 ✅ |
| DMEM | (60; 464) | (55; 464) | esq. 40,0 | 40,02 ✅ |
| out_mem | (1192; 1002) | (1198; 1002) | dir. 1960,1 | 1959,6 ✅ |
| in_mem | (1204; 100) | (1210; 100) | dir. 1960,8 | 1959,6 ✅ |

O canal IMEM ↔ DMEM cresce de 40,7 para **44,7 µm** úteis (890 − 815,3 − 30).
As imagens de antes ficaram em `imagens/antes_L23/` (vira slide: antes/depois).
**Tempo:** ~30 min (ler o log, zoom automático, medir na imagem).
**Vira slide?** Sim: "um aviso que não quebra nada, mas mostra uma sobra
inútil no floorplan". Zoom antes/depois lado a lado.

### Conferência da L23 — 02 + 03 de novo na mesma rodada (`logs_1056`)

Passos `20-…` a `29-…` da rodada `2026-09-30_0934` (os `09`–`19` são os de antes).

| Item | Antes (L17) | Depois (L23) | Fonte |
|---|---|---|---|
| Linhas de células depois do corte | 1.124 (linhas partidas em pedaços, inclusive os de 4,8 µm) | **521** (cada linha virou um único trecho) | `ODB-0303` |
| Sítios disponíveis | 1.108.096 | 1.109.034 | idem |
| Endcaps / tap cells | 1.042 / 20.139 | 1.042 / 20.186 | `TAP-0004/0005` |
| Utilização das células padrão | 0,491 | 0,491 | métrica `…utilization__stdcell` |
| Avisos `PDN-0110` | 6 | **0** | log do `28-openroad-generatepdn`; nenhuma `03_pdn_zoom_pdn0110.png` gerada |
| Conectividade (PSM) / violações da grade | conectado / 0 | conectado / 0 | `PSM-0040`; `…grid-errors.rpt` vazios |
| Avisos que sobraram | — | só `IFP-0028` (canto do núcleo), `ODB-0220` (LEF antigo), `ORD-0039` | métricas `flow__warnings__count:*` |

As imagens `02_floorplan_planta.png` e `03_pdn_malha.png` agora saem na
proporção do chip (2399 × 1811 px).
**Vira slide?** Sim: a planta e a malha de depois, com o zoom do PDN-0110
de antes ao lado.

### 🐛 Planta inteira com 1448 × 7200 px

**Sintoma:** com `SEM_GUI=1`, `02_floorplan_planta.png` e `03_pdn_malha.png`
saíram estreitas e altíssimas, com o chip pequeno no meio.
**Causa:** sem janela (Qt `offscreen`) o OpenROAD não tem proporção de tela;
`save_image` sem `-area` usa essa "tela" inventada. Os zooms saíram certos
porque já tinham `-area`.
**Resolvi com:** `area_die` no `tcl/imagem.tcl` — as vistas inteiras usam a
área do die + 20 µm de margem.
**Tempo:** 5 min. **Vira slide?** Não.

### Etapa 4 — script `04_posicionamento.sh` (escrito, não rodado)

Trecho do fluxo `Classic` (lista de passos conferida em
`librelane/flows/classic.py`, tag 3.0.14): de `Odb.AddRoutingObstructions`
até `OpenROAD.DetailedPlacement`.

| Passo | O que faz |
|---|---|
| `OpenROAD.GlobalPlacementSkipIO` | posicionamento global sem os pinos de E/S, só para saber onde a lógica fica |
| `OpenROAD.IOPlacement` | os 4 pinos de E/S na borda, perto de quem os usa |
| `OpenROAD.GlobalPlacement` | RePlAce: as células se espalham como cargas elétricas até a densidade alvo |
| `OpenROAD.STAMidPNR` | STA com fio estimado |
| `OpenROAD.RepairDesignPostGPL` | resizer: buffers e troca de tamanho para slew, capacitância e fanout |
| `OpenROAD.DetailedPlacement` | encaixa cada célula num sítio, sem sobreposição |

| Parâmetro | Valor | De onde |
|---|---|---|
| Densidade alvo | não definida no config → LibreLane usa utilização (com macros) + 10 = 71,2 + 10 ≈ **81 %** | `steps/openroad.py` (`_GlobalPlacement.run`); o log confirma |
| Posicionamento guiado por timing | desligado (`PL_TIMING_DRIVEN` padrão) | `resolved.json` |
| Guiado por roteabilidade | ligado | idem |
| Fanout máx. / slew / cap | 10 / margem de 20 % / 20 % | idem |

O script salva `04_posicionamento_metricas.json`, `04_posicionamento.txt`
(resumo do log de cada passo) e três imagens: células no chip inteiro, mapa de
densidade e zoom no canal IMEM/DMEM.

### Números pré-posicionamento (não se leem ainda)

| Métrica (passo 16) | Valor | Por que não conta |
|---|---|---|
| Setup WS (TT / SS) | −47,35 / −86,12 ns; 6.800 violações | sem fio, sem buffer, relógio ideal com as cargas da síntese; mesmo número da etapa 1 |
| Hold WS (FF) | −0,039 ns; 369 violações | antes da CTS não há relógio real |
| Slew máx. (SS) | 61.470 violações | o reparo (`repair_design`) só roda no posicionamento (etapa 4) |
| Potência total | 75.787.760 W | `.lib` das macros com `internal_power` fora de escala (herdado) |

A leitura de verdade começa depois da CTS (etapa 5).

### Imagens do 02 que faltavam

Refeitas com `SO_GUI=1 SEM_GUI=1 bash layout/nucleo/02_floorplan.sh`:
saíram as duas. A falta da primeira vez não se repetiu (causa não
descoberta; provavelmente a janela do 02 foi fechada antes de salvar).

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L5 | Die 2,0 × 1,5 mm | 🟡 → mantém | Utilização das células padrão 0,491; confirmar depois do posicionamento (congestão) |
| L17 | `config.json` do núcleo | 🟡 → mantém | Floorplan e PDN passaram; orientação das macros conferida pelo LEF |
| L22 | Investigar o PDN-0110 com zoom automático antes de mover macros | ✅ | O zoom mostrou a causa (met4 de 0,8 µm na tira de 4,8 µm) |
| L23 | Halo das macros alcança a borda do núcleo (sem tiras de poucos µm) | 🟡 | Tira fina só tem endcaps e gera met4 sem via. Refeito: 0 `PDN-0110`, 521 linhas inteiras |

---

## 2026-09-30 (15ª sessão) — ✅ Etapa 4 (posicionamento) passou; congestionamento a vigiar

Rodada `2026-09-30_0934`, passos `30-…` a `41-…`. Fontes:
`04_posicionamento.txt`, `04_posicionamento_metricas.json`, `logs_1132.tar.gz`.

### Posicionamento global (RePlAce)

| Item | Valor | Fonte |
|---|---|---|
| Densidade alvo | **0,8125** (utilização 71,2 % + 10, cálculo do LibreLane) | `GPL-0023` |
| Área livre / densidade mínima possível | 1.358.455 µm² / 0,60 | `GPL-1003/1004` |
| Fim | iteração 1.422, overflow 0,0991 (alvo 0,1) | tabela do Nesterov |
| Modo roteabilidade | 13 rodadas; congestionamento estimado (RUDY) mínimo **1,18**, final 1,19; ~35–40 % dos tiles acima da capacidade | `GPL-0040…0047`, `GPL-0056`, `GPL-1005` |
| Resultado do modo roteabilidade | "Reverting to minimal observed routing congestion, **could not reach target**" | `GPL-0089` |
| Inflação de área para abrir espaço | +17,27 % (809.509 → 981.658 µm²) | `GPL-1012/1014` |
| Tempo | 1 min 22 s (e 32 s do `SkipIO`) | `runtime.txt` |

⚠️ **Congestionamento estimado > 1.** O RUDY é uma estimativa grosseira
(espalha cada rede pela caixa que a envolve), mas diz que falta trilha em
boa parte do chip na densidade 0,81. O veredito de verdade é o roteamento
global (etapa 6), e o `GRT_ALLOW_CONGESTION` está `false`: se não couber,
o GRT para. Plano B já medido pelos próprios números: a densidade mínima é
0,60, então dá para baixar o alvo (`PL_TARGET_DENSITY_PCT` ≈ 65) e espalhar
as células; custa fio mais longo. Seguimos para a CTS e decidimos com o GRT.

### Pinos de E/S

| Item | Valor | Fonte |
|---|---|---|
| Pinos | 4 (`clk_i`, `rstn_i`, `uart0_txd_o`, `uart0_rxd_i`), todos com carga | `PPL-0002/0003`; cabeçalho do `asic_top` no netlist |
| Posições livres na borda | 6.542 | `PPL-0001` |
| HPWL das redes de E/S | 6.472,86 µm | `PPL-0012` |

### Reparo do projeto (`RepairDesignPostGPL`)

| Item | Valor | Fonte |
|---|---|---|
| Violações encontradas (antes do reparo) | slew 2.697, fanout 1.707, capacitância 43 | `RSZ-0034/35/36` |
| **Buffers inseridos** | **12.930 em 2.818 redes** (+117.892 µm²) | `RSZ-0038`; classe `timing_repair_buffer` |
| Células redimensionadas | 301 | `RSZ-0039` |
| Buffers nas portas | 2 de entrada + 1 de saída | `RSZ-0027/0028` |
| Tie cells | 10 `conb_1` novas (uma por carga, `DESIGN_REPAIR_TIE_FANOUT`) | `RSZ-0042` |
| Aviso | "found 2 floating nets": são `vccd1` e `vssd1` (o resizer não vê a PDN) — inofensivo | `RSZ-0020` |
| Legalização depois dos buffers | deslocamento médio 3,1 µm, máx. 191,8 µm; HPWL +10 % | "Placement Analysis" |
| Tempo | **6 min 03 s** (o passo mais lento até aqui) | `runtime.txt` |

Por que tanto buffer: o Genus não tinha limite de fanout e o PDK manda
**fanout máximo 10** (`MAX_FANOUT_CONSTRAINT`). As 1.707 redes acima disso
(reset, habilitações de registradores, seleções de mux) viram árvores de
buffers. A utilização das células padrão foi de 0,491 para **0,569**.
**Vira slide?** Sim: "síntese entrega a lógica; o layout paga o fanout".

### Posicionamento detalhado

| Item | Valor | Fonte |
|---|---|---|
| Células espelhadas para encurtar fio | 31.012 | `DPL-0020` |
| HPWL | 3.081.852 → 3.008.057 µm (−2,4 %) | `DPL-0021/0022/0023` |
| Deslocamento | 0 (o reparo já tinha legalizado) | "Placement Analysis" |
| Instâncias no fim | 93.145 (93.141 células padrão + 4 macros) | métricas |
| Área das instâncias | 2.057.080 µm²; utilização 0,756 (com macros) / 0,569 (só células) | métricas |

### 🐛 Timing de −166 ns em setup **e** em hold — não é do projeto

**Sintoma:** `04_posicionamento_metricas.json` diz setup WS −166,6 ns e hold
WS −166,8 ns (TT), 79.886 violações de slew; o SS continua −86,12 ns.
**Causa** (lida no `38-openroad-stamidpnr/max.rpt` e `clock.rpt`):

| O que se vê | Explicação |
|---|---|
| `clk_i`: fanout **19.829**, 47,15 pF, slew 209,8 ns, atraso 155,9 ns até o flip-flop | Antes da CTS o relógio é **um fio só** ligando todos os flip-flops e as 6 entradas de relógio das macros |
| Latência 131–157 ns, "skew" 26 ns | O `nucleo.sdc` (igual ao `base.sdc` do LibreLane) faz `set_propagated_clock` sempre que `OPENLANE_SDC_IDEAL_CLOCKS` não é 1, e só o `STAPrePNR` põe 1 (`steps/openroad.py`). No meio do fluxo o relógio é propagado por esse fio único |
| Pior caminho: flip-flop da UART → `uart0_txd_o` | 155,9 ns de relógio + 24,5 ns de CK→Q com 210 ns de slew na entrada |
| As métricas são do passo **38** (STA), **antes** do reparo (39) | O arquivo de métricas do fim da etapa carrega o último STA que rodou |
| SS igual ao da etapa 1 | O STA do meio do fluxo só roda o corner TT (`DEFAULT_CORNER`); o SS é o valor velho do `STAPrePNR` |

**Resolvi com:** nada a fazer — a CTS (etapa 5) troca o fio por uma árvore.
Os números valem a partir do `STAMidPNR-2` (depois do reparo pós-CTS).
**De brinde, um bug do LibreLane:** o `clock.rpt` diz "Virtual: yes /
Propagated: no", mas o relógio é real e propagado:
`scripts/openroad/sta/corner.tcl` (tag 3.0.14) faz
`if {is_propagated} { set is_virtual "yes" }` — troca as variáveis.
**Tempo:** ~20 min. **Vira slide?** Sim: "o STA antes da CTS mente — um
relógio com 19.829 cargas num fio só".

### Imagens

| Arquivo | O que mostra |
|---|---|
| `04_posicionamento_celulas.png` | células ocupando o meio e o canto de baixo à esquerda; o canal IMEM/DMEM com uma faixa de células |
| `04_posicionamento_densidade.png` | mapa de densidade: vermelho no centro-direita e embaixo à esquerda; faixas vazias junto à borda esquerda e à direita da in_mem |
| `04_posicionamento_zoom_canal.png` | canal IMEM/DMEM: células no meio do canal, com espaço livre junto às macros |

### Etapa 5 — script `05_cts.sh` (escrito, não rodado)

| Passo | ID no fluxo | O que faz |
|---|---|---|
| CTS | `OpenROAD.CTS` | TritonCTS: raiz `clkbuf_16`, buffers `clkbuf_8/4/2`, agrupamento de folhas ligado |
| STA | `OpenROAD.STAMidPNR-1` | primeiro STA com a árvore |
| Reparo | `OpenROAD.ResizerTimingPostCTS` | `repair_timing` de setup e de hold (margem de hold 0,1 ns, até 50 % de buffers) |
| STA | `OpenROAD.STAMidPNR-2` | STA depois do reparo — **os números que valem** |

IDs repetidos ganham sufixo `-1`, `-2`… (`flows/sequential.py`); por isso o
`--to` é `OpenROAD.STAMidPNR-2`.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L24 | Manter a densidade alvo padrão (0,81) e decidir com o roteamento global | 🟡 | RUDY 1,19 é estimativa; o GRT mede de verdade. Plano B: `PL_TARGET_DENSITY_PCT` ≈ 65 |
| L25 | Números de timing só a partir do `STAMidPNR-2` (pós-CTS) | 🟡 | Antes disso o relógio é um fio só, e o STA do meio do fluxo é só TT |

---

## 2026-09-30 (16ª sessão) — 🐛 Etapa 5 parou: reparo em 9 corners; reparo passa a ser só no TT (L26)

Rodada `2026-09-30_0934`, passos `42-…` a `44-…`. Fonte:
`resultados/2026-09-30_0934_layout_nucleo/logs_1236.tar.gz` (commit `ef44543`).

### CTS (passo 42) e STA com a árvore (passo 43) — passaram

| Item | Valor | Fonte |
|---|---|---|
| Redes de relógio | `clk_i` das macros (6 entradas) + `clk_i_regs` (19.823 flip-flops) | `CTS-0011`, log do 42 |
| Buffers de relógio | 3 (macros) + **2.120** (registradores), ≥ 7 níveis até o flip-flop | `CTS-0018`, `CTS-0012` |
| Latência (TT) | 1,44 ns (`out_mem`) a 2,08 ns (flip-flop do banco de registradores) | `43-…/clock.rpt` |
| Skew de setup (TT) | 0,87 ns (antes: ~26 ns com o fio único) | `43-…/skew.max.rpt` |
| Setup (TT) | **+0,93 ns**, TNS 0 | `43-…/ws.max.rpt`, `tns.max.rpt` |
| Hold (TT) | −0,046 ns, TNS −0,119 ns (poucos pontos) | `43-…/ws.min.rpt`, `tns.min.rpt` |
| Tempo | 2 min 22 s (CTS), 24 s (STA) | `runtime.txt` |

Com a árvore, o setup em TT **fecha** a 50 MHz (+0,93 ns; o Genus previa
+2,41 ns com relógio ideal e sem fio).

### 🐛 Passo 44 (`ResizerTimingPostCTS`): 19.485 buffers de hold e `DPL-0036`

**Sintoma:**

| Fase do reparo | O que aconteceu | Fonte |
|---|---|---|
| Setup | 990 pontos violando, WNS **−20,84 ns**, TNS −8.693 ns → depois de 2.800 iterações: 850 pontos, WNS −10,74 ns. `RSZ-0062` "Unable to repair all setup violations" | log do 44, tabela de iterações |
| Hold (margem 0,1 ns) | **18.624** pontos violando, WNS −0,132 ns → **19.485 buffers** inseridos (+9,4 % de área). `RSZ-0064` "Unable to repair all hold checks" | idem |
| Legalização | `detailed_placement` não achou lugar para **379** instâncias (quase todas no `ifft_1d.stage8` da ISFFT) → `[ERROR DPL-0036] Detailed placement failed` | idem |

**Causa:** os números do reparo não batem com o STA do passo 43 (setup TT
+0,93 ns, hold TT −0,046 ns). O STA do meio do fluxo **relata** só o TT,
mas o reparo usa `RSZ_CORNERS`, que, vazio, vira o `STA_CORNERS` inteiro
(`librelane/steps/openroad.py`, `ResizerStep.run`, tag 3.0.14): **os 9
corners** (TT, SS 1,60 V/100 °C e FF 1,95 V/−40 °C, cada um com RC mín.,
nominal e máx.). Conferido no `config.json` do passo 44:
`RSZ_CORNERS: null`, `STA_CORNERS` com os 9.
- **Setup −20,8 ns vem do SS** (dedução: o log não diz o corner, mas o TT tem +0,93 ns e o FF é mais rápido): com 1,60 V a 100 °C as células ficam perto
  de 2× mais lentas; o caminho da CPU que tem 15,5 ns em TT (Genus) não cabe
  em 20 ns. Nenhum redimensionamento conserta isso — o projeto nunca foi
  feito para o SS (fora de escopo desde o `DIARIO.md`: "múltiplos corners").
- **Hold vem do FF** (com a margem de 0,1 ns): no FF o dado é rápido e o
  skew da árvore pesa mais. Os ~17.600 flip-flops sem reset das memórias em
  flip-flop (FIFOs do SLINK, ping-pong, Spiral) são cadeias de registrador
  a registrador quase sem lógica no meio: quase todo ponto vira violação, um
  buffer para cada um. (Leitura: o primeiro pior ponto de hold é um `shiftFIFO…mem_reg` do Spiral; a distribuição por tipo de flip-flop não foi medida.)
- **Os `.lib` das macros só existem em TT:** o log do 44 mostra o mesmo
  `..._TT_1p8V_25C.lib` carregado nos corners SS e FF. Nos caminhos que
  passam por macro, o "SS" e o "FF" não são SS nem FF.
- O `DPL-0036` é consequência: 19.485 buffers a mais numa região que já
  tinha densidade alta (RUDY 1,19, 15ª sessão) não cabem com deslocamento
  máximo de 500 × 100 µm.

**Resolvi com (L26):** reparo só nos 3 corners **TT** (RC mín., nominal e
máx.), no `config.json`:
```json
"RSZ_CORNERS": ["nom_tt_025C_1v80", "min_tt_025C_1v80", "max_tt_025C_1v80"]
```
- É o mesmo corner em que o Genus sintetizou e em que as macros foram
  caracterizadas; os 3 RC continuam cobrindo a incerteza do fio.
- `STA_CORNERS` fica com os 9: o STA final (etapa 7) **relata** SS e FF
  (o número do SS vira resultado: "a 50 MHz só no típico; no pior caso o
  chip pediria ~40 ns"). O checker de **setup** do sky130 só reprova no TT
  (`TIMING_VIOLATION_CORNERS = ["*tt*"]`, `librelane/config/pdk_compat.py`).
  ⚠️ O de **hold** reprova em todos — corrigido na 17ª sessão (L27).
- `RSZ_CORNERS` vale para todos os passos de reparo (`RepairDesign*`,
  `ResizerTiming*`). O passo 39 (reparo pós-posicionamento) já rodou com os
  9 corners e não é refeito: a etapa 5 continua do fim da etapa 4.
- Comentário do `05_cts.sh` corrigido (dizia que o meio do fluxo "só usa o
  TT" — só o **relatório** usa).

**Ainda não conferido (só rodando):** quantos pontos de hold sobram no TT
com a margem de 0,1 ns. Plano B, se a legalização falhar de novo: margem de
hold menor (`PL_RESIZER_HOLD_SLACK_MARGIN`) ou densidade menor (L24).
**Tempo gasto:** ~40 min (ler o log, achar no código do LibreLane de onde
vêm os corners).
**Vira slide?** Sim: "o que é um corner (processo × tensão × temperatura
× RC) e por que consertar num corner para o qual o projeto não foi feito
enche o chip de buffers".

**Para continuar:** `git pull` e rodar de novo só o `05_cts.sh` (ele
retoma do fim da etapa 4; as pastas novas começam em `45-…`). Depois,
`junta_logs.sh` e push.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L26 | Reparo de timing só nos corners TT (`RSZ_CORNERS`); SS e FF só relatados no STA final | 🟡 | Síntese e `.lib` das macros só em TT; o reparo em 9 corners pôs 19.485 buffers e travou a legalização |

---

## 2026-10-05 (17ª sessão) — ✅ Etapa 5 (CTS) passou com a L26

Rodada `2026-09-30_0934`, passos `45-…` a `48-…` (refeitos depois da L26;
os `42`–`44` são a tentativa que falhou). Fontes: `05_cts.txt`,
`05_cts_metricas.json`, `logs_1715.tar.gz`, `imagens/05_cts_buffers.png`
(commit `cdae648`).

### Árvore de relógio (passo 45)

| Item | Valor | Fonte |
|---|---|---|
| Redes | `clk_i` → 6 entradas de relógio das macros; `clk_i_regs` → 19.823 flip-flops | `CTS-0011` |
| Topologia | árvore H, folhas agrupadas: 19.823 → 1.713 grupos | `CTS-0027`, `CTS-0019` |
| Buffers | 3 (macros) + **2.120** (registradores) | `CTS-0018` |
| Profundidade | 2 buffers até as macros; **7** até qualquer flip-flop (mín. = máx.: árvore balanceada) | `CTS-0012/0013` |
| Latência (TT) | 1,44 ns (`out_mem`) a 2,08 ns (banco de registradores) | `48-…/clock.rpt` |
| Skew de setup (TT) | **0,87 ns** (com o fio único eram ~26 ns) | métrica `clock__skew__worst_setup` |
| Tempo | 2 min 35 s | `runtime.txt` |

Igual à tentativa anterior (a L26 só muda o reparo, que vem depois).

### Reparo de timing pós-CTS (passo 47) — com a L26

| | Antes (9 corners, 16ª sessão) | Agora (só TT, L26) | Fonte |
|---|---|---|---|
| Setup | 990 pontos violando, WNS −20,84 ns; não conseguiu | **"No setup violations found"** | `RSZ-0098` |
| Hold (margem 0,1 ns) | 18.624 pontos, 19.485 buffers | **383 pontos, 383 buffers** (+0,2 % de área); WNS −0,046 → **+0,100 ns** | `RSZ-0046/0032`, tabela |
| Legalização | `DPL-0036`: 379 instâncias sem lugar | deslocamento médio 0,1 µm, máx. 25,3 µm | log do 47 |
| Tempo | — | 42 s | `runtime.txt` |

O pior ponto de hold antes do reparo era um `shiftFIFO…mem_reg` da IFFT
(cadeia de registrador a registrador, quase sem lógica no meio).

### Timing no fim da etapa (STA, passo 48, corner TT)

| Métrica | Valor | Fonte |
|---|---|---|
| Setup WS | **+0,93 ns**, 0 violações | `timing__setup__ws__corner:nom_tt` |
| Hold WS | **+0,098 ns**, 0 violações | `timing__hold__ws__corner:nom_tt` |
| Instâncias | 97.889 (96.843 células + 4 macros + 1.042 endcaps…); 3.120 buffers e 199 inversores de relógio; 13.316 buffers de reparo; 383 de hold | métricas `design__instance__count__class:*` |
| Utilização (só células) | 0,600 (era 0,569 na etapa 4) | `design__instance__utilization__stdcell` |

**A 50 MHz no TT, com relógio real, o núcleo fecha setup e hold.**
Comparação: Genus +2,41 ns (relógio ideal, sem fio) → layout +0,93 ns
(árvore com 0,87 ns de skew + fio estimado).

⚠️ Os números de SS e FF do mesmo arquivo de métricas (setup −86,12 /
−28,81 ns, hold FF 369 violações) **são velhos**: são exatamente os da
etapa 1 (`STAPrePNR`). O STA do meio do fluxo só recalcula o TT (15ª
sessão); SS e FF só voltam no STA final (etapa 7).

### O que sobra de violação no TT — e de onde vem

| Violação | Quantas | Origem (conferida) | Precisa consertar? |
|---|---|---|---|
| Fanout > 10 | 1.423 | **buffers da árvore de relógio** com 11 a 15 cargas: a distribuição do `CTS-0016` (11:434, 12:588, 13:313, 14:84, 15:4) soma exatamente 1.423. A CTS agrupa as folhas pelo limite de capacitância, não pelo de fanout | Não: as redes de relógio ficam fora do reparo de fanout; o que importa nelas é o skew e a transição |
| Transição máxima | 57 | **todas em pinos de entrada das macros** (`addr`, `wmask`): 15 IMEM, 14 DMEM, 12 `in_mem`, 16 `out_mem`. O `.lib` da OpenRAM declara `max_transition 0.04` (40 ps) nesses pinos, que é o fim da tabela de caracterização (`index_1("0.00125, 0.005, 0.04")`); o sinal real chega com 0,14–0,23 ns | Não dá: nenhum buffer do sky130 entrega 40 ps com fio. O limite é da tabela do modelo analítico, não do circuito. O checker de transição do LibreLane não reprova (`corner_override = [""]`) |

**Vira slide?** Sim, os dois: "violação que não é do circuito: o limite
vem da tabela da OpenRAM" e "fanout do relógio não se conta como o dos
dados".

### 🐛 Correção da 16ª sessão: o checker de hold reprova em qualquer corner

Na 16ª sessão escrevi que "o checker de timing do sky130 só reprova no
TT". **Vale para setup, não para hold.** Conferido em
`librelane/steps/checker.py` (tag 3.0.14):

| Checker | Corners que reprovam | Por quê |
|---|---|---|
| `Checker.SetupViolations` | `*tt*` | herda `TIMING_VIOLATION_CORNERS` do sky130 (`pdk_compat.py`) |
| `Checker.HoldViolations` | **`*` (todos)** | `corner_override = ["*"]` |
| `Checker.MaxSlewViolations` / `MaxCapViolations` | nenhum (só aviso) | `corner_override = [""]` |

Os checkers rodam no fim do fluxo e o erro é adiado (`DeferredStepError`):
o fluxo vai até o fim e só então acusa. Ou seja, se depois do roteamento
sobrar hold no **FF**, o fluxo termina com erro.

Isso tem fundamento físico: **setup se resolve baixando o relógio; hold
não** — violação de hold quebra o chip em qualquer frequência. Duas
saídas, a decidir com o número real do FF (STA final, etapa 7):

| Opção | O que é | Custo |
|---|---|---|
| A | Reparar hold também no FF: `RSZ_CORNERS` com TT + FF (sem o SS, que é só setup) | Buffers a mais (na 16ª foram 18.624 pontos com margem 0,1 ns misturando SS e FF); talvez com margem menor |
| B | `HOLD_VIOLATION_CORNERS: ["*tt*"]` e o FF só relatado | Coerente com a L26 (macros só têm `.lib` TT), mas deixa um risco real sem tratar |

Recomendação: **A**, se couber. Hold é o tipo de violação que um projeto
de verdade nunca deixa passar; e os caminhos que violam são de registrador
a registrador (sem macro), onde o `.lib` do FF das células vale.

### Imagens

`05_cts_buffers.png`: buffers de relógio (verde) espalhados de forma
uniforme por toda a área de células, inclusive no canal IMEM/DMEM e nas
faixas em volta das macros. A imagem da árvore (`05_cts_arvore.png`) não
veio: o `save_clocktree_image` deve ter falhado (o aviso fica no terminal;
não está no log da rodada).

### Etapa 6 — script `06_roteamento.sh` (escrito, não rodado)

| Passo | O que faz |
|---|---|
| `OpenROAD.GlobalRouting` | FastRoute: escolhe ladrilhos e camadas de cada rede. Sem `GRT_ALLOW_CONGESTION`: se faltar trilha, para (L24) |
| `CheckAntennas`, `RepairDesignPostGRT`, diodos, `RepairAntennas` | antena e slew/cap com o fio estimado |
| `ResizerTimingPostGRT` → `STAMidPNR-3` | reparo e STA com o fio do roteamento global (TT, L26) |
| `OpenROAD.DetailedRouting` | TritonRoute: cada fio e via nas trilhas; o passo mais lento |
| `CheckAntennas-1`, `Checker.TrDRC`, `DisconnectedPins`, `WireLength` | 0 DRV de roteamento, nenhum pino solto |

`ATE_GLOBAL=1` para só no `STAMidPNR-3`, para olhar a congestão antes de
gastar tempo no detalhado. Imagens novas no `tcl/imagem.tcl` (modo
`roteamento`): mapa de congestão, chip roteado, zoom no canal IMEM/DMEM.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L25 | Timing só vale depois do `STAMidPNR-2` | 🟡 | Números do 48 coerentes: TT setup +0,93 / hold +0,098 ns |
| L26 | Reparo só no TT | 🟡 funcionou (setup ok, 383 buffers de hold) — ⚠️ hold no FF a decidir (L27) | Saiu de 19.485 para 383 buffers |
| L27 | Hold no FF: reparar (A) ou só relatar (B) | 🟡 recomendo A | O checker de hold reprova em todos os corners; decidir com o número do STA final |
| L28 | Fanout do relógio e transição dos pinos das macros: aceitos, documentados | 🟡 | Origem conferida; nenhum dos dois é defeito do circuito |

---

## 2026-10-05 (18ª sessão) — 🐛 Etapa 6: roteamento global com congestão; densidade alvo 65 % (L29)

Rodada `2026-09-30_0934`, passo `49-openroad-globalrouting`. Fonte:
`resultados/2026-09-30_0934_layout_nucleo/logs_1909.tar.gz` (commit
`cad07e5`).

### 🐛 `[ERROR GRT-0116] Global routing finished with congestion`

**Sintoma:** o FastRoute rodou as 50 iterações extras para tirar o
excesso e não zerou. Relatório final (log do passo 49, `GRT-0096`):

| Camada | Direção | Capacidade (trilhas, já com 30 % de redução) | Demanda | Uso | Excesso (*overflow*) |
|---|---|---|---|---|---|
| met1 | H | 352.940 | 221.648 | 62,8 % | 1.017 |
| met2 | V | 368.279 | 241.812 | 65,7 % | 1.822 |
| met3 | H | 259.176 | 138.715 | 53,5 % | 888 |
| met4 | V | 164.713 | 62.711 | 38,1 % | 764 |
| met5 | H | 36.506 | 12.631 | 34,6 % | 191 |
| **Total** | | **1.181.614** | **677.517** | **57,3 %** | **4.682** |

Comprimento de fio estimado 6,68 m; 776.929 vias (`global_route__*`).

**Leitura:** na média sobra trilha (57 % de uso), mas há **regiões
locais** onde a demanda passa da capacidade, e o excesso se concentra nas
camadas de baixo (met1/met2), as das ligações curtas entre células
vizinhas. É o que o RUDY já tinha avisado na etapa 4 (congestão estimada
1,19, ~40 % dos ladrilhos acima da capacidade, `GPL-0089` "could not
reach target"). Com `GRT_ALLOW_CONGESTION = false` o fluxo para aqui, o
que é bom: o roteamento detalhado num chip congestionado leva horas e
termina com violações.

**Causa (conferida no código):** a densidade alvo do posicionamento não
estava no `config.json`. O LibreLane calcula
`utilização + 5 × GPL_CELL_PADDING + 10` (`steps/openroad.py`,
`_GlobalPlacement`), e a utilização que ele usa é a métrica
`design__instance__utilization`, que **conta as macros**: 0,712. Deu
**81,25 %**. Só com as células padrão a utilização era 0,491 (14ª
sessão). Ou seja, as macros, que ocupam 62 % da área, empurraram a lógica
para se amontoar a 81 % de densidade local, quando havia espaço para
espalhar.
**Resolvi com (L29):** `"PL_TARGET_DENSITY_PCT": 65` no `config.json`.
- Abaixo dos 81 % que congestionaram.
- Acima da utilização final das células (0,600 depois da CTS, 17ª sessão):
  os buffers de reparo (~13 mil) e de relógio (~2 mil) entram **depois**
  do posicionamento global e precisam de lugar perto de onde já está a
  lógica.
- Era o plano B da L24 (15ª sessão), agora com a causa explicada.
- Custo esperado: fio mais longo (células mais espalhadas); conferir o
  timing do TT depois da CTS de novo.

**Tempo gasto:** ~20 min.
**Vira slide?** Sim: "densidade × congestão" — o mapa de densidade da
etapa 4 ao lado do relatório do GRT, e a pegadinha da utilização que
conta as macros.

**Para continuar** (a densidade muda o posicionamento: refazer 4, 5 e 6
na mesma rodada; cada script retoma da etapa anterior mais recente):
```bash
git pull
bash layout/nucleo/04_posicionamento.sh
bash layout/nucleo/05_cts.sh
ATE_GLOBAL=1 bash layout/nucleo/06_roteamento.sh
bash layout/nucleo/junta_logs.sh      # e o git add/commit que ele imprime
```
Plano C, se ainda congestionar: densidade 60 % (o mínimo possível era
0,60, 15ª sessão) ou `GRT_ALLOW_CONGESTION` e deixar o TritonRoute tentar.

### `junta_logs.sh`: nome do arquivo com a data de hoje

**Pedido do Lukas:** o nome saía com "data errada". O script usava só a
hora (`logs_1909.tar.gz`) e sugeria a mensagem de commit com o nome da
**rodada** (`2026-09-30_0934`, a data em que ela começou). Com a rodada
durando dias, ficava ambíguo. Agora:
- arquivo `logs_AAAA-MM-DD_HHMM.tar.gz` (quando os logs foram juntados);
- mensagem sugerida: `gdsii: logs do layout ate <última etapa> (juntados
  em <data_hora>, rodada <tag>)`.
Testado com uma rodada falsa.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L24 | ~~Densidade padrão e decidir com o GRT~~ → decidido: o GRT congestionou | ✅ substituída por L29 | 4.682 de excesso no roteamento global |
| L29 | `PL_TARGET_DENSITY_PCT = 65` | 🟡 | A densidade automática (81 %) contava as macros na utilização |

---

## 2026-10-06 (19ª sessão) — Etapas 4–5 refeitas com a L29; GRT ainda congestionado (menos); diagnóstico de onde

Rodada `2026-09-30_0934`, passos `50-…` a `66-…`. Fonte:
`resultados/2026-09-30_0934_layout_nucleo/logs_2026-10-06_0055.tar.gz`
(commit `abe4120`). Primeira vez com o nome novo do `junta_logs.sh`.

### O que a densidade 65 % mudou

| Item | Densidade 81 % (passos 35–49) | Densidade 65 % (passos 55–66) | Fonte |
|---|---|---|---|
| Densidade alvo usada | 0,8125 | **0,6500** | `GPL-0023` |
| Congestão estimada no posicionamento (RUDY, média do 0,5 % pior) | 1,21 | 1,21 | `GPL-0043` |
| Ladrilhos acima da capacidade (estimativa) | 40,1 % | 39,6 % | `GPL-0042` |
| Buffers do reparo pós-posicionamento | 12.930 em 2.818 redes | 12.763 em 1.969 redes | `RSZ-0038` |
| Buffers de hold (TT) | 383 | 369 | `RSZ-0032` |
| Setup / hold no TT depois da CTS | +0,93 / +0,098 ns | **+0,98 / +0,102 ns** | métricas do 48 / 65 |
| Utilização das células no fim da CTS | 0,600 | 0,599 | idem |
| **Excesso no roteamento global (total)** | **4.682** | **2.038** (−56 %) | `GRT-0096` |
| met1 / met2 / met3 / met4 / met5 | 1.017 / 1.822 / 888 / 764 / 191 | 359 / 939 / 157 / 339 / 244 | idem |
| Excesso máximo numa aresta (H / V) | 11 / 9 | 7 / 7 | idem |
| Uso médio das trilhas | 57,3 % | 55,5 % | idem |
| Fio estimado | 6,68 m | 6,38 m (−4,5 %) | `GRT-0018` |

**Leitura:** espalhar ajudou (menos da metade do excesso, e até o fio
encurtou: com mais espaço o posicionador acha lugares melhores), mas não
zerou. A estimativa do posicionador (RUDY) **não mudou** — ela mede a
congestão relativa à densidade escolhida e não serve para comparar as
duas rodadas; o número que vale é o do GRT. O timing no TT continua
fechando, um pouco melhor.

### 🔍 A redução de 30 % do GRT não está valendo (achado de leitura)

O log do GRT diz "Global adjustment: 30%", mas o
`set_layer_adjustments.tcl` do LibreLane aplica os 30 % em todas as
camadas e **depois** sobrescreve camada a camada com o
`GRT_LAYER_ADJUSTMENTS` do PDK: `0.99 0 0 0 0 0` (li1 99 %, met1 a met5
**0 %**; `_env.tcl` do passo 66). Ou seja, as metais já roteiam com 100 %
da capacidade, e a "redução de recursos" de 31–48 % da tabela `GRT-0053`
é de **obstrução** (macros cobrem met1–met4; malha de alimentação em
met4/met5), não de margem. Não há folga para tirar por aí.

### Próximo passo: ver **onde** está o excesso

Quando o GRT para com `GRT-0116`, o passo não grava estado, então não dá
para abrir a GUI no fim dele. Script novo: `layout/nucleo/diag_congestao.sh`
(+ `tcl/diag_congestao.tcl`, `resume_congestao.py`):
- refaz o mesmo `global_route` fora do fluxo (lê o `_env.tcl` do último
  `GlobalRouting`: mesmo `.odb`, mesmas camadas e ajustes), mas com
  `-allow_congestion -congestion_report_file`;
- salva `06_congestao.rpt` (regiões), `06_congestao.txt` (excesso por
  camada e as 15 regiões de 100 × 100 µm com mais excesso, dizendo se
  ficam junto de alguma macro), `imagens/06_congestao_mapa.png` (mapa de
  calor);
- não mexe na rodada.

O resumo foi testado com um relatório sintético (formato do DRC Viewer
do OpenROAD); se o formato real for outro, ele imprime as primeiras
linhas para eu ajustar.

| Se o excesso estiver… | Então |
|---|---|
| concentrado junto das macros (canal IMEM/DMEM, faixas de 44 µm das memórias da ISFFT) | mexer no floorplan: canais mais largos / macros afastadas |
| espalhado e baixo (máx. ~7 por aresta, 0,17 % da capacidade) | `GRT_ALLOW_CONGESTION: true` e deixar o roteamento detalhado resolver (comum com excesso pequeno; o veredito vira o número de DRV do TritonRoute) |
| concentrado no meio da lógica da ISFFT | densidade 60 % ou espaçamento só naquela região |

### 🐛 `diag_congestao.sh`: `can't read "::env(SCRIPTS_DIR)"`

**Sintoma:** primeira rodada no notebook parou na linha 13 do
`tcl/diag_congestao.tcl` (`source $::env(SCRIPTS_DIR)/…/io.tcl`), e o
resumo em Python não achou o `06_congestao.rpt`.
**Causa:** o `_env.tcl` de um passo só tem as variáveis de
**configuração**. As que o LibreLane injeta na hora de rodar
(`SCRIPTS_DIR`, `_SDC_IN`, `_LIB_CORNER_*`, `_PNR_EXCLUDED_CELLS`…) não
estão lá (`steps/tclstep.py`). Eu tinha testado a sintaxe, não o ambiente.
**Resolvi com:** o Tcl do diagnóstico não usa mais os scripts do
LibreLane: chama direto os comandos do roteamento global (`read_db`,
`set_routing_layers`, os ajustes por camada, `set_macro_extension`,
`global_route`), que só precisam de 7 variáveis — todas no `_env.tcl`
(conferido). O `.sh` agora para com mensagem clara se o `.rpt` não sair.
**Vira slide?** Não.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L29 | Densidade 65 % | 🟡 ajudou (−56 % de excesso), não basta | Fica; o resto depende do diagnóstico |
| L30 | Diagnosticar a congestão fora do fluxo antes de decidir (L31) | 🟡 | Três remédios diferentes conforme o lugar |

---

## 2026-10-06 (20ª sessão) — 🔍 Onde está a congestão: canal IMEM/DMEM estreito e fios atravessando a DMEM; DMEM para o canto (L31)

Fonte: `diag_congestao.sh` (19ª sessão) rodado no notebook (commit
`ee3049b`): `resultados/2026-09-30_0934_layout_nucleo/06_congestao.rpt`
(1.883 regiões), `06_congestao.txt`, `imagens/06_congestao_mapa.png`.
Mesmo `.odb` de entrada do passo 66 (densidade 65 %).

### Primeiro resumo (`06_congestao.txt`)

| Achado | Valor |
|---|---|
| Regiões congestionadas / excesso somado | 1.883 / 1.939 (o GRT do fluxo deu 2.038; aqui sem a última tentativa de reparo — mesma ordem) |
| Regiões com **capacidade 0** | **1.598 de 1.883** (85 %) |
| Excesso a até 60 µm de alguma macro, ou sobre ela | **1.822 de 1.939 (94 %)** |
| As 15 piores regiões de 100 × 100 µm | todas sobre a IMEM ou a DMEM, x = 400–900 µm, y = 500–1.100 µm |

O relatório não traz a camada (`on Layer -`: a congestão é medida no
grafo 2D, antes de escolher camada); por isso a coluna "Camadas" saiu `-`.

### Segunda leitura: em que parte de cada macro (análise do `.rpt`)

Cada região classificada pela posição em relação às macros do
`config.json` + `SIZE` do LEF; H = congestão horizontal, V = vertical.

| Onde | Excesso | % | H | V |
|---|---|---|---|---|
| DMEM, 0–50 µm abaixo da borda de cima (a dos pinos) | 316 | 16,3 % | 152 | 164 |
| IMEM, 0–50 µm acima da borda de baixo (a dos pinos) | 267 | 13,8 % | 120 | 147 |
| IMEM, 50–100 µm | 200 | 10,3 % | 132 | 68 |
| DMEM, 50–100 µm | 188 | 9,7 % | 82 | 106 |
| **canal IMEM/DMEM** (fora das macros) | 150 | 7,7 % | 149 | 1 |
| lógica do centro/direita | 143 | 7,4 % | 30 | 113 |
| DMEM, 100–150 µm | 118 | 6,1 % | 19 | 99 |
| IMEM, 100–150 µm | 118 | 6,1 % | 84 | 34 |
| **DMEM, 150–350 µm** (quatro faixas) | 349 | 18,0 % | 1 | **348** (84 + 84 + 84 + 96) |
| IMEM, 150–250 µm | 84 | 4,3 % | 64 | 20 |
| `in_mem` | 6 | 0,3 % | 0 | 6 |

Nenhuma macro tem pino longe da borda (LEF: todos os pinos de sinal
encostados na borda, em met3/met4). Então o excesso **sobre** as macros é
fio passando por cima delas — e sobre uma macro da OpenRAM só a **met5**
está livre (OBS de met1 a met4), e a met5 é **horizontal**:

| Padrão | O que é |
|---|---|
| ~60 % até 150 µm para dentro da IMEM e da DMEM, dos dois lados do canal, + 7,7 % no próprio canal | o **canal** de 44,7 µm úteis entre IMEM e DMEM não comporta os 140 pinos das duas macros + as células que ficam nele + o tráfego que passa ao longo dele; o roteador "transborda" para cima das macros |
| **84 de excesso vertical em cada faixa de 50 µm da DMEM, de cima a baixo** | um feixe de ~84 fios **atravessando a DMEM inteira na vertical**: da lógica posicionada **abaixo** da DMEM (y 40–449) até o canal, onde estão os pinos. Atravessar uma macro na vertical é **impossível** (met2 e met4 bloqueadas; a met5 é horizontal): o roteamento detalhado não teria como resolver |

**Causa:** o floorplan (L5/L17/L23). A DMEM estava em y = 464, deixando
~410 µm de área de células **embaixo** dela, de costas para os pinos (a
DMEM em `S` tem todos os pinos em cima, virados para o canal). O
posicionador pôs lógica ali (tinha espaço), e essa lógica precisa falar
com a IMEM/DMEM pelo canal: ou dá a volta pela direita da DMEM, ou passa
por cima. E o canal, de 44,7 µm, já estava cheio.
**Vira slide?** Sim, o melhor até aqui: "a macro é uma parede" — mapa de
calor + a tabela por faixa, mostrando o feixe vertical de 84 fios.

### Resolvi com (L31): DMEM no canto de baixo

| | Antes | Depois |
|---|---|---|
| DMEM (canto, orientação) | (55; 464), `S` | **(55; 55)**, `S` |
| Borda de baixo do halo da DMEM | 449 (sobravam ~409 µm de lógica embaixo) | 40,0 — alcança a borda do núcleo (40,8), como manda a L23 |
| Canal IMEM/DMEM (útil, tirando os halos) | 44,7 µm | **453,7 µm** |
| Área de células na coluna da esquerda | embaixo da DMEM (de costas para os pinos) + canal estreito | toda no canal, **de frente** para os pinos das duas macros |

A área total de células não muda: a faixa de baixo vira canal. Toda a
lógica da coluna da esquerda fica entre as duas memórias, com acesso
direto aos 140 pinos, e nenhum fio precisa atravessar macro.

**Custo:** refazer da etapa 2 (floorplan) em diante, na mesma rodada
(como na L23). A densidade continua 65 % (L29).

### Para continuar

```bash
git pull
bash layout/nucleo/02_floorplan.sh
bash layout/nucleo/03_pdn.sh
bash layout/nucleo/04_posicionamento.sh
bash layout/nucleo/05_cts.sh
ATE_GLOBAL=1 bash layout/nucleo/06_roteamento.sh
bash layout/nucleo/junta_logs.sh     # e o git add/commit que ele imprime
```
As imagens atuais foram movidas para `imagens/antes_L31/` antes de
refazer (os scripts sobrescrevem pelo nome): 02 e 03 são do floorplan com
a L23 (30/09); 04 e 05 da densidade 65 % (L29, 06/10); `06_congestao_mapa`
do diagnóstico. As da densidade 81 % ficam no histórico do git (commit
`4aab297`). Com as novas, dá o slide antes/depois da L31.

Conferir nas imagens do 02 a DMEM no canto e o canal largo; no 03, 0
`PDN-0110`; no 06, o excesso do GRT. Se ainda sobrar excesso, rodar o
`diag_congestao.sh` de novo para comparar a tabela.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L30 | Diagnóstico fora do fluxo | ✅ | Mostrou a causa: 94 % do excesso nas macros IMEM/DMEM |
| L31 | DMEM para (55; 55): canal IMEM/DMEM de 44,7 → 453,7 µm, sem lógica atrás da DMEM | 🟡 | Canal estreito + feixe vertical de ~84 fios atravessando a DMEM |

---

## 2026-10-06 (21ª sessão) — ✅ Roteamento global sem excesso com a L31

Rodada `2026-09-30_0934`, passos `67-…` a `97-…` (etapas 2 a 6-global
refeitas com a DMEM no canto). Fontes: `06_roteamento_global.txt`,
`06_roteamento_global_metricas.json`, `logs_2026-10-06_1500.tar.gz`,
imagens `06_roteamento_global_*` (commit `4d00d69`).

### Roteamento global (passo 93)

| Camada | Uso das trilhas | Excesso | Antes da L31 (passo 66) |
|---|---|---|---|
| met1 | 52,8 % | **0** | 359 |
| met2 | 53,2 % | **0** | 939 |
| met3 | 44,9 % | **0** | 157 |
| met4 | 29,9 % | **0** | 339 |
| met5 | 27,0 % | **0** | 244 |
| **Total** | **47,2 %** (era 55,5 %) | **0** (era 2.038) | |

| Item | Antes da L31 | Depois | Fonte |
|---|---|---|---|
| Fio estimado | 6,38 m | **5,48 m** (−14 %) | `GRT-0018` |
| Vias | — | 663.981 | `GRT-0111` |
| Redes roteadas | 77.227 | 77.124 | `GRT-0014` |
| Tempo do GRT | — | 2 min 10 s | `runtime.txt` |

O fio encurtou 14 %: a lógica da CPU, agora entre as duas memórias, fica
perto dos pinos que usa. O mapa de calor (`06_roteamento_global_congestao.png`)
não mostra mais nada sobre as macros; o mais quente é uma faixa horizontal
no meio do chip, entre o canal IMEM/DMEM e a lógica da ISFFT, sem excesso.
**Vira slide?** Sim: `antes_L31/06_congestao_mapa.png` ×
`06_roteamento_global_congestao.png`.

A estimativa do posicionador (RUDY, `GPL-0043`) continuou em ~1,18–1,22 e
"could not reach target" (`GPL-0089`), e mesmo assim o GRT fechou sem
excesso: a estimativa não enxerga as macros como parede, que era o
problema real. Lição: o veredito é o GRT.

### Antenas (passos 94–96)

| Momento | Violações | Fonte |
|---|---|---|
| Checagem depois do GRT (94) | 804 redes / 1.006 pinos | `ANT-0001/0002` |
| Reparo com diodo `diode_2` (96), iterações | 195 → 18 → 12 → 1 | `GRT-0012` |
| Checagem final do 96 | **0 / 0** | `ANT-0001/0002` |

O reparo de antena (6 min 56 s) foi o passo mais demorado do trecho.

### Etapas 2–5 refeitas (conferência rápida)

| Item | Valor | Fonte |
|---|---|---|
| PDN | "All shapes … connected" nas duas redes | `PSM-0040`, passo 75 |
| Densidade alvo | 0,65 | `GPL-0023`, passo 82 |
| Buffers de reparo pós-posicionamento | 12.640 em 1.968 redes | `RSZ-0038`, passo 86 |
| Buffers de relógio | 3 + 2.089 | `CTS-0018`, passo 89 |
| Reparo pós-CTS | sem violação de setup; 382 pontos de hold, 383 buffers | `RSZ-0098/0046/0032`, passo 91 |

### Timing com o fio do roteamento global (STA, passo 97, TT)

| Métrica | Fim da CTS (92) | Com o fio do GRT (97) | Fonte |
|---|---|---|---|
| Setup WS | +1,57 ns | **+1,13 ns**, 0 violações | métricas |
| Hold WS | +0,099 ns | **+0,088 ns**, 0 violações | idem |
| Skew de setup | — | 0,72 ns | idem |
| Utilização das células | 0,598 | 0,600 | idem |

### ⚠️ Transição e capacitância com o fio real: 230 e 11 no TT

Com o fio do GRT (antes era fio estimado pela distância), a checagem de
transição (`97-…/checks.rpt`) acusa 230 pinos:

| Origem | Pinos | Exemplo |
|---|---|---|
| Pinos de entrada das macros (o limite de 40 ps do `.lib` da OpenRAM, L28) | 67 | — |
| **Células da ISFFT** | **163** | `u_isfft.inst_isfft_matriz.g247863/B2`: 3,35 ns, limite 0,75 ns |

E 11 de capacitância (saídas de células da ISFFT e alguns `dout` das
macros). As 163 são **reais**: redes com fio longo que só agora apareceram.
O passo que repara isso com o fio do GRT, `OpenROAD.RepairDesignPostGRT`,
estava **desligado** (`RUN_POST_GRT_DESIGN_REPAIR`, padrão `false` no
`classic.py`, marcado como "experimental"). Por isso o trecho só teve 5
passos (93–97): `RepairDesignPostGRT`, `HeuristicDiodeInsertion` e
`ResizerTimingPostGRT` estão atrás de chaves desligadas.

**Decisão (L32):** `"RUN_POST_GRT_DESIGN_REPAIR": true`. Custa refazer o
roteamento global (~12 min com antenas) antes do detalhado. Se travar
(o LibreLane avisa que pode), voltar para `false` e tratar a transição
depois do roteamento detalhado. `RUN_POST_GRT_RESIZER_TIMING` fica
desligado: o setup do TT já fecha com +1,13 ns.

### 🐛 Imagens trocadas no rebase

**Sintoma:** depois do `git pull --rebase`, as imagens **novas** do 02 ao
05 (DMEM no canto) apareceram dentro de `imagens/antes_L31/`, por cima
das antigas, e `imagens/` ficou sem elas.
**Causa:** o meu commit tinha **movido** as imagens para `antes_L31/`; o
do Lukas **modificava** os mesmos nomes. O git detecta o movimento e
aplica a modificação no caminho novo — sem conflito, sem aviso.
**Resolvi com:** as novas tiradas do commit `4d00d69` de volta para
`imagens/`; as antigas tiradas do `ebcc2c8` de volta para `antes_L31/`
(conferido: a planta antiga é idêntica, byte a byte, à de 30/09).
**Lição:** antes de refazer etapas, guardar o "antes" por **cópia** no
mesmo commit em que o Lukas sobe as novas, ou pedir para ele copiar
antes de rodar.
**Vira slide?** Não.

### Para continuar

```bash
git pull
bash layout/nucleo/06_roteamento.sh       # sem ATE_GLOBAL: global de novo (com o reparo) + detalhado
bash layout/nucleo/junta_logs.sh          # e o git add/commit que ele imprime
```
O detalhado (TritonRoute) é o passo mais longo do fluxo: dezenas de
minutos a algumas horas com 4 núcleos. Critério: `Number of violations = 0`
na última iteração, e `Checker.TrDRC` sem erro.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L31 | DMEM no canto | 🟡 funcionou: excesso 2.038 → 0, fio −14 % | — |
| L32 | Reparo de transição/capacitância depois do GRT (`RUN_POST_GRT_DESIGN_REPAIR`) | 🟡 | 163 pinos de células com transição de até 3,35 ns (limite 0,75) com o fio do GRT |

---

## 2026-10-06 (22ª sessão) — 🐛 Etapa 6: o reparo pós-GRT funcionou; o de antena caiu com `GRT-0183`

Rodada `2026-09-30_0934`, passos `98-…` a `102-…`. Fonte:
`logs_2026-10-06_1552.tar.gz` (commit `7e9b7fa`).

### L32 funcionou

| Passo | Resultado | Fonte |
|---|---|---|
| 98 `GlobalRouting` | passou (mesmo estado do 93) | log do 98 |
| 99 `CheckAntennas` | 804 redes / 1.006 pinos (igual ao 94) | `ANT-0001/0002` |
| **100 `RepairDesignPostGRT`** (L32) | 155 violações de transição e 19 de capacitância encontradas → **38 buffers em 144 redes, 82 células redimensionadas** | `RSZ-0034/0036/0038/0039` |
| 101 `DiodesOnPorts` | — | — |
| 102 `RepairAntennas` | **caiu** | abaixo |

### 🐛 `[ERROR GRT-0183] Net clknet_leaf_861_clk_i_regs: heap underflow during 3D maze routing`

**Sintoma:** o reparo de antena (`repair_antennas … -iterations 3`)
caiu na 1ª iteração, ao re-rotear as redes alteradas:

| | Rodada que passou (96, sem L32) | Esta (102, com L32) |
|---|---|---|
| Violações no início | 920 | 915 |
| Jumpers (troca de camada no fio) | 908 em 720 redes | 908 em 726 redes |
| Violações depois dos jumpers | 342 | 306 |
| Diodos | 834 | 771 |
| Re-roteamento depois dos diodos | ok (195 → 18 → 12 → 1 → 0 nas iterações) | **`GRT-0183`** numa rede da árvore de relógio |
| Tempo | 6 min 56 s | 6 min 05 s até cair |

**Causa:** erro interno do roteador global do OpenROAD (o FastRoute ficou
sem candidatos — "heap underflow" — no roteamento em labirinto 3D de uma
rede). Não é erro de configuração nem de projeto: o mesmo procedimento
passou na rodada anterior, e a diferença é só o estado de entrada (os 38
buffers e 82 células do reparo pós-GRT). A rede é uma folha da árvore de
relógio (`clknet_leaf_861…`), que recebeu jumpers na 1ª fase.
**Resolvi com (L33, tentativa):** `"GRT_ANTENNA_REPAIR_DIODE_ONLY": true`
— só diodos, sem jumpers. O jumper muda a topologia do fio (sobe de
camada perto do pino) e exige re-rotear a rede no labirinto 3D; o diodo
só acrescenta uma célula ligada à rede. Menos re-roteamento, menos chance
de cair no mesmo erro. Custo: mais diodos (área e um pouco de capacitância
nas redes).
**Plano B**, se cair de novo: `RUN_POST_GRT_DESIGN_REPAIR` de volta para
`false` (o caminho que já passou, 21ª sessão) e tratar as 163 transições
depois do roteamento detalhado.
**Vira slide?** Talvez: "ferramenta aberta também quebra — e o log diz em
que rede".

### Para continuar

```bash
git pull
bash layout/nucleo/06_roteamento.sh
bash layout/nucleo/junta_logs.sh     # e o git add/commit que ele imprime
```

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L32 | Reparo pós-GRT | 🟡 funcionou (155 + 19 violações reparadas) | — |
| L33 | Reparo de antena só com diodos (`GRT_ANTENNA_REPAIR_DIODE_ONLY`) | 🟡 tentativa | `GRT-0183` no re-roteamento depois dos jumpers/diodos |

---

## 2026-10-07 (23ª sessão) — ✅ Etapa 6 passou: roteamento detalhado com 0 violações

Rodada `2026-09-30_0934`, passos `103-…` a `116-…`. Fontes:
`06_roteamento.txt`, `06_roteamento_metricas.json`,
`logs_2026-10-07_0821.tar.gz`, imagens `06_roteamento_*` (commit
`4ab3bbc`).

### Antes do detalhado (passos 103–108)

| Passo | Resultado | Fonte |
|---|---|---|
| 103 roteamento global | 0 de excesso (igual ao 93) | log |
| 105 reparo pós-GRT (L32) | fio 5,479 → 5,482 m; 6 min 13 s | métricas, `runtime.txt` |
| 107 reparo de antena **só com diodos (L33)** | 915 → 159 → 7 → 1 violações; **1.833 + 251 + 7 diodos**; 3 min 14 s, **sem `GRT-0183`** | `GRT-0012/0015` |
| 108 STA com o fio do GRT (TT) | setup +1,11 ns, hold +0,083 ns, 0 violações | métricas |

A L33 contornou o erro do OpenROAD.

### Roteamento detalhado (TritonRoute, passo 109)

| Item | Valor | Fonte |
|---|---|---|
| **Violações de roteamento (DRV) no fim** | **0** | `route__drc_errors` |
| Violações por iteração | 169 → 88 → 62 → 49 → 49 → **0** (5ª); na fase seguinte 299 → 278 → … → 33 → 5 → 4 → 2 → 1 → **0** (22ª e 23ª) | `route__drc_errors__iter:*` |
| Fio desenhado | **3,99 m** (o GRT estimava 5,48 m) | `route__wirelength` |
| Fio mais longo | 1.878 µm | `route__wirelength__max` |
| Vias | 710.304, todas de corte simples | `route__vias*` |
| Redes | 77.293 (+ 2 de alimentação) | `route__net*` |
| **Tempo** | **4 h 45 min** | `runtime.txt` |

O roteador limpa as violações em fases: depois de zerar na 5ª iteração,
ele recomeça uma fase de otimização (as violações sobem para 299 e voltam
a cair) e termina com 0. O fio real ficou 27 % menor que a estimativa do
GRT (que conta os ladrilhos, não o caminho exato).

### Checagens do fim da etapa (passos 111–116)

| Checagem | Resultado | Fonte |
|---|---|---|
| `Checker.TrDRC` | passou (0 DRV) | passo 112 |
| Pinos desconectados (`Checker.DisconnectedPins`) | **0** (0 críticos) | `design__disconnected_pin__count` |
| `Checker.WireLength` | passou | passo 116 |
| Antena depois do detalhado | **1 rede, 1 pino**: `net8308`, pino `fanout8295/A`, met2, razão 487,9 para 400 permitidos (1,22×) | `111-…/reports/antenna_summary.rpt` |
| Diodos de antena no chip | 2.359 células, 5.903 µm² | métricas |
| Instâncias / utilização das células | 99.704 / 0,602 | métricas |

A violação de antena que sobrou é pequena (22 % acima) e numa rede só; o
checker de antena não reprova o fluxo. Fica registrada; se quiser zerar,
um diodo nessa rede resolve (a decidir depois do DRC/LVS, etapa 8).

### Timing ainda com o fio do GRT (STA 108, TT)

| | Valor |
|---|---|
| Setup / hold | +1,11 / +0,083 ns, 0 violações |
| Transição | 93 (64 em pinos das macros, L28; 29 em células) |
| Capacitância | 5 |
| Fanout | 1.472 (árvore de relógio, L28) |

O número que vale é o da etapa 7, com os parasitas **extraídos** do fio
desenhado (RCX).

**Vira slide?** Sim: "4 h 45 min, 710 mil vias, 0 violações" e a curva
de violações por iteração.

### Etapa 7 — script `07_sta.sh` (escrito, não rodado)

| Passo | O que faz |
|---|---|
| `OpenROAD.FillInsertion` | células de preenchimento nos buracos das linhas |
| `Odb.CellFrequencyTables` | contagem de células por tipo |
| `OpenROAD.RCX` | extrai R e C do fio desenhado (SPEF por corner de RC) |
| `OpenROAD.STAPostPNR` | STA final nos 9 corners — decide a **L27** (hold no FF) |
| `OpenROAD.IRDropReport` | queda de tensão (indicativa: sem pads) |

O `07_sta.txt` sai com uma tabela por corner (setup, hold, transição,
capacitância).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L33 | Antena só com diodos | 🟡 funcionou (sem `GRT-0183`) | — |
| L34 | 1 violação de antena restante (`net8308`, 1,22×) aceita por ora | 🟡 | Uma rede; decidir junto com o DRC/LVS |

## 2026-10-07 (24ª sessão) — ⚠️ Etapa 7: com o fio extraído, setup do TT −0,10 ns e hold do FF −0,11 ns

Rodada `2026-09-30_0934`, passos `117-…` a `121-…`. Fontes: `07_sta.txt`,
`07_sta_metricas.json`, `logs_2026-10-07_0832.tar.gz` (`120-openroad-
stapostpnr/summary.rpt`, `*/violator_list.rpt`, `*/clock.rpt`,
`*/power.rpt`; `121-…/irdrop.rpt`), imagem `07_final.png` (commit
`2225af1`). O fluxo não parou: os checkers de timing só rodam no fim do
fluxo (depois do LVS, etapa 8) — lá **reprovariam**.

### Passos e tempos

| Passo | Resultado | Tempo | Fonte |
|---|---|---|---|
| 117 `FillInsertion` | 141.258 células de preenchimento (142.300 com as que já havia) | 10 s | `DPL-0001`, `runtime.txt` |
| 118 `CellFrequencyTables` | tabelas de células | — | `118-…/cell.rpt` |
| 119 `RCX` | SPEF min/nom/max do fio desenhado | 37 s | `runtime.txt` |
| 120 `STAPostPNR` | 9 corners (tabela abaixo) | 2 min 3 s | `summary.rpt` |
| 121 `IRDropReport` | número sem sentido (ver abaixo) | 38 s | `irdrop.rpt` |

### Timing por corner com os parasitas extraídos

| Corner | Setup WS (ns) | Viol. setup | Hold WS (ns) | Viol. hold | fmax (MHz) |
|---|---|---|---|---|---|
| min_tt | +0,262 | 0 | +0,048 | 0 | 50,66 |
| **nom_tt** | **−0,096** | **1** | +0,036 | 0 | **49,76** |
| **max_tt** | **−0,368** | **2** | +0,029 | 0 | **49,10** |
| min_ff | +7,36 | 0 | **−0,076** | **179** | 85,77 |
| nom_ff | +7,26 | 0 | **−0,096** | **174** | 83,99 |
| max_ff | +7,13 | 0 | **−0,112** | **176** | 82,70 |
| min_ss | −21,84 | 1.372 | +0,410 | 0 | 23,90 |
| nom_ss | −22,51 | 1.469 | +0,400 | 0 | 23,53 |
| max_ss | −23,01 | 1.571 | +0,380 | 0 | 23,25 |

(`summary.rpt`; fmax = `report_clock_min_period` de cada `clock.rpt`)

**Leitura:** o relógio de 50 MHz fecha "no fio da navalha" no TT. O
mesmo chip faz ~84 MHz no FF (rápido, frio, 1,95 V) e ~23 MHz no SS (lento,
quente, 1,60 V): **um fator 3,6** entre os cantos do processo.

### 🐛 Setup do TT: +1,11 ns com o fio estimado → −0,10 ns com o fio extraído

- **Sintoma:** no STA 108 (fio do GRT, etapa 6) o setup do nom_tt tinha
  +1,113 ns; no STA final, −0,096 ns (nom) e −0,368 ns (max). 1 e 2
  caminhos violando.
- **Causa:** o caminho é **o mesmo** da síntese: controle da CPU
  (`n7868_q_reg[16]`) → multiplicador/divisor (`n12685_q_reg[63]` e
  `[62]`), a subtração de 32 bits em *ripple carry* (tabelas da síntese,
  §5). A estimativa do GRT não conta o acoplamento entre fios vizinhos; o
  RCX conta. Diferença medida: **1,21 ns** (nom) a ~1,5 ns (max) num
  caminho de ~15 ns (≈ 8–10 %). Na síntese a folga era +2,41 ns, mas com
  2 ns de incerteza de relógio; o layout usa 0,25 ns e a árvore de relógio
  real (latência 2,39–3,36 ns, skew 0,98 ns no nom_tt).
- **Resolvi com (L36, proposta):** ligar o `OpenROAD.ResizerTimingPostGRT`
  (`RUN_POST_GRT_RESIZER_TIMING`) com **margem de setup de 1,5 ns**
  (`GRT_RESIZER_SETUP_SLACK_MARGIN`): o resizer, vendo o fio estimado,
  conserta até sobrar 1,5 ns — o tamanho do erro da estimativa. No caminho
  em *ripple carry*, o esperado é ele trocar `fa_1` por `fa_2`/`fa_4`.
- **Tempo:** 20 min de análise.
- **Vira slide?** Sim: "o fio estimado mente ~1,2 ns" — estimado × extraído
  no mesmo caminho.

### 🐛 Hold no FF: 529 violações (176–179 por corner), pior −0,112 ns

- **Sintoma:** os 3 corners FF com hold negativo; o checker de hold do
  sky130 reprova em **qualquer** corner (17ª sessão).
- **Causa:** a L26 tirou o FF do reparo (`RSZ_CORNERS` só TT). No FF as
  células são rápidas e o dado chega cedo demais. Onde (`max_ff`,
  `violator_list.rpt`):

| Bloco (destino) | Violações |
|---|---|
| núcleo Spiral da ISFFT (`inst_isfft_matriz`: FFT/IFFT, registradores de *pipeline*) | 151 |
| CPU / SoC NEORV32 | 16 |
| wrapper da ISFFT (`ob_q0/ob_q1`, `reserved`: saída do `out_mem`) | 8 |
| conversor `u_up` | 1 |
| **Total** | **176** |

  O pior: `ob_q1_reg[32]` → `ob_q0_reg[32]` (−0,112 ns), registradores
  vizinhos, sem lógica no meio; o skew de hold do relógio é −1,47 ns no
  nom_tt (`skew.min.rpt`).
- **Resolvi com (L27 → opção A, proposta):** `RSZ_CORNERS` = TT + FF.
  São só ~180 destinos e −0,11 ns: poucos buffers de atraso. Margem de
  hold 0,1 ns (`GRT_RESIZER_HOLD_SLACK_MARGIN`; o padrão é 0,05 e o fio
  extraído tirou ~0,05 ns do hold do TT: +0,083 → +0,036).
- **Por que não a B** (relatar só o TT): hold não depende do período —
  um hold violado no FF quebra o chip em **qualquer** frequência. Setup no
  SS se resolve baixando o relógio; hold, não.
- **Vira slide?** Sim: setup × hold, "um se resolve com relógio mais lento,
  o outro não".

### SS fora (L35)

Setup no SS de −22 a −23 ns: o chip faria 23 MHz nesse canto. Fazer
50 MHz no SS exigiria refazer a CPU (o pior caminho precisa de 43,0 ns
no max_ss, `report_clock_min_period`). O checker de setup do sky130 só olha o TT
(`TIMING_VIOLATION_CORNERS = ["*tt*"]`); o SS fica **relatado**, com a
fmax por corner na tabela acima.

### Potência e 🐛 IR drop sem sentido

| Grupo (nom_tt, sem atividade de simulação) | Potência |
|---|---|
| Registradores | 39,5 mW |
| Árvore de relógio | 28,7 mW |
| Combinacional | 1,0 mW |
| **Lógica (sem macros)** | **~69 mW** |
| Macros | **75,8 MW** ← impossível |

(`120-…/nom_tt_025C_1v80/power.rpt`)

- **Sintoma:** queda de tensão de pior caso de **8,9 × 10⁶ V** em 1,8 V
  (`irdrop.rpt`, "494487040 %").
- **Causa:** a mesma pendência herdada do front-end: o `.lib` das macros
  da OpenRAM tem `internal_power` fora de escala (na síntese: 2.767 W). O
  PDNSim distribui essa potência na grade e o resultado é lixo. A grade
  em si está ligada: `PSM-0040 All shapes on net vccd1/vssd1 are
  connected`.
- **Resolvi com (L37, proposta):** IR drop do LibreLane **não vale** até
  corrigir a potência das macros. Fica como pendência (dá para refazer só
  o PDNSim com `set_pdnsim_inst_power` nas 4 macros). Não bloqueia o GDSII.
- **Vira slide?** Sim, como lição: "número absurdo → olhar a entrada, não
  a ferramenta".

### Contagens do chip pronto (fim da etapa 7)

| Item | Valor |
|---|---|
| Instâncias | 240.962 (98.658 células lógicas + 142.300 preenchimento + 4 macros) |
| Buffers de reparo de timing | 13.064 (383 de hold) |
| Árvore de relógio | 3.045 buffers + 122 inversores |
| Diodos de antena | 2.359 |
| Utilização (com macros / só células) | 77,5 % / 60,2 % |
| Fio | 3,99 m; 1 violação de antena (L34) |

(`07_sta_metricas.json`)

### Reparo: `REPARO=1 bash layout/nucleo/07_sta.sh`

Volta ao estado do passo 107 (fim do reparo de antena, etapa 6) e roda
de novo `ResizerTimingPostGRT` → `STAMidPNR-3` → roteamento detalhado
(~5 h) → etapa 7. Não refaz CTS nem posicionamento: o reparo pós-GRT é o
último ponto em que o OpenROAD ainda insere células antes do fio
desenhado.

| Mudança no `config.json` | Valor | Decisão |
|---|---|---|
| `RSZ_CORNERS` | 3 TT + **3 FF** | L27 (A) |
| `RUN_POST_GRT_RESIZER_TIMING` | `true` | L36 |
| `GRT_RESIZER_SETUP_SLACK_MARGIN` | **1,5 ns** (padrão 0,025) | L36 |
| `GRT_RESIZER_HOLD_SLACK_MARGIN` | 0,1 ns (padrão 0,05) | L27 |

Saída: `07_sta_reparo.txt`, `07_sta_reparo_metricas.json`,
`imagens/07_reparo_final.png`; os arquivos da 1ª rodada ficam para a
tabela antes × depois. Conferir: setup ≥ 0 nos 3 TT, hold ≥ 0 nos 6
TT/FF, DRV = 0 de novo, antena.

Riscos: (1) a margem de 1,5 ns pode fazer o resizer mexer em muitos
caminhos da CPU (o limite é `GRT_RESIZER_SETUP_MAX_BUFFER_PCT` = 50 %);
(2) o passo refaz o GRT depois do reparo — o `GRT-0183` da 22ª sessão
foi no reparo de antena, não no GRT completo.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L27 | Hold no FF: **A** (FF no `RSZ_CORNERS`, margem 0,1 ns) | 🟡 | Hold não melhora com relógio mais lento; 176 destinos, −0,11 ns |
| L35 | SS fora do reparo; só relatado (fmax 23 MHz) | 🟡 | 50 MHz no SS exige outra CPU; o checker olha só o TT |
| L36 | `ResizerTimingPostGRT` ligado com margem de setup de 1,5 ns | 🟡 | Estimado × extraído: −1,21 ns no mesmo caminho |
| L37 | IR drop do LibreLane não vale até corrigir a potência das macros | 🟡 | 75,8 MW nas macros (`.lib` da OpenRAM) |

## 2026-10-08 (25ª sessão) — 🐛 Reparo pós-GRT: o hold com margem de 0,1 ns inseriu buffers até congestionar (`GRT-0232`)

`REPARO=1 bash layout/nucleo/07_sta.sh`, passo
`122-openroad-resizertimingpostgrt`. Fonte:
`logs_2026-10-07_2329.tar.gz` (`openroad-resizertimingpostgrt.log`,
`*.process_stats.json`, commit `711dc9c`). Parou no próprio passo 122: o
roteamento detalhado nem começou.

### O que deu certo: setup (L36)

| | Antes | Depois | Fonte |
|---|---|---|---|
| Destinos com setup < 1,5 ns (fio do GRT, 6 corners) | 2 | 0 | `RSZ-0094`, tabela de setup |
| Pior folga de setup (estimada) | +1,127 ns | **+1,567 ns** | idem |
| O que o resizer fez | — | **8 células aumentadas** (`RSZ-0051`), 0 buffers, 9 iterações | idem |

Os 2 destinos são os do multiplicador/divisor (`n12685_q_reg[63]`/`[62]`).
Com 1,5 ns de folga estimada, o fio extraído (−1,2 a −1,5 ns) deve deixar
o TT ≥ 0 — confirma no STA final.

### 🐛 O que deu errado: hold

- **Sintoma:** `[ERROR GRT-0232] Routing congestion too high`, depois de
  **1 h 16 min** no passo (`process_stats.json`).
- **Causa:** com margem de hold de 0,1 ns nos 6 corners (TT + FF), o
  resizer achou **18.041 destinos** abaixo da margem (`RSZ-0046`) — quase
  todos os registradores do núcleo Spiral, ligados Q → D quase direto.
  Progresso do reparo (tabela de hold do log):

| Iteração | Pior folga de hold (estimada) | Soma negativa (TNS) | Área a mais |
|---|---|---|---|
| 0 | −0,054 ns | −2,73 ns | 0 |
| 100 | −0,011 ns | −0,38 ns | +0,1 % |
| ~190 | **≥ 0** | 0 | **+0,1 %** (~300 buffers) |
| 1.220 | +0,028 ns | 0 | +0,8 % |
| 14.600 | +0,028 ns (parada) | 0 | **+7,4 %** |

  Zerar a violação **real** custou ~300 buffers. Os outros ~14.000 foram
  para tentar pôr 18 mil caminhos acima de **+0,1 ns**; a pior folga
  travou em +0,028 ns (o reparo de hold não pode estragar a margem de
  setup de 1,5 ns) e os buffers foram enchendo o chip até o roteamento
  global de dentro do reparo não fechar.
- **Resolvi com (L38, proposta):** margem de hold **0,05 ns** (o padrão
  do LibreLane) e **teto de 2 % de buffers**
  (`GRT_RESIZER_HOLD_MAX_BUFFER_PCT`; o padrão é 50 %). 2 % das ~99 mil
  células ≈ 2.000 buffers ≈ +0,8 % de área — a esse ponto o GRT ainda
  estava sem excesso. Com o teto, o reparo para com um aviso em vez de
  entupir o chip.
- **Por que 0,05 e não 0:** o fio extraído tirou ~0,06 ns do hold no FF
  (estimado −0,054 × RCX −0,112 ns). Margem zero deixaria o FF negativo
  de novo. Se ainda sobrar violação pequena no STA final, ela aparece na
  tabela por corner e decidimos lá.
- **Tempo:** 1 h 16 min de máquina + 15 min de análise.
- **Vira slide?** Sim: "margem de hold é cara" — 0,1 ns de margem custou
  50 × mais buffers que a violação real (14.600 × 300).

### Para continuar

```
git pull
REPARO=1 bash layout/nucleo/07_sta.sh     # de novo do passo 107; ~5–6 h
bash layout/nucleo/junta_logs.sh
```

No log do passo `ResizerTimingPostGRT` (sai em ~30 min), conferir:
`RSZ-0046` (quantos destinos), a pior folga de hold chegando a ≥ 0 e,
se aparecer, `RSZ-0060` (teto de buffers atingido — esperado, não é
erro).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L36 | Margem de setup de 1,5 ns no pós-GRT | 🟡 funcionou (8 células, +1,567 ns estimado) | — |
| L38 | Hold pós-GRT: margem 0,05 ns + teto de 2 % de buffers | 🟡 | Com 0,1 ns: 18.041 destinos, +7,4 % de área, `GRT-0232` |

## 2026-10-09 (26ª sessão) — 🐛 Reparo pós-GRT de novo com `GRT-0232`: o teto de buffers não segura, a margem é que não converge

`REPARO=1` rodou **duas vezes** (passos `123-…` e `124-…`, 53 min e
59 min), as duas com o mesmo erro. Fonte: `logs_2026-10-09_1524.tar.gz`
(`124-…/openroad-resizertimingpostgrt.log`, `*.process_stats.json`,
commit `8affe3e`).

### O que repetiu

| | 25ª sessão (margem 0,1) | 26ª sessão (margem 0,05 + teto 2 %) | Fonte |
|---|---|---|---|
| Setup | 8 células, +1,567 ns | igual | `RSZ-0051` |
| Destinos de hold abaixo da margem | 18.041 | 15.260 | `RSZ-0046` |
| Pior folga de hold ≥ 0 | iteração ~190 | iteração ~190 | tabela de hold |
| Pior folga ≥ +0,025 ns | — | **iteração 790** (+0,5 % de área) | idem |
| Pior folga trava em | +0,028 ns | **+0,028 ns** (desde a iteração 1.110) | idem |
| Parou em | 14.600 iterações, +7,4 % | 13.060 iterações, +6,5 % | idem |
| Erro | `GRT-0232` | `GRT-0232` (+ `GRT-0704`: sugere baixar o ajuste de camada de 30 % para 21 %) | idem |

### 🐛 Por que o teto de 2 % não funcionou

- **Sintoma:** com `GRT_RESIZER_HOLD_MAX_BUFFER_PCT = 2` (≈ 2.000
  buffers), a área subiu +6,5 % (bem mais que 2.000 buffers).
- **Causa (lida no log):** a coluna "Buffers" da tabela de hold **volta a
  zero 81 vezes** — o reparo trabalha em passadas e o contador é da
  passada. O maior valor em uma passada foi 1.349, nunca chegou a 2.000.
  O teto vale por passada, não para o reparo inteiro.
- **A causa de verdade (dos dois erros):** a pior folga trava em
  **+0,028 ns** (destino `…stage5.instPerm7842.memSys.memMod1.mem_reg[4][13]`)
  e o reparo só para quando **todos** os destinos passam da margem. Com
  margem 0,1 ou 0,05 ns ele **nunca termina**: fica dando passadas,
  pondo buffer em outros caminhos, até o roteamento global não fechar.
- **Resolvi com (L39, proposta):** margem de hold **0,02 ns**, abaixo do
  ponto em que trava (+0,028). Pelo log, a pior folga passa de +0,02 ns
  por volta da iteração 590 (+0,4 % de área) — o reparo deve terminar
  sozinho ali. Tirei o teto (não servia).
- **O que fica em risco:** o fio extraído tirou ~0,06 ns do hold no FF
  (24ª sessão). Com margem 0,02 ns, alguns caminhos podem ficar até
  ~−0,04 ns no STA final. Se ficarem, a decisão é no STA final: poucos
  caminhos → reparo pós-roteamento (`repair_timing -hold` no `.odb` final
  + ECO do roteador) ou aceitar como limite do modelo.
- **Tempo:** ~1 h 52 min de máquina nas duas tentativas + 15 min de
  análise.
- **Vira slide?** Sim: "o otimizador não para sozinho se a meta for
  impossível" — a margem tem que ser alcançável.

### Para continuar

```
git pull
REPARO=1 bash layout/nucleo/07_sta.sh
```

Uns 15 min depois de começar (10 min de GRT + reparo), conferir no log do
`ResizerTimingPostGRT`: a tabela de hold termina com `final` e o passo
segue para o `STAMidPNR-3`. Se em 30 min a coluna "Area" passar de +1 %,
interromper (Ctrl+C) e me mandar o log.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L38 | ~~Hold pós-GRT: margem 0,05 ns + teto de 2 %~~ → L39 | ❌ não convergiu | Teto vale por passada; pior folga trava em +0,028 ns |
| L39 | Hold pós-GRT: margem **0,02 ns**, sem teto | 🟡 | Abaixo do ponto de trava (+0,028 ns) |

## 2026-10-09 (27ª sessão) — ✅ Reparo pós-GRT com a L39: TT fecha com folga; sobram 15 holds de ≤ 28 ps no FF

`REPARO=1 bash layout/nucleo/07_sta.sh`, passos `125-…` a `139-…`.
Fontes: `07_sta_reparo.txt`, `07_sta_reparo_metricas.json`,
`logs_2026-10-09_1803.tar.gz` (`125-…/openroad-resizertimingpostgrt.log`,
`138-…/*/violator_list.rpt`, `*/clock.rpt`, `*/skew.min.rpt`), imagem
`07_reparo_final.png` (commit `7f158ce`).

### O reparo (passo 125)

| Item | Valor | Fonte |
|---|---|---|
| Setup | 8 células aumentadas; +1,567 ns estimado | `RSZ-0051` |
| Hold: destinos abaixo de 0,02 ns | **585** (com 0,05: 15.260; com 0,1: 18.041) | `RSZ-0046` |
| Hold: buffers inseridos | **242**, +0,3 % de área; pior folga estimada +0,020 ns | `RSZ-0032`, linha `final` |
| Tempo do passo | **15 min** (as 3 tentativas anteriores: 53–76 min cada) | `runtime.txt` |

A L39 funcionou: com a margem alcançável o reparo **termina sozinho**.

### Roteamento detalhado e checagens (passos 126–134)

| Item | 1ª rodada (23ª sessão) | Com o reparo | Fonte |
|---|---|---|---|
| DRV no fim | 0 | **0** | `route__drc_errors` |
| Tempo do TritonRoute | 4 h 45 min | **2 h 05 min** | `runtime.txt` |
| Fio | 3,99 m | 3,96 m | `route__wirelength` |
| Antena depois do detalhado | 1 (`net8308`, L34) | **0** | `CheckAntennas-1` |
| Diodos de antena | 2.359 | 2.773 | métricas |
| Pinos desconectados | 0 | 0 | métricas |
| Células lógicas | 98.658 | 99.718 | métricas |

A violação de antena da L34 sumiu sozinha: o roteamento mudou e ela não
voltou. Por que o detalhado levou menos da metade do tempo não dá para
afirmar pelos logs (as violações por iteração mudaram de perfil); fica
como observação.

### STA final com o fio extraído (passo 138) — antes × depois

| Corner | Setup antes | **Setup depois** | Hold antes | **Hold depois** | fmax depois |
|---|---|---|---|---|---|
| min_tt | +0,262 | **+0,858** | +0,048 | **+0,139** | 52,24 MHz |
| nom_tt | −0,096 (1) | **+0,562** | +0,036 | **+0,134** | 51,45 MHz |
| max_tt | −0,368 (2) | **+0,320** | +0,029 | **+0,128** | 50,81 MHz |
| min_ff | +7,36 | +7,47 | −0,076 (179) | **−0,012 (7)** | 88,80 MHz |
| nom_ff | +7,26 | +7,37 | −0,096 (174) | **−0,015 (9)** | 87,22 MHz |
| max_ff | +7,13 | +7,27 | −0,112 (176) | **−0,028 (15)** | 85,98 MHz |
| min/nom/max_ss | −21,8 / −22,5 / −23,0 | −20,7 / −21,2 / −21,7 | > +0,38 | > +0,54 | 24,0–24,6 MHz |

(ns; entre parênteses, caminhos violando. `07_sta.txt` × `07_sta_reparo.txt`;
fmax de `report_clock_min_period`)

**Leitura:** o TT, que é o que o checker de setup olha, fechou com
**+0,32 ns** no pior corner de RC. Estimado × extraído no setup agora:
+1,63 → +0,56 ns (−1,07 ns), coerente com a 24ª sessão. O hold do FF
caiu de 529 para **31 violações** (15 destinos diferentes), a pior de
**−28 ps**.

### Os 15 holds que sobraram (max_ff)

| Onde | Destinos | Pior |
|---|---|---|
| SLINK TX → conversor `u_up` (`m_data_o`) e `u_up` interno | 4 | −28 ps |
| Núcleo Spiral (FFT estágios 0, 1, 6; IFFT estágio 8) | 8 | −22 ps |
| CPU: SYSINFO → barramento; gerador de relógio do SoC | 3 | −21 ps |
| Ponte XBUS→AXI → `u_isfft.w_data` | 1 | −1 ps |

(`138-…/max_ff_n40C_1v95/violator_list.rpt`)

### 🟡 L40: aceitar os 15 holds de ≤ 28 ps (por ora)

- **Por que é aceitável:** o SDC do layout põe **0,25 ns de incerteza de
  relógio também no hold** (`skew.min.rpt`: "−0,250000 clock
  uncertainty"). Uma folga de −0,028 ns quer dizer que o caminho ainda
  tem +0,22 ns de sobra antes de o dado chegar cedo demais **de
  verdade**, no canto mais rápido do processo.
- **O custo de não aceitar:** reparo de hold **depois** do roteamento
  (ECO: `repair_timing -hold` com os parasitas extraídos + roteamento
  incremental). O Classic do LibreLane não tem esse passo; seria um
  script nosso.
- **Consequência no fluxo:** o `Checker.HoldViolations` olha todos os
  corners e vai **reprovar no fim da etapa 8**. É um erro adiado: o fluxo
  roda tudo (GDS, DRC, LVS) e só então lista. Não escondi o checker.
- **Vira slide?** Sim: "−28 ps dentro de 250 ps de margem".

### Etapa 8 — script `08_verificacao.sh` (escrito, não rodado)

| Passo | O que faz |
|---|---|
| `Magic.StreamOut` / `KLayout.StreamOut` | o GDS do chip, por duas ferramentas |
| `KLayout.Render` | PNG do GDS → `imagens/08_gds_klayout.png` |
| `Magic.WriteLEF` | LEF do núcleo (para o padring, etapa 11) |
| `KLayout.XOR` + checker | os dois GDS têm de ser iguais |
| `Magic.DRC` + checker | DRC com as macros como caixa-preta (DEF + LEF, `MAGIC_DRC_USE_GDS` false, L3) |
| `KLayout.DRC` | **desligado** (L41): lê o miolo das macros da OpenRAM (~1,2 milhão de erros conhecidos, L3) |
| `Magic.SpiceExtraction` + `Netgen.LVS` + checker | layout × Verilog, macros como caixa-preta |
| `Checker.IllegalOverlap` | células sobrepostas |
| `Checker.Setup/HoldViolations`, `MaxSlew/MaxCap` | veredito do timing (hold do FF reprova, L40) |
| `Misc.ReportManufacturability` | resumo DRC/LVS/antena |

Sai `08_verificacao.txt` (métricas de DRC/LVS/XOR, resumo dos logs,
`manufacturability.rpt`, fim do `error.log`) e `08_verificacao_metricas.json`.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L39 | Hold pós-GRT: margem 0,02 ns | 🟡 funcionou (242 buffers, 15 min) | — |
| L40 | 15 holds de ≤ 28 ps no FF aceitos por ora | 🟡 | Dentro dos 0,25 ns de incerteza; ECO pós-roteamento fica como opção |
| L41 | `KLayout.DRC` desligado; DRC só pelo Magic com macros caixa-preta | 🟡 | Consequência da L3 |
| L34 | ~~1 violação de antena aceita~~ | ✅ resolvida sozinha (0 no reparo) | — |

## 2026-10-09 (28ª sessão) — Etapa 8: ✅ LVS passou; ⚠️ DRC 1.182 e XOR 15,7 milhões — os dois são da forma de olhar, não do desenho

`bash layout/nucleo/08_verificacao.sh`, passos `140-…` a `157-…`.
Fontes: `08_verificacao.txt`, `08_verificacao_metricas.json`,
`logs_2026-10-09_1924.tar.gz` (`147-magic-drc/reports/drc.magic.rpt`,
`145-klayout-xor/klayout-xor.log`, `141-…/klayout-streamout.log`,
`flow.log`, `154-…/state_in.json`), commit `7909258`.

### Veredito do fluxo

| Checagem | Resultado | Fonte |
|---|---|---|
| **LVS** (Netgen, layout × Verilog, macros caixa-preta) | ✅ **"Circuits match uniquely"**, 0 erros em todas as categorias | `151-…`, `design__lvs_*` |
| Antena | ✅ 0 | `manufacturability.rpt` |
| Células sobrepostas | ✅ 0 | `magic__illegal_overlap__count` |
| Rede de alimentação | ✅ 0 violações (vccd1, vssd1) | `design__power_grid_violation__count` |
| Setup (TT) | ✅ sem violação no TT; SS só aviso (L35) | `flow.log` |
| Hold | ❌ reprovou (esperado, L40): 15 + 9 + 7 no FF | `154-…/state_in.json`; o passo não grava `state_out` |
| Slew / cap | só avisos (todos os corners) | `flow.log` |
| **DRC (Magic)** | ⚠️ **1.182** | `magic__drc_error__count` |
| DRC (KLayout) | desligado (L41) | — |
| **XOR (Magic × KLayout)** | ⚠️ **15.679.857** diferenças | `design__xor_difference__count` |

| Passo | Tempo |
|---|---|
| `Magic.StreamOut` | 16 min 21 s |
| `KLayout.StreamOut` | 6 s |
| `KLayout.XOR` | 3 min 39 s |
| `Magic.DRC` | 5 min |
| `Magic.SpiceExtraction` | 1 min 55 s |
| `Netgen.LVS` | 37 s |

**O LVS passar é o resultado mais importante da etapa:** o desenho liga
exatamente o que o netlist do Genus manda (as macros como caixa-preta).

### 🐛 DRC: 1.182 erros, três tipos — nenhum é defeito do nosso desenho

| Regra | Caixas | Onde | Por quê |
|---|---|---|---|
| `nwell.4` (nwell sem tap N+ ligado a metal) | **1.052** | **todas** as linhas de células, em pedaços de ~315 µm (o ladrilho do DRC) | DRC sobre DEF + **LEF**: a célula padrão abstrata tem `nwell` (pino `VPB` no LEF) mas não tem a difusão do tap. Os 20 mil taps estão lá, o Magic é que não os vê |
| `met4.4a` (área mínima de met4) | 128 | 64 na borda de baixo da `in_mem` (y = 100) e 64 da `out_mem` (y = 1002) | pinos `dout0[0..63]` das macros 1rw1r: **saída da porta 0, que não usamos** (escrevemos pela 0, lemos pela 1). No LEF, cada pino é um quadrado de 0,38 × 0,38 µm (0,144 µm² < 0,24); sem fio ligado, o quadrado fica sozinho |
| `met3.6` (área mínima de met3) | 2 | x = 55 µm, na IMEM e na DMEM | pino `dout0[32]` das macros 1rw: o **33º bit** (L1, `spare_wen0`), que não tem uso |

(`drc.magic.rpt`; pinos conferidos no LEF: `sram_1rw1r_64x64_wpr2.lef`
`dout0[0]` = `RECT 170.465 0.0 170.845 0.38` em met4 = x 1.380,465 µm do
relatório; `sram_4kbyte_1rw_32x1024_8.lef` `dout0[32]` em met3,
orientação S)

O próprio script do LibreLane avisa: `[INFO] COUNT: 1182` / "Should be
divided by 3 or 4" — o Magic conta cada erro em mais de uma caixa.

- **Resolvi com (L42, proposta):** DRC de novo **no GDS**
  (`MAGIC_DRC_USE_GDS` true), com as macros como caixa-preta pela vista
  abstrata do Magic (`MAGIC_DRC_MAGLEFS`, que o `drc.tcl` do LibreLane
  carrega antes do GDS). Assim as células padrão entram **reais** (com os
  taps) e o miolo da OpenRAM continua de fora (L3). Script novo:
  `08_drc_gds.sh` (gera as 4 maglef a partir do LEF e roda só
  `Magic.DRC` + checker).
- **O que deve sobrar (L43, proposta):** os 130 quadradinhos dos pinos
  sem uso continuam no abstrato. No GDS real da macro o pino é parte de um
  fio interno maior — não é erro de fábrica. Ficam documentados como
  isenção (*waiver*), com a lista.
- **Vira slide?** Sim: "o DRC olha o que você mostra para ele" — abstrato
  × real, e por que 1.052 erros em todas as linhas eram um sinal de que o
  problema era a vista, não o desenho.

### 🐛 XOR: 15,7 milhões de diferenças entre o GDS do Magic e o do KLayout

- **Sintoma:** diferença em quase todas as camadas, sempre com o GDS do
  **Magic tendo mais** formas. Algumas camadas só existem no do Magic:

| Camada | Magic | KLayout | O que é |
|---|---|---|---|
| 33/42, 33/43 | 1.026.968 / 2.616.854 | 0 / 0 | camadas da célula de bit da OpenRAM |
| 22/21, 22/22 | 1.196.648 / 485.696 | 0 / 0 | idem |
| 235/0, 115/42, 115/43 | 127.920 / 200.208 / 400.416 | 0 | idem |
| 68/20 (met1) | 3.780.124 | 1.568.791 | metal 1 |
| 236/0, 67/16, 81/23 | iguais | iguais | — |

(`klayout-xor.log`, "Polygons (raw)" de cada entrada, contagem achatada)

- **Causa provável:** as camadas que faltam no do KLayout são exatamente
  as que o Magic avisou como "Unknown layer/datatype" ao ler o GDS da
  OpenRAM (`error.log`) — ou seja, existem **dentro das macros**. O Magic
  guarda o GDS da macro como veio (`gds readonly`); o KLayout, pelo jeito,
  não trouxe o miolo das macros (o `KLayout.StreamOut` levou 6 s e diz
  "All LEF cells have matching GDS cells"). Não dá para afirmar só pelos
  logs: os GDS (centenas de MB) ficam no notebook.
- **Diagnóstico (L44):** `diag_xor.sh` conta as formas por camada nos
  dois GDS separando **dentro das 4 macros** × **resto do chip** (contagem
  hierárquica, sem achatar: segundos). Se o "resto do chip" bater, o nosso
  desenho é igual nos dois e o XOR só acusa a leitura das macros.
  Testado aqui com um GDS sintético (`klayout` do pip).
- **Vira slide?** Talvez: "duas ferramentas, dois GDS" — por que o fluxo
  faz XOR.

### Para continuar

```
git pull
bash layout/nucleo/diag_xor.sh          # minutos
bash layout/nucleo/08_drc_gds.sh        # DRC no GDS (tempo ainda desconhecido)
bash layout/nucleo/junta_logs.sh
```

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L42 | DRC do Magic no GDS + macros caixa-preta por maglef | 🟡 | DEF + LEF dá alarme falso de `nwell.4` em todas as linhas |
| L43 | 130 erros de área mínima nos pinos sem uso das macros = isenção | 🟡 | Quadrados do LEF; no GDS da macro o pino é fio interno |
| L44 | Diagnóstico do XOR por contagem dentro/fora das macros | 🟡 | 15,7 milhões de diferenças, todas com cara de macro |

## 2026-10-10 (29ª sessão) — 🐛 XOR: o GDS do KLayout saiu com as macros vazias (LEF sem `FOREIGN`)

Fonte: saída do `diag_xor.sh` e do `08_drc_gds.sh` colada pelo Lukas no
chat (o `08_xor_diag.txt` ficou no notebook); código do LibreLane 3.0.14
(`scripts/klayout/stream_out.py`, `steps/klayout.py`); teste aqui com o
`klayout` do pip e o LEF/GDS da `sram_1rw1r_64x64_wpr2`.

### O diagnóstico (L44) respondeu

| | GDS do Magic | GDS do KLayout |
|---|---|---|
| Células no arquivo | 826 | 169 |
| IMEM (`sram_8kbyte…`) | 12.693.546 formas, 16 subcélulas | **0 formas, 0 subcélulas** |
| DMEM (`sram_4kbyte…`) | 6.532.834 | **0** |
| `out_mem` (`sram_1rw1r_64x256`) | 7.881.205 | **0** |
| `in_mem` (`sram_1rw1r_64x64_wpr2`) | 2.251.863 | **0** |

**Fora das macros** (o nosso desenho), as contagens batem em quase todas
as camadas: poço, difusão, poly, li1, contatos, vias, pinos, fronteira
(236/0), diodos (81/23). Diferem só:

| Camada | Magic (fora) | KLayout (fora) | Leitura |
|---|---|---|---|
| met1–met5 desenho (68/20 … 72/20) | 822.221 / 171.785 / 33.178 / 6.879 / 429 | 1.568.791 / 673.511 / 123.387 / 27.216 / 1.661 | o Magic **funde** retângulos que se tocam num polígono só; o KLayout escreve cada trecho do DEF. Mesma área, contagem diferente |
| rótulos de pino met4/met5 (71/5, 72/5) | 74 / 24 | 2 / 2 | rótulos dos pinos de alimentação: cada ferramenta escreve de um jeito |

A contagem não prova que a geometria fora das macros é idêntica (isso é o
XOR), mas mostra que **as 15,7 milhões de diferenças são as macros**.

### 🐛 Por que as macros saíram vazias no KLayout

- **Causa:** os LEF da OpenRAM **não têm a linha `FOREIGN`** (os das
  células padrão têm: `FOREIGN sky130_fd_sc_hd__a2bb2o_1 ;`). O
  `stream_out.py` do LibreLane:
  1. lê o DEF com os LEF. Célula com `FOREIGN` vira célula **fantasma**
     (só o nome, "o desenho está num GDS externo"); sem `FOREIGN`, o
     KLayout **desenha a macro com a geometria do LEF**;
  2. limpa todas as células (fica vazia, mas não é fantasma);
  3. lê os GDS com `KLAYOUT_CONFLICT_RESOLUTION = RenameCell`: a célula
     fantasma é preenchida; a que já existe gera conflito, e o conteúdo do
     GDS entra como **`sram_…$1`**. A instância do chip continua na célula
     vazia.
  4. a checagem "All LEF cells have matching GDS cells" só procura
     fantasmas — a vazia passa.
- **Reproduzido aqui** com o LEF e o GDS reais da `in_mem`:

| LEF | Subcélulas da macro depois do GDS | Células renomeadas |
|---|---|---|
| original (sem `FOREIGN`) | **0** | `sram_1rw1r_64x64_wpr2$1` |
| com `FOREIGN sram_1rw1r_64x64_wpr2 ;` | **16** (igual ao GDS do Magic) | nenhuma |

- **Resolvi com (L45, proposta):** `macros/lef_foreign.py` põe
  `FOREIGN <nome> ;` depois de `CLASS BLOCK ;` nos 4 LEF (idempotente,
  `--check`). Nenhuma coordenada muda. Aplicado e versionado.
  Alternativa que não escolhi: `KLAYOUT_CONFLICT_RESOLUTION = AddToCell`
  no config — funciona, mas esconde o defeito do LEF, que é o que está
  errado (e outra ferramenta pode tropeçar nele de novo).
- **Por que o Magic não teve o problema:** o Magic lê o GDS com
  `gds readonly` e casa a macro pelo nome; ele não desenha nada a partir do
  LEF antes.
- **Tempo:** 30 min.
- **Vira slide?** Sim: "o XOR existe para isso" — duas ferramentas, uma
  delas esqueceu 29 milhões de formas, e o motivo era uma linha no LEF.

### 🐛 `08_drc_gds.sh`: "a etapa Checker.XOR ainda não rodou"

- **Causa:** checker que reprova (erro adiado) **não grava
  `state_out.json`** — o mesmo que já se viu no `Checker.HoldViolations`
  (28ª sessão). O script procurava o estado do `Checker.XOR`.
- **Resolvi com:** parte do `KLayout.XOR`. As maglef foram geradas
  (4 `.mag`), então a 1ª metade do script funcionou.

### Scripts

| Arquivo | Mudança |
|---|---|
| `macros/lef_foreign.py` | novo (L45) |
| `macros/*/*.lef` | + `FOREIGN` |
| `layout/nucleo/comum.sh` | + `gera_maglef` e `resume_drc_magic` |
| `layout/nucleo/08_verificacao.sh` | gera as maglef antes; confere o `FOREIGN`; resumo do DRC por regra; copia o `drc.magic.rpt` para `resultados/` |
| `layout/nucleo/08_drc_gds.sh` | parte do `KLayout.XOR`; só para refazer o DRC sozinho |
| `CLAUDE.md` | armadilhas: `FOREIGN` e "checker reprovado não grava estado" |

### Para continuar: etapa 8 inteira de novo

```
git pull
bash layout/nucleo/08_verificacao.sh     # GDS (16 min) + XOR + DRC no GDS (tempo novo) + LVS
bash layout/nucleo/junta_logs.sh
```

Esperado: XOR **0** (ou só diferenças de rótulo); DRC sem `nwell.4`, com os
130 de área mínima nos pinos sem uso (L43); LVS de novo limpo; hold do FF
reprovando (L40).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L44 | Diagnóstico do XOR dentro/fora das macros | ✅ funcionou | Macros vazias no GDS do KLayout |
| L45 | `FOREIGN` nos LEF das macros (`lef_foreign.py`) | 🟡 | Sem ele o KLayout esvazia as macros; reproduzido |

## 2026-10-10 (30ª sessão) — ✅ Etapa 8 fechada: XOR 0, LVS limpo, DRC só com os 130 previstos

`bash layout/nucleo/08_verificacao.sh` com a L42 (DRC no GDS) e a L45
(`FOREIGN`), passos `158-…` a `175-…`. Fontes: `08_verificacao.txt`,
`08_verificacao_metricas.json`, `08_drc_magic.rpt`, `08_xor_diag.txt`,
`logs_2026-10-10_0007.tar.gz`, imagem `08_gds_klayout.png` (commit
`9216761`).

### Antes × depois

| Checagem | 28ª sessão | **30ª sessão** | Fonte |
|---|---|---|---|
| XOR Magic × KLayout | 15.679.857 | **0** (56 camadas, todas 0) | `klayout-xor.log`, `design__xor_difference__count` |
| DRC (Magic) | 1.182 (DEF + LEF) | **130** (GDS + macros caixa-preta) | `magic__drc_error__count` |
| ↳ `nwell.4` | 1.052 | **0** | `08_drc_magic.rpt` |
| ↳ `met4.4a` (área mínima) | 128 | 128 | idem |
| ↳ `met3.6` (área mínima) | 2 | 2 | idem |
| LVS | limpo | **limpo** ("Circuits match uniquely") | `169-…` |
| Antena / sobreposição / alimentação | 0 / 0 / 0 | 0 / 0 / 0 | métricas |
| Hold (FF) | reprova (L40) | reprova (L40) | `172-…` sem `state_out` |

As 130 caixas de DRC são **as mesmas** da 28ª sessão (comparadas
coordenada a coordenada): 64 em y = 100 µm (`in_mem`) + 64 em y = 1.002 µm
(`out_mem`), os pinos `dout0` sem uso, e 2 em x = 55 µm (IMEM e DMEM), o
`dout0[32]`. As duas hipóteses se confirmaram:

- **L42:** com as células padrão reais (GDS), os taps aparecem e o `nwell.4`
  vai a zero. Os 1.052 eram da vista abstrata.
- **L45:** com `FOREIGN`, o GDS do KLayout tem as macros e os dois GDS são
  **idênticos** em todas as 56 camadas.

### Tempos da etapa 8

| Passo | Tempo |
|---|---|
| `Magic.StreamOut` | 20 min 46 s |
| `KLayout.StreamOut` | 9 s |
| `KLayout.XOR` | 2 min 56 s |
| `Magic.DRC` (no GDS) | **31 min 39 s** (no DEF: 5 min) |
| `Magic.SpiceExtraction` | 1 min 52 s |
| `Netgen.LVS` | 37 s |

### 🟡 L43: os 130 de área mínima ficam como isenção

| Regra | Caixas | Pino (LEF) | Por que não é defeito |
|---|---|---|---|
| `met4.4a` | 64 | `dout0[0..63]` da `in_mem` (y = 100 µm) | saída da porta 0 das 1rw1r, que só escreve; no LEF o pino é um quadrado de 0,38 × 0,38 µm (0,144 µm² < 0,24 µm²) sem fio |
| `met4.4a` | 64 | `dout0[0..63]` da `out_mem` (y = 1.002 µm) | idem |
| `met3.6` | 2 | `dout0[32]` da IMEM e da DMEM (x = 55 µm) | 33º bit (L1), sem uso |

No GDS de verdade da macro o pino é o fim de um fio interno da OpenRAM —
a área mínima é cumprida lá dentro. O erro existe só porque a macro entra
como caixa-preta (L3). Para eliminar de fato, seria preciso ligar um
pedaço de metal em cada pino sem uso (*stub*), o que não muda nada no
chip; fica registrado como isenção.

**Vira slide?** Sim, a tabela antes × depois: "1.182 → 130 → 0 defeitos
reais", com o porquê de cada degrau.

### Estado do layout do núcleo

| Item | Situação |
|---|---|
| GDS do núcleo | ✅ `asic_top.gds` (Magic) = `asic_top.klayout.gds` (XOR 0) |
| DRC | ✅ 0 defeitos reais; 130 isentos (L43) |
| LVS | ✅ limpo (macros caixa-preta) |
| Antena | ✅ 0 |
| Setup TT | ✅ +0,32 ns no pior corner |
| Hold | ⚠️ 15 caminhos ≤ 28 ps no FF (L40) |
| IR drop | ❓ sem número válido (L37) |

### Para continuar

Faltam as etapas 9–12 (roteiro da 7ª sessão): 9 LEC e simulação do netlist
do layout (VM), 10 `chip_top.v` com os pads, 11 padring (fluxo Chip), 12
DRC/LVS finais. Pendentes opcionais: ECO de hold (L40), IR drop (L37).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L42 | DRC no GDS + macros caixa-preta | 🟡 funcionou (`nwell.4` 1.052 → 0) | — |
| L43 | 130 de área mínima em pinos sem uso = isenção | 🟡 | Confirmados os mesmos 130, todos em pinos sem uso |
| L45 | `FOREIGN` nos LEF | 🟡 funcionou (XOR 0) | — |

## 2026-10-10 (31ª sessão) — Etapa 9 preparada: LEC e simulação do netlist do layout na VM

Pedido do Lukas: "bora testar na VM!". Nada rodou ainda; esta sessão monta
os arquivos. Fontes: `vm/backend/synthesis/scripts/run_first.tcl` (blocos
2 e 3 da síntese, reaproveitados), `layout/nucleo/01_leitura.sh` (de onde
vem o netlist que entrou no layout), `state_out.json` do passo 175 (o
netlist final é o `135-openroad-fillinsertion/asic_top.nl.v`), código do
LibreLane 3.0.14 (`write_verilog -remove_cells [get_physical_cells]`).

### O que a etapa 9 prova

| Pergunta | Golden | Revised | Ferramenta | Bloco |
|---|---|---|---|---|
| O layout é o mesmo circuito que entrou nele? | netlist do Genus **achatado** (o que o `01_leitura.sh` deu ao LibreLane) | netlist do layout | Conformal | **4a** |
| O layout funciona? | — | netlist do layout + firmware das 3 matrizes | Xcelium | **4b** |
| A cadeia inteira de uma vez? | RTL | netlist do layout | Conformal | 4c (opcional) |

A cadeia fica fechada assim: RTL ≡ Genus (LEC da síntese, PASS, 12ª
sessão) → Genus ≡ Genus achatado (conferência pino a pino do
`01_leitura.sh`, L19) → **Genus achatado ≡ layout** (4a). O golden achatado
tem os **mesmos nomes de flip-flop** do layout (o OpenROAD não renomeia o
que já existe), então o Conformal mapeia por nome.

### 🟡 L46: o netlist do layout vai sem as células só físicas

- O `asic_top.nl.v` final tem **todas** as instâncias do desenho: ~142 mil
  de preenchimento, ~20 mil taps, 2.773 diodos. Elas não têm função lógica
  e as `sky130_ef_sc_hd__decap_12` nem têm modelo `.v` no pacote da VM (o
  Xcelium pararia na elaboração).
- `tira_fisicas.py` tira `fill`, `decap`, `tapvpwrvgnd` e `diode` — a mesma
  escolha do LibreLane para o netlist "lógico" — e **confere** que
  flip-flops e macros do layout batem com os do golden (19.823 e 4). Se não
  baterem, o script para.
- Testado aqui com um netlist sintético no formato do OpenROAD (instâncias
  em várias linhas, nomes escapados).

### Arquivos

| Arquivo | O quê |
|---|---|
| `layout/nucleo/09_netlist.sh` | novo: pega o netlist final, tira as físicas, confere, compacta em `vm/backend/synthesis/netlist_layout/`, resumo em `09_netlist.txt`; `SIM_ICARUS=1` simula no Icarus antes da VM |
| `layout/nucleo/tira_fisicas.py` | novo (L46) |
| `vm/backend/synthesis/scripts/layout_lec.do` | novo: dofile do LEC da etapa 9 (golden trocado por `sed`) |
| `vm/backend/synthesis/scripts/run_first.tcl` | PATH completo (CLAUDE.md); bloco 1 (Genus) **comentado**; blocos 4a e 4b **descomentados**, 4c comentado |
| `sim/run_gls_yosys.sh` | `NETLIST=<arquivo>`: pula a síntese e simula o netlist dado |
| `sim/traz_vm.sh` | traz `sim_layout/`; data da pasta = a dos relatórios da etapa 9 |

Conferido aqui: as substituições do dofile (os dois casos, 4a e 4c, sem
nenhum `@` sobrando) e a sintaxe dos scripts. O `lec` e o `xrun` só na VM.

### O que esperar

| Bloco | Esperado | Por quê |
|---|---|---|
| 4a | 0 não equivalentes, 0 abortados, ~19.828 pontos equivalentes | igual ao LEC da síntese (19.823 flip-flops + saída + 4 macros) |
| 4b | as 3 somas = RTL (`0xeb88508e`, `0xba7fc58e`, `0xb29c0211`), `[TB] PASSOU`, ~188 mil ciclos | mesma simulação do netlist do Genus (5ª sessão) |

Riscos: (1) o Conformal pode não mapear pelos nomes escapados e cair no
mapeamento por função (mais lento, mas funciona); (2) a simulação tem
~100 mil células e 188 mil ciclos: deve levar mais que a do Genus.

### Para continuar

No notebook:
```
git pull
bash layout/nucleo/09_netlist.sh          # (SIM_ICARUS=1 para conferir no Icarus antes)
git add vm/backend/synthesis/netlist_layout resultados/2026-09-30_0934_layout_nucleo/09_netlist.txt
git commit -m 'gdsii: netlist do layout para a VM (etapa 9)' && git push
bash sim/monta_vm.sh
```
Na VM: levar `backend/synthesis/scripts/` e `backend/synthesis/netlist_layout/`
e `source run_first.tcl` (roda 4a e depois 4b). Volta com
`bash sim/traz_vm.sh <pasta> layout_etapa9`.

### 🐛 1ª rodada do `09_netlist.sh`: "flip-flops não batem" (20.857 × 19.823)

- **Sintoma:** o script parou: golden 19.823 flip-flops, layout 20.857
  (saída colada pelo Lukas).
- **Causa:** erro **meu** no padrão de flip-flop do `tira_fisicas.py`:
  `dl*` (para pegar os latches `dlx*`/`dlr*`) pegava também as células de
  **atraso** `dlygate4sd3_1` (1.029) e `dlymetal6s2s_1`/`dlymetal6s4s_1`
  (3 + 2) — os buffers de hold. 19.823 + 1.034 = 20.857, exato.
- **Resolvi com:** padrão `df*|sdf*|edf*|dlx*|dlr*|dlclkp*` (conferido
  contra `dlygate…`, `dlymetal…` e `clkdlybuf…`, que não entram).
- **O que a 1ª rodada já mostrou** (`09_netlist.txt`, no notebook):

| Item | Valor |
|---|---|
| Células físicas retiradas | 163.169: `decap_3` 103.829, `tapvpwrvgnd_1` 20.046, `fill_1` 19.777, `fill_2` 16.744, `diode_2` 2.773 |
| Instâncias lógicas | golden 60.027 → layout 76.903 (+16.876) |
| Macros | 4 = 4 |
| Células novas no layout (as maiores) | `clkdlybuf4s25_1` 9.141, `clkbuf_4` 2.165, `clkbuf_8` 2.157, `dlygate4sd3_1` 1.029, `clkbuf_16` 266 |
| Netlists compactados | 2,1 MB (layout 36 MB e golden 31 MB descompactados) |
| `assign` no layout | 0 |

- **Tempo:** 5 min.
- **Vira slide?** Não (mas a tabela de células novas sim: o que o layout
  acrescenta à síntese).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L46 | Netlist do layout para LEC/simulação sem fill/decap/tap/diodo | 🟡 | Sem função lógica; `ef_` sem modelo `.v`; mesma escolha do LibreLane |
| L47 | Golden do LEC da etapa 9 = netlist do Genus achatado (RTL × layout como extra, 4c) | 🟡 | Mesmos nomes de flip-flop → mapeamento por nome; a cadeia RTL→Genus já tem LEC |

---

## 2026-10-21 (32ª sessão, registrada pelo chat do UVM) — PATH da VM trocado no `run_first.tcl`

A VM goku foi **atualizada**: as pastas da Cadence mudaram de nome
(`XCELIUM2309` → `XCELIUM2603`, `CONFRML232` → `CONFRML261`,
`VMANAGER2409` → `VMANAGER2603`…; tabela completa no `DIARIO_UVM.md`, 6ª
sessão). Com o PATH antigo, `xrun` e `imc` dão `command not found`.

**Mudou neste diretório:** só a linha `export PATH` do
`vm/backend/synthesis/scripts/run_first.tcl` (a mesma do `CLAUDE.md`).
Nada mais.

| Consequência para o GDSII | |
|---|---|
| Genus | continua o **22.1** (`DDI221`): as sínteses de set/2026 são reproduzíveis |
| Conformal | 23.2 → **26.1** no LEC da etapa 9 (L47). Resultado de equivalência não depende da versão, mas o log vai dizer outra versão |
| Xcelium | 23.09 → **26.03** na simulação do netlist do layout (etapa 9). Conferir: somas = RTL, como sempre |

## 2026-10-26 (33ª sessão) — 🐛 Etapa 9 na VM: LEC parou em "Module 'sram_…' is referenced but not defined"

Saída do terminal da VM colada pelo Lukas (Conformal **26.10-s200**, o da
VM atualizada). Os dois netlists chegaram e foram descompactados
(golden 31,7 MB, layout 29,1 MB).

### 🐛 Sintoma

```
// Error: .../asic_top_genus_flat.v:194333 Module 'sram_4kbyte_1rw_32x1024_8' is referenced but not defined.
(… as 4 macros …)
// 'dofile .../layout_lec_genus.do' is aborted at line 33
SETUP>
```

- **Causa:** o meu `layout_lec.do` (copiado do dofile escrito à mão da
  síntese, o 3b, que **nunca tinha rodado**) só fazia
  `add notranslate module <macro> -both`. Isso marca como caixa-preta um
  módulo que o Conformal **encontra**; aqui ninguém define as macros (o
  netlist só as instancia) e o Conformal, por padrão, para com módulo
  indefinido. O dofile que o **Genus** escreve (o 3a, que passou na
  síntese) faz três coisas
  (`resultados/2026-09-29_sintese_layout/deliverables/neorv32_isfft_soc_lec_genus.do`,
  linhas 83–94):

| Comando no dofile do Genus | Para quê |
|---|---|
| `set_undefined_cell black_box -noascend -both` | módulo sem definição vira caixa-preta, não erro |
| `add_notranslate_modules -library -both sram_…` | as 4 macros não são traduzidas, nos dois lados |
| `read_library -liberty -both <sky130> <4 .lib das macros>` | as macros entram como células de biblioteca (pinos e direções vêm do `.lib`) |

- **Resolvi com:** os mesmos três comandos no `layout_lec.do` e no
  `neorv32_isfft_soc_lec.do` (o 3b tinha o mesmo defeito, só não tinha
  aparecido).
- **Lição:** dofile "escrito à mão e didático" que nunca rodou não é
  referência; o que já passou na ferramenta é.
- **Tempo:** 15 min.
- **Vira slide?** Não.

### 🐛 2ª tentativa: "Golden design has been elaborated"

- **Sintoma:** com as macros resolvidas, o golden foi lido ("Total black
  box modules referenced in Golden = 4") e o dofile parou na linha 40,
  `elaborate design -golden`: `Error: Golden design has been elaborated`.
- **Causa:** sem `-noelab`, o `read design` já elabora sozinho ("Golden
  root module is set to 'asic_top'"); o `elaborate` seguinte é recusado. O
  dofile do Genus usa `read_design … -noelab` + `elaborate_design -root`.
- **Resolvi com:** `-noelab` nos dois `read design` dos dois dofiles.
  Aproveitei e comparei o resto com o dofile do Genus: entraram as mesmas
  opções de achatamento (`-seq_constant_x_to 0`, `-nodff_to_dlat_zero`,
  `-nodff_to_dlat_feedback`); o relatório de comparação passa a listar só
  não equivalentes/abortados/não comparados (senão são ~20 mil linhas); o
  resumo do `lec_layout` lê a tabela "Compared points" do log.
- **Lição (a mesma, de novo):** dofile que nunca rodou → comparar linha a
  linha com um que já rodou **antes** de ir para a VM.
- **Tempo:** 10 min.

### Para continuar (na VM, sem refazer nada)

O `source run_first.tcl` já definiu a função `lec_layout` e as variáveis no
terminal. No prompt `SETUP>` do Conformal, `exit -force`: o script segue
para o bloco 4b (simulação). Depois, com o `layout_lec.do` e o
`run_first.tcl` novos em `backend/synthesis/scripts/` (`source
run_first.tcl` de novo, ou só redefinir a função), no mesmo terminal:

```
lec_layout layout_lec_genus "-netlist" "${NL_DIR}/asic_top_genus_flat.v"
```

## 2026-10-28 (34ª sessão) — ✅ Etapa 9 passou: o layout é o mesmo circuito (LEC) e funciona (simulação)

Rodado na VM em 26/10 (blocos 4a e 4b do `run_first.tcl`, depois das
duas correções do dofile da 33ª sessão), trazido pelo Lukas com
`traz_vm.sh … layout_etapa9`. Fontes: `resultados/2026-10-26_layout_etapa9/`
— `logs/layout_lec_genus_run.log.gz`, `reports/layout_lec_genus_*.rpt`,
`logs/xrun_layout.log.gz`, `logs/xrun_layout_comando.log` (commit `156be7d`).
Ferramentas: Conformal **26.10-s200**, Xcelium **26.03-s005** (VM nova).

### 4a — LEC: netlist do Genus (achatado) × netlist do layout

| Item | Golden (Genus) | Revised (layout) | Fonte |
|---|---|---|---|
| Pontos mapeados (PI / PO / DFF / caixa-preta) | 3 / 1 / 19.823 / 4 | 3 / 1 / 19.823 / 4 | tabela "Mapped points" |
| Pontos não mapeados | — | — | `_unmapped.rpt`: "There is no unmapped point" |
| Caixas-pretas | as 4 macros, nos dois lados | | `_blackbox.rpt` |
| **Comparados: equivalentes** | **19.828** (1 saída + 19.823 flip-flops + 4 macros) | | tabela "Compared points" |
| Não equivalentes / abortados / não comparados | **0 / 0 / 0** | | `_compare.rpt` |
| Tempo | ~15 s de CPU | | log |

**Todos os flip-flops mapearam por nome** (nenhum não mapeado): o golden
achatado (L47) tinha exatamente os nomes que o OpenROAD manteve. Os
~16.900 buffers, inversores e células trocadas que o layout pôs (árvore de
relógio, reparo, hold) não mudaram a função lógica de nenhum dos 19.828
pontos. Mesmo número do LEC da síntese (RTL × Genus, 12ª sessão).

### 4b — Simulação do netlist do layout (Xcelium)

| Item | Netlist do Genus (5ª sessão) | **Netlist do layout** | Fonte |
|---|---|---|---|
| Matriz 0 | soma = RTL (`0xeb88508e`) | **soma = RTL (`0xeb88508e`)** | `[TB]` |
| Matriz 1 | soma = RTL (`0xba7fc58e`) | **soma = RTL (`0xba7fc58e`)** | `[TB]` |
| Matriz 2 | soma = RTL (`0xb29c0211`) | **soma = RTL (`0xb29c0211`)** | `[TB]` |
| Ciclos | 188.195 (RTL: 188.194) | **188.195** (3,764 ms a 50 MHz) | `[TB] fim` |
| Veredito | PASSOU | **`[TB] PASSOU`** | |
| Tempo total do `xrun` | — | 1 min 05 s | `TOOL: … Exiting` |

Os 188.195 ciclos são os mesmos do netlist do Genus: o ciclo a mais em
relação ao RTL vem da síntese, não do layout.

Avisos do `xrun` (nenhum erro):

| Aviso | Quantos | O que é |
|---|---|---|
| `CUVWSP` (saída não ligada) | ≥ 1.000 (limite) | as **1.069 células `clkload`** da árvore de relógio: buffers de **carga falsa** que o CTS põe para equilibrar o atraso entre ramos — a saída fica solta de propósito. O Conformal viu o mesmo: "Open output port connection (occurrence: 1079)" |
| `NODNTW` | ≥ 1.000 | `default_nettype none` nos arquivos de células do sky130 (`primitives.v`, `sky130_fd_sc_hd.v`) — é o que o `restore_nettype.v` resolve para o netlist |
| `DLCPTH` | 120 | `cds.lib` da instalação nova aponta para pastas VHDL que não existem; não usamos VHDL |

**Vira slide?** Sim, os dois: "19.828 pontos equivalentes, 0 diferenças"
e "as mesmas 3 somas no netlist do layout". E o `clkload` como curiosidade:
célula que existe só para ser carga.

### A cadeia de verificação fechada

| Elo | Como | Resultado |
|---|---|---|
| RTL → Genus | LEC (Conformal) | ✅ 19.828 equivalentes (12ª sessão) |
| Genus → Genus achatado | conferência pino a pino (`01_leitura.sh`, L19) | ✅ |
| Genus achatado → layout | LEC (Conformal) | ✅ 19.828 equivalentes (esta sessão) |
| Layout → GDS | LVS (Netgen) | ✅ "Circuits match uniquely" (30ª sessão) |
| O circuito funciona? | simulação RTL, Genus e layout com as 3 matrizes da Kria | ✅ as mesmas somas nos três |

**Conclusão: o GDS do núcleo é o RTL.** Do Verilog ao desenho, cada passo
foi provado equivalente ao anterior, e o desenho roda o firmware.

### Para continuar

Nível 1 (núcleo `asic_top`) fechado. Próximo: **etapa 10**, `chip_top.v`
com os pads `sky130_ef_io` + o núcleo (roteiro da 7ª sessão), e depois o
padring (11) e o GDS final (12).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L46 | Netlist do layout sem células só físicas | 🟡 funcionou (LEC e simulação) | — |
| L47 | Golden do LEC = Genus achatado | 🟡 funcionou (100 % mapeado por nome) | — |

## 2026-10-28 (35ª sessão) — ✅ Etapa 10: `chip_top.v` com os pads simula igual ao núcleo

Nível 2 começou. Tudo nesta sessão foi feito e simulado **aqui na nuvem**
(Icarus 12.0); nada para rodar no notebook ou na VM ainda. Fontes:
`resultados/2026-10-28_chip_etapa10/` (`10_simula_chip_top.log`,
`10_mutacao_pad_tx.log`); modelos de pad do open_pdks `8afc8346` e do
`skywater-pdk-libs-sky130_fd_io` `63752cd` (`tech/sky130_io/LEIAME.md`).

### O que o PDK tem (conferido nos arquivos, não na documentação)

| Célula | LEF (`SIZE`, `CLASS`) | Para quê |
|---|---|---|
| `sky130_ef_io__gpiov2_pad_wrapped` | 80 × 210,965 µm, `PAD INOUT` | pino digital; 39 pinos |
| `sky130_ef_io__{vccd,vssd}_lvc_clamped_pad` | 75 × 197,965, `PAD POWER` | 1,8 V do núcleo |
| `sky130_ef_io__{vddio,vssio}_hvc_clamped_pad` | 75 × 197,965, `PAD POWER` | 3,3 V dos pads |
| `sky130_ef_io__{vdda,vssa}_hvc_clamped_pad` | 75 × 197,965, `PAD POWER` | domínio analógico do anel |
| `sky130_ef_io__corner_pad` | 200 × 204, `ENDCAP` | canto |
| `sky130_ef_io__com_bus_slice_{1,5,10,20}um` | `PAD SPACER` | preenchimento do anel |
| `sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um` | 20 × 197,965, `PAD AREAIO` | liga VCCHIB→VCCD e VSWITCH→VDDIO |

Nenhum desses LEF declara `SITE` (vai precisar de `PAD_FAKE_SITES`, L16, na
etapa 11). O pad de GPIO da tabela da 6ª sessão estava certo (`_wrapped`).

### O `chip_top.v` (`layout/chip/chip_top.v`)

| Instância | Célula | Ligação |
|---|---|---|
| `u_core` | `asic_top` (o núcleo das etapas 1–9) | 4 sinais de 1,8 V |
| `pad_clk`, `pad_rstn`, `pad_rx` | `gpiov2_pad_wrapped`, **entrada** | `IN` → núcleo |
| `pad_tx` | `gpiov2_pad_wrapped`, **saída** | núcleo → `OUT` |
| `tie_clk`, `tie_rstn`, `tie_rx`, `tie_tx` | `sky130_fd_sc_hd__conb_1` | constantes de 1,8 V, uma por pad |
| `pad_vccd` … `pad_vssa` | 6 pads de alimentação (L48) | |
| `fatia_vcchib` | `connect_vcchib_vccd_and_vswitch_vddio_slice_20um` (L50) | |

Configuração dos pads de GPIO (semântica lida no modelo
`sky130_fd_io__top_gpiov2.functional.pp.v`):

| Pino | Domínio | Entrada (clk, rstn, rx) | Saída (tx) | O que faz |
|---|---|---|---|---|
| `DM[2:0]` | 1,8 V | `001` | `110` | 001 = só entrada (driver em Z); 110 = push-pull forte |
| `OE_N` | 1,8 V | 1 | 0 | habilita o driver |
| `OUT` | 1,8 V | 0 | `uart0_txd_o` | |
| `INP_DIS` | 1,8 V | 0 | 1 | liga/desliga o buffer de entrada |
| `IB_MODE_SEL`, `VTRIP_SEL`, `SLOW`, `HLD_OVR`, `ANALOG_*` | 1,8 V | 0 | 0 | limiar CMOS, borda rápida, sem analógico |
| `ENABLE_VDDIO` | 1,8 V | 1 | 1 | |
| `ENABLE_H`, `HLD_H_N` | **3,3 V** | `TIE_HI_ESD` | `TIE_HI_ESD` | pad ligado, sem "hold" |
| `ENABLE_INP_H`, `ENABLE_VDDA_H`, `ENABLE_VSWITCH_H` | **3,3 V** | `TIE_LO_ESD` | `TIE_LO_ESD` | |

Os pinos `_H` são do domínio de 3,3 V e **não podem** vir de célula de
1,8 V: vêm das saídas `TIE_HI_ESD`/`TIE_LO_ESD` do próprio pad, como no
Caravel.

As 12 barras do anel (AMUXBUS_A/B, VSSA, VDDA, VSWITCH, VDDIO_Q, VCCHIB,
VDDIO, VCCD, VSSIO, VSSD, VSSIO_Q) só aparecem no Verilog com
`USE_POWER_PINS` (simulação e LVS); no layout elas se ligam por encosto
(`connect_by_abutment` do `PadRing`). Cantos e preenchimentos não entram no
netlist: o `PadRing` os põe sozinho.

### Simulação (`layout/chip/10_simula.sh`)

`tb_gate.v` com `-DCHIP_TOP`: o mesmo testbench das etapas 0, 2 e 9, agora
ligando `chip_top`. Relógio, reset, RX e TX passam pelos pads; os 6 pinos
de alimentação são pinos do testbench (1 = tensão nominal do domínio).
Núcleo = **o netlist do layout** (o da etapa 9).

| Item | Núcleo sozinho (etapa 9, Xcelium) | **Chip com pads (Icarus)** |
|---|---|---|
| Matriz 0 | `0xeb88508e` = RTL | **`0xeb88508e` = RTL** |
| Matriz 1 | `0xba7fc58e` = RTL | **`0xba7fc58e` = RTL** |
| Matriz 2 | `0xb29c0211` = RTL | **`0xb29c0211` = RTL** |
| Firmware | `RESULTADO: OK` | **`RESULTADO: OK`** |
| Ciclos | 188.195 | **188.195** |
| Veredito | PASSOU | **`[TB] PASSOU`** |
| Tempo | 1 min 05 s | 4.074 s (~68 min; Icarus é mais lento) |

**Mutação** (a versão certa passou primeiro): `pad_tx` com `DM = 001` (só
entrada) no lugar de `110` → `[TB] ERRO: uart0_txd_o = z no ciclo 21`. O
teste enxerga o pad de verdade (`10_mutacao_pad_tx.log`).

### 🐛 1ª tentativa: módulos não encontrados

- **Sintoma:** 315 erros `Unknown module type: sky130_fd_io__top_ground_*`.
- **Causa:** (1) faltavam os modelos dos pads de **terra** (`VSSD`, `VSSIO`,
  `VSSA`); (2) o Icarus elabora como raiz todo módulo não instanciado — e o
  `sky130_ef_io.v` tem dezenas de pads que não usamos.
- **Resolvi com:** os dois modelos de terra trazidos; `iverilog -s tb_gate`.

### 🐛 2ª tentativa: tudo em X — `USE_POWER_PINS` vazando

- **Sintoma:** `uart0_txd_o = x` no ciclo 21; a sonda mostrou o anel
  certo (VCCD = VDDIO = VCCHIB = 1, VSS* = 0) mas `DM = xxx` nos pads.
- **Causa:** `-DUSE_POWER_PINS` na linha de comando vale para **todos** os
  arquivos — e a biblioteca de células usa a **mesma macro** para ganhar
  `VPWR/VGND`. As `conb_1` (e todas as células do núcleo) ficaram com os
  pinos de alimentação soltos e as saídas em X. Os modelos das macros da
  OpenRAM também têm `` `ifdef USE_POWER_PINS``.
- **Resolvi com:** a macro entra por um arquivo,
  `layout/chip/pinos_alimentacao_pads.v`, lido **depois** das células, do
  núcleo e das macros e **antes** dos pads e do `chip_top` — o mesmo
  mecanismo do `restore_nettype.v`.
- **Vira slide?** Sim: "um `` `define`` vale para tudo o que vem depois" —
  duas bibliotecas usando a mesma macro com sentidos diferentes.

### 🐛 A mutação não aparecia

- **Causa:** o aviso de X do `tb_gate.v` ficava no buffer da saída até o
  próximo `$fflush()`, que só acontece quando a UART fala — e com o pad
  morto ela nunca fala.
- **Resolvi com:** `$fflush()` logo depois do aviso; `10_simula.sh` aceita
  `CHIP_V=` (cópia com defeito) e `EXTRA="+LIMITE_MS=1"`.

### Arquivos

| Arquivo | O quê |
|---|---|
| `layout/chip/chip_top.v` | novo |
| `layout/chip/pinos_alimentacao_pads.v` | novo: `` `define USE_POWER_PINS`` só para pads |
| `layout/chip/10_simula.sh` | novo |
| `tech/sky130_io/` | modelos dos pads (SkyWater/Efabless, Apache-2.0) + o modelo da fatia VCCHIB (nosso) + `LEIAME.md` |
| `vm/backend/synthesis/scripts/tb_gate.v` | `` `ifdef CHIP_TOP``; `$fflush()` depois do aviso de X |

### Para continuar: etapa 11 (padring, fluxo `Chip`)

| A decidir/fazer | Por quê |
|---|---|
| Tamanho do die e lado de cada pad (`PAD_SOUTH/EAST/NORTH/WEST`) | núcleo 2,0 × 1,5 mm + ~211 µm de pad + cantos de 200 µm por lado → ~2,5 × 2,0 mm; pads perto dos pinos do núcleo |
| `PAD_FAKE_SITES`, `PAD_SITE_NAME`, `PAD_CORNER`, `PAD_FILLERS` | o sky130 não traz (L16) |
| `fatia_vcchib` é `CLASS PAD AREAIO`, não `SPACER` | precisa entrar numa lista de lado como se fosse pad |
| Núcleo como macro: `asic_top.lef` (etapa 8, `Magic.WriteLEF`) + GDS | |
| Alimentação do núcleo pelo anel (VCCD/VSSD → `vccd1`/`vssd1`) | |

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L48 | 6 pads de alimentação: um de cada (vccd, vssd, vddio, vssio, vdda, vssa) | 🟡 | Mínimo que alimenta o anel; VSSA = 0 é exigido pelo driver de saída do gpiov2 |
| L49 | `ENABLE_H`/`HLD_H_N` = `TIE_HI_ESD` (sem power-on-reset de 3,3 V) | 🟡 | Caravel usa POR; aqui o pad liga com o VDDIO. Basta para estudo |
| L50 | Fatia `connect_vcchib_vccd_and_vswitch_vddio` no anel, com modelo Verilog nosso | 🟡 | Sem ela VCCHIB fica sem fonte e o buffer de entrada dá X |
| L51 | `USE_POWER_PINS` só para pads, por arquivo na ordem de leitura | 🟡 | A macro também liga os pinos de alimentação das células e das macros |


## 2026-10-29 (36ª sessão) — Etapa 11, parte 1: o anel de pads (fluxo `Chip`)

**Combinado novo (Lukas, 29/10):** "essas decisões você pode decidir sozinho,
esse projeto não vai para fabricação, é apenas para meu aprendizado". A partir
daqui o Claude decide as escolhas de projeto do back-end e as registra já como
✅, **sempre com o motivo** (é o que vira aula). As pendentes 🟡 da etapa 10
(L48–L51) passam a ✅ pelo mesmo combinado. Registrado também no `CLAUDE.md`.

### O plano da etapa 11

O núcleo (etapas 1–9) vira **uma macro** dentro de um segundo layout, o do
chip: `chip_top.v` (etapa 10) com os pads `sky130_ef_io` em volta. O LibreLane
tem um fluxo para isso, o `Chip` (conferido no fonte, `flows/chip.py`): é o
`Classic` com o `OpenROAD.PadRing` logo depois do `Odb.SetPowerConnections`,
sem posicionamento de pinos (os pinos do chip **são** os pads) e com
SealRing/Filler/Density no fim.

Em duas partes, para não gastar horas antes de ver o anel:

| Parte | Config | Até onde | Para quê |
|---|---|---|---|
| 1 (esta) | `config.json` + `config_anel.json` | `OpenROAD.PadRing` → posição do núcleo → GDS/PNG | conferir pads, cantos, rotação, enchimento |
| 2 | só `config.json` | fluxo `Chip` inteiro | PDN do chip, roteamento pad↔núcleo, DRC/LVS (etapa 12) |

`config_anel.json` só tem `meta.flow` = lista de passos. O LibreLane aceita
vários arquivos de config: junta as variáveis (o último sobrepõe) e o `meta.flow`
do último manda (`__main__.py`, laço `for config_file in config_files`).

### Arquivos (`layout/chip/`)

| Arquivo | O quê |
|---|---|
| `config.json` | fluxo `Chip`, die, núcleo como macro, todas as `PAD_*` |
| `config_anel.json` | fluxo reduzido da parte 1 |
| `pad_cfg.tcl` | cópia do `pad_cfg.tcl` do LibreLane 3.0.14 com rotação R180 (L55) |
| `caixas_pretas.v` | `asic_top` e a fatia VCCHIB como `(* blackbox *)` (L58) |
| `chip.sdc` | relógio no `clk_pad` (20 ns), UART 6 ns, reset e alimentação fora |
| `11_anel.sh` | traz LEF/GDS do núcleo, confere os pads do PDK, roda, junta resultados |

### As contas do anel

Larguras dos pads (LEF do PDK, `SIZE`): `gpiov2_pad_wrapped` 80 µm, pads de
alimentação 75 µm, fatia 20 µm. Canto `sky130_ef_io__corner_pad` 200 × 204 µm.
O `pad_cfg.tcl` divide a sobra de cada lado em espaços **iguais** (antes,
entre e depois dos pads); se a divisão não for inteira em µm, o pad cai fora
da grade do sítio (1 µm). Conta (Python, nesta sessão):

| Lado | Pads | Soma | Comprimento útil | Espaço |
|---|---|---|---|---|
| Sul | vssd, clk, rstn, vccd | 310 µm | 2700 − 2×200 = 2300 | 1990 / 5 = **398** |
| Norte | vssio, rx, tx, vddio | 310 µm | 2300 | **398** |
| Leste | vdda, fatia_vcchib | 95 µm | 2201 − 2×204 = 1793 | 1698 / 3 = **566** |
| Oeste | vssa | 75 µm | 1793 | 1718 / 2 = **859** |

Daí o 2201 "estranho": com 2200 o Leste daria 565,67 µm.

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L52 | O Claude decide as escolhas do back-end e registra como ✅ com o motivo | ✅ (Lukas, 29/10) | Projeto de aprendizado, sem fabricação |
| L53 | Die 2700 × 2201 µm, área de núcleo 300..2400 × 300..1901 | ✅ | Núcleo 2000 × 1500 + ~211 µm de pad + folga para o anel de alimentação do chip; 2201 deixa os espaços inteiros (tabela acima) |
| L54 | Núcleo em (350, 350), orientação N | ✅ | 50 µm de folga dentro da área de núcleo para o anel de PDN do chip; N mantém os pinos onde a etapa 2 os pôs |
| L55 | `PAD_CFG` nosso: sítios com rotação R180 | ✅ | Os pinos de 1,8 V dos pads do sky130 (VCCD em met3, IN/OUT em met2) ficam em y = 0 do LEF; com R0 apontariam para fora do chip. O teste do OpenROAD que monta o Caravel (`skywater130_caravel.tcl`) usa R180 |
| L56 | Sítios falsos `IO_SITE` 1 × 200 e `IO_CSITE` 200 × 204 | ✅ | Os LEF dos pads não declaram `SITE` (L16); mesmos números do teste do Caravel |
| L57 | Lados: S = vssd, clk, rstn, vccd; N = vssio, rx, tx, vddio; L = vdda, fatia; O = vssa | ✅ | Cada sinal entre o par de alimentação do seu domínio; clk/rstn embaixo, perto dos pinos de relógio e reset do núcleo; a fatia (`CLASS PAD AREAIO`) entra numa lista de lado como pad |
| L58 | Núcleo e fatia como `(* blackbox *)` em `caixas_pretas.v`; pads pelo Liberty (`PAD_LIBS`, TT) | ✅ | Yosys só precisa das portas; ler o netlist do núcleo achataria 100 mil células no chip |
| L59 | `KLayout.SealRing` fora (`substituting_steps`) | ✅ | Sem saber se o passo tem regras do sky130 nesta versão; o anel de selagem não muda nada do que se aprende aqui. Rever na etapa 12 |
| L60 | Etapa 11 em duas partes: anel primeiro (`config_anel.json`), fluxo inteiro depois | ✅ | O PadRing é o passo novo; errar a rotação só apareceria depois de horas de roteamento |
| L16 | (de 27/09) padring `sky130_ef_io` no nosso config | ✅ | Feito: `layout/chip/config.json` |
| L48–L51 | (etapa 10) | ✅ | Pelo combinado L52 |

### Para continuar

| Quem | O quê |
|---|---|
| Lukas | `git pull`; no nix-shell do LibreLane: `bash layout/chip/11_anel.sh`; `git add resultados/<tag>_layout_chip` e push |
| Claude | Ler o PNG e o resumo do PadRing; conferir pads virados para dentro (L55) e núcleo no lugar; ver os pinos de alimentação do LEF do núcleo e montar o PDN do chip (parte 2) |

### 🐛 1ª rodada (`2026-10-28_2111`): parou no 1º passo, `Yosys.JsonHeader`

- **Sintoma:** `ERROR: Module \sky130_ef_io__vssa_hvc_clamped_pad referenced in
  module \chip_top in cell \pad_vssa is not part of the design.` (0 de 13 passos)
- **Causa:** conferida no fonte (`steps/pyosys.py`, `VerilogStep`). O
  `JsonHeader` é o passo que descobre **quem liga em qual rede de
  alimentação** (o `Odb.SetPowerConnections` usa o JSON dele). Por isso ele
  lê o projeto com `USE_POWER_PINS` e as caixas-pretas vêm dos **modelos
  Verilog** (`CELL_VERILOG_MODELS`, `PAD_VERILOG_MODELS`), não do Liberty:
  o Liberty não tem os 12 barramentos do anel como portas. Sem
  `PAD_VERILOG_MODELS`, nenhum pad existia para ele. O passo seguinte
  (`Yosys.Synthesis`, sem `USE_POWER_PINS`) é que usa o `PAD_LIBS`.
- **Resolvi com** (L61, L62):
  - `PAD_VERILOG_MODELS` = `sky130_ef_io.v` + `sky130_ef_io__gpiov2_pad_wrapped.v`
    de `tech/sky130_io/verilog/` (iguais aos do open_pdks `8afc8346`, `diff`
    sem diferença). A fatia continua só em `caixas_pretas.v` (o PDK não tem
    modelo dela; duas definições dariam erro de redefinição).
  - Com `USE_POWER_PINS` o `u_core` não tinha pino de alimentação nenhum: o
    núcleo ficaria sem ligação ao anel no netlist (e o LVS da etapa 12
    reclamaria). Agora `caixas_pretas.v` dá `vccd1`/`vssd1` ao `asic_top` e o
    `chip_top.v` liga `.vccd1(vccd)`, `.vssd1(vssd)` — os barramentos VCCD/VSSD
    do anel. `VDD_NETS`/`GND_NETS` do chip passam a `vccd`/`vssd`.
  - A simulação da etapa 10 usa o netlist do núcleo **sem** pinos de
    alimentação: o `pinos_alimentacao_pads.v` define `NUCLEO_SEM_ALIMENTACAO`
    e o `chip_top.v` só liga `vccd1`/`vssd1` sem ela.
- **Conferido aqui antes de mandar de volta** (sem PDK/OpenROAD na nuvem: o
  download do PDK pelo `ciel` é bloqueado): emulei os dois passos do Yosys com
  o `create_blackbox_model` do próprio LibreLane e o yowasp-yosys.

| Passo emulado | Entrada | Resultado |
|---|---|---|
| `Yosys.JsonHeader` | células + pads (Verilog, `USE_POWER_PINS`) + `chip_top.v` + `caixas_pretas.v` | passa; `u_core.vccd1 → vccd`, `vssd1 → vssd`; pads e fatia com VCCD/VSSD/VCCHIB/VDDIO/VSWITCH nas redes do anel |
| `Yosys.Synthesis` (elaboração) | 7 Liberty TT dos pads + Liberty das células + os dois `.v` | passa; 16 instâncias: núcleo, fatia, 4 gpiov2, 6 pads de alimentação, 4 `conb_1` |
| Etapa 10 com o `chip_top.v` novo | Icarus, mesma lista do `10_simula.sh`, núcleo trocado por um fio rx→tx | compila (a guarda `NUCLEO_SEM_ALIMENTACAO` funciona); `tx_pad` sem X em 1 ms. A simulação inteira (~1 h) não foi refeita: só a ligação do `u_core` mudou, e ela some com a guarda |

- **Tempo:** ~1 h (achar o porquê no fonte do LibreLane).
- **Vira slide?** Sim: "por que o LibreLane lê o mesmo pad de dois jeitos"
  — Verilog com pinos de alimentação para saber as ligações, Liberty para
  a síntese e o tempo.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L61 | `PAD_VERILOG_MODELS` = cópias em `tech/sky130_io/verilog/` | ✅ | Arquivos já versionados e conferidos iguais aos do PDK; a fatia fica em `caixas_pretas.v` |
| L62 | Núcleo ligado aos barramentos VCCD/VSSD do anel no `chip_top.v` (`VDD_NETS` = `vccd`) | ✅ | Sem isso o netlist do chip não diz de onde o núcleo tira 1,8 V; a simulação continua sem (`NUCLEO_SEM_ALIMENTACAO`) |

### 🐛 2ª rodada (`2026-10-31_0034`): o anel saiu, mas o PadRing parou ao ligar os barramentos

O que já deu certo (log do `OpenROAD.PadRing`, colado pelo Lukas):

| Lado | Soma dos pads | Comprimento | Espaço entre pads | Previsto (36ª) |
|---|---|---|---|---|
| Sul | 310 µm | 2300 | 398 | 398 ✅ |
| Leste | 95 µm | 1793 | 566 | 566 ✅ |
| Norte | 310 µm | 2300 | 398 | 398 ✅ |
| Oeste | 75 µm | 1793 | 859 | 859 ✅ |

`JsonHeader`, síntese (16 instâncias), floorplan (núcleo 300,38 … 2399,82 ×
301,92 … 1898,56 µm, por causa da grade das linhas) e `SetPowerConnections`
(todos os pinos de alimentação dos pads e do núcleo ligados) passaram. Os
cantos e o enchimento foram colocados.

- **Sintoma:** `[PAD-0002] fatia_vcchib/VDDIO (vddio) and IO_FILL_IO_EAST_1_565/VDDIO
  (vswitch) are touching, but are connected to different nets`, em
  "Connecting ring signals" (`connect_by_abutment`).
- **Causa:** LEF da fatia (open_pdks `8afc8346`) comparado com o de uma
  `com_bus_slice_1um`: a faixa de **met4 em y = 17,75–22,4 µm**, que nas fatias
  comuns é `VDDIO`, na fatia `connect_vcchib…` se chama **`VSWITCH`**; e o met5
  do `VCCHIB` (y 0,1–11,4) cobre a faixa do `VCCD` (6,95–11,4). A fatia não
  "liga uma rede na outra" por um fio: ela **funde os barramentos no metal**, e
  como os barramentos correm pelo anel inteiro, VSWITCH e VDDIO são **uma rede
  só no chip todo** (VCCHIB e VCCD também). O `chip_top.v` da etapa 10 tinha 12
  redes, com `vswitch` e `vcchib` separadas, e o modelo da fatia fazia a ligação
  com `tran`. Na simulação isso dá o mesmo resultado; no layout o PadRing achou
  duas redes se tocando e parou. Ele propaga as redes pelo encosto, por isso o
  enchimento vizinho herdou `vswitch` no lugar de `vddio`.
- **Resolvi com** (L63): no `chip_top.v`, todos os pads e a fatia ligam
  `.VSWITCH(vddio)` e `.VCCHIB(vccd)`; o anel passa a ter **10 redes**. O modelo
  da fatia (`tran`) agora liga uma rede nela mesma: inofensivo, e continua
  descrevendo o que a célula faz.
- **Conferido aqui:**

| Teste | Resultado |
|---|---|
| Elaboração com `USE_POWER_PINS` (Yosys) | `fatia_vcchib` e `pad_clk`: VCCHIB = VCCD = `vccd`, VSWITCH = VDDIO = `vddio`; `u_core`: `vccd1 → vccd` |
| Etapa 10 com núcleo de mentira (rx → tx), Icarus | compila; `tx_pad` sem X em 1 ms (sem VCCHIB alimentado, a entrada do pad daria X) |
| Faixas de met4/met5 na borda dos 6 pads de alimentação, do gpiov2 e do canto × `com_bus_slice` | todas com o mesmo nome (30 retângulos por pad); o mesmo script acusa a fatia (`met4 y17.75-22.4: VSWITCH, comum: VDDIO`), então ele funciona |

- **Tempo:** ~40 min.
- **Vira slide?** Sim: "uma célula que liga duas redes sem fio nenhum: os
  barramentos do anel de pads, com nome trocado no LEF".

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L63 | No `chip_top.v`, VSWITCH = `vddio` e VCCHIB = `vccd` em todos os pads (anel com 10 redes) | ✅ | A fatia funde esses barramentos no metal; o netlist tem de dizer o mesmo que o layout (PadRing agora, LVS na etapa 12) |

## 2026-10-31 (37ª sessão) — Etapa 11: o anel fechou; falta o GDS de 2 células

### 3ª rodada (`2026-10-31_0042`): `OpenROAD.PadRing` ✅

Do log colado pelo Lukas (passos 1–11 de 13 passaram):

| O quê | Resultado (log do PadRing / `odb-manualmacroplacement`) |
|---|---|
| Ligação dos barramentos por encosto | sem erro (L63 resolveu o `PAD-0002`) |
| Instâncias depois do anel | 446: núcleo, 4 gpiov2, 6 pads de alimentação, fatia, 4 `conb_1`, **426 fatias de enchimento** (*pad spacer*, 1,46 mm²) e **4 cantos** (*endcap*, 163.200 µm²) |
| Terminais (`PAD-0116`), todos em met5 | sul: `vssd_pad` y 30,8–98,1; `clk_pad`/`rstn_pad` y 33,0–95,4; norte: `rx_pad`/`tx_pad` y 2105,6–2168,0 (die vai até 2201); leste: `vdda_pad` x 2605,1–2665,9 (die até 2700); oeste: `vssa_pad` x 34,1–94,9 |
| Núcleo | `u_core` em (350, 350), N |

Os terminais confirmam a **rotação R180 (L55)**: em todos os lados o bond pad
ficou a ~30–100 µm da borda do die, ou seja, virado para fora; o lado de
1,8 V (IN/OUT, VCCD) olha para o núcleo.

### 🐛 `KLayout.StreamOut`: duas células sem GDS

- **Sintoma:** `[ERROR] LEF Cell 'sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um'
  has no matching GDS cell.` e o mesmo para `sky130_ef_io__gpiov2_pad_wrapped`.
- **Causa:** o **LEF** combinado `sky130_ef_io.lef` tem as duas células (o
  OpenROAD posicionou tudo), mas o **GDS** combinado `sky130_ef_io.gds` não.
  No open_pdks (`8afc8346`, `sky130/custom/sky130_fd_io/gds/`) cada uma vem num
  arquivo próprio. Conferido com o gdstk: o do gpiov2 tem 1 célula, que
  referencia `sky130_ef_io__gpiov2_pad`, e essa já está no combinado (o KLayout
  não reclamou dela); o da fatia é autocontido.
- **Resolvi com** (L64): `PAD_GDS` ganha
  `sky130_ef_io__gpiov2_pad_wrapped.gds` e
  `sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.gds`, e o
  `11_anel.sh` confere se os dois estão no PDK do notebook antes de rodar.
- **Tempo:** ~15 min.
- **Vira slide?** Sim, junto com o `FOREIGN` (L45): LEF e GDS são vistas
  separadas da mesma célula, e uma pode ter o que a outra não tem.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L64 | `PAD_GDS` com os GDS próprios do `gpiov2_pad_wrapped` e da fatia VCCHIB | ✅ | O GDS combinado do PDK não traz essas duas células |

### 🐛 Nota de git (não é do layout, mas custou uma rodada)

- **Sintoma:** depois de desfazer um commit local com `git reset origin/main`, a
  4ª rodada (`2026-10-31_0102`) falhou igual à 3ª: o comando do KLayout ainda
  tinha só 2 GDS de pads.
- **Causa:** `git reset` sem `--hard` move o ramo e o índice, mas **não mexe nos
  arquivos do disco**; eles ficaram na versão de antes da L64 (o próprio git
  avisou: `Unstaged changes after reset: M ... config.json`). O `git pull`
  respondeu "Already up to date" porque o ramo já estava certo.
- **Resolvi com:** `git checkout -- <os 3 arquivos>`. O comando certo teria sido
  `git reset --hard origin/main` (quando não há nada local a guardar).
- **Vira slide?** Não; vira dica no LEIAME.

### 5ª rodada (`2026-10-31_0106`): parte 1 ✅ — 13/13 passos

Fonte: log colado pelo Lukas e `resultados/2026-10-31_0106_layout_chip/`
(`11_anel_metricas.json`, `imagens/11_anel.png`).

| Métrica (`11_anel_metricas.json`) | Valor |
|---|---|
| Die | 0 0 2700 2201 µm (5,94 mm²) |
| Área de núcleo (linhas) | 300,38 301,92 2399,82 1898,56 µm (3,35 mm²) |
| Instâncias | 446 |
| Área das células de pad (`padcells`) | 1,62 mm²: enchimento 1,46 mm², cantos 0,16 mm², pads de alimentação 0,089 mm², gpiov2 0,068 mm², fatia 0,004 mm² |
| Núcleo (macro) | 3,00 mm² |
| Células-padrão | 4 `conb_1` (15 µm²) |
| `KLayout.StreamOut` | "All LEF cells have matching GDS cells" |

O que se vê na imagem (`11_anel.png`, 1000 × 815 px):

| Conferência | Resultado |
|---|---|
| Anel contínuo nos 4 lados, cantos nos 4 cantos | ✅ |
| Norte e sul com 4 pads cada; oeste com 1; leste com o pad de VDDA (a fatia de 20 µm quase não aparece nessa escala) | ✅ |
| Bond pads (quadrados laranja) na borda **de fora** em todos os lados (L55) | ✅ |
| Núcleo em (350, 350): na imagem vai de x ≈ 148 a 845 px e y ≈ 144 a 660 px, o que bate com 350…2350 × 350…1850 µm na escala de 0,352 px/µm | ✅ |
| Faixas de alimentação do núcleo visíveis (met5 horizontal em amarelo, met4 vertical em roxo): são os pinos `vccd1`/`vssd1` do LEF (50 retângulos cada) | ✅ |
| Folga entre o anel e o núcleo: ~100–150 µm | onde vão o anel de PDN do chip e as ligações pad ↔ núcleo (parte 2) |

### Para continuar: etapa 11, parte 2

| A fazer | Como (a conferir no fonte do LibreLane 3.0.14 antes de escrever) |
|---|---|
| Ligar VCCD/VSSD dos pads ao núcleo | anel de PDN do chip em volta da macro (met4/met5) ligado aos pinos de 1,8 V dos pads, e as faixas do núcleo ligadas ao anel; PDN de células-padrão quase vazio (só 4 `conb_1`) |
| Rotear 4 sinais + as amarrações dos pads | pinos IN/OUT dos gpiov2 (met2, borda de dentro) até os pinos do núcleo (met2/met3 na borda da macro); `conb_1` posicionadas perto de cada pad |
| Fluxo | `config.json` sozinho (fluxo `Chip` inteiro), depois DRC/LVS (etapa 12) |

### Parte 2a: o PDN do chip (`pdn_chip.tcl`)

O LEF do núcleo veio pelo git (`resultados/2026-10-31_0106_layout_chip/asic_top.lef.gz`).
O que ele diz sobre a alimentação (números do arquivo):

| O quê | Onde (coordenadas da macro, µm) |
|---|---|
| Anel do núcleo | `vssd1` por fora (met4 x 29,12–30,72 e 1968,9–1970,5; met5 y 29,9–31,5 e 1467,22–1468,82), `vccd1` por dentro (x 32,42–34,02 / 1965,6–1967,2; y 33,2–34,8 / 1463,92–1465,52), 1,6 µm de largura |
| Faixas met4 (verticais) | 13 por rede, passo 153,6, `vccd1` a partir de x = 55,54; várias partidas onde há SRAM |
| Faixas met5 (horizontais) | 10 por rede, passo 153,18, `vccd1` a partir de y = 56,65; todas de x = 29,12 a 1970,5 |
| Obstrução (OBS) perto da borda | met4: faixa corrida y 2,2–29,5 (embaixo) e y 1469,2–1470,7 (em cima); met5: x 21,7–27,5 na frente de cada faixa (à esquerda), mas **nada à direita de x = 1953,5** |

Os pads (LEF do open_pdks): só `vccd_lvc_clamped_pad` e `vssd_lvc_clamped_pad` têm
pino de alimentação virado para o núcleo, em met3 (dois retângulos de ~24 µm).

**O problema:** o núcleo ocupa met4 **e** met5. O jeito comum de alimentar uma
macro (faixa de met5 do chip passando por cima dos pinos de met4 dela, com via,
como foi feito com as SRAMs no núcleo) não serve: não há camada livre por cima.
A ligação tem de ser na borda, e a única borda sem obstrução na frente dos pinos
é a **direita, em met5**.

**A solução (L65):**
1. grade do chip com o mesmo passo, largura e espaçamento das faixas do núcleo
   (os padrões do LibreLane para o sky130, conferidos: o centro da 1ª faixa do
   núcleo = canto da área de núcleo dele + 16,32 / 16,65) e deslocamento
   calculado para a macro em (350, 350): `-offset 105.96` (met4) e
   `105.53` (met5);
2. anel do chip em met4/met5 (5 µm), ligado ao met3 dos pads VCCD/VSSD
   (`-connect_to_pads -connect_to_pad_layers met3`);
3. a macro com uma grade de instância vazia (halo de 5 µm), só para o `pdngen`
   não passar faixas por cima dela;
4. **depois do `pdngen`**, uma ponte de met5 por faixa, da ponta da faixa do chip
   até 1 µm dentro do pino do núcleo (mesma camada, mesma rede: liga por
   sobreposição, sem via). 10 por rede. O LibreLane não tem gancho depois do
   `pdngen`, então o `pdn_chip.tcl` roda o `pdngen` ele mesmo e troca o
   comando por um aviso para a segunda chamada (a do `pdn.tcl`).

Mais um par de faixas met4 em cada faixa estreita à esquerda e à direita da
macro (L66): sem elas, as linhas de células (tap cells, `conb_1`) de lá ficariam
sem alimentação, porque as faixas alinhadas com o núcleo só começam em x = 406.

**Conferido aqui (sem OpenROAD):**

| Teste | Resultado |
|---|---|
| Pontes contra a OBS do LEF (Python) | por baixo: as 26 batem na OBS de met4 (y 2,2–29,5); pela direita: as 20 livres |
| `pdn_chip.tcl` num OpenDB de mentira (tclsh, caixas reais do LEF) | 1ª tentativa: **0 pontes** (o filtro descartava faixas com `xMin` < 40 µm, e todas começam em 29,12); corrigido: 20 pontes, 1ª `vccd` em y 406,65–408,25 (centro 407,45 = 301,92 + 105,53, alinhada com a grade), x 2319,5–2365 |

Para conferir no notebook: `bash layout/chip/11_anel.sh pdn` (fluxo reduzido
`config_pdn.json`: anel → `CutRows` → `TapEndcapInsertion` → `GeneratePDN` → GDS/PNG
→ `Checker.PowerGridViolations`).

Observação para depois (não muda nada agora): os pinos de sinal do núcleo estão
na borda **esquerda** (`clk_i` y 1447, `uart0_rxd_i` 681, `uart0_txd_o` 610) e em
cima (`rstn_i` x 1629). Os pads de clk/rstn estão embaixo e os de rx/tx em cima
(L57), então o roteamento vai dar a volta na macro. Funciona, mas se o tempo de
entrada/saída ficar ruim, mudar os pads de lado é a correção.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L65 | PDN do chip: grade alinhada com a do núcleo + anel ligado aos pads + 20 pontes met5 pela direita, feitas depois do `pdngen` | ✅ | Núcleo ocupa met4/met5; a única borda sem OBS na frente dos pinos é a direita |
| L66 | Um par de faixas met4 em cada faixa estreita ao lado da macro | ✅ | Alimentar as linhas de células fora do alcance da grade alinhada |
| L67 | Parte 2 em duas: PDN primeiro (`config_pdn.json`), fluxo inteiro depois | ✅ | Mesmo motivo da L60: ver o PDN antes de horas de roteamento |

### Parte 2a, 1ª rodada (`2026-10-31_0135`): PDN gerado, 17/17 passos

Do log colado pelo Lukas:

| Passo | Resultado |
|---|---|
| `CutRows` | 587 linhas cortadas pela macro (halo 10 µm) em 1146 pedaços (223.940 sítios) |
| `TapEndcapInsertion` | 1174 endcaps e 3710 tap cells (instâncias: 446 → 4156; metade dos endcaps contados como *fill*) |
| `GeneratePDN` | `Inserting grid: chip`, `Inserting grid: nucleo - u_core`, **20 pontes** (`pontes_nucleo: 10 ... vccd`, `10 ... vssd`), a 2ª chamada do `pdngen` virou o aviso esperado |
| `KLayout.StreamOut`/`Render` | GDS e `11_pdn.png` |
| `Checker.PowerGridViolations` | 2 "violações" = os 2 `PSM-0025` abaixo (erro adiado) |

### 🐛 `[PSM-0025] vccd does not contain any terminals` (e `vssd`)

- **Causa:** o `check_power_grid` (OpenROAD PSM) parte dos **terminais** da rede,
  os pinos de topo do bloco, e confere se tudo se liga a eles. No núcleo,
  `vccd1`/`vssd1` eram pinos de topo. No chip a alimentação entra pelo **pad**: o
  pino de topo é o `vccd_pad` (o bond pad), do outro lado da célula do pad, e a
  rede interna `vccd` não tem terminal. A verificação não tem de onde partir; não é
  sinal de rede solta (os relatórios `vccd/vssd-grid-errors.rpt` saíram vazios porque
  a verificação nem começou).
- **Resolvi com** (L68): `ERROR_ON_PDN_VIOLATIONS = false` no `config.json` do chip.
  A conferência da alimentação fica com a imagem agora e com o **LVS** na etapa 12
  (o próprio LibreLane diz: "you may ignore these if LVS passes").
- **Vira slide?** Sim: o que um verificador precisa saber para funcionar (aqui, onde
  a corrente entra).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L68 | `ERROR_ON_PDN_VIOLATIONS = false` no chip | ✅ | O PSM precisa de pino de topo na rede; no chip a alimentação entra pelo pad. Quem confere é o LVS |

**A imagem `11_pdn.png`** (`resultados/2026-10-31_0135_layout_chip/imagens/`): aparecem
as linhas de células com tap cells em volta da macro (a faixa azul densa entre o
anel e o núcleo), as faixas met5 (amarelo) indo do anel até a macro dos dois
lados e as faixas met4 em cima/embaixo e nas laterais. O que **não dá para ver**
nessa escala (0,35 px/µm): se o `-connect_to_pads` ligou o anel aos pads VCCD/VSSD,
e o log do `GeneratePDN` não diz nada sobre isso.

**`layout/chip/confere_pdn.py`** (sem nix-shell, só lê o DEF do passo de PDN): conta,
para `vccd`/`vssd`, (1) fios e vias entre cada pad de alimentação e o anel
(y = 150–280 µm), (2) as pontes até o núcleo, (3) os lados do anel (5 µm). Testado
com um DEF sintético no formato do OpenROAD: a 1ª versão lia o `( * VPWR )` do
cabeçalho da rede como ponto (corrigido) e contava o próprio anel como ligação ao
pad (janela fechada em y = 280, abaixo do anel). O `11_anel.sh pdn` passa a rodá-lo
e salvar `11_pdn_geometria.txt`.

### 🐛 O anel não estava ligado aos pads

- **Sintoma** (`confere_pdn.py` no DEF da rodada `2026-10-31_0135`, colado pelo Lukas):

| Item | vccd | vssd |
|---|---|---|
| Fios/vias entre o pad e o anel (y 150–280) | **0 / 0** (pad em x = 2027) | **0 / 0** (pad em x = 598) |
| Pontes até o núcleo | 10 (y 407,45; 560,63; 713,81…) | 10 (y 410,75; 563,93; 717,11…) |
| Anel | 4 lados, (289,4; 290,9)–(2410,8; 1909,6) | 4 lados, (282,7; 284,2)–(2417,5; 1916,3) |

  Grade, anel e pontes certos; **o chip não recebia alimentação**: o `-connect_to_pads`
  não fez nada, sem erro nem aviso no log.
- **Causa** (fonte do pdngen, `src/pdn/src/straps.cpp` e `grid.cpp`): os pinos foram
  achados (o `getPinsFacingCore` quer o pino encostado na borda da célula virada para
  o núcleo, e o met3 do `vccd_lvc_clamped_pad` encosta, depois do R180). Mas a ligação
  é uma faixa **na camada do pino (met3)** que só pode terminar em via para uma camada
  **vizinha** (met2/met4). O lado de baixo do anel é **met5**: sem alvo, a faixa é
  descartada (a mensagem "Rejecting pad cell pin" só sai com o depurador ligado).
- **Resolvi com** (L69): `ligacao_pads` no `pdn_chip.tcl`, depois do `pdngen`. Para cada
  pino de met3 virado para dentro: faixa de met3 do pino até a barra met5 da própria
  rede e pilhas `M3M4_PR` + `M4M5_PR` (vias do tlef do sky130) a cada 2 µm onde a faixa
  cruza a barra. Cada pilha tem só o seu quadrado de met4 (1,18 µm): perto do pad de
  VCCD desce até o anel uma faixa met4 de **vssd** da grade (x 2098,44–2100,04), e uma
  placa de met4 inteira curtaria as duas redes. Colunas a menos de 0,3 µm de met4 de
  outra rede são puladas. O `-connect_to_pads` saiu do `add_pdn_ring`.
- **Conferido aqui** (OpenDB de mentira com as caixas reais dos LEFs dos pads e o anel
  e as faixas na posição do DEF):

| Pad | Faixas met3 (µm) | Pilhas de via |
|---|---|---|
| `pad_vccd` | x 2027,3–2051,245 e 2077,5–2101,5; y 191,1 → 295,92 | 44 (4 colunas puladas perto da faixa de vssd); 0 encostando nela |
| `pad_vssd` | x 598,3–622,245 e 648,5–672,5; y 158,4 → 289,22 | 48 |

- **Tempo:** ~1 h (achar a causa no fonte do pdngen).
- **Vira slide?** Sim: "uma ferramenta que desiste em silêncio", e por que conferir
  pela geometria quando a verificação automática não se aplica.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L69 | Ligação pad → anel feita à mão (faixa met3 + pilhas de via), sem `-connect_to_pads` | ✅ | O pdngen só liga o met3 do pad a met2/met4; o anel embaixo é met5 |

### Parte 2a, 2ª rodada (`2026-10-31_1024`): PDN ✅ — alimentação ligada de ponta a ponta

Do log e de `resultados/2026-10-31_1024_layout_chip/11_pdn_geometria.txt`:

| Conferência | Resultado |
|---|---|
| `ligacao_pads` (log do `GeneratePDN`) | `pad_vccd/VCCD`: 2 faixas met3, **44** pilhas (barra y 290,92–295,92); `pad_vssd/VSSD`: 2 faixas, **48** pilhas (barra 284,22–289,22) — igual ao previsto pelo teste com o OpenDB de mentira |
| Formas especiais no DEF | vccd 4747 → **4837** (+90 = 2 faixas + 44 × 2 vias); vssd 4747 → **4845** (+98 = 2 + 48 × 2): as vias foram criadas |
| Fios entre pad e anel (y 150–280) | vccd 2 (met3), vssd 2 (met3) — antes 0 |
| Pontes até o núcleo | 10 + 10 |
| Anel | 4 lados em cada rede |
| Fluxo | 17/17, código 0 (o PSM virou aviso, L68) |

Cadeia completa: bond pad → célula do pad → met3 (faixa) → via3/via4 → anel met5/met4 →
faixas da grade (met4/met5) → pontes met5 → pinos `vccd1`/`vssd1` do núcleo. Quem
confirma eletricamente é o LVS (etapa 12).

### Parte 2b: o fluxo `Chip` inteiro — o que fica de fora e por quê

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L70 | `RUN_CTS = false` no chip | ✅ | Não há flip-flop no nível do chip: a árvore de relógio está dentro do núcleo; aqui o relógio é um fio do pad ao pino `clk_i` da macro (sem Liberty), e a CTS não teria destino |
| L71 | `RUN_MAGIC_DRC`, `RUN_KLAYOUT_DRC`, `RUN_LVS = false` na parte 2b | ✅ | Ficam para a etapa 12, preparados: o núcleo como caixa-preta no DRC do Magic (como a L42) e os modelos SPICE dos pads para o LVS. Sem isso reprovariam por falta de preparação, depois de muito tempo rodando. O XOR (Magic × KLayout) continua: já pegou erro antes (L45) |

`bash layout/chip/11_anel.sh chip` roda só o `config.json` (fluxo `Chip`: posicionamento das 4
`conb_1`, roteamento global e detalhado dos sinais pad ↔ núcleo, RCX, STA, GDS pelo Magic e
pelo KLayout, XOR, antena, enchimento, densidade) e guarda também folga de setup/hold,
erros de roteamento e comprimento de fio.

### Parte 2b, 1ª rodada (`2026-10-31_1029`): 49 passos bons, parou no `OpenROAD.IRDropReport`

Números de `resultados/2026-10-31_1029_layout_chip/11_chip_metricas.json` (estado do passo 49,
`STAPostPNR`) e dos logs em `logs_anel.tar.gz`:

| Passo | Resultado |
|---|---|
| Posicionamento | 3780 células-padrão: 3710 tap, 4 endcap, **55** `conb_1`, 11 diodos; 437 células do anel (4 pads de sinal, 6 de alimentação, 426 enchimentos, 1 fatia) |
| `RepairDesignPostGPL` | `RSZ-0042`: inseriu 42 + 13 `conb_1` (4 → 55): o resizer dá **um tie por pino** ligado a constante (pinos de configuração dos pads), em vez de um tie puxando fio longo. `RSZ-0020`: 2 redes "flutuando", `vccd` e `vssd` — no netlist são redes de sinal que só ligam pinos de alimentação; quem as liga é o PDN (aviso esperado) |
| Roteamento global | 15207 µm estimados |
| Antena | `rstn_core` reprovou no global; `RepairAntennas` resolveu (1 jumper, 11 diodos); depois do detalhado: **0** redes violando |
| Roteamento detalhado | **0** erros de DRC (18 → 1 → 1 → 0 nas iterações); **14696 µm** de fio; maior rede 2767 µm |
| Pinos desconectados | 17, nenhum crítico |
| Enchimento | 75420 células de enchimento; utilização das células-padrão 47,7 % |
| STA pós-roteamento (RCX) | setup e hold: 0 violações, folga 1e39 = **sem caminho restrito**. O núcleo é macro sem Liberty: o relógio chega no pino `clk_i` e para ali. O tempo dos sinais pad ↔ núcleo só aparece com um `.lib` do núcleo (etapa 12 ou depois) |
| `IRDropReport` | ❌ `[PSM-0069] Check connectivity failed on vccd` |

### 🐛 `PSM-0069`: o núcleo não estava ligado à grade do chip

- **Sintoma:** `analyze_power_grid -net vccd` → 49 × `PSM-0038 Unconnected shape on net vccd`
  (as faixas met4/met5 do **próprio núcleo**, em coordenadas do chip) e
  `PSM-0039 Unconnected instance u_core/vccd1`; depois `PSM-0069`. Nenhum pad e nenhuma
  célula-padrão na lista: o resto da rede estava inteiro.
- **Causa:** a forma met5 acusada vai de (379,12; 406,65) a (**2365,000**; 408,25): é o pino do
  núcleo juntado com a ponte, e acaba exatamente na ponta da ponte (`borda + 15 µm`). Eu contava
  com um **toco da faixa met5 do chip** entre o halo da macro (2355) e o anel (2405,8) para a
  ponte sobrepor. O toco existe, mas **começa em x ≈ 2379** (faixa met4 de borda): o pdngen
  apara a ponta solta de cada faixa até a última via. Ficaram 13 µm de vão entre a ponte e o
  toco (confirmado na 2ª rodada, abaixo). Sobrepor no mesmo metal só liga se houver o que
  sobrepor. O `confere_pdn.py` contava as pontes, mas não
  olhava onde elas terminavam: por isso a parte 2a pareceu fechada.
- **Resolvi com (L72):** `pontes_nucleo` agora leva cada ponte até o **lado direito do anel da
  própria rede** (met4 vertical de 5 µm: vccd até x = 2410,82, vssd até 2417,52) e põe vias
  `M4M5_PR` (a cada 2 µm, centradas) onde a ponte cruza met4 da mesma rede fora da macro: o lado
  do anel (2 vias) e a faixa de borda em x ≈ 2379/2383 (1 via). Se o pdngen já tiver via ali,
  não repete. Ponte sem nenhuma via → erro no `GeneratePDN` (não deixa passar calado de novo).
  A ponte de vssd cruza o lado do anel de vccd em met5 sobre met4: camadas diferentes, sem via.
  O `confere_pdn.py` passou a mostrar onde as pontes terminam e quantas têm via (no DEF de teste
  antigo: "terminam em x = 2365,00; 0 com via" — teria pegado o erro na parte 2a).
- **Conferido** com o OpenDB de mentira (`mock3.tcl`, pinos reais do LEF, anel e faixas do DEF):
  20 pontes até o anel, 60 vias M4M5, todas com o met4 da via dentro de met4 da própria rede;
  a `ligacao_pads` continua igual (44 e 48 pilhas).
- **Tempo:** ~40 min de diagnóstico e correção.
- **Vira slide?** Sim: "o checador que conta não basta, tem de olhar onde termina" — e o PSM
  como verificação de conectividade da alimentação antes do LVS.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L72 | Pontes met5 do núcleo vão até o lado direito do anel do chip (met4) com vias M4M5 feitas à mão; ponte sem via é erro | ✅ | O toco de faixa met5 do chip com que a 1ª versão contava começa só em x ≈ 2379 (o pdngen apara a ponta solta), 13 µm depois da ponte (PSM-0069). Levar a ponte até o anel não depende de como o pdngen apara as faixas perto da macro |

### Parte 2b, 2ª rodada (`2026-10-31_1524`): PDN ✅, parou no `Magic.StreamOut`

| Conferência | Resultado (fonte) |
|---|---|
| `pontes_nucleo` (log do `GeneratePDN`) | 10 + 10 pontes, até x = 2410,82 (vccd) e 2417,52 (vssd); **0 vias novas**: em todo cruzamento já havia via do pdngen (o toco met5 × faixa de borda × anel), então a função só reconheceu a ligação |
| `confere_pdn.py` (`11_pdn_geometria.txt`) | vccd: 10 pontes, 10 com via à direita da macro; vssd: 10, 10 |
| `IRDropReport` (`irdrop.rpt`) | `PSM-0040 All shapes on net vccd are connected` (e vssd). Queda pior: vccd **16 µV**, vssd **77,5 µV** (0,00 %), potência 1,73 mW — só as células do chip; o núcleo é macro sem consumo declarado, então isto testa a **ligação**, não a queda real |
| Roteamento, antena, STA | iguais à 1ª rodada (0 DRC, 14696 µm, 0 antena, 0 violações) |
| `Magic.StreamOut` | ❌ `Encountered one or more fatal errors while running Magic` — com o GDS gravado ("GDS Write Complete") |

### 🐛 `Magic.StreamOut`: 19 células dos pads vazias, por causa da ordem dos GDS

- **Sintoma:** 38 linhas `Error while reading cell "...": cell sky130_fd_io__overlay_vccd_hvc
  was used but not defined` (19 células: `overlay_*`, `top_gpiov2`, `top_power_*_wpad*`,
  `top_ground_*_wpad`, `corner_bus_overlay`), metade ao ler `sky130_ef_io.gds` e metade ao ler
  `sky130_fd_io.gds`. O Magic não devolve código de erro; o LibreLane procura essa frase no log
  (`MAGIC_CAPTURE_ERRORS`, regex `Error while reading cell(?!.*Warning:)`) e reprova. Os
  milhares de "Unknown layer/datatype" das SRAM aparecem só no `asic_top.get_bbox.log`, que não
  passa por esse filtro (são as camadas da OpenRAM já vistas na L44).
- **Causa:** o `read_pad_gds` lê o `PAD_GDS` na ordem da lista, com `gds noduplicates true`.
  O `sky130_ef_io.gds` vinha primeiro e usa células que estão no `sky130_fd_io.gds`: o Magic cria
  células **vazias** no lugar delas. Quando o `sky130_fd_io.gds` chega, o `noduplicates` pula
  essas 19 porque "já existem", e elas continuam vazias (por isso a mesma lista aparece de novo
  no fim do 2º arquivo). Seria um GDS com pads ocos.
- **Resolvi com (L73):** `PAD_GDS` com a biblioteca base primeiro (`sky130_fd_io.gds`, depois
  `sky130_ef_io.gds`, depois os dois avulsos) — a mesma regra da ordem de ligação de
  bibliotecas: quem define vem antes de quem usa. O `11_anel.sh` agora grava
  `11_magic_resumo.txt` (linhas fatais e ordem dos `gds read`).
  Sem Magic e sem PDK na sessão do Claude: a conferência é a próxima rodada (deve vir sem
  nenhuma linha "was used but not defined").
- **Por que não `MAGIC_CAPTURE_ERRORS = false`:** passaria, mas com as 19 células vazias no GDS
  — o filtro do LibreLane pegou um defeito real.
- **Tempo:** ~30 min.
- **Vira slide?** Sim: "ordem de leitura importa" (mesma ideia da ordem de `-l` no ligador).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L73 | `PAD_GDS`: `sky130_fd_io.gds` antes de `sky130_ef_io.gds` | ✅ | Com `gds noduplicates`, a célula usada antes de ser definida fica vazia para sempre; a biblioteca base tem de vir primeiro |

### Parte 2b, 3ª rodada (`2026-10-31_1645`): a L73 funcionou; sobrou 1 linha

`resultados/2026-10-31_1645_layout_chip/11_magic_resumo.txt`: a ordem dos `gds read` agora é
`fd_io` → `ef_io` → os dois avulsos, e as 38 linhas "was used but not defined" sumiram. PDN e
IR drop iguais à 2ª rodada (`PSM-0040` nas duas redes). Sobrou **uma** linha fatal, e o passo
reprovou de novo:

### 🐛 `Boundary is not closed` no GDS do próprio PDK

- **Sintoma:** `Error while reading cell "sky130_fd_io__overlay_vddio_lvc" (byte position
  11540404): Boundary is not closed.` O Magic termina ("GDS Write Complete"), o LibreLane reprova.
- **Causa:** no GDSII um polígono (`BOUNDARY`) tem de repetir o primeiro ponto no fim. Um
  polígono dessa célula do `sky130_fd_io.gds` não repete: defeito do arquivo do PDK. Nem usamos
  essa célula (ela não aparece nas linhas "Copying output for cell" do log), mas o Magic lê o
  arquivo inteiro e reclama.
- **Resolvi com (L74):** `layout/chip/fecha_gds.py` lê os registros do GDS direto (2 bytes de
  tamanho, 1 de tipo, 1 de tipo de dado, dados big-endian; sem biblioteca), lista os `BOUNDARY`
  abertos (célula, camada, primeiro e último ponto) e grava uma cópia em que só o `XY` desses
  polígonos ganha o primeiro ponto repetido no fim — o resto sai byte a byte igual. O
  `11_anel.sh` gera `layout/chip/entrada/sky130_fd_io.gds` (fora do git; refaz só se o PDK
  mudar), confere os outros três GDS dos pads, e o `PAD_GDS` aponta para a cópia.
  Testado com um GDS sintético (KLayout do pip): um polígono aberto de propósito é achado, e a
  cópia consertada sai **idêntica** (`cmp`) ao arquivo original fechado.
- **Por que não regravar com o KLayout:** ele também fecha o polígono, mas reescreve o arquivo
  todo (ordem das células, propriedades); o conserto no registro mexe só no que está errado e
  dá para conferir.
- **Por que não `MAGIC_CAPTURE_ERRORS = false`:** desligaria o filtro que acabou de pegar as
  células vazias da L73.
- **Tempo:** ~30 min.
- **Vira slide?** Sim: o formato GDSII por dentro (registros) e "o PDK também tem defeito".

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L74 | Cópia do `sky130_fd_io.gds` com os `BOUNDARY` fechados (`fecha_gds.py`), usada no `PAD_GDS` | ✅ | Defeito do arquivo do PDK; conserto mínimo e conferível, sem desligar o filtro de erros do Magic |

### 🐛 4ª rodada (`2026-10-31_2015`): a cópia saiu de **outra versão do PDK**

- **Sintoma:** o `Boundary is not closed` sumiu, mas apareceram 8 linhas `Error while reading
  cell "sky130_fd_io__res250_sub_small" (byte position 188864): NODE elements not supported`
  (`11_magic_resumo.txt`). Na rodada `1645`, lendo o `sky130_fd_io.gds` do PDK, essa célula
  passou sem aviso.
- **Causa:** a `entrada/sky130_fd_io.gds` não é a mesma biblioteca: no `magic-streamout.log` ela
  começa com as células `polygon03812`, `polygon03811`... e tem 1049 linhas de leitura contra
  3750 do arquivo da `1645` (que começa com `hvDFL1sd_CDNS_...`). O `11_anel.sh` achava a pasta
  dos pads com `find ... | head -1`, sem filtrar a versão; no notebook há mais de uma versão do
  PDK, e veio uma que não é a `8afc8346` do LibreLane (L10). Até aqui isso só servia para
  conferir se os arquivos existiam, e ninguém notou; com a L74 o arquivo passou a ser **usado**.
  É a mesma armadilha que o `gera_maglef` do `comum.sh` já evitava com `-path '*8afc8346*'`.
- **Resolvi com (L75):** o `find` filtra `*8afc8346*` (e erra se não achar, em vez de pegar outra
  versão). A cópia guarda a origem (`entrada/sky130_fd_io.gds.origem`: caminho real e tamanho) e
  é refeita quando a origem muda — o teste antigo por data (`-nt`) não refaria, porque a cópia
  errada é mais nova que o original certo. Testado o `find` numa árvore falsa com duas versões.
- **Tempo:** ~25 min.
- **Vira slide?** Sim, junto com a L10: "qual PDK?" — duas versões instaladas, e um `head -1`
  decide qual entra no chip.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L75 | `11_anel.sh` acha os pads só na versão `8afc8346` do PDK; a cópia da L74 é refeita quando a origem muda | ✅ | Com duas versões instaladas, o `head -1` pegou a outra; o arquivo dos pads tem de ser o mesmo PDK do resto do fluxo |

### Parte 2b, 5ª rodada (`2026-10-31_2058`): o fluxo `Chip` foi até o fim — 67 passos

`11_magic_resumo.txt`: **nenhuma** linha fatal; `sky130_fd_io.gds` lido da cópia
consertada da versão `8afc8346`. Métricas de `11_chip_metricas.json`, mensagens do `flow.log`:

| Passo | Resultado |
|---|---|
| Roteamento detalhado | **0** erros de DRC, 14696 µm |
| Antena (OpenROAD) | 0 redes violando |
| IR drop | `PSM-0040` nas duas redes; pior 16 µV (com "bump pattern", ver pendência) |
| STA / slew / capacitância | 0 / 0 / 0 violações (sem caminho restrito: núcleo sem `.lib`) |
| `Magic.StreamOut`, `KLayout.StreamOut` | ✅ os dois GDS |
| `Checker.XOR` | ❌ adiado: **3** diferenças, todas na camada **71/44 (via4)**: 57649 × 57654 polígonos |
| `Magic.SpiceExtraction` + `Checker.IllegalOverlap` | ❌ adiado: **24** sobreposições "obsm4 × metal4" |
| `KLayout.Antenna`, `Filler`, `Density` | pulados: o PDK não traz os runsets do KLayout para o sky130 no LibreLane (`KLAYOUT_*_RUNSET is unset`) |
| DRC, LVS | pulados de propósito (L71, etapa 12) |

Imagem: `resultados/2026-10-31_2058_layout_chip/imagens/11_chip.png`.

### 🐛 XOR na via4: via em cima de via

- **Sintoma:** 3 diferenças entre o GDS do Magic e o do KLayout, só na via4 (5 polígonos a
  mais num deles).
- **Causa:** a `ligacao_pads` (L69) pulava as colunas com met4 da **outra** rede, mas não as da
  **própria**. Perto do `pad_vccd`, a faixa met4 vccd da grade (x 2095,14–2096,74) desce até a
  barra do anel, e o pdngen já põe ali a via4 dele. Duas pilhas minhas (x = 2096,5;
  y = 292,42 e 294,42, pelo mock) caíam em cima: cortes de via4 encavalados. O KLayout grava as
  duas vias como estão; o Magic junta os contatos numa área só e gera os cortes de novo pela
  regra dele. Daí os dois GDS divergem — e via encavalada é erro de DRC de qualquer jeito.
  (O local exato das 3 diferenças não está nos logs: o XML do XOR ficava fora do pacote.)
- **Resolvi com (L76):** a `ligacao_pads` pula também as colunas sobre met4 da própria rede (ali
  a faixa já liga na barra pela via do pdngen). Mock: `pad_vccd` 44 → **40** pilhas, nenhuma
  sobre a faixa; `pad_vssd` continua com 48. O `11_anel.sh` passa a guardar os `*.xml` (o
  relatório do XOR) no `logs_anel.tar.gz`.
- **Tempo:** ~30 min.
- **Vira slide?** Sim, junto com a L45: o XOR entre duas ferramentas pegou um erro que nenhum
  dos checadores anteriores pegou.

### 🐛 24 sobreposições ilegais: a sobra de OBS dos pads lvc

- **Sintoma:** `Illegal overlap between obsm4 and metal4 (types do not connect)`, em 4 grupos de
  caixas: x 586,8–598,0 e 2015,8–2027,0, y 153,8–163,3 µm (`feedback.txt` × `cif_scale.txt`
  = 0,005). É a faixa logo à **esquerda** do `pad_vssd` (x = 598) e do `pad_vccd` (x = 2027).
- **Causa:** a extração do LibreLane (`Magic.SpiceExtraction`) monta o chip pelo DEF + os
  **LEF** (vista abstrata), não pelo GDS. O LEF de `sky130_ef_io__vccd_lvc_clamped_pad` e de
  `..._vssd_lvc_clamped_pad` tem dois `OBS` de met4 que **saem 11,16 µm da célula**
  (x 75,0–86,14 e 75,0–86,165, y 34,7–44,2 no LEF; em R180 caem à esquerda do pad, y 153,8–163,3).
  Ali está o met4 do vizinho no anel, e o Magic acusa obstrução × metal. Os pads hvc não têm
  essa sobra (conferido no LEF do `vdda_hvc`). Afastar não adianta: o anel precisa de vizinho
  encostado para os barramentos continuarem.
- **Decisão (L77):** `ERROR_ON_ILLEGAL_OVERLAPS = false` no chip. A sobreposição é da vista
  abstrata; quem decide se há curto de verdade é o LVS da etapa 12, extraído do **GDS**
  (`MAGIC_EXT_USE_GDS`), onde aquela obstrução vira o metal que ela representa.
- **Tempo:** ~20 min.
- **Vira slide?** Talvez: "vista abstrata × vista real" (a mesma lição da L42, ao contrário).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L76 | `ligacao_pads` pula colunas sobre met4 da própria rede também | ✅ | Ali o pdngen já pôs via4; via em cima de via deu XOR (e seria erro de DRC) |
| L77 | `ERROR_ON_ILLEGAL_OVERLAPS = false` no chip | ✅ | As 24 sobreposições vêm do OBS met4 que sai 11 µm do LEF dos pads lvc; extração abstrata. O LVS pelo GDS (etapa 12) é a verificação que vale |

## 2026-11-01 (38ª sessão) — ✅ Etapa 11 fechada: o fluxo `Chip` completo, `Flow complete.`

Rodada `2026-11-01_1249` (`resultados/2026-11-01_1249_layout_chip/`): 67 passos,
`flow.log` termina em "Flow complete." e não há nenhum erro adiado.

| Conferência | Resultado (fonte) |
|---|---|
| `ligacao_pads` (log do `GeneratePDN`) | `pad_vccd`: **40** pilhas (era 44, L76), `pad_vssd`: 48 — igual ao mock |
| `pontes_nucleo` | 10 + 10 pontes até o anel; 0 vias novas (as do pdngen já estavam lá, L72) |
| Magic (`11_magic_resumo.txt`) | **0** linhas fatais; `sky130_fd_io.gds` da cópia consertada da versão `8afc8346` (L73–L75) |
| XOR Magic × KLayout | **0** diferenças ("Check for XOR differences clear") |
| Sobreposição ilegal | 24, agora só aviso (L77; o LVS pelo GDS decide) |
| Roteamento detalhado | 0 erros de DRC, 14696 µm |
| Antena | 0 redes violando |
| IR drop | `PSM-0040` nas duas redes; pior 16 µV ("bump pattern") |
| STA / slew / capacitância | 0 / 0 / 0 violações (sem caminho restrito: núcleo sem `.lib`) |
| Tamanho | die 2700 × 2201 µm = 5,94 mm²; 3780 células-padrão (3710 tap), 437 células do anel, 1 macro (o núcleo) |

Imagem: `resultados/2026-11-01_1249_layout_chip/imagens/11_chip.png`.

### O caminho da parte 2b (para a aula)

| Rodada | Parou em | O que era | Decisão |
|---|---|---|---|
| `1029` | `IRDropReport` (PSM-0069) | ponte do núcleo 13 µm antes do toco da faixa do chip | L72 |
| `1524` | `Magic.StreamOut` | ordem dos GDS dos pads → 19 células vazias | L73 |
| `1645` | `Magic.StreamOut` | BOUNDARY aberto no GDS do PDK | L74 |
| `2015` | `Magic.StreamOut` | cópia feita de outra versão do PDK | L75 |
| `2058` | fim, 2 adiados | via4 sobre via4 (XOR); OBS dos pads lvc (sobreposição) | L76, L77 |
| `1249` | — | **Flow complete.** | — |

Lição geral: cada checador pegou uma coisa diferente (PSM a conectividade, o filtro de erros do
Magic as células vazias e o GDS defeituoso, o XOR a via encavalada). Nenhum deles sozinho bastaria.

### Para continuar: etapa 12 (DRC e LVS do chip)

1. **DRC (Magic) do GDS do chip**, com o núcleo como caixa-preta (maglef, como a L42): o DRC do
   núcleo já foi feito na etapa 8; aqui interessa o anel, as pontes, a ligação pad → anel e o
   roteamento pad ↔ núcleo. Atenção à via4 da `ligacao_pads` e às pontes (feitas à mão).
2. **LVS (Netgen)** extraído do **GDS** (`MAGIC_EXT_USE_GDS`), com os modelos SPICE dos pads e o
   núcleo como caixa-preta (`LVS_IGNORE_CELLS` ou subcircuito vazio): confirma eletricamente a
   cadeia pad → anel → pontes → núcleo e decide as 24 sobreposições da L77.
3. Selo (seal ring, L59): decidir se entra.

### Etapa 12 preparada: `layout/chip/12_verifica.sh`

| Arquivo | O quê |
|---|---|
| `12_verifica.sh` | Continua da rodada da etapa 11 (`.rodada_atual`, ou o 1º argumento) numa rodada **nova** (`runs/<data>_12`), com `--with-initial-state` no passo anterior ao `Magic.DRC`; gera o maglef do núcleo; roda de `Magic.DRC` até `Misc.ReportManufacturability`; guarda `12_drc.txt`, `12_lvs.txt`, os relatórios completos e as duas netlists (`.gz`) em `resultados/<data>_12_layout_chip/` |
| `config_verifica.json` | Liga `RUN_MAGIC_DRC` e `RUN_LVS`; `MAGIC_DRC_MAGLEFS` = núcleo; `ERROR_ON_MAGIC_DRC` e `ERROR_ON_LVS_ERROR` = false na 1ª rodada (para ler a lista inteira, não parar no 1º checker) |
| `resume_verifica.py` | DRC: caixas por regra e por **região** — `chip` (o que desenhamos nas etapas 11/12: PDN, pontes, ligação pad → anel, roteamento pad ↔ núcleo), `anel` (faixa dos pads, 205 µm da borda) e `nucleo` (só o abstrato). LVS: resultado final, dispositivos/redes dos dois lados, linhas de diferença sem repetição. Testado nos relatórios do núcleo (etapa 8): 130 caixas e "Circuits match uniquely" |

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L78 | DRC do chip: GDS do Magic, **núcleo caixa-preta** (maglef do `asic_top.lef`), **pads e fatias com o GDS real** | ✅ | O miolo do núcleo já passou na etapa 8 (130 isentos, L43); os pads são a parte nova e encostam no nosso metal (pontes, faixas met3, a sobra de met4 da L77) — o DRC tem de ver o metal deles de verdade |
| L79 | LVS do chip, 1ª rodada: extração **abstrata** (DEF + LEF, `MAGIC_EXT_USE_GDS = false`); pads, fatias e núcleo como caixas-pretas casadas pelos pinos | ✅ | Confere a nossa ligação (pad ↔ núcleo, anel de 10 redes pelos pinos das fatias, alimentação até `vccd1`/`vssd1`) sem precisar do SPICE de transistor dos pads. A extração pelo GDS com os pads inteiros (`PAD_SPICE_MODELS`) fica para depois, se o resultado pedir — é a que responderia de vez a L77 |
| L80 | Sem selo (seal ring) | ✅ | O `KLayout.SealRing` do LibreLane 3.0.14 só tem gerador para o IHP; para o sky130 depende de `KLAYOUT_SEALRING_SCRIPT`, que o PDK não define (como os runsets de antena/densidade do KLayout, vistos pulados na rodada `2058`). Fecha a L59 |

O que pode aparecer (para não assustar):
- **DRC nos pads**: o GDS das células de I/O do sky130 foi desenhado com regras próprias; erros
  dentro de `anel` precisam ser separados entre "da célula da foundry" e "do encosto com o nosso
  metal" (as caixas trazem coordenada).
- **LVS e as fatias do anel**: as `com_bus_slice` têm pinos no LEF (`AMUXBUS_A`, `VDDIO`...). Se o
  netlist do Verilog não tiver essas instâncias, o Netgen vê células a mais no layout; é a
  primeira coisa a olhar no `12_lvs.txt`.

### Etapa 12, 1ª rodada (`2026-11-01_1717_12`): ✅ LVS limpo; DRC só na faixa dos pads

Fontes: `resultados/2026-11-01_1717_12_layout_chip/` (`12_lvs.txt`, `12_lvs_netgen.rpt.gz`,
`12_drc.txt`, `12_metricas.json`).

| Verificação | Resultado |
|---|---|
| **LVS** (Netgen, extração abstrata, L79) | ✅ **"Circuits match uniquely"**; `design__lvs_error__count` 0 (e 0 em dispositivos, redes, pinos e propriedades) |
| Dois lados | 502 "dispositivos" e 143 redes em cada; todas as células do anel nos dois: 358 + 41 + 15 + 12 fatias `com_bus_slice`, 4 `gpiov2_pad_wrapped`, 4 cantos, 6 pads de alimentação, a fatia VCCHIB, 55 `conb_1`, o núcleo. As 71735 `decap_3` etc. viram 1 por "dispositivos paralelos" (não têm sinal) |
| Pinos do chip | os 10 bond pads (`clk_pad` ... `vssio_pad`) casam um a um |
| "5 simetrias" | células idênticas e trocáveis entre si (ex.: os 4 cantos); o Netgen resolve pelo nome e fecha "uniquely" |
| **DRC** (Magic no GDS, L78) | 305299 caixas: **0** na região `chip` (tudo o que desenhamos nas etapas 11/12), **305262** na faixa dos pads, **37** no núcleo |
| Tempo do DRC | 17 min 52 s |
| Sobreposição ilegal | as mesmas 24 (L77) |

O LVS limpo **fecha a cadeia elétrica**: bond pad → pad → met3 → pilhas de via → anel → grade →
pontes → `vccd1`/`vssd1` do núcleo, os sinais pad ↔ núcleo e as 10 redes do anel passando de
fatia em fatia. (Pela vista abstrata: pinos dos LEF; o miolo dos pads não entra.)

### 🐛 37 caixas de `nwell.4` no núcleo: nwell na OBS do LEF

- **Sintoma:** 37 caixas "All nwells must contain metal-connected N+ taps" dentro da macro, de
  (389,83; 390,715) a (2309,79; 1808,11), recortadas na grade de ladrilhos do Magic (314,56 µm)
  e com buracos onde estão as SRAM.
- **Causa:** o LEF do núcleo (`Magic.WriteLEF`, etapa 8) tem na `OBS` um retângulo de **nwell**
  `39.830 40.715 1959.790 1458.110` (= as mesmas coordenadas + 350). O `lef read` do Magic
  transforma isso em nwell de verdade no maglef, sem nenhum tap → `nwell.4`. Alarme falso da
  vista abstrata (o miolo real tem os taps e passou na etapa 8).
- **Resolvi com (L82):** o `12_verifica.sh` gera o maglef de uma cópia do LEF sem o nwell da
  OBS (`entrada/maglef/asic_top_sem_nwell.lef`). Testado no LEF da etapa 11: só as 2 linhas do
  nwell saem (`diff`).
- **Vira slide?** Junto com a L42: o abstrato também mente — às vezes para mais.

### As 305262 caixas na faixa dos pads: método para separar (L81)

Todas caem dentro das células de I/O (exemplos: `diff/tap.3` "LV to MV Diffusion spacing" com
213330 caixas, `diff/tap.18,20`, `diff/tap.21`, `poly.7`, `licon.7`...): regras de transistores e
difusões de média/alta tensão — o miolo das células da SkyWater, que nós não desenhamos. Mas
"parece da foundry" não é prova. A pergunta certa: **algum erro vem do encosto** (pad × fatia,
pad × o nosso metal, a sobra de met4 dos pads lvc da L77)?

- **Método (`12_drc_celulas.sh`, L81):** o Magic lê o **mesmo** `chip_top.gds` da etapa 11, carrega
  cada célula do anel **sozinha** e roda o mesmo DRC (`drc(full)`, euclidiano). O
  `resume_verifica.py anel` soma, por regra, a **área** de erro de cada célula × instâncias no chip
  e compara com a área de erro do chip na faixa dos pads. Área igual → erro interno da célula;
  área a mais no chip → encosto, e ele lista as caixas.
- **Por que área e não número de caixas:** o Magic recorta cada erro na grade de ladrilhos dele
  (as caixas do `nwell.4` acima mostram isso); a mesma célula, em outro lugar, sai em outro
  número de pedaços. A área não muda.
- **Testado** com uma referência falsa montada do próprio relatório: as regras presentes dão 0,00 %
  e a regra tirada de propósito aparece como "DIFERENTE" com as caixas.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L81 | Erros de DRC na faixa dos pads separados por DRC de referência de cada célula sozinha, comparando área por regra | ✅ | Prova (em vez de supor) que os erros são internos das células da foundry; o que sobrar é encosto e tem coordenada |
| L82 | Maglef do núcleo sem o nwell da OBS do LEF | ✅ | 37 `nwell.4` falsos: nwell sem tap só existe no abstrato |

### Etapa 12, 2ª rodada (`2026-11-01_1839_12`) + DRC das células sozinhas

`resultados/2026-11-01_1839_12_layout_chip/` (`12_drc.txt`, `12_lvs.txt`, `12_drc_anel.txt`):

| Verificação | Resultado |
|---|---|
| LVS | ✅ de novo "Circuits match uniquely", 502/143 |
| DRC núcleo | **0** (eram 37: a L82 funcionou) |
| DRC região `chip` | **0** |
| DRC faixa dos pads | 305262 caixas (as mesmas) |
| Comparação por área (L81) | 27 regras "diferentes"; total chip 30518 µm² × células 25365 µm² |

### 🐛 A comparação por área total não serve (L83)

- **Sintoma:** regras com área a mais no chip (`Can't overlap those layers` +40 %,
  `diff/tap.18,20` presente só no chip, `diff/tap.16`, `licon.5b`...) e outras com área a **menos**
  (`met5.4` some no chip, `LU.3` −69 %).
- **Causa (três coisas misturadas):**
  1. **caixas repetidas**: o relatório traz a mesma caixa duas vezes (ex.:
     `1083.525 29.975 1083.590 30.025`), e o Magic corta erros na borda dos ladrilhos (as caixas
     param em x ou y = 1100,96 = 3,5 × 314,56). Somar área conta repetido;
  2. **erros que somem no contexto** (normal): a fatia de 1 µm sozinha tem met5 menor que a área
     mínima; no chip o met5 dela emenda no do vizinho e o erro some;
  3. **erros de interação entre subcélulas**, que só existem com as células encostadas:
     `Can't overlap those layers` e `This layer can't abut or partially overlap between subcells`
     são do próprio Magic (o `sky130.tech` do open_pdks só tem `exact_overlap`/`no_overlap` para
     contatos; a mensagem vem do verificador de interação). Exemplo: no `pad_vssa` (lado oeste),
     faixas de 55 nm em y = 1120,565–1120,62, de 20 em 20 µm em x — cara de borda entre o pad e a
     fatia vizinha.
- **Resolvi com (L83):** `compara_drc_anel.py`, comparação **geométrica**: cada caixa de erro de
  cada célula sozinha é levada para o lugar de **cada instância** (posição e orientação do DEF,
  tamanho do LEF); por regra, com **regiões** (união, sem repetição; módulo de geometria do
  KLayout): `só chip = chip − levado` e `só célula = levado − chip`. O que sobra em "só chip" sai
  com a instância onde cai e a **distância até a borda dela** (encosto = perto da borda). Regras
  separadas por camada: **metal/via** (o que o nosso desenho poderia ter causado) × **dispositivo**
  (difusão, poço, poly, implantes: só existem dentro das células da foundry — no anel não pusemos
  nenhuma dessas camadas). O `12_drc_celulas.sh` passa a gravar cada caixa da referência.
- **Testado** com um caso sintético (3 instâncias em N, S e W, caixa repetida, um erro de metal fora
  das células e um de difusão dentro): a caixa repetida conta uma vez, as orientações levam a caixa
  ao lugar certo, e só os dois erros plantados aparecem em "só chip", com a localização certa.
  O Tcl novo do Magic foi conferido com um `drc` de mentira no `tclsh`.
- **O que já dá para dizer pelos números da área (sem a geométrica):** nenhuma regra de
  **metal/via** cresceu no chip (`met2.3a` e `mcon.2` iguais; `via4.2` −22 %, `met5.4` e `met1.6`
  somem). Todas as que cresceram são de camada de dispositivo ou de interação.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L83 | Comparação geométrica (por instância, regiões, por camada) no lugar da soma de área | ✅ | Área total mistura repetição, erro que some no contexto e erro de interação; a geométrica diz onde cada sobra cai |

### Comparação geométrica, 1ª rodada (`12_drc_anel.txt` em `1839_12`)

441 instâncias do anel no DEF; DRC sozinho de 9 células (as fatias de 5/10/20 µm não têm erro).

| Classe | O que sobrou "só no chip" | Onde cai |
|---|---|---|
| **metal/via** | só `via4.2`: 0,0069 µm² (e 0,0125 µm² "só célula") | dentro dos **cantos**, a 18,7 µm da borda: o mesmo erro da célula, recortado em fatias de 10 nm de outro jeito |
| `Can't overlap those layers` | 47,56 µm² (de 8425,7) | dentro dos 4 `gpiov2`, a 7,9–25,9 µm da borda |
| dispositivo | várias regras (`diff/tap.18,20` 2352,7 µm², `diff/tap.16` 127,1...) | dentro dos `gpiov2`, quase tudo a mais de 5 µm da borda; dois casos a 0,00 µm, na fatia de 1 µm encostada no `pad_clk`/`pad_rstn` (`licon.1`/`licon.2`: contato de difusão do pad que passa da borda do LEF — o GDS do `gpiov2_pad_wrapped` vai até x = 80,085 num LEF de 80,000) |
| dispositivo, `pad_vddio` | `diff/tap.3` 5487,6 µm² "só chip" **e** 5493,1 µm² "só célula" | ver o 🐛 abaixo |

Já dá para afirmar: **nenhum erro de metal/via nasceu do encosto** e nenhum erro "só chip" cai fora
das células do anel (no metal das etapas 11/12). O que sobra está dentro das células da foundry,
em camadas que só elas têm.

### 🐛 `pad_vddio`: as caixas da célula foram para o lugar errado (L84)

- **Sintoma:** no `pad_vddio`, "só chip" ≈ "só célula" (5487,6 × 5493,1 µm²) — o mesmo tanto de
  erro sobrando dos dois lados é sinal de caixa no lugar errado, não de erro novo.
- **Causa:** o transporte usou a orientação **escrita no DEF**; para esse pad ela não reproduz o
  desenho. Testando as 8 orientações contra os erros do chip, a célula **espelhada (FN)** encaixa
  com XOR **0,000 µm²** (deslocamento x = 2027,27, y = 2003,035), e as outras dão 740–1842 µm².
  Os `gpiov2` encaixaram com a orientação do DEF (`poly.7`, por exemplo, sem nenhuma sobra). O DEF
  não veio no pacote, então não deu para ver qual nome de orientação está nele.
- **Resolvi com (L84):** o `compara_drc_anel.py` testa, para cada instância com erros de
  referência, as 4 orientações do mesmo contorno, nas coordenadas do DEF, e usa a de menor XOR. A
  tabela mostra posição, orientação do DEF, a usada e os dois XOR (com aviso quando diferem). O
  `12_drc_celulas.sh` grava as posições do DEF (`12_anel_posicoes.txt`). Testado: com o DEF
  dizendo `N` para uma instância desenhada em `S`, ele escolhe `S` e avisa.
- **Vira slide?** Sim: convenção de orientação (N/S/FN/FS, R180/MX/MY) é uma das armadilhas
  clássicas entre ferramentas.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L84 | Orientação de cada instância escolhida pelo encaixe dos erros (menor XOR), não só pelo nome do DEF | ✅ | O `pad_vddio` encaixa com XOR 0 espelhado e não encaixa pela orientação do DEF; a tabela registra cada divergência |

## 2026-11-02 (39ª sessão) — ✅ Etapa 12 fechada: LVS limpo, DRC sem erro nosso

### A L84 não era o problema: o posicionamento estava certo

Com as posições do DEF (`12_anel_posicoes.txt`, rodada `1839_12`), a tabela de orientação mostrou
que **a orientação do DEF é a que melhor encaixa em todas as instâncias** (nenhum aviso); os pads
hvc ficam com XOR de 1620,74 µm² em qualquer orientação, e uma busca de deslocamento (±8 µm) não
leva abaixo de 1377 µm². A conta **por regra** dentro do `pad_vddio` explicou:

| Regra (dentro do `pad_vddio`) | chip µm² | célula µm² | só chip | só célula |
|---|---|---|---|---|
| `diff/tap.21` (HV nwell só com difusão HV) | 97,406 | 97,406 | 0 | 0 |
| `Can't overlap those layers` | 814,937 | 814,937 | 0 | 0 |
| `diff/tap.3` (LV to MV Diffusion spacing) | 945,540 | 945,540 | **813,800** | **813,800** |
| `diff/tap.18,20` | 97,406 | 0 | 97,406 | 0 |

- Duas regras casam **exatamente**: o lugar está certo.
- `diff/tap.3` tem a **mesma área** dos dois lados, deslocada: é o mesmo erro de espaçamento, com a
  marca desenhada do **outro lado** do espaço entre as duas difusões.
- `diff/tap.18,20` só no chip, com a **mesma área** de `diff/tap.21`: o mesmo defeito recebendo um
  segundo nome. O Magic, onde há interação (subcélulas sobrepostas, metal do topo por cima), achata a
  região e rechecha; a marca e o nome da regra saem diferentes do DRC hierárquico da célula sozinha.
- A L84 (orientação por encaixe) fica no script: não muda nada aqui e protege contra DEF com outra
  convenção. A afirmação "o `pad_vddio` encaixa espelhado" da 38ª sessão estava errada: o teste usava
  uma regra só, e o espelhamento casa com o deslocamento da marca do `diff/tap.3`.

### O critério que fecha (L85)

A pergunta certa não é "a marca é igual?", e sim: **o erro do chip cai onde a célula sozinha já
tinha erro?** `compara_drc_anel.py` passou a medir a parte de "só chip" a mais de **0,5 µm** de
**qualquer** erro das células sozinhas (todas as regras). Conta feita aqui com os arquivos da
rodada `1839_12` (`12_drc_magic.rpt.gz`, `12_drc_ref_celulas.tsv.gz`, `12_anel_posicoes.txt`):

| | µm² |
|---|---|
| "Só chip" (todas as regras, faixa dos pads) | 8192,27 |
| a ≤ 0,5 µm de um erro da célula sozinha | 8155,82 (**99,6 %**) |
| **longe** de qualquer erro da célula | **36,45** |

Os 36,45 µm² que sobram, todos **no miolo dos 4 `gpiov2_pad_wrapped`**, nenhum em metal/via:

| Regra | longe, µm² | onde |
|---|---|---|
| `Can't overlap those layers` | 21,373 | faixa y ≈ 25,7–30,1 (sul) / 2175 (norte), x de 1074 a 1119 e de 1552 a 1597: dentro dos pads, perto do bond pad |
| `diff/tap.20` (MV diffusion em N-well × P-tap) | 7,504 | y ≈ 84, dentro do pad |
| `diff/tap.16` (MV butting tap) | 7,034 | y ≈ 29,3, dentro do pad |
| `hvntm.2` | 0,486 | y ≈ 186, dentro do pad |
| `hvntm.1` | 0,055 | y ≈ 172, dentro do pad |

São camadas de **dispositivo** (difusão MV, tap, HVNTM) e a interação entre as subcélulas do
próprio pad. No anel nós só pusemos metal (faixas met3, vias, fios de sinal met2/met3, o terminal
met5 do bond pad que o PadRing cria); a hipótese mais provável é a do rechecado achatado do Magic
onde esse metal de topo passa por cima do pad (os 4 `gpiov2` são os pads com terminal **e** fio de
sinal). Os pads hvc/lvc não deixam nada longe.

### Veredito da etapa 12

| Verificação | Resultado | Fonte |
|---|---|---|
| **LVS** (Netgen, abstrato: pads, fatias e núcleo como caixas-pretas) | ✅ "Circuits match uniquely"; 0 erros em dispositivos, redes, pinos, propriedades | `1839_12/12_lvs.txt`, `12_metricas.json` |
| **DRC** região `chip` (o que desenhamos nas etapas 11/12) | ✅ **0** | `12_drc.txt` |
| DRC núcleo (abstrato) | ✅ **0** (L82) | `12_drc.txt` |
| DRC faixa dos pads, metal/via | ✅ nenhum erro do encosto (`via4.2` só dentro dos cantos, junto do erro da própria célula) | `12_drc_anel.txt` |
| DRC faixa dos pads, dispositivo | ⚠️ isento: 99,6 % coincide com erros das células sozinhas; 36,45 µm² no miolo dos `gpiov2`, camadas que só a foundry desenhou | esta sessão |
| Selo | fora (L80) | — |

**Isenção documentada (L85):** os erros de DRC na faixa dos pads são das células de I/O do
sky130 (`sky130_ef_io`/`sky130_fd_io`), conhecidas por não passarem limpas no `drc(full)` do Magic
(regras de média/alta tensão desenhadas com as regras próprias da SkyWater). Nada de metal/via, nada
fora das células, nada no nosso desenho.

O que fica em aberto, documentado: a extração **pelo GDS** com os pads inteiros (`PAD_SPICE_MODELS`)
para responder de vez a L77 (as 24 sobreposições "obsm4 × metal4" da vista abstrata); o DRC pelo
GDS real já não acusou nada de metal ali.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L85 | Erros de DRC na faixa dos pads = isenção da foundry, pelo critério "≤ 0,5 µm de um erro da célula sozinha" (99,6 %) + o resto só em camada de dispositivo no miolo dos pads | ✅ | A marca e o nome da regra mudam no rechecado achatado do Magic; o lugar do defeito não. Metal/via sem nenhum erro de encosto |

### Etapa 12, extras (pedido do Lukas): densidade, STA do chip e LVS pelo GDS

Três scripts novos em `layout/chip/`, cada um com a sua rodada (`runs/<data>_12dens|_12sta|_12lvs`)
e a sua pasta em `resultados/`. O que é comum (rodada da etapa 11, PDK `8afc8346`, Python com o
módulo do KLayout, DRC do Magic com o núcleo caixa-preta) foi para `comum_chip.sh`.

| Script | O que faz | Testado aqui |
|---|---|---|
| `12_densidade.sh` | `check_density.py` (open_pdks, `libs.tech/magic/`) no GDS da etapa 11 → `generate_fill.py -dist` → KLayout junta chip + `chip_top_fill_pattern` → `check_density.py` de novo → DRC do Magic no GDS preenchido → imagem do GDS final | a junção chip + fill (GDS sintéticos, fill `.gds.gz`); o leitor da saída do `check_density.py` (`resume_verifica.py densidade`) |
| `12_sta.sh` | A: OpenROAD lê o `.odb` + SPEF `nom` do núcleo (rodada da etapa 7/8), libs TT e `nucleo.sdc`, confere o STA TT e roda `write_timing_model` → `entrada/asic_top_tt.lib`. B: `config_sta.json` (MACROS com o `.lib`, caminhos absolutos) e só o `OpenROAD.STAPostPNR` do chip, a partir do RCX da etapa 11 | o gerador do `config_sta.json` com o `config.json` real; o resumo dos pinos/arcos do `.lib` (num `.lib` de mentira) |
| `12_lvs_gds.sh` | acha em que arquivo SPICE do PDK está cada célula do anel (como a L64: o combinado pode não ter todas) → `MAGIC_EXT_USE_GDS`, núcleo abstraído (`MAGIC_EXT_ABSTRACT_CELLS`), `PAD_SPICE_MODELS` → `Magic.SpiceExtraction` + `Netgen.LVS` | a escolha dos SPICE (diretório de mentira: combinado, arquivo próprio e célula sem SPICE) |

Densidade, na teoria: o sky130 pede, por janela de 700 × 700 µm (passo de 70 µm), li/met1–met4
entre 35 % e 60 %, met5 entre 45 % e 76 %, difusão (FOM) entre 33 % e 57 % (limites do
`check_density.py`). Sem isso o polimento químico-mecânico (CMP) deixa a superfície ondulada:
onde há pouco metal o polimento "afunda" e a camada de cima sai fora de foco na litografia. O
preenchimento ("wafflefill" do Magic) põe quadradinhos soltos, sem ligação elétrica, nos vazios,
respeitando o espaçamento com o desenho.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L86 | Densidade e preenchimento com os scripts do open_pdks para o Magic (`check_density.py`, `generate_fill.py`), fill juntado por instância; DRC de novo no GDS preenchido | ✅ | Os passos do KLayout pularam (sem runset no PDK); são os scripts que o Caravel usa; o fill não pode criar erro, então o DRC repete |
| L87 | STA do chip com um modelo de tempo do núcleo (`write_timing_model`, TT, chave `"*"` como as SRAM) | ✅ | Sem `.lib` do núcleo o STA do chip não tem caminho (folga 1e39); o modelo leva para o chip a árvore de relógio e os fios extraídos do núcleo |
| L88 | LVS pelo GDS com os pads inteiros, núcleo abstraído, `MAGIC_CAPTURE_ERRORS = false` só nessa rodada (camadas da OpenRAM, L44; o script lista as linhas) | ✅ | É o LVS que enxerga o metal real dentro do anel: fecha a L77 (curto apareceria como redes fundidas) |

### 🐛 1ª tentativa do `12_sta.sh` e do `12_lvs_gds.sh` (notebook, 02/11 16:12)

- **`12_sta.sh` — sintoma:** `nucleo.sdc, 43 can't read "::env(SYNTH_DRIVING_CELL)"`.
  **Causa:** passei ao OpenROAD só 7 das variáveis que o SDC lê; ele usa 13 (`SYNTH_DRIVING_CELL`,
  `SYNTH_CLK_DRIVING_CELL`, `OUTPUT_CAP_LOAD`, `TIME_DERATING_CONSTRAINT`,
  `CLOCK_TRANSITION_CONSTRAINT`...). **Resolvi:** o script lê do próprio `nucleo.sdc` todas as
  `::env(X)` e pega o valor no `resolved.json` da rodada do núcleo (e imprime a lista).
- **`12_lvs_gds.sh` — sintoma 1:** `Path provided for variable 'MACROS.asic_top.gds[0]' is
  invalid: .../layout/chip/entrada/entrada/asic_top.gds` (e todos os `dir::` do `config.json`).
  **Causa:** com dois arquivos de configuração, o LibreLane resolveu o `dir::` do `config.json`
  pela pasta do **último** arquivo (eu gravei o extra em `entrada/`). O `config_verifica.json`
  funcionou porque está na mesma pasta do `config.json`. **Resolvi:** os extras gerados vão para
  `layout/chip/.config_lvs_gds.json` e `.config_sta.json` (fora do git pelo `.gitignore`).
  O `12_sta.sh` ia tropeçar no mesmo.
- **Sintoma 2:** "SEM SPICE" para todas as 13 células do anel: o `spice/` do PDK só tem
  `sky130_fd_io.spice`. **Causa:** as células `sky130_ef_io` (os pads "embrulhados", fatias, canto)
  não vêm da SkyWater; são do open_pdks, que as descreve num **CDL** próprio
  (`libs.ref/sky130_fd_io/cdl/sky130_ef_io.cdl`, conferido no fonte do open_pdks: `.SUBCKT` em
  sintaxe SPICE pura, que o Netgen lê). Ele instancia as células `sky130_fd_io__top_*` da
  SkyWater, que estão no `sky130_fd_io.spice`. **Resolvi:** o script usa os dois e confere o
  **fecho** (tudo o que as células do anel instanciam, recursivamente, tem de ter definição; o que
  faltar sai listado). Testado com o CDL real do open_pdks e um `sky130_fd_io.spice` de mentira
  sem uma das células: as 13 acham definição e a célula tirada aparece como faltando.
- **Tempo:** ~30 min. **Vira slide?** O `dir::` relativo ao último arquivo, talvez.

### `12_densidade.sh`, 1ª rodada (`2026-11-02_1614_12dens`): o preenchimento resolve quase tudo

Números da saída do script no notebook (os arquivos vão em `resultados/2026-11-02_1614_12dens_layout_chip/`).
Janela = 700 × 700 µm, passo 70 µm: 690 janelas no chip de 2700 × 2201 µm.

| Camada | Limites | Global antes | Global depois | Janelas reprovadas antes | depois | Janela mín. depois |
|---|---|---|---|---|---|---|
| FOM (difusão) | 0,33–0,57 | 0,160 | 0,424 | 636 | **26** | 0,295 |
| poly | — | 0,131 | 0,183 | — | — | 0,130 |
| li | 0,35–0,60 | 0,241 | 0,542 | 393 | **0** | 0,449 |
| met1 | 0,35–0,60 | 0,157 | 0,476 | 690 | **0** | 0,369 |
| met2 | 0,35–0,60 | 0,101 | 0,450 | 690 | **209** | 0,252 |
| met3 | 0,35–0,60 | 0,083 | 0,449 | 690 | **139** | 0,314 |
| met4 | 0,35–0,60 | 0,292 | 0,519 | 654 | **39** | 0,335 |
| met5 | 0,45–0,76 | 0,299 | 0,545 | 687 | **224** | 0,326 |

- **Antes:** nenhuma camada passava, nem na média do chip (met3 com 8,3 %). Esperado: entre o anel e
  o núcleo e em volta das SRAM há muito vazio, e a etapa 11 só pôs células de preenchimento nas
  linhas, sem metal.
- **Depois:** todas as médias globais dentro dos limites; li e met1 sem nenhuma janela reprovada;
  sobram janelas em met2/met3/met5 (e poucas em FOM/met4), com mínimo acima de 0,25. Falta saber
  **onde** (os índices das janelas estão no `12_densidade_depois.txt`): perto do anel de pads, onde
  as células da foundry têm áreas vazias que o fill não pode ocupar, ou sobre as SRAM.
- **Fill:** 29 min (`-dist`), 125 MB (`.gds.gz`), 17 células; GDS final com fill: 932 MB.

DRC do GDS preenchido (mesmo método do `12_verifica.sh`, núcleo caixa-preta):

| | sem fill (`1839_12`) | com fill |
|---|---|---|
| região `chip` | 0 | **0** |
| faixa dos pads | 305262 | 316073 (+10811) |
| `licon.7` P-tap overlap | 4544 | 23056 |
| `LU.3` P-diff a mais de 15 µm de N-tap | 210 | 9010 |
| `diff/tap.3` MV diffusion × MV tap | 6308 | 8076 |
| `diff/tap.23` MV × LV P-diffusion | 270 / 42 | 1422 / 1194 |

O fill **não** criou erro no nosso desenho (região `chip` continua 0, e lá ele preencheu de verdade).
Os erros novos estão todos na faixa dos pads e são de **difusão/tap/latch-up**: o fill de FOM
(difusão "fantasma", obrigatória pela densidade de FOM) caiu perto dos transistores de média tensão
dos pads, e o `LU.3` conta esses quadrados como P-diff sem tap N por perto. Exemplo: `licon.7` em
(606,5; 151,0), dentro do `pad_vssd` (x 598–673). Próximo passo: com as caixas
(`12_drc_preenchido.rpt.gz`), confirmar e então **tirar o fill da faixa dos pads** (as células de
I/O são entregues completas pela foundry; o Caravel também não preenche dentro delas), conferindo se a
densidade continua passando sem ele.

### `12_sta.sh` (`2026-11-02_1923_12sta`): ✅ o chip tem tempo de verdade

Saída do script no notebook (arquivos em `resultados/2026-11-02_1923_12sta_layout_chip/`).

**A. Modelo do núcleo** (`write_timing_model`, núcleo da rodada `2026-09-30_0934`: `.odb` do passo
136, SPEF `nom` do passo 137, 5 libs TT, as 13 variáveis do `nucleo.sdc`):

| Conferência do STA TT do núcleo | Valor |
|---|---|
| WNS / TNS de setup | 0,00 / 0,00 |
| Pior folga de setup | **+0,56 ns** |
| Pior folga de hold | **+0,13 ns** |

O modelo (`asic_top_tt.lib`, 3,4 kB) tem: `clk_i` como relógio (com `max/min_clock_tree_path`: o
atraso da árvore de relógio do núcleo), `uart0_rxd_i` com `setup_rising`/`hold_rising`,
`uart0_txd_o` com `rising_edge` (clk → saída), e `rstn_i` **sem arco** (é falso caminho no
`nucleo.sdc`).

**B. STA do chip** (`OpenROAD.STAPostPNR`, SPEF do chip da etapa 11):

| Corner (RC) | Setup: pior folga | Hold: pior folga | Violações setup/hold |
|---|---|---|---|
| `nom_*` | +2,237 ns | +3,686 ns | 0 / 0 |
| `min_*` | +2,471 ns | +3,675 ns | 0 / 0 |
| `max_*` | **+2,101 ns** | +3,698 ns | 0 / 0 |
| max cap / max slew | 0 / **1** | | |

- **Antes:** folga 1e39 (sem caminho). **Agora:** os caminhos pad ↔ núcleo existem e passam com
  folga em todos os corners: pior setup **+2,10 ns** num período de 20 ns com 6 ns de atraso de
  entrada/saída (`chip.sdc`).
- **Por que tt/ss/ff dão o mesmo número dentro de cada RC:** o `.lib` dos pads é só TT (`PAD_LIBS`
  `"*"`) e o modelo do núcleo também (como as SRAM, L87). Só muda a extração (min/nom/max) do
  fio do chip. O número vale para TT; ss/ff ficariam para um modelo por corner (as SRAM só têm TT,
  então o núcleo também não teria).
- **1 violação de max slew:** falta ver qual rede (relatório no `resultados/`); candidato natural é
  um fio longo pad ↔ núcleo (até 2767 µm, etapa 11).

### `12_lvs_gds.sh`, 1ª rodada (`2026-11-02_1933_12lvs`): 2 h 37 min, "Top level cell failed pin matching"

Saída do Netgen no notebook (layout = circuito 1, esquemático = circuito 2). Cada pad, comparado
transistor com transistor, **não casa com o SPICE/CDL do PDK**:

| Célula | Layout (extraído do GDS) | Esquemático (`sky130_ef_io.cdl` + `sky130_fd_io.spice`) |
|---|---|---|
| pads hvc (`vddio`/`vssio`/`vdda`/`vssa`) | 5 `nfet_g5v0d10v5`, 2 `res_generic_m3`, 7 redes | 3 `nfet_g5v0d10v5`, 2 `res_generic_m3`, **1 `res_generic_m5`**, 6 redes |
| pads lvc (`vccd`/`vssd`) | 6 nfet, 2 pfet, 2 res po, 2 res m3, 20 redes | o mesmo + **2 `diode_pd2nw_05v5`** + **1 `res_generic_m5`**, 11 redes |
| `chip_top` inteiro | 1740 nfet_g5v0d10v5, 1352 pfet_g5v0d10v5, 0 diodos, 0 res m5 | 1680, 1292, 4 diodos, 6 res m5 |

- O `res_generic_m5` do esquemático é o resistor do **bond pad** (metal 5) e os
  `diode_pd2nw_05v5` são diodos de proteção que o SPICE da SkyWater descreve e a extração do Magic
  não reconhece no GDS; os transistores a mais no layout são dedos de ESD que o esquemático junta.
  Diferença de **modelagem da célula da foundry**, igual nos 6 pads de alimentação: não depende do
  nosso chip.
- Por isso o Netgen achata as células que não casaram e reprova no topo. **Esse resultado ainda não
  responde a L77.** A pergunta da L77 é de ligação entre células (curto entre redes do anel), não de
  transistor dentro de pad.
- **Próximo passo:** com a netlist extraída do GDS (`12_extraida_gds.spice.gz`), comparar **só a
  ligação de topo**: para cada pino de cada pad/fatia/núcleo, em que rede ele cai no layout (metal
  real do GDS) × no `chip_top` do Verilog. Curto = dois pinos de redes diferentes na mesma rede do
  layout. É um LVS no nível dos pinos, com o metal de verdade.
- `Checker.IllegalOverlap`: 798 (eram 24 pela vista abstrata); a extração pelo GDS vê as sobreposições
  internas das células da foundry.

### LVS só da ligação de topo, sem nomes (`compara_ligacao.py`, L89)

O GDS não guarda nome de instância, então a comparação não usa nomes: cada rede do `chip_top` vira
uma **assinatura**, o multiconjunto de (célula, pino) que encostam nela; compara-se o multiconjunto
de assinaturas do layout (netlist extraída) com o do Verilog (`chip_top.pnl.v`). Curto = uma rede
do layout que é a soma de duas assinaturas do Verilog; aberto = o contrário. Decap/fill/tap ficam de
fora (milhares, só alimentação). Dois cuidados no leitor de Verilog: barramento concatenado
(`.DM({net4, net5, net6})` → `DM[2]`, `DM[1]`, `DM[0]`) e pino sem ligação (o `HI` das `conb_1`),
que vira rede de um pino só, como sai na extração. Também mostra em quantas redes cai cada barramento
do anel.

| Teste | Resultado |
|---|---|
| Extração **abstrata** (`1839_12`, que o Netgen já casou) × `pnl.v` | ✅ 159 de 159 assinaturas iguais; mesmas contagens de célula; anel com 10 redes nos dois lados (`VSWITCH=VDDIO`, `VCCHIB=VCCD`, L63) |
| Mutação 1: `pad_tx/OUT` em curto com `pad_rx/IN` | ❌ acusou "CURTO? uma rede do layout junta 2 redes do verilog" com as duas listadas |
| Mutação 2: `VSSIO` em curto com `VDDIO` (o caso da L77) | ❌ acusou; anel caiu para 9 redes, `VSWITCH=VDDIO=VSSIO` |

Falta rodar na netlist extraída **do GDS** (`12_extraida_gds.spice.gz` da rodada `1933_12lvs`); o
`12_lvs_gds.sh` passa a fazer isso sozinho no fim (`12_ligacao_gds.txt`).

### Os três resultados olhados de perto (rodadas `1614_12dens`, `1923_12sta`, `1933_12lvs`)

**Densidade — onde estão as janelas que reprovam** (`12_densidade_depois.txt`, índices de janela
→ posição; mapa feito aqui): **todas no miolo do chip, em cima do núcleo**; nenhuma na faixa dos pads.

| Camada | Janelas | Onde |
|---|---|---|
| met2 | 209 | o miolo inteiro (janelas x = 5..26, y = 4..16) |
| met5 | 224 | idem |
| met3 | 139 | idem, um pouco menor |
| met4 | 39 | o centro |
| FOM | 26 | canto superior esquerdo (sobre a SRAM de 8 kB) |

Dentro do núcleo o roteamento é denso e deixa vãos menores que um quadrado de fill + espaçamento:
o fill feito no **nível do chip** não entra ali. É responsabilidade do **bloco** (o núcleo teria de
sair da etapa 8 já com fill de metal). Fica documentado como limite: média global de todas as
camadas dentro da faixa, mínimo de janela 0,25 (met2) a 0,33 (met5).

**Fill na faixa dos pads (L90):** como os erros novos de DRC (difusão/tap/latch-up) vieram de lá e
nenhuma janela da faixa reprova por densidade, o `12_densidade.sh` agora junta o fill **sem a faixa
dos pads** (só ficam as formas inteiramente a mais de 205 µm da borda; a que atravessa sai inteira,
para não virar lasca fora de regra) e aceita `FILL=` para reaproveitar o fill de 29 min e `ANTES=0`.
Testado com GDS sintético (quadrado na faixa, no meio e atravessando a borda: só o do meio fica; a
célula original do fill sai do GDS).

**STA — a violação de transição:** `pad_tx/OUT`, transição **3,540 ns** contra o limite de
**1,500 ns** do `.lib` do pad (`12_sta_nom_tt_025C_1v80_checks.rpt`). O caminho crítico de setup é o
mesmo fio: `clk_pad → pad_clk/IN` (1,409 ns) `→ u_core/clk_i` (1,576) `→ u_core/uart0_txd_o`
(7,694: **6,118 ns** dentro do modelo do núcleo, saída com transição 3,496 ns) `→ pad_tx/OUT`
(8,013) `→ tx_pad` (11,513); folga +2,237 ns. **Causa:** a saída do núcleo foi dimensionada para a
carga de saída do `nucleo.sdc` (`OUTPUT_CAP_LOAD` = 33,4 fF), e no chip ela enxerga **0,352 pF**
(fio de ~2,7 mm até o pad + a entrada do pad): 10 vezes mais. Orçamento de bloco que não bateu com o
chip — uma lição clássica de hierarquia. **Duas saídas:** (a) refazer o fluxo do chip com o modelo do
núcleo no `MACROS` (o resizer do chip passa a "ver" a saída fraca e põe um buffer junto do pino);
(b) refazer o núcleo com `OUTPUT_CAP_LOAD` ≈ 350 fF (horas). A violação não quebra o tempo (folga
+2,24 ns), mas tira o pad da faixa em que o `.lib` foi caracterizado.

**LVS pelo GDS — o script morreu antes de copiar a netlist:** o `comum.sh` liga
`set -euo pipefail`; o `grep … | head -15` da tabela de dispositivos fecha o pipe, o `pipefail`
transforma isso em erro e o script sai logo ali (só ficaram `12_extracao_gds.txt` e
`12_lvs_gds_spice.txt`). **Resolvi:** `gzip` da netlist antes da tabela, `|| true` na tabela e em
todos os `… | head -N` de exibição dos scripts da etapa 12 (10 linhas). Do que veio:
2 h 36 min de extração; núcleo abstraído (`asic_top matched`); as linhas "fatais" são só as camadas
da OpenRAM (33/42, 33/43, 22/21, 22/22, 92/44, 115/42, 115/43, 235/0, L44); fecho dos SPICE completo
(114 subcircuitos, nenhum faltando).

### Ligação de topo pelo GDS: os barramentos viraram uma rede só (`12_ligacao_gds.txt`)

`compara_ligacao.py` na netlist extraída do GDS (rodada `1933_12lvs`) × `chip_top.pnl.v`:

| | Layout (GDS) | Verilog |
|---|---|---|
| Redes do anel | **7**: `VSSA=VSWITCH=VDDIO=VSSIO=VSSD` juntas | 10 (`VSWITCH=VDDIO`, `VCCHIB=VCCD`, L63) |
| Portas do `chip_top` | 7 (`clk`, `rstn`, `rx`, `tx`, `vccd`, `vdda`, `vssd`): sumiram `vddio_pad`, `vssio_pad`, `vssa_pad` | 10 |
| Fatias e cantos como instância | 0 (o Magic achata célula sem dispositivo; o metal delas vira metal do topo) | 431 |

Investigação (feita aqui com a netlist e os LEF):

1. **A sobra de met4 dos pads lvc (L77) não é a causa.** Ela fica em y = 34,7–38,15 e 39,55–44,2
   do LEF, exatamente a altura dos barramentos `VSSA` e `VSSD` do vizinho (LEF da
   `com_bus_slice_1um`): é o próprio barramento do pad continuando, e encosta em metal da **mesma** rede.
2. **A fusão já vem de dentro de uma célula da foundry.** O `sky130_ef_io__gpiov2_pad_wrapped`
   extraído tem 42 portas e **nenhuma `VDDIO`** (e `VSSA`/`VSSIO` só como `gpio/VSSA_uq9` e
   `gpio/VSSIO_uq4`). O Magic, quando duas portas são o mesmo nó dentro da célula, guarda um nome só:
   dentro do gpiov2 extraído, `VDDIO` já é o mesmo nó que outra porta. Como todos os pads dividem os
   barramentos do anel, basta **um** tipo de célula fundir por dentro para o anel inteiro virar uma
   rede no topo. O `vddio_hvc_clamped_pad`, por exemplo, sai com todos os 12 barramentos separados.
3. Na prática essa fusão não existe no silício (o Caravel usa esses pads com VDDIO = 3,3 V e os terras
   separados). É a extração do Magic sobre o GDS da foundry: o mesmo tipo de diferença que fez o LVS
   de transistor reprovar (resistores de metal e diodos que o SPICE da SkyWater descreve e o Magic não
   reconhece no desenho), mais o substrato `VSUBS` comum.

**Prova que falta (L91):** `12_extrai_celulas.sh` extrai cada célula do anel **sozinha**, a partir
dos GDS do PDK (fora do chip), e lista os barramentos ausentes/fundidos em cada uma. Se o gpiov2
sozinho já vier sem `VDDIO`, a fusão é da célula da foundry e não do nosso chip, e a L77 fecha pelo
que já se tinha: ligação por pinos limpa (LVS abstrato), DRC sem nenhum erro de metal no encosto (L85)
e a sobra de met4 encostando na mesma rede. Testado o resumo com os cabeçalhos reais vindos do chip
(gpiov2: `VDDIO` ausente; vddio_hvc: nenhum ausente).

### ✅ Extração das células sozinhas (`resultados/2026-11-04_1538_12cel_layout_chip/`): a L77 fecha

`12_extrai_celulas.txt` (Magic, cada célula extraída **sozinha** a partir dos GDS do PDK, fora do chip):

| Célula | Portas | Barramentos ausentes (fundidos dentro da célula) |
|---|---|---|
| `gpiov2_pad_wrapped` | 36 | **`VDDIO`, `VSSA`, `VSSIO`** |
| `vccd_lvc_clamped_pad` | 10 | `VSSA`, `VSSIO` |
| `vssd_lvc_clamped_pad` | 10 | `VSSA`, `VSSIO` |
| `vddio`/`vssio`/`vdda`/`vssa_hvc_clamped_pad` | 12 | nenhum |
| `corner_pad`, `com_bus_slice_20um` | 12 | nenhum |
| `connect_vcchib_vccd_and_vswitch_vddio_slice_20um` | 10 | `VSWITCH`, `VCCHIB` — **a fusão de propósito** (L63): confere o método |

- O `gpiov2_pad_wrapped` **sozinho** já sai sem `VDDIO`: o nó de `VDDIO` é o mesmo de outra porta
  dentro da célula da foundry, sem o nosso chip por perto. Os pads lvc fundem `VSSA` e `VSSIO`.
- A união dessas fusões (gpiov2: `VDDIO`+`VSSA`+`VSSIO`; lvc: `VSSA`+`VSSIO` com um terra; fatia:
  `VSWITCH`+`VDDIO`, `VCCHIB`+`VCCD`) é o conjunto que apareceu no chip
  (`VSSA=VSWITCH=VDDIO=VSSIO=VSSD`, `VCCHIB=VCCD`): **nada sobra para explicar com a ligação entre
  células**.
- **Por que o Magic funde e o silício não:** o log da extração lê células como
  `sky130_fd_pr__m4short__example_…`, `m2short`, `M1short_CDNS_…`: são os "curtos de metal" que a
  SkyWater usa para separar **nomes** de redes que no desenho são o mesmo metal (no SPICE viram os
  resistores `res_generic_m*` de valor ínfimo), e os diodos de proteção entre terras. Onde o Magic
  não reconhece o marcador, os nós se fundem. Juntando com o substrato comum (`VSUBS`, presente em
  todos os pads), a extração do GDS da foundry não separa essas redes — com ou sem o nosso chip.

**Fechamento da L77 (sobreposições "obsm4 × metal4" dos pads lvc):**

| Evidência | Resultado |
|---|---|
| LVS pela vista abstrata (pinos dos LEF, metal do DEF) | ✅ "Circuits match uniquely" (L79) |
| Ligação de topo do LVS abstrato × Verilog (`compara_ligacao.py`) | ✅ 159/159 assinaturas, anel com 10 redes |
| DRC pelo GDS real, metal/via na faixa dos pads | ✅ nenhum erro de encosto (L85) |
| A sobra de met4 dos pads lvc | encosta nos barramentos `VSSA`/`VSSD` do vizinho, **mesma rede** (LEF da fatia) |
| Fusão de barramentos na extração pelo GDS | ✅ reproduzida pelas células **sozinhas** (esta tabela): é da extração das células da foundry |

Não há curto do nosso chip no anel. O LVS de transistor pelo GDS com os pads inteiros fica
documentado como **não conclusivo para pads da SkyWater no Magic** (modelagem das células), não como
erro do desenho.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L91 | A fusão dos barramentos na extração pelo GDS é investigada célula a célula (extração das células do anel sozinhas) | ✅ | Se a fusão já existe na célula da foundry sozinha, ela não diz nada sobre a ligação entre células; a L77 se decide pelo que não depende do modelo interno dos pads |

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L90 | Fill só fora da faixa dos pads (205 µm); densidade do miolo do núcleo documentada como limite do fill de chip | ✅ | Os erros novos de DRC vieram do fill dentro das células de I/O, e a faixa não reprova por densidade; o miolo do núcleo só se resolve com fill no próprio bloco |

| # | Decisão | Status | Motivo |
|---|---|---|---|
| L89 | A L77 se decide pela ligação de topo extraída do GDS (assinaturas, sem nomes), não pelo LVS de transistor dos pads | ✅ | O LVS de transistor reprova pela modelagem da foundry (resistor do bond pad, diodos, dedos de ESD), igual nos 6 pads; curto entre células aparece como redes fundidas no topo, e o comparador pega (mutações) |

---

## Índice de decisões

| # | Resumo | Status | Data |
|---|---|---|---|
| L1 | `.lib` 1rw com 33 bits + `spare_wen0` | ✅ | 2026-09-26 |
| L2 | Tie cells no Genus | ✅ 10 `conb_1`, LEC PASS | 2026-09-26 |
| L3 | DRC/LVS com macros como caixa-preta | 🟡 | 2026-09-26 |
| L4 | Netlist do layout = Genus | ✅ | 2026-09-26 |
| L5 | Floorplan 2,0 × 1,5 mm | 🟡 | 2026-09-26 |
| L6 | ~~Sem padring~~ → com padring | ✅ | 2026-09-27 |
| L7 | Diário próprio, prefixo L | ✅ | 2026-09-26 |
| L8 | Repositório git, donos por pasta | ✅ | 2026-09-26 |
| L9 | `SRAM_LIB_VIEW` extinto; `imem_sim_model.v` | ✅ | 2026-09-26 |
| L10 | PDK do LibreLane (`8afc8346`) em `PDK_ROOT` separada | ✅ | 2026-09-27 |
| L11 | LibreLane 3.0.14 via Nix | ✅ smoke test ok | 2026-09-27 |
| L12 | `CLAUDE.md` com regras de trabalho e git | ✅ | 2026-09-27 |
| L13 | Resultados da VM pelo git (`sim/traz_vm.sh`) | ✅ | 2026-09-27 |
| L14 | Netlist do layout = rodada de ~~27/09~~ **29/09** (L20) | ✅ | 2026-09-30 |
| L15 | Dois níveis: núcleo → chip com padring | ✅ | 2026-09-27 |
| L16 | Padring `sky130_ef_io` no nosso config | ✅ feito (36ª) | 2026-09-27 |
| L17 | `config.json` do núcleo | 🟡 | 2026-09-27 |
| L18 | Uma etapa por script, com GUI e imagem | ✅ | 2026-09-27 |
| L19 | Achatar o netlist antes do LibreLane (0 `assign`) | ✅ | 2026-09-27 |
| L20 | Genus evita `drc_exclude.cells` | ✅ 0 proibidas | 2026-09-27 |
| L21 | LEF das macros em 1000 unidades por µm | ✅ | 2026-09-30 |
| L22 | PDN-0110: zoom automático antes de mover macros | ✅ | 2026-09-30 |
| L23 | Halo das macros até a borda do núcleo | 🟡 | 2026-09-30 |
| L24 | ~~Densidade alvo padrão; decidir com o GRT~~ → L29 | ✅ decidida | 2026-09-30 |
| L25 | Timing só vale depois do `STAMidPNR-2` | 🟡 | 2026-09-30 |
| L26 | Reparo de timing só no TT (`RSZ_CORNERS`) | 🟡 funcionou (hold no FF: L27) | 2026-09-30 |
| L27 | Hold no FF: ~~reparar (A) ou só relatar (B)~~ → **A** (FF no `RSZ_CORNERS`) | 🟡 | 2026-10-07 |
| L28 | Fanout do relógio e transição das macros aceitos | 🟡 | 2026-10-05 |
| L29 | Densidade alvo 65 % (a automática contava as macros) | 🟡 ajudou, não basta | 2026-10-05 |
| L30 | Diagnóstico da congestão fora do fluxo (`diag_congestao.sh`) | ✅ | 2026-10-06 |
| L31 | DMEM no canto (55; 55): canal IMEM/DMEM de 453,7 µm | 🟡 funcionou (GRT sem excesso) | 2026-10-06 |
| L32 | `RUN_POST_GRT_DESIGN_REPAIR` ligado | 🟡 funcionou | 2026-10-06 |
| L33 | Antena só com diodos (`GRT_ANTENNA_REPAIR_DIODE_ONLY`) | 🟡 funcionou | 2026-10-06 |
| L34 | ~~1 violação de antena restante aceita por ora~~ | ✅ sumiu no reparo (0) | 2026-10-09 |
| L35 | SS só relatado (fmax 23 MHz), fora do reparo | 🟡 | 2026-10-07 |
| L36 | `ResizerTimingPostGRT` com margem de setup de 1,5 ns | 🟡 funcionou (TT +0,32 ns) | 2026-10-07 |
| L37 | IR drop do LibreLane não vale (potência das macros) | 🟡 | 2026-10-07 |
| L38 | ~~Hold pós-GRT: margem 0,05 ns + teto de 2 %~~ → L39 | ❌ não convergiu | 2026-10-08 |
| L39 | Hold pós-GRT: margem 0,02 ns, sem teto | 🟡 funcionou (242 buffers) | 2026-10-09 |
| L40 | 15 holds de ≤ 28 ps no FF aceitos por ora | 🟡 | 2026-10-09 |
| L41 | `KLayout.DRC` desligado (macros, L3) | 🟡 | 2026-10-09 |
| L42 | DRC do Magic no GDS + macros caixa-preta (maglef) | 🟡 funcionou (`nwell.4` → 0) | 2026-10-09 |
| L43 | 130 erros de área mínima em pinos sem uso das macros = isenção | 🟡 | 2026-10-09 |
| L44 | Diagnóstico do XOR dentro/fora das macros (`diag_xor.sh`) | ✅ macros vazias no KLayout | 2026-10-09 |
| L45 | `FOREIGN` nos LEF das macros (`macros/lef_foreign.py`) | 🟡 funcionou (XOR 0) | 2026-10-10 |
| L46 | Netlist do layout sem células só físicas (`tira_fisicas.py`) | 🟡 funcionou | 2026-10-10 |
| L47 | Golden do LEC da etapa 9 = Genus achatado (+ RTL no 4c) | 🟡 funcionou (0 não mapeados) | 2026-10-10 |
| L48 | 6 pads de alimentação (um de cada) | ✅ (L52) | 2026-10-28 |
| L49 | `ENABLE_H` = `TIE_HI_ESD`, sem POR | ✅ (L52) | 2026-10-28 |
| L50 | Fatia VCCHIB/VSWITCH no anel (modelo nosso) | ✅ (L52) | 2026-10-28 |
| L51 | `USE_POWER_PINS` só para pads (arquivo na ordem de leitura) | ✅ (L52) | 2026-10-28 |
| L52 | Claude decide o back-end e registra com o motivo | ✅ (Lukas) | 2026-10-29 |
| L53 | Die 2700 × 2201 µm | ✅ | 2026-10-29 |
| L54 | Núcleo em (350, 350), N | ✅ | 2026-10-29 |
| L55 | `PAD_CFG` com rotação R180 | ✅ | 2026-10-29 |
| L56 | Sítios falsos 1 × 200 e 200 × 204 | ✅ | 2026-10-29 |
| L57 | Pads por lado (sinal entre o par do domínio) | ✅ | 2026-10-29 |
| L58 | Núcleo e fatia como caixa-preta; pads pelo Liberty | ✅ | 2026-10-29 |
| L59 | Sem `KLayout.SealRing` | ✅ | 2026-10-29 |
| L60 | Etapa 11 em duas partes (anel primeiro) | ✅ | 2026-10-29 |
| L61 | `PAD_VERILOG_MODELS` = cópias em `tech/sky130_io/verilog/` | ✅ | 2026-10-29 |
| L62 | Núcleo ligado a VCCD/VSSD do anel no `chip_top.v` | ✅ | 2026-10-29 |
| L63 | Anel com 10 redes: VSWITCH = VDDIO, VCCHIB = VCCD | ✅ | 2026-10-31 |
| L64 | `PAD_GDS` + GDS do gpiov2_pad_wrapped e da fatia | ✅ | 2026-10-31 |
| L65 | PDN do chip com pontes met5 pela direita (`pdn_chip.tcl`) | ✅ | 2026-10-31 |
| L66 | Faixas met4 nas laterais da macro | ✅ | 2026-10-31 |
| L67 | Parte 2a só até o PDN (`config_pdn.json`) | ✅ | 2026-10-31 |
| L68 | `ERROR_ON_PDN_VIOLATIONS = false` no chip (PSM sem terminal) | ✅ | 2026-10-31 |
| L69 | Ligação pad → anel à mão (met3 + vias) | ✅ | 2026-10-31 |
| L70 | Sem CTS no chip | ✅ | 2026-10-31 |
| L71 | DRC e LVS do chip ficam para a etapa 12 | ✅ | 2026-10-31 |
| L72 | Pontes do núcleo até o anel do chip, com vias M4M5 (PSM-0069) | ✅ | 2026-10-31 |
| L73 | `PAD_GDS` com `sky130_fd_io.gds` primeiro (células vazias no Magic) | ✅ | 2026-10-31 |
| L74 | `sky130_fd_io.gds` com os polígonos fechados (`fecha_gds.py`) | ✅ | 2026-10-31 |
| L75 | Pads da versão `8afc8346` do PDK (não `head -1`); cópia refeita se a origem mudar | ✅ | 2026-10-31 |
| L76 | `ligacao_pads` sem via4 sobre via4 do pdngen (XOR) | ✅ | 2026-11-01 |
| L77 | Sobreposição ilegal no chip vira aviso (OBS dos pads lvc; LVS pelo GDS decide) | ✅ | 2026-11-01 |
| L78 | DRC do chip: núcleo caixa-preta, pads com GDS real | ✅ | 2026-11-01 |
| L79 | LVS do chip: extração abstrata primeiro | ✅ | 2026-11-01 |
| L80 | Sem selo: o PDK não define `KLAYOUT_SEALRING_SCRIPT` (fecha a L59) | ✅ | 2026-11-01 |
| L81 | DRC de referência das células do anel (área por regra) | ✅ | 2026-11-01 |
| L82 | Maglef do núcleo sem nwell (37 `nwell.4` falsos) | ✅ | 2026-11-01 |
| L83 | DRC do anel: comparação geométrica por instância (`compara_drc_anel.py`) | ✅ | 2026-11-02 |
| L84 | Orientação por encaixe (menor XOR) na comparação do DRC do anel | ✅ | 2026-11-02 |
| L85 | DRC da faixa dos pads isento (≤ 0,5 µm de erro da célula; resto só dispositivo no miolo dos `gpiov2`) — etapa 12 ✅ | ✅ | 2026-11-02 |
| L86 | Densidade + preenchimento (scripts do open_pdks), DRC de novo no preenchido | ✅ | 2026-11-02 |
| L87 | STA do chip com modelo de tempo do núcleo (`write_timing_model`) | ✅ | 2026-11-02 |
| L88 | LVS pelo GDS com pads inteiros, núcleo abstraído | ✅ | 2026-11-02 |
| L89 | L77 decidida pela ligação de topo do GDS (`compara_ligacao.py`) | ✅ | 2026-11-03 |
| L90 | Fill fora da faixa dos pads; densidade do miolo do núcleo é limite do fill de chip | ✅ | 2026-11-03 |
| L91 | Extração das células do anel sozinhas: a fusão dos barramentos é das células da foundry; L77 fechada | ✅ | 2026-11-04 |

---

## Pendências abertas

- [x] ~~Decidir L4~~ — Genus (caminho A)
- [x] ~~Rodada para o layout na VM~~ — 5ª sessão: tudo passou
- [x] ~~`layout/nucleo/`: `config.json` e scripts das etapas 1–3~~ — 8ª sessão
- [x] ~~Etapa 1 no notebook~~ — passou (10ª sessão)
- [x] ~~Etapas 2 e 3 no notebook~~ — passaram (14ª sessão)
- [x] ~~Imagens do 02 e zoom do PDN-0110 (L22)~~
- [x] ~~Refazer 02 + 03 com a L23 e conferir 0 `PDN-0110`~~ — 0 avisos
- [x] ~~Script da etapa 4 (posicionamento)~~
- [x] ~~Rodar a etapa 4 no notebook~~ — passou (15ª sessão)
- [x] ~~Rodar a etapa 5 (CTS)~~ — passou com a L26 (17ª sessão)
- [x] ~~Refazer 4 → 5 → 6 com a L29~~ — excesso 4.682 → 2.038 (19ª sessão)
- [x] ~~Rodar `diag_congestao.sh`~~ — 94 % do excesso nas macros da CPU (20ª sessão)
- [x] ~~Refazer 2 → 6 (global) com a L31~~ — 0 de excesso (21ª sessão)
- [x] ~~Etapa 6 completa~~ — 0 DRV, 0 pinos soltos, 4 h 45 min (23ª sessão)
- [x] ~~Etapa 7 (`07_sta.sh`): RCX + STA final~~ — setup TT −0,10 ns, hold FF −0,11 ns (24ª sessão)
- [x] ~~Decidir L27 (hold no FF) com o STA final~~ — A (24ª sessão)
- [x] ~~`REPARO=1 bash layout/nucleo/07_sta.sh`~~ — TT ok, 15 holds ≤ 28 ps no FF (27ª sessão)
- [x] ~~Script da etapa 8~~ — `08_verificacao.sh` (27ª sessão)
- [x] ~~Rodar a etapa 8 (`08_verificacao.sh`)~~ — LVS ✅; DRC 1.182 e XOR 15,7 M a explicar (28ª sessão)
- [x] ~~`diag_xor.sh` (L44)~~ — macros vazias no GDS do KLayout → L45 (29ª sessão)
- [x] ~~Etapa 8 de novo com L42 + L45~~ — XOR 0, DRC 130 isentos, LVS limpo (30ª sessão)
- [x] ~~Etapa 9~~ — LEC 19.828 equivalentes, simulação PASSOU com as 3 somas (34ª sessão)
- [x] ~~Etapa 10~~ — `chip_top.v` com pads simula PASSOU, 3 somas = RTL (35ª sessão)
- [x] ~~Etapa 11, parte 1~~ — anel de pads, 13/13 passos, GDS + PNG (37ª sessão)
- [x] ~~Etapa 11, parte 2a~~ — PDN ligado pad → anel → núcleo (37ª sessão)
- [ ] IR drop do chip com a fonte **no pad** (`VSRC_LOC_FILES` com a posição do `pad_vccd`/`pad_vssd`): sem terminal de topo, o `analyze_power_grid` usa "bump pattern" (`PSM-0073`: fontes virtuais a cada 140 µm no met5, como num flip-chip) e a queda sai otimista; o `PSM-0025` do `GeneratePDN` é a mesma falta de terminal (L68)
- [x] Etapa 11, parte 2b: fluxo `Chip` completo na rodada `2026-11-01_1249` (L72–L77, 38ª sessão)
- [x] Etapa 12: LVS limpo, DRC 0 no nosso desenho e no núcleo, faixa dos pads isenta (L85; 39ª sessão)
- [x] Etapa 12, STA do chip: setup +2,10 ns, hold +3,68 ns, 0 violações (L87)
- [x] Etapa 12, L77 fechada: fusão dos barramentos é da extração das células da foundry (L89, L91)
- [ ] Etapa 12, densidade de novo com o fill fora da faixa dos pads (`FILL=… ANTES=0 bash layout/chip/12_densidade.sh`, L90)
- [ ] Transição do `pad_tx/OUT` (3,54 ns > 1,5 ns): refazer o chip com o modelo do núcleo (buffer) ou registrar como conhecida — escolha do Lukas
- [ ] (opcional) ECO de hold pós-roteamento para zerar os 15 holds do FF (L40)
- [ ] IR drop com a potência das macros corrigida (L37)
- [x] ~~VM: síntese com L20~~ — 12ª sessão, tudo passou
- [x] ~~Refazer a etapa 1 com o netlist de 29/09~~ — rodada `2026-09-30_0934`
- [x] ~~Etapa 2 depois da L21~~ — passou
- [x] ~~Máquina e PDK~~ — 3ª sessão
- [x] ~~Instalar LibreLane e passar o `--smoke-test`~~ — 3ª sessão
- [x] ~~Confirmar L6~~ — com padring
- [x] ~~Decidir a organização entre chats~~ — git (L8)
- [x] ~~Ligar o GitHub e fazer o primeiro push~~ — `0086abd`
- [ ] Notebook: trocar `~/Projects/asic` pelo clone do repositório
- [ ] Localizar os 2 erros de DRC das macros com mux de coluna (herdado, FE)
- [ ] `.lib` das macros com `internal_power` fora de escala (herdado, FE 14ª sessão)
