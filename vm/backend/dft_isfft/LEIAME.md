# backend/dft_isfft/ — síntese com scan e ATPG do IP da ISFFT (`isfft_axi_v4`)

Frente de **DFT** (`DIARIO_DFT.md`, decisões Tn). Pasta própria, com
script próprio (`scripts/run_first_dft.tcl`): **não mexe** na síntese do chip
(`backend/synthesis/`, `run_first.tcl`). De lá só **lê** o `path.tcl` e o
`tech.tcl` (mesmas bibliotecas, mesmas células proibidas), e muda uma
coisa: as células de scan deixam de ser evitadas (T2).

Fonte de verdade: `vm/backend/dft_isfft/` do repositório; chega à VM pelo
`sim/monta_vm.sh`. **Não edite aqui**: mude no repositório e monte de novo.

## Como rodar (VM)

```bash
cd /prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc/backend/dft_isfft/scripts
source run_first_dft.tcl        # bloco 1 (Genus) já vem descomentado
```

Depois, **um bloco por vez** (comente o atual, descomente o próximo):

| Bloco | O quê | Esperado |
|---|---|---|
| 1 | Síntese com scan (Genus, ~5 min) | 0 violações de DFT; só flip-flops de scan (`sdfxtp`/`sedfxtp`); 16 cadeias de ~785; arquivos em `modus_work/` |
| 2a | LEC: RTL sem scan × netlist com scan (Conformal) | 0 non-equivalent; 2 caixas-pretas (as macros) |
| 2b | Regressão da Kria no netlist com scan, `scan_en = 0` (Xcelium) | `PASSOU: 40 matrizes identicas a referencia` |
| 3 | ATPG *stuck-at* (Modus) | cadeias passam no teste de estrutura; cobertura no log |

Resultados de volta para o repositório (notebook):

```bash
bash sim/traz_dft.sh ~/Downloads/neorv32_isfft_soc scan
git add resultados/<data>_dft_scan && git commit -m "dft: resultados da VM -- scan" && git push
```

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `scripts/` | `run_first_dft.tcl` (blocos), `isfft_dft.tcl` (Genus) |
| `constraints/` | `isfft_dft.sdc`: 50 MHz, modo funcional (`scan_en = 0` por *case analysis*) |
| `modus/` | biblioteca das células para o Modus (`sky130_fd_sc_hd_atpg.v.gz`, pré-processada com `FUNCTIONAL`; T7) e as 2 macros só com portas (`macros_caixa_preta.v`; T6) |
| `tb/` | `tb_isfft_dft.v`: o tb da Kria com o DUT = netlist com scan (bloco 2b) |
| `work/`, `reports/`, `deliverables/`, `modus_work/`, `sim_kria/` | criadas pelo script |

## Por que estas escolhas (resumo; detalhe no diário)

- **Scan completo, 16 cadeias** (T1, T5): 12.559 flip-flops / 16 ≈ 785 ciclos
  de deslocamento por padrão.
- **Sem `test_mode`** (T3): o IP não tem reset assíncrono, clock gating nem
  latch — nada que precise ser "domado" em modo de teste.
- **Macros caixa-preta, sem *shadow logic*** (T6): primeiro medir quanto de
  cobertura se perde em volta delas, depois remediar.

## Conferido antes de vir para a VM

`sim/run_dft_aberto.sh` (notebook ou nuvem, Yosys + Icarus): scan "de
mentira" no netlist do Yosys (mesmas células de scan), regressão da Kria com
`scan_en = 0`, teste de cadeia (flush) das 16 cadeias e uma mutação (cadeia
quebrada) detectada. Resultados no `DIARIO_DFT.md`.
