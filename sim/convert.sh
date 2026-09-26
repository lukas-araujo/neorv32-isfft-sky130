#!/usr/bin/env bash
#=============================================================================
# convert.sh -- NEORV32 (VHDL) -> um unico Verilog, com IMEM/DMEM trocadas
#
# Mesmo metodo do rtl/verilog/Makefile oficial do NEORV32 ("Replaceable
# Modules"): os arquivos neorv32_imem.vhd e neorv32_dmem.vhd ficam FORA da
# conversao; o GHDL deixa as duas instancias como caixas-pretas, e os nossos
# rtl/neorv32_imem.v / rtl/neorv32_dmem.v (macro OpenRAM) as preenchem.
#
# Saida: build/neorv32_asic.v   (um modulo por hierarquia nao achatada)
#
# Uso: NEORV32_HOME=~/Projects/neorv32 bash sim/convert.sh
#=============================================================================
set -eu
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
NEORV32_HOME="${NEORV32_HOME:-$HOME/Projects/neorv32}"
B="$PROJ/build"
W="$B/ghdl_work"
rm -rf "$W"; mkdir -p "$W"

command -v ghdl >/dev/null || { echo "ERRO: ghdl fora do PATH (terminal novo, sem env_openram.sh)"; exit 1; }

# Lista oficial de arquivos, SEM imem e dmem
SRCS=$(sed "s|\$NEORV32_HOME|$NEORV32_HOME|" "$NEORV32_HOME/rtl/file_list_core.f" \
       | grep -v -e 'neorv32_imem\.vhd$' -e 'neorv32_dmem\.vhd$')
SRCS="$SRCS $NEORV32_HOME/rtl/system_integration/xbus2axi4_bridge.vhd"

echo "=== Conversao VHDL -> Verilog ==="
echo "  NEORV32: $NEORV32_HOME"
echo "  excluidos (caixas-pretas): neorv32_imem.vhd neorv32_dmem.vhd"

ghdl -i --std=08 --work=neorv32 --workdir="$W" $SRCS "$PROJ/rtl/soc/neorv32_asic.vhd"
ghdl -m --std=08 --work=neorv32 --workdir="$W" neorv32_asic
ghdl synth --std=08 --work=neorv32 --workdir="$W" --out=verilog neorv32_asic \
    > "$B/neorv32_asic.v" 2> "$B/convert.log" \
  || { echo "ERRO: ghdl synth falhou -- ver $B/convert.log"; tail -20 "$B/convert.log"; exit 1; }

echo "  saida: $B/neorv32_asic.v ($(wc -l < "$B/neorv32_asic.v") linhas, $(grep -c '^module' "$B/neorv32_asic.v") modulos)"
echo
echo "=== Caixas-pretas esperadas (instancias de neorv32_imem / neorv32_dmem) ==="
grep -nE "^\s*neorv32_(imem|dmem)\b" "$B/neorv32_asic.v" || { echo "ERRO: nenhuma caixa-preta -- a exclusao nao funcionou"; exit 1; }
# Nao pode haver definicao de modulo imem/dmem vinda do VHDL
if grep -qE "^module neorv32_(imem|dmem)\b" "$B/neorv32_asic.v"; then
  echo "ERRO: o Verilog convertido DEFINE neorv32_imem/dmem -- o VHDL original entrou na conversao"; exit 1
fi
echo "OK"
