# neorv32_isfft_soc — pasta da VM (Genus · Xcelium · Conformal)

Chip **NEORV32 + ISFFT** em **SkyWater 130 nm**, com 4 macros SRAM da
OpenRAM. Mesmo formato do `neorv32_sram_soc`. Montada por
`sim/monta_vm.sh` a partir do projeto do notebook — **não edite aqui**:
edite o projeto e monte de novo.

## Como rodar

```bash
# copiar a pasta para /prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc
cd /prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc/backend/synthesis/scripts
source run_first.tcl        # bloco 1 (Genus) já vem descomentado
```

O Genus termina no próprio prompt: confira o que quiser e digite `exit`.
Aí o `run_first.tcl` imprime a conferência da síntese.

Depois, **um bloco por vez** (comente o 1, descomente o próximo):

| Bloco | O quê | Esperado |
|---|---|---|
| 0 | Simulação RTL no Xcelium (opcional, antes do 1) | `[TB] PASSOU` |
| 1 | Síntese no Genus | macros: 4 linhas no `_gates.rpt`; células evitadas: 0; constantes soltas: 0; `conb_1` > 0; `spare_wen0` nas 2 macros de 1 porta |
| 2 | Simulação pós-síntese no Xcelium | `soma = RTL` nas 3 matrizes e `[TB] PASSOU` |
| 3a / 3b | LEC no Conformal (dofile do Genus / escrito à mão) | 0 non-equivalent |

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `frontend/` | RTL do chip, **só Verilog**: `asic_top.v` (topo), `neorv32_asic.v` (NEORV32 convertido pelo GHDL — gerado), IMEM/DMEM com macro, conversores 32↔64, `isfft_axi_v4.v` |
| `frontend/isfft/` | Núcleo da ISFFT (Spiral + FSMs), igual ao da Kria |
| `sw/isfft_evm/` | Firmware (3 matrizes do notebook da Kria) + `chk_rtl.txt` (somas da simulação RTL) |
| `sw/hello/` | Firmware de teste da IMEM inteira (`+BAUD=115200`) |
| `tech/lib/` | `.lib` das células sky130 (TT) e das 4 macros (rodada back-end; as 2 de 1 porta corrigidas para 33 bits) |
| `tech/lef/` | LEF das células e das 4 macros (para o layout; o Genus não usa) |
| `tech/verilog/` | Modelos de simulação: células sky130 (**1 linha corrigida**, ver abaixo) e macros OpenRAM |
| `backend/synthesis/scripts/` | `run_first.tcl`, script do Genus, `common/`, dofile do LEC, testbench, modelo da IMEM (`imem_sim_model.v`) |
| `backend/synthesis/constraints/` | SDC (50 MHz) |
| `verification/uvm_isfft/` | Verificação **UVM** do IP da ISFFT (`isfft_axi_v4`), com script próprio: `scripts/run_first_uvm.tcl`. Ver o `LEIAME.md` de lá e o `DIARIO_UVM.md` |
| `backend/dft_isfft/` | **DFT** do IP da ISFFT: síntese com scan (Genus) e ATPG (Modus), com script próprio: `scripts/run_first_dft.tcl`. Ver o `LEIAME.md` de lá e o `DIARIO_DFT.md` |

## Pontos que já custaram tempo (não mude sem ler o DIARIO)

- **Macros de 1 porta com 33 bits em tudo** (desde a rodada para o
  layout, `DIARIO_GDSII` L1): o `.lib` da OpenRAM tinha 32 bits e foi
  corrigido por `macros/lib_33bits.py`. O antigo `-define SRAM_LIB_VIEW`
  **não existe mais** — se aparecer em algum comando, está errado.
- **Constantes em `conb_1`** (`add_tieoffs` no script do Genus, L2): o
  layout não aceita `1'b0`/`1'b1` soltos no netlist.
- **`-define FUNCTIONAL`** na simulação pós-síntese: o
  `sky130_fd_sc_hd.v` não tem blocos `specify`; sem `FUNCTIONAL` todo
  flip-flop fica em X (era o X do projeto anterior).
- **Linha 49162 do `sky130_fd_sc_hd.v`**: `` `endif `` sem `//` no
  arquivo do PDK, corrigido aqui (só aparece com `FUNCTIONAL`).
- **Sem `-v`** no arquivo de células; **`restore_nettype.v`** logo depois dele.
- **Sem simulação com SDF**: sem `specify` não há onde anotar atraso.
- O programa entra pela **macro da IMEM** (`+IMEM_HEX`), dentro do
  `imem_sim_model.v` — o testbench não depende dos nomes do netlist.

## Conferido antes de vir para a VM (na nuvem, com ferramentas abertas)

`sim/run_gls_yosys.sh` (roda também no notebook):

- RTL desta pasta no Icarus, com os mesmos modelos de memória e o mesmo
  testbench: `PASSOU` (somas = RTL).
- Síntese do mesmo RTL com Yosys nas mesmas células sky130 (mesmas
  células evitadas) + simulação do netlist no Icarus com `FUNCTIONAL`:
  as 3 somas iguais às do RTL, contadores certos, `PASSOU`.

Para chegar nisso a simulação de portas achou 3 problemas (DIARIO, 13ª
sessão): o modelo das células sem `FUNCTIONAL` (todo flip-flop em X — era
o X do projeto anterior) e dois pontos do núcleo Spiral que ligam com
lixo no silício (corrigidos: D34).

O Genus e o Xcelium não existem na nuvem: os comandos deles seguem o
projeto anterior, que rodou nesta VM. O netlist do Genus não é o do Yosys
— a simulação de portas na VM (bloco 2) continua sendo a prova.
