#!/usr/bin/env bash
#=============================================================================
# run_tb_top.sh -- chip inteiro: converte, compila o firmware e simula
#
# Uso: NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_top.sh [sw/isfft_dma]
#      DEBUG=1 liga o monitor; DUMP=<pasta> grava as saidas (ver run_tb_evm.sh)
# Precisa: ghdl, iverilog, riscv-none-elf-gcc (terminal SEM env_openram.sh)
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
NEORV32_HOME="${NEORV32_HOME:-$HOME/Projects/neorv32}"
APP="${1:-sw/isfft_dma}"
B="$PROJ/build"

for t in ghdl iverilog vvp riscv-none-elf-gcc; do
  command -v $t >/dev/null || { echo "ERRO: '$t' fora do PATH"; exit 1; }
done

NEORV32_HOME="$NEORV32_HOME" bash "$PROJ/sim/convert.sh" > "$B.convert.out" 2>&1 \
  || { cat "$B.convert.out"; exit 1; }
tail -4 "$B.convert.out"

echo
echo "=== Firmware: $APP ==="
( cd "$PROJ/$APP" && NEORV32_HOME="$NEORV32_HOME" make -s clean_all hex >/dev/null ) || exit 1
riscv-none-elf-size "$PROJ/$APP/main.elf"

echo
echo "=== Simulacao ==="
iverilog -g2012 -o "$B/tb_top.vvp" \
  "$PROJ/rtl/mem/sram4k_1rw.v" "$PROJ/rtl/mem/sram8k_1rw.v" "$PROJ/rtl/neorv32_imem.v" "$PROJ/rtl/neorv32_dmem.v" \
  "$PROJ/macros/sram_4kbyte_1rw_32x1024_8/sram_4kbyte_1rw_32x1024_8.v" \
  "$PROJ/macros/sram_8kbyte_1rw_32x2048_8/sram_8kbyte_1rw_32x2048_8.v" \
  "$B/neorv32_asic.v" \
  "$PROJ"/rtl/isfft/stream_*.v "$PROJ/rtl/isfft/isfft_axi_v4.v" "$PROJ"/rtl/isfft/core/*.v \
  "$PROJ/macros/sram_1rw1r_64x64_wpr2/sram_1rw1r_64x64_wpr2.v" \
  "$PROJ/macros/sram_1rw1r_64x256/sram_1rw1r_64x256.v" \
  "$PROJ/rtl/soc/asic_top.v" "$PROJ/tb/tb_top.v" || exit 1

t0=$SECONDS
vvp -n "$B/tb_top.vvp" +HEX="$PROJ/$APP/neorv32_raw_exe.hex" +BAUD=1000000 ${DEBUG:+"+DEBUG"} ${DUMP:+"+DUMP=$DUMP"} \
  | grep --line-buffered -E "^\[TB\]|^\[UART\]" | tee "$B/tb_top.log"
echo "(tempo real: $((SECONDS - t0)) s)"
grep -q "\[TB\] PASSOU" "$B/tb_top.log"
