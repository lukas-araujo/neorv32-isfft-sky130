#!/usr/bin/env bash
#=============================================================================
# run_tb_evm.sh -- validacao numerica da ISFFT no chip (EVM, criterio da Kria)
#
# 1. evm.py gera as 3 matrizes do notebook da Kria (sw/isfft_evm/vetores.h)
# 2. run_tb_top.sh roda o chip inteiro com o firmware isfft_evm; o testbench
#    copia a saida que chegou na DMEM para build/evm/saida_<m>.hex
# 3. evm.py compara com o modelo numpy e com o EVM medido na Kria
#
# Uso: NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_evm.sh
# Precisa: o mesmo do run_tb_top.sh + python3 com numpy
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
D="$PROJ/build/evm"
rm -rf "$D"; mkdir -p "$D"
python3 -c "import numpy" 2>/dev/null || { echo "ERRO: python3 sem numpy"; exit 1; }

python3 "$PROJ/sw/isfft_evm/evm.py" gera "$PROJ/sw/isfft_evm/vetores.h" || exit 1
DUMP="$D" bash "$PROJ/sim/run_tb_top.sh" sw/isfft_evm || exit 1
echo
echo "=== EVM (modelo numpy x saida na DMEM) ==="
python3 "$PROJ/sw/isfft_evm/evm.py" avalia "$D"
