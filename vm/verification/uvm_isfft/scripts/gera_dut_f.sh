#!/usr/bin/env bash
#=============================================================================
# gera_dut_f.sh -- escreve o isfft_dut.f (arquivos do DUT) a partir da pasta
# do projeto
#
# Uso:  bash gera_dut_f.sh <PROJECT_DIR> <UVM_DIR> <saida.f>
#
# Chamado pelo run_first_uvm.tcl (VM) e pelo sim/run_uvm_verilator.sh
# (notebook/nuvem): os dois simuladores leem a MESMA lista.
#
# A lista e montada na hora, do que existe em frontend/ -- o MESMO RTL que
# o Genus sintetizou. Assim ela nunca fica velha quando o RTL muda.
#   DUT        : frontend/isfft_axi_v4.v + frontend/isfft/*.v (nucleo)
#   macros     : tech/verilog/sram_1rw1r_*.v (modelo .v da OpenRAM)
#   referencia : <UVM_DIR>/ref/isfft_axi_wrapper.v (wrapper da etapa 1)
#=============================================================================
set -u
P="${1:?PROJECT_DIR}"; U="${2:?UVM_DIR}"; SAI="${3:?saida.f}"
MACROS="sram_1rw1r_64x64_wpr2 sram_1rw1r_64x256"

falta () { echo "gera_dut_f.sh: FALTA $1" >&2; exit 1; }
[ -f "$P/frontend/isfft_axi_v4.v" ]      || falta "$P/frontend/isfft_axi_v4.v"
[ -f "$P/frontend/isfft/top_isfft.v" ]   || falta "$P/frontend/isfft/top_isfft.v"
[ -f "$U/ref/isfft_axi_wrapper.v" ]      || falta "$U/ref/isfft_axi_wrapper.v"
for m in $MACROS; do [ -f "$P/tech/verilog/$m.v" ] || falta "$P/tech/verilog/$m.v"; done

{
  echo "// isfft_dut.f -- GERADO por gera_dut_f.sh em $(date '+%Y-%m-%d %H:%M'). Nao edite."
  echo "$P/frontend/isfft_axi_v4.v"
  for f in "$P"/frontend/isfft/*.v; do echo "$f"; done
  for m in $MACROS; do echo "$P/tech/verilog/$m.v"; done
  echo "$U/ref/isfft_axi_wrapper.v"
} > "$SAI"
echo "isfft_dut.f: $(grep -c '/frontend/' "$SAI") arquivos do frontend, 2 macros, 1 referencia"
