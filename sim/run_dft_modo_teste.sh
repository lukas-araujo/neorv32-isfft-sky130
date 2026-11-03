#!/usr/bin/env bash
#=============================================================================
# run_dft_modo_teste.sh -- o IP em MODO DE TESTE, no Icarus (DIARIO_DFT, T13)
#
# 1. sim/dft/mapa_cadeias.py segue as cadeias do netlist e escreve o
#    mapa_cadeias.vh (cadeia/posicao de cada bit; pino da falha injetada)
# 2. simula o vm/backend/dft_isfft/tb/tb_isfft_modo_teste.v (testes A a E)
#
# Uso:
#   bash sim/run_dft_modo_teste.sh                       # netlist do Genus que
#        veio da VM (o mais novo em resultados/*_dft_*/deliverables/
#        isfft_dft_flat.v[.gz]); o mapa vai para vm/backend/dft_isfft/tb/
#        (e e ESSE que a VM usa no bloco 5)
#   NETLIST=sim/build_dft/isfft_scan.v bash sim/run_dft_modo_teste.sh
#        # netlist de conferencia (sim/run_dft_aberto.sh); mapa so em build
# Precisa: iverilog >= 12, python3. ~4 min.
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/sim/build_dft"; mkdir -p "$B"
T="$PROJ/tech/sky130"
TB="$PROJ/vm/backend/dft_isfft/tb"

if [ -n "${NETLIST:-}" ]; then
  NL="$NETLIST"; DEF="-DSCAN_BARRAMENTO"; MAPA="$B/mapa_cadeias.vh"
else
  G=$(ls -t "$PROJ"/resultados/*_dft_*/deliverables/isfft_dft_flat.v* 2>/dev/null | head -1)
  [ -n "$G" ] || { echo "Sem netlist do Genus em resultados/*_dft_*/ (rode sim/traz_dft.sh)"; exit 1; }
  case "$G" in *.gz) zcat "$G" > "$B/isfft_dft_flat.v"; NL="$B/isfft_dft_flat.v";; *) NL="$G";; esac
  DEF=""; MAPA="$TB/mapa_cadeias.vh"
  echo "netlist do Genus: ${G#$PROJ/}"
fi

echo "=== 1. Mapa das cadeias ==="
python3 "$PROJ/sim/dft/mapa_cadeias.py" "$NL" isfft_axi_v4 "$MAPA" "$B/mapa_cadeias.txt" \
  | sed 's/^/  /' || exit 1
cp "$MAPA" "$B/mapa_cadeias.vh" 2>/dev/null

echo "=== 2. Modo de teste (Icarus) ==="
iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 $DEF -I "$B" -o "$B/modo_teste.vvp" -s tb_isfft_modo_teste \
  "$T/verilog/primitives.v" "$T/verilog/sky130_fd_sc_hd.v" \
  "$PROJ/vm/backend/synthesis/scripts/restore_nettype.v" "$NL" \
  "$PROJ/macros/sram_1rw1r_64x64_wpr2/sram_1rw1r_64x64_wpr2.v" \
  "$PROJ/macros/sram_1rw1r_64x256/sram_1rw1r_64x256.v" \
  "$TB/tb_isfft_modo_teste.v" 2> "$B/modo_teste.compile.log" \
  || { grep -v timescale "$B/modo_teste.compile.log" | head; exit 1; }
t0=$SECONDS
vvp -n "$B/modo_teste.vvp" | grep --line-buffered "^\[MT\]" | tee "$B/modo_teste.log"
echo "($((SECONDS - t0)) s)"
grep -q "RESULTADO: TUDO OK" "$B/modo_teste.log"
