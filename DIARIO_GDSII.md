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
| L14 | Netlist do layout = rodada de 27/09 | ✅ | 2026-09-27 |
| L15 | Dois níveis: núcleo → chip com padring | ✅ | 2026-09-27 |
| L16 | Padring `sky130_ef_io` no nosso config | 🟡 | 2026-09-27 |
| L17 | `config.json` do núcleo | 🟡 | 2026-09-27 |
| L18 | Uma etapa por script, com GUI e imagem | ✅ | 2026-09-27 |

---

## Pendências abertas

- [x] ~~Decidir L4~~ — Genus (caminho A)
- [x] ~~Rodada para o layout na VM~~ — 5ª sessão: tudo passou
- [x] ~~`layout/nucleo/`: `config.json` e scripts das etapas 1–3~~ — 8ª sessão
- [ ] Rodar `01_leitura.sh`, `02_floorplan.sh`, `03_pdn.sh` no notebook
- [x] ~~Máquina e PDK~~ — 3ª sessão
- [x] ~~Instalar LibreLane e passar o `--smoke-test`~~ — 3ª sessão
- [x] ~~Confirmar L6~~ — com padring
- [x] ~~Decidir a organização entre chats~~ — git (L8)
- [x] ~~Ligar o GitHub e fazer o primeiro push~~ — `0086abd`
- [ ] Notebook: trocar `~/Projects/asic` pelo clone do repositório
- [ ] Localizar os 2 erros de DRC das macros com mux de coluna (herdado, FE)
- [ ] `.lib` das macros com `internal_power` fora de escala (herdado, FE 14ª sessão)
