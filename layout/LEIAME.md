# layout/ — back-end no LibreLane (notebook)

Dois níveis (L15 do `DIARIO_GDSII.md`):

| Pasta | Nível | Fluxo | Situação |
|---|---|---|---|
| `nucleo/` | 1 — `asic_top` (netlist do Genus + 4 macros) | `Classic` | etapas 1–3 prontas para rodar |
| `chip/` | 2 — padring + núcleo como macro | `Chip` | a fazer |

## Como rodar o núcleo, uma etapa por vez

```bash
nix-shell ~/Projects/librelane/shell.nix          # terminal sem venv
cd ~/Projects/neorv32-isfft-sky130
git pull --rebase origin main

bash layout/nucleo/01_leitura.sh     # começa uma rodada nova; lê o netlist
bash layout/nucleo/02_floorplan.sh   # die, macros, linhas  -> abre a GUI
bash layout/nucleo/03_pdn.sh         # rede de alimentação  -> abre a GUI
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
