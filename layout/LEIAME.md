# layout/ — back-end no LibreLane (notebook)

Dois níveis (L15 do `DIARIO_GDSII.md`):

| Pasta | Nível | Fluxo | Situação |
|---|---|---|---|
| `nucleo/` | 1 — `asic_top` (netlist do Genus + 4 macros) | `Classic` | etapas 1–9 passaram (GDS, DRC/LVS, LEC e simulação) |
| `chip/` | 2 — padring + núcleo como macro | `Chip` | etapa 10 ✅ (`chip_top.v` + simulação com os pads); etapa 11 parte 1 (`11_anel.sh`: anel de pads) pronta para rodar |

## Como rodar o núcleo, uma etapa por vez

```bash
nix-shell ~/Projects/librelane/shell.nix          # terminal sem venv
cd ~/Projects/neorv32-isfft-sky130
git pull --rebase origin main

bash layout/nucleo/01_leitura.sh     # começa uma rodada nova; lê o netlist
bash layout/nucleo/02_floorplan.sh   # die, macros, linhas  -> abre a GUI
bash layout/nucleo/03_pdn.sh         # rede de alimentação  -> abre a GUI
bash layout/nucleo/04_posicionamento.sh  # células nas linhas -> abre a GUI
bash layout/nucleo/05_cts.sh         # árvore de relógio + reparo de timing
```

Cada script roda **um trecho** do fluxo, sempre na mesma rodada, e
continua exatamente de onde o anterior parou. Pode rodar uma etapa de novo
(depois de mudar o `config.json`, por exemplo) sem refazer as anteriores:
ela recomeça do estado em que a etapa anterior terminou.

| Variável | Efeito |
|---|---|
| `SO_GUI=1` | não roda o LibreLane; só reabre a janela da etapa |
| `SEM_GUI=1` | salva as imagens e fecha, sem abrir janela |
| `NETLIST=<arq>` | (só no 01) outro netlist de entrada |

## Deu erro? Mande os logs pelo git

```bash
bash layout/nucleo/junta_logs.sh     # logs + relatórios da rodada -> resultados/
git add resultados/ && git commit -m "gdsii: logs do layout" && git push
```

`runs/` fica fora do git (tem `.odb`, `.def`, GDS). O script separa só o
que é texto: `*.log`, `*.rpt`, `*.json`, `*.txt`, o `flow.log`.

## O que sai

| Onde | O quê | Vai para o git? |
|---|---|---|
| `layout/nucleo/runs/<rodada>/NN-<etapa>/` | tudo do LibreLane: logs, relatórios, `.odb`, `.def` | não (pesado; refaz) |
| `resultados/<rodada>_layout_nucleo/` | `NN_<etapa>_metricas.json`, `01_leitura.txt` | sim |
| `resultados/<rodada>_layout_nucleo/imagens/` | PNGs de cada etapa (2400 px de largura) | sim |

`<rodada>` = data e hora em que o `01_leitura.sh` começou
(ex.: `2026-09-27_1600`).

## Arquivos

| Arquivo | Papel |
|---|---|
| `nucleo/config.json` | configuração do LibreLane: netlist, die, macros (posição e orientação), PDN |
| `nucleo/nucleo.sdc` | restrições: o `base.sdc` do LibreLane + `rstn_i` como false path (igual ao Genus) |
| `nucleo/comum.sh` | funções dos scripts (rodada, retomar estado, métricas, abrir a GUI) |
| `nucleo/tcl/imagem.tcl` | ajusta a visão no OpenROAD e salva as imagens de cada etapa |
| `nucleo/NN_*.sh` | uma etapa cada |
