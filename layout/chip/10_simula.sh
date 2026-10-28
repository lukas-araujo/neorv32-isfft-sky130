#!/usr/bin/env bash
#=============================================================================
# 10_simula.sh -- ETAPA 10: o chip COM os pads simula igual ao nucleo?
#
#   chip_top.v (4 gpiov2 + 6 pads de alimentacao + fatia VCCHIB + nucleo)
#   + tb_gate.v com -DCHIP_TOP: o clock, o reset e a UART passam pelos
#   pads. Esperado: as 3 somas = RTL e [TB] PASSOU, como nas etapas
#   anteriores.
#
#   Nucleo (NUCLEO=):
#     layout  (padrao) netlist do LAYOUT do nucleo, o mesmo da etapa 9
#             (vm/backend/synthesis/netlist_layout/asic_top_layout.v.gz):
#             e o circuito que vai virar macro no chip. ~30 min no Icarus.
#     <arquivo.v>      outro netlist do asic_top
#
#   Modelos: celulas (tech/sky130/verilog), pads (tech/sky130_io/verilog,
#   da SkyWater/Efabless -- ver o LEIAME de la), macros (macros/*/*.v, com
#   VERBOSE=0, IMEM pelo imem_sim_model.v), como no run_first.tcl.
#
#   CHIP_V=<arquivo.v>    outro chip_top (ex.: uma copia com defeito
#                         plantado, para o teste de mutacao)
#   EXTRA="+LIMITE_MS=1"  plusargs a mais para o tb_gate (ex.: teste de
#                         mutacao que nao precisa da simulacao inteira)
#
#   Precisa: iverilog (OSS CAD Suite no notebook; apt na nuvem).
#   Uso: bash layout/chip/10_simula.sh
#=============================================================================
set -euo pipefail
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
CHIP="$REPO/layout/chip"
B="$REPO/build/chip_sim"
SCR="$REPO/vm/backend/synthesis/scripts"
IO="$REPO/tech/sky130_io/verilog"
T="$REPO/tech/sky130/verilog"
command -v iverilog >/dev/null || { echo "ERRO: iverilog fora do PATH"; exit 1; }
rm -rf "$B"; mkdir -p "$B/modelos"

# Nucleo
NUCLEO="${NUCLEO:-layout}"
if [ "$NUCLEO" = layout ]; then
  zcat "$REPO/vm/backend/synthesis/netlist_layout/asic_top_layout.v.gz" > "$B/asic_top.v"
else
  cp "$NUCLEO" "$B/asic_top.v"
fi

# Macros: o mesmo que o prepara_modelos do run_first.tcl
m=sram_8kbyte_1rw_32x2048_8
sed -e "s/module ${m}(/module ${m}_beh(/" -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' \
    "$REPO/macros/$m/$m.v" > "$B/modelos/${m}_beh.v"
for m in sram_4kbyte_1rw_32x1024_8 sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2; do
  sed -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' "$REPO/macros/$m/$m.v" > "$B/modelos/$m.v"
done

echo "=== Compilando (Icarus $(iverilog -V 2>&1 | head -1 | cut -d' ' -f4)) ==="
# USE_POWER_PINS NAO vai na linha de comando: entra pelo
# pinos_alimentacao_pads.v, e por isso pads e chip_top vem por ULTIMO --
# celulas, nucleo e modelos das macros (que tambem tem ifdef
# USE_POWER_PINS) sao lidos antes, sem a macro.
# -s tb_gate: so elabora a partir do testbench (o sky130_ef_io.v tem
# varios pads que nao usamos, com celulas-base que nao trouxemos)
iverilog -g2005 -s tb_gate -DFUNCTIONAL -DUNIT_DELAY=#1 -DCHIP_TOP -o "$B/chip.vvp" \
  "$T/primitives.v" "$T/sky130_fd_sc_hd.v" "$SCR/restore_nettype.v" \
  "$B/asic_top.v" "$SCR/imem_sim_model.v" "$B"/modelos/*.v "$SCR/tb_gate.v" \
  "$CHIP/pinos_alimentacao_pads.v" \
  "$IO/sky130_fd_io__top_gpiov2.functional.pp.v" \
  "$IO/sky130_fd_io__top_power_lvc_wpad.functional.pp.v" \
  "$IO/sky130_fd_io__top_power_hvc_wpadv2.functional.pp.v" \
  "$IO/sky130_fd_io__top_ground_lvc_wpad.functional.pp.v" \
  "$IO/sky130_fd_io__top_ground_hvc_wpad.functional.pp.v" \
  "$IO/sky130_ef_io.v" "$IO/sky130_ef_io__gpiov2_pad_wrapped.v" \
  "$IO/sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.v" \
  "${CHIP_V:-$CHIP/chip_top.v}" \
  2> "$B/compila.log" || { grep -v "timescale" "$B/compila.log" | head -30; exit 1; }
grep -v "timescale\|inherits" "$B/compila.log" | head -10 || true

echo "=== Simulando ==="
t0=$SECONDS
vvp -n "$B/chip.vvp" +IMEM_HEX="$REPO/sw/isfft_evm/neorv32_raw_exe.hex" \
    +CHK_FILE="$REPO/sw/isfft_evm/chk_rtl.txt" ${EXTRA:-} \
  | grep --line-buffered -E "^\[" | tee "$B/sim.log"
echo "(tempo real: $((SECONDS - t0)) s)"
grep -q "\[TB\] PASSOU" "$B/sim.log"
