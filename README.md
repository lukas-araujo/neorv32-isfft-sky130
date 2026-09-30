# neorv32-isfft-sky130

SoC **NEORV32 + acelerador ISFFT** (transceptor OTFS, Programa CI Digital)
levado do RTL ao layout em **SkyWater 130 nm**, com as memórias grandes
geradas pela **OpenRAM**.

| Etapa | Situação | Diário |
|---|---|---|
| Macros SRAM, RTL, simulação, EVM = Kria | ✅ | `DIARIO.md` (congelado) |
| Síntese Genus, pós-síntese Xcelium, LEC Conformal | ✅ | `DIARIO.md` |
| Ressíntese para o layout + LibreLane → GDSII | ▶ | `DIARIO_GDSII.md` |
| UVM no IP da ISFFT (8/8 no Xcelium, cobertura funcional 94,4 %, 12/12 mutações) | ▶ | `DIARIO_UVM.md` |
| Síntese com DFT no IP da ISFFT | ⏳ | `DIARIO_DFT.md` |

Números de referência (Genus, 50 MHz): 1,91 mm² (62% macros), slack
+2,4 ns, LEC 169/169 módulos. EVM do chip = Kria (3,41 / 0,78 / 0,60 %).

---

## Para chats do Claude

Leia o `CLAUDE.md` (regras de trabalho e de git) e o diário da sua frente.

---

## Mapa do repositório e donos

Cada frente de trabalho (um chat) é **dona** de algumas pastas e só **lê**
as outras. Mudança fora da própria pasta: registrar no diário de quem mudou
e avisar nos outros.

| Pasta | O quê | Dono |
|---|---|---|
| `rtl/` | RTL do chip (NEORV32 em VHDL + Verilog próprio) | front-end¹ |
| `rtl/isfft/` | `isfft_axi_v4` (chip), núcleo Spiral, conversores; `ref/` = etapa 1 | front-end¹ |
| `tb/`, `sim/run_tb_*.sh` | Testbenches e bancadas do notebook | front-end¹ |
| `sw/` | Firmwares (`main.c`, `makefile`, `.hex`, vetores, somas) | front-end¹ |
| `macros/` | 4 macros OpenRAM: `.v`, `.lef`, `.lib`, `.html`, `.gds.gz` | GDSII |
| `openram/` | Configs e scripts de geração | GDSII |
| `tech/sky130/` | Cópia das células sky130 (lib, lef, verilog) usada pela VM | GDSII |
| `vm/backend/synthesis/` | Scripts Genus / Xcelium / Conformal do **chip** | GDSII |
| `vm/backend/dft_isfft/` | Síntese com DFT do IP da ISFFT | DFT |
| `vm/verification/uvm_isfft/` | Ambiente UVM do IP da ISFFT | UVM |
| `sim/run_uvm_*.sh`, `sim/traz_uvm.sh` | UVM no Verilator (conferência aberta, mutações) e retorno dos resultados da VM | UVM |
| `layout/` | Configuração do LibreLane (notebook) | GDSII |
| `resultados/<data>_<etapa>/` | Relatórios e entregáveis que voltaram da VM ou do LibreLane | quem rodou |
| `doc/` | Diagramas e figuras | todos (cada um os seus arquivos) |
| `DIARIO*.md` | Um diário por frente | cada frente o seu |

¹ Front-end fechado: mudança de RTL só com motivo registrado no diário da
frente que precisou dela (ex.: DFT pedir porta de teste) e regressão
rodada de novo (`sim/run_tb_isfft_ref.sh`, `sim/run_tb_evm.sh`).

---

## Fluxo de trabalho com git

```bash
git pull                     # sempre antes de começar
# ... trabalho ...
git add <arquivos da sua pasta>
git commit -m "gdsii: .lib de 33 bits nas macros 1rw (L1)"
git push
```

- Prefixo da mensagem = frente: `fe:`, `gdsii:`, `uvm:`, `dft:`, `doc:`.
- Citar a decisão do diário (`L1`, `U3`, `T2`...) quando houver.
- Resultado que volta da VM entra em `resultados/<data>_<etapa>/`
  (relatórios, netlist, logs úteis compactados), nunca a pasta de trabalho
  inteira. Quem separa é o script:

  ```bash
  # pasta da VM copiada para o notebook
  bash sim/traz_vm.sh ~/Downloads/neorv32_isfft_soc sintese_layout
  git add resultados/ && git commit -m "gdsii: resultados da VM -- sintese_layout" && git push
  ```

  A data da pasta é a do netlist (quando o Genus rodou). Arquivo acima de
  500 kB vai compactado (`zless` para ler); `.sdf` não vem.

---

## A pasta da VM é montada, nunca editada à mão

```bash
bash sim/monta_vm.sh              # -> build/vm/neorv32_isfft_soc/ (+ .tgz)
```

- Tudo o que está em `vm/` vai para a pasta, na mesma posição.
  Frente nova = subpasta nova em `vm/`; o script não precisa mudar.
- `frontend/` vem de `rtl/` e do `build/neorv32_asic.v` (convertido pelo
  GHDL com `sim/convert.sh`); `tech/` vem de `tech/sky130/` + `macros/`.
- Na VM só se comenta/descomenta os blocos do `run_first.tcl`. Mudou
  conteúdo de script? Mude em `vm/`, faça commit e monte de novo.

---

## Preparar um clone novo

```bash
bash macros/descompacta_gds.sh    # .gds.gz -> .gds (os .gds ficam fora do git)
```

Dependências fora do repositório:

| O quê | Versão | Para quê |
|---|---|---|
| NEORV32 | commit `8bdbe48` (v1.13.5.6), `NEORV32_HOME=~/Projects/neorv32` | `sim/convert.sh` |
| OSS CAD Suite | GHDL 4.1 (com `synth`), Icarus 12, Yosys | conversão e simulação no notebook |
| `riscv-none-elf-gcc` | xPack 15.2.0 | firmwares |
| OpenRAM | v1.2.49 (`b2b069ce`) | só para gerar macro nova |
| LibreLane (OpenROAD, Magic, Netgen, KLayout) | 3.0.14 via Nix, `~/Projects/librelane` | layout |
| PDK sky130 do layout | `8afc8346` (fixado pelo LibreLane), `PDK_ROOT=~/Projects/pdks/librelane` | layout |
| PDK sky130 da OpenRAM | `e8294524` (2022.07.29), `~/Projects/pdks` | macros |
| Cadence (VM goku) | Genus 22.1, Xcelium 23.09, Conformal 23.2 | síntese, pós-síntese, LEC |

---

## Ambiente do layout (notebook)

```bash
nix-shell ~/Projects/librelane/shell.nix        # terminal sem venv
export PDK_ROOT=$HOME/Projects/pdks/librelane
```

---

## O que não entra no git

Ver `.gitignore`: `build/`, saídas de simulação, objetos do firmware,
`openram/out/`, `.gds` descompactados, `xcelium.d/`, `work/` do Genus,
`.sdf` (o Genus refaz) e as rodadas do LibreLane (`layout/runs/`).
