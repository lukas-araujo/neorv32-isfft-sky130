#!/usr/bin/env bash
#=============================================================================
# run_tb_soc.sh -- simula o SoC convertido rodando um firmware das macros
#
# Uso:
#   NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_soc.sh [sw/hello]
#
# Passos: converte (sim/convert.sh), compila o firmware (make hex) e simula
# no Icarus. Precisa de ghdl, iverilog e riscv-none-elf-gcc no PATH.
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
NEORV32_HOME="${NEORV32_HOME:-$HOME/Projects/neorv32}"
APP="${1:-sw/hello}"
B="$PROJ/build"

for t in ghdl iverilog vvp riscv-none-elf-gcc; do
  command -v $t >/dev/null || { echo "ERRO: '$t' fora do PATH"; exit 1; }
done

NEORV32_HOME="$NEORV32_HOME" bash "$PROJ/sim/convert.sh" || exit 1

echo
echo "=== Firmware: $APP ==="
( cd "$PROJ/$APP" && NEORV32_HOME="$NEORV32_HOME" make -s clean_all hex ) || exit 1
HEX="$PROJ/$APP/neorv32_raw_exe.hex"
riscv-none-elf-size "$PROJ/$APP/main.elf"

echo
echo "=== Simulacao ==="
iverilog -g2012 -o "$B/tb_soc.vvp" \
  "$PROJ/rtl/mem/sram4k_1rw.v" "$PROJ/rtl/mem/sram8k_1rw.v" "$PROJ/rtl/neorv32_imem.v" "$PROJ/rtl/neorv32_dmem.v" \
  "$PROJ/macros/sram_4kbyte_1rw_32x1024_8/sram_4kbyte_1rw_32x1024_8.v" \
  "$PROJ/macros/sram_8kbyte_1rw_32x2048_8/sram_8kbyte_1rw_32x2048_8.v" \
  "$B/neorv32_asic.v" "$PROJ/tb/tb_soc.v" || exit 1

t0=$SECONDS
vvp -n "$B/tb_soc.vvp" +HEX="$HEX" | grep --line-buffered -E "^\[TB\]|^\[UART\]" | tee "$B/tb_soc.log"
echo "(tempo de simulacao real: $((SECONDS - t0)) s)"
grep -q "\[TB\] PASSOU" "$B/tb_soc.log"
