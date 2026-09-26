#!/usr/bin/env bash
#=============================================================================
# run_gls_yosys.sh -- conferencia ABERTA antes da VM: sintese com Yosys nas
# celulas sky130 + simulacao de portas no Icarus
#
# Roda sobre a pasta da VM montada por sim/monta_vm.sh: usa EXATAMENTE os
# arquivos que vao para o Genus e o Xcelium (frontend, .lib, modelos,
# testbench, adaptadores). O netlist do Yosys nao e o do Genus, mas pega
# o que importa antes de gastar horas na VM:
#   - o RTL sintetiza (Verilog puro, macros como caixa-preta do .lib)
#   - o netlist sai do reset sem X (o problema do projeto anterior)
#   - o testbench, os adaptadores e os modelos funcionam em portas
#
# Uso:
#   bash sim/run_gls_yosys.sh [pasta_vm]      (padrao: build/vm/neorv32_isfft_soc)
#   MODO=rtl bash sim/run_gls_yosys.sh        (so o tb_gate sobre o RTL, rapido)
#
# Precisa: yosys (OSS CAD Suite) ou yowasp-yosys (pip), iverilog.
# Tempo: sintese ~1 min; simulacao de portas ~20 min (188 mil ciclos).
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
VM="${1:-$PROJ/build/vm/neorv32_isfft_soc}"
B="$PROJ/sim/build_gls"
MODO="${MODO:-portas}"

[ -f "$VM/backend/synthesis/scripts/tb_gate.v" ] || { echo "Pasta da VM nao encontrada: $VM (rode sim/monta_vm.sh)"; exit 1; }
command -v iverilog >/dev/null || { echo "ERRO: iverilog fora do PATH"; exit 1; }
YOSYS="$(command -v yosys || command -v yowasp-yosys || true)"
[ "$MODO" = rtl ] || [ -n "$YOSYS" ] || { echo "ERRO: yosys/yowasp-yosys fora do PATH"; exit 1; }

rm -rf "$B"; mkdir -p "$B/src" "$B/modelos"
SCR="$VM/backend/synthesis/scripts"
T="$VM/tech"

# Modelos das macros: o mesmo que o prepara_modelos do run_first.tcl
m=sram_8kbyte_1rw_32x2048_8
sed -e "s/module ${m}(/module ${m}_beh(/" -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' \
    "$T/verilog/${m}.v" > "$B/modelos/${m}_beh.v"
for m in sram_4kbyte_1rw_32x1024_8 sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2; do
  sed -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' "$T/verilog/${m}.v" > "$B/modelos/${m}.v"
done
MODELOS="$SCR/imem_sim_model.v $B/modelos/*.v"
ARGS="+IMEM_HEX=$VM/sw/isfft_evm/neorv32_raw_exe.hex +CHK_FILE=$VM/sw/isfft_evm/chk_rtl.txt"

if [ "$MODO" = rtl ]; then
  echo "=== tb_gate sobre o RTL ==="
  iverilog -g2005 -o "$B/rtl.vvp" "$VM"/frontend/*.v "$VM"/frontend/isfft/*.v \
    $MODELOS "$SCR/tb_gate.v" 2> "$B/rtl.compile.log" || { cat "$B/rtl.compile.log"; exit 1; }
  vvp -n "$B/rtl.vvp" $ARGS | grep --line-buffered -E "^\[" | tee "$B/rtl.log"
  grep -q "\[TB\] PASSOU" "$B/rtl.log"; exit $?
fi

#-----------------------------------------------------------------------------
# Sintese (yowasp roda em caixa de areia: arquivos no diretorio atual)
#-----------------------------------------------------------------------------
cp "$VM"/frontend/*.v "$VM"/frontend/isfft/*.v "$B/src/"
cp "$T"/lib/*.lib "$B/"
LIB=sky130_fd_sc_hd__tt_025C_1v80.lib
EVITA="-dont_use *__sdf* -dont_use *__sedf* -dont_use *__sdlclkp* -dont_use *__lpflow_* -dont_use *__probe* -dont_use *__macro_sparecell*"
( cd "$B"
  {
    echo "read_verilog $(cd "$B" && ls src/*.v | tr '\n' ' ')"
    for l in sram_*_TT_1p8V_25C.lib $LIB; do echo "read_liberty -lib $l"; done
    echo "hierarchy -check -top asic_top"
    echo "synth -top asic_top"
    echo "dfflibmap -liberty $LIB $EVITA"
    echo "abc -liberty $LIB $EVITA"
    echo "opt_clean"
    echo "hilomap -singleton -hicell sky130_fd_sc_hd__conb_1 HI -locell sky130_fd_sc_hd__conb_1 LO"
    echo "setundef -zero"
    echo "opt_clean -purge"
    echo "tee -o stat.txt stat -liberty $LIB"
    echo "write_verilog -noattr -noexpr -nohex -nodec netlist_yosys.v"
  } > synth.ys
  echo "=== Sintese Yosys ==="
  "$YOSYS" -q -l yosys.log synth.ys > yosys.out 2>&1 || { tail -20 yosys.out; exit 1; }
)
grep "Chip area for top module" "$B/stat.txt" | sed 's/^ */  logica (sem macros): /'
echo "  macros no netlist: $(grep -cE '^\s*sram_(8kbyte|4kbyte|1rw1r)\S* ' "$B/netlist_yosys.v") (esperado 4)"
echo "  celulas evitadas:  $(grep -cE 'sky130_fd_sc_hd__(sdf|sedf|sdlclkp|lpflow|probe)' "$B/netlist_yosys.v") (esperado 0)"
echo "  constantes soltas: $(grep -oE "1'b[01]" "$B/netlist_yosys.v" | wc -l) (esperado 0)"
echo "  spare_wen0 ligado: $(grep -c '\.spare_wen0' "$B/netlist_yosys.v") (esperado 2)"

#-----------------------------------------------------------------------------
# Simulacao de portas: mesma ordem e mesmos defines do bloco 2 do run_first
#-----------------------------------------------------------------------------
echo "=== Simulacao de portas (FUNCTIONAL, UNIT_DELAY=#1) ==="
iverilog -g2005 -DFUNCTIONAL -DUNIT_DELAY=#1 -o "$B/gls.vvp" \
  "$T/verilog/primitives.v" "$T/verilog/sky130_fd_sc_hd.v" "$SCR/restore_nettype.v" \
  "$B/netlist_yosys.v" $MODELOS "$SCR/tb_gate.v" 2> "$B/gls.compile.log" \
  || { grep -v timescale "$B/gls.compile.log" | head; exit 1; }
t0=$SECONDS
vvp -n "$B/gls.vvp" $ARGS | grep --line-buffered -E "^\[" | tee "$B/gls.log"
echo "(tempo real: $((SECONDS - t0)) s)"
grep -q "\[TB\] PASSOU" "$B/gls.log"
