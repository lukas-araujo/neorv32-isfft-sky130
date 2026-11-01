#!/usr/bin/env bash
#=============================================================================
# run_dft_aberto.sh -- conferencia ABERTA da frente de DFT (antes da VM)
#
# DIARIO_DFT, 1a sessao. Com Yosys + Icarus, no notebook ou na nuvem:
#   1. sintese do IP da ISFFT (isfft_axi_v4) nas celulas sky130, SEM scan
#      (mesmas celulas evitadas do chip) -> conta os flip-flops por tipo
#   2. regressao da Kria no netlist SEM scan (base: o netlist esta certo)
#   3. scan "de mentira" (sim/dft/dft_costura.py): dfxtp -> sdfxtp,
#      edfxtp -> sedfxtp, N cadeias
#   4. regressao da Kria no netlist COM scan, scan_en = 0 (o circuito e o
#      mesmo)
#   5. flush das N cadeias (sim/dft/tb_dft_flush.v)
#   6. mutacao: SCE = 0 num flip-flop da cadeia 0 -> o flush TEM de
#      reprovar so a cadeia 0
#   7. biblioteca do Modus: sky130_fd_sc_hd.v pre-processado com FUNCTIONAL
#      -> vm/backend/dft_isfft/modus/sky130_fd_sc_hd_atpg.v.gz
#
# O netlist com scan de verdade e o do Genus (VM). Este script so prova o
# que o Genus vai assumir: as celulas de scan do sky130 deslocam, e o
# circuito com scan_en = 0 e o mesmo.
#
# Uso: bash sim/run_dft_aberto.sh            (CADEIAS=16 por padrao)
#      SO_LIB=1 bash sim/run_dft_aberto.sh   (so o passo 7)
#      SO_CADEIAS=1 bash sim/run_dft_aberto.sh  (pula as regressoes 2 e 4, ~5 min cada)
# Precisa: yosys ou yowasp-yosys, iverilog (>= 12), python3
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/sim/build_dft"
N="${CADEIAS:-16}"
T="$PROJ/tech/sky130"
LIB="$T/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
CORE="$(ls "$PROJ"/rtl/isfft/core/*.v | grep -v isfft_axi_v3 | tr '\n' ' ')"
MACROS="$PROJ/macros/sram_1rw1r_64x64_wpr2/sram_1rw1r_64x64_wpr2.v $PROJ/macros/sram_1rw1r_64x256/sram_1rw1r_64x256.v"
CELULAS="$T/verilog/primitives.v $T/verilog/sky130_fd_sc_hd.v $PROJ/vm/backend/synthesis/scripts/restore_nettype.v"
MODUS="$PROJ/vm/backend/dft_isfft/modus"
mkdir -p "$B" "$MODUS"

#-----------------------------------------------------------------------------
# 7. Biblioteca para o Modus (rapido; roda sempre)
#
# O sky130_fd_sc_hd.v tem dois modelos por celula; o comportamental (padrao)
# depende de fios *_delayed que so um bloco 'specify' acionaria -- e o
# arquivo nao tem 'specify' (doc/specify_sky130.md). Na simulacao isso se
# resolve com -define FUNCTIONAL; para o Modus (que le a biblioteca como
# modelo estrutural), o arquivo vai ja resolvido: iverilog -E com
# FUNCTIONAL e UNIT_DELAY vazio (ATPG nao usa atraso).
#-----------------------------------------------------------------------------
echo "=== 7. Biblioteca do Modus ==="
iverilog -E -DFUNCTIONAL -DUNIT_DELAY= -o "$B/sky130_fd_sc_hd_atpg.v" \
  "$T/verilog/primitives.v" "$T/verilog/sky130_fd_sc_hd.v" || exit 1
n_mod=$(grep -c "^module" "$B/sky130_fd_sc_hd_atpg.v")
n_udp=$(grep -c "^primitive" "$B/sky130_fd_sc_hd_atpg.v")
n_ruim=$(grep -vE "^\s*//|^\s*\*" "$B/sky130_fd_sc_hd_atpg.v" | grep -cE "_delayed|specify|notifier|\`ifdef")
echo "  modulos: $n_mod  UDPs: $n_udp  restos do modelo comportamental: $n_ruim (esperado 0)"
[ "$n_ruim" -eq 0 ] || exit 1
{
  echo "// sky130_fd_sc_hd_atpg.v -- GERADO por sim/run_dft_aberto.sh (passo 7). NAO EDITE."
  echo "// primitives.v + sky130_fd_sc_hd.v (tech/sky130/, open_pdks) pre-processados com"
  echo "// iverilog -E -DFUNCTIONAL -DUNIT_DELAY= : so o modelo funcional de cada celula."
  echo "// Licenca dos arquivos de origem: Apache-2.0 (SkyWater PDK). DIARIO_DFT, T7."
  cat "$B/sky130_fd_sc_hd_atpg.v"
} | gzip -9n > "$MODUS/sky130_fd_sc_hd_atpg.v.gz"
echo "  -> vm/backend/dft_isfft/modus/sky130_fd_sc_hd_atpg.v.gz ($(du -h "$MODUS/sky130_fd_sc_hd_atpg.v.gz" | cut -f1))"
[ -n "${SO_LIB:-}" ] && exit 0

YOSYS="$(command -v yosys || command -v yowasp-yosys || true)"
[ -n "$YOSYS" ] || { echo "ERRO: yosys/yowasp-yosys fora do PATH"; exit 1; }
command -v iverilog >/dev/null || { echo "ERRO: iverilog fora do PATH"; exit 1; }

#-----------------------------------------------------------------------------
# 1. Sintese do IP com Yosys (sem scan)
#-----------------------------------------------------------------------------
echo "=== 1. Sintese do IP (Yosys, sem scan) ==="
EVITA="-dont_use *__sdf* -dont_use *__sedf* -dont_use *__sdlclkp* -dont_use *__lpflow_* -dont_use *__probe* -dont_use *__macro_sparecell*"
cat > "$B/synth.ys" <<EOF
read_liberty -lib $LIB
read_liberty -lib $PROJ/macros/sram_1rw1r_64x256/sram_1rw1r_64x256_TT_1p8V_25C.lib
read_liberty -lib $PROJ/macros/sram_1rw1r_64x64_wpr2/sram_1rw1r_64x64_wpr2_TT_1p8V_25C.lib
read_verilog $PROJ/rtl/isfft/isfft_axi_v4.v $CORE
synth -top isfft_axi_v4 -flatten
dfflibmap -liberty $LIB $EVITA
abc -liberty $LIB $EVITA
opt_clean
stat -liberty $LIB
write_verilog -noattr $B/isfft_yosys.v
EOF
t0=$SECONDS
( cd "$B" && "$YOSYS" -q -l yosys.log synth.ys > yosys.out 2>&1 ) || { tail -20 "$B/yosys.out"; exit 1; }
echo "  ($((SECONDS - t0)) s) flip-flops por tipo:"
grep -oE "sky130_fd_sc_hd__\w*df\w+" "$B/isfft_yosys.v" | sort | uniq -c | sed 's/^/   /'
echo "  macros: $(grep -cE '^\s*sram_1rw1r\S* ' "$B/isfft_yosys.v") (esperado 2)"

#-----------------------------------------------------------------------------
# Regressao da Kria (tb_isfft_axi_v3.v, o mesmo do run_tb_isfft_ref.sh) no
# netlist. $1 = nome, $2 = netlist, $3 = portas de scan no DUT (ou vazio)
#-----------------------------------------------------------------------------
kria () {
  sed -e "s/^\(\s*\)isfft_axi_v3 dut (/\1isfft_axi_v4 dut ($3/" \
      -e 's/^endmodule/    defparam dut.u_in_mem.VERBOSE = 0;\n    defparam dut.u_out_mem.VERBOSE = 0;\nendmodule/' \
      "$PROJ/tb/ref/tb_isfft_axi_v3.v" > "$B/tb_$1.v"
  grep -q "isfft_axi_v4 dut" "$B/tb_$1.v" || { echo "ERRO: sed do tb"; return 2; }
  iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -o "$B/$1.vvp" -s tb_isfft_axi_v3 \
    $CELULAS "$2" $MACROS $CORE "$PROJ/rtl/isfft/ref/isfft_axi_wrapper.v" "$B/tb_$1.v" \
    2> "$B/$1.compile.log" || { grep -v timescale "$B/$1.compile.log" | head; return 2; }
  local t0=$SECONDS
  timeout "${LIMITE:-3600}" vvp -n "$B/$1.vvp" > "$B/$1.log"
  echo "  ($((SECONDS - t0)) s)"
  grep -E "^(Fase|PASSOU|FALHOU|ERRO)" "$B/$1.log" | head -8 | sed 's/^/    /'
  grep -q "^PASSOU" "$B/$1.log"
}
# O nucleo ($CORE) entra so por causa do wrapper da etapa 1 (referencia), que
# instancia top_isfft; o DUT e o netlist (modulo isfft_axi_v4 achatado).

FALHOU=0
echo "=== 2. Regressao da Kria: netlist SEM scan ==="
if [ -n "${SO_CADEIAS:-}" ]; then echo "  (pulada: SO_CADEIAS)"; else
kria gls_sem_scan "$B/isfft_yosys.v" "" || { echo "  FALHOU -- o resto nao e avaliado"; exit 1; }
fi

#-----------------------------------------------------------------------------
# 3. Scan de mentira
#-----------------------------------------------------------------------------
echo "=== 3. Costura das cadeias ($N) ==="
python3 "$PROJ/sim/dft/dft_costura.py" "$B/isfft_yosys.v" isfft_axi_v4 "$B/isfft_scan.v" "$N" \
  | tee "$B/costura.txt" | sed 's/^/  /' || exit 1
python3 "$PROJ/sim/dft/dft_costura.py" "$B/isfft_yosys.v" isfft_axi_v4 "$B/isfft_scan_mut.v" "$N" --mutacao \
  > "$B/costura_mut.txt" || exit 1
{
  read -r _ n resto < <(grep "^CADEIAS" "$B/costura.txt")
  echo "localparam integer NCAD = $n;"
  echo "function integer L(input integer c);"
  echo "  case (c)"
  i=0; for l in $resto; do echo "    $i: L = $l;"; i=$((i+1)); done
  echo "    default: L = 0;"
  echo "  endcase"
  echo "endfunction"
} > "$B/cadeias.vh"

echo "=== 4. Regressao da Kria: netlist COM scan, scan_en = 0 ==="
if [ -n "${SO_CADEIAS:-}" ]; then echo "  (pulada: SO_CADEIAS)"; else
kria gls_scan "$B/isfft_scan.v" ".scan_en(1'b0), .scan_in({$N{1'b0}}), .scan_out()," || FALHOU=1
fi

flush () {  # nome netlist
  iverilog -g2012 -DFUNCTIONAL -DUNIT_DELAY=#1 -I "$B" -o "$B/$1.vvp" -s tb_dft_flush \
    $CELULAS "$2" $MACROS "$PROJ/sim/dft/tb_dft_flush.v" 2> "$B/$1.compile.log" \
    || { grep -v timescale "$B/$1.compile.log" | head; return 2; }
  vvp -n "$B/$1.vvp" > "$B/$1.log"
  grep -q "^\[FLUSH\] PASSOU" "$B/$1.log"
}
echo "=== 5. Flush das cadeias ==="
if flush flush "$B/isfft_scan.v"; then
  echo "  $(grep -cE -- '-> +ok' "$B/flush.log") de $N cadeias ok ($(grep -m1 -oE 'L = [0-9]+' "$B/flush.log") ...)"
  grep "acessos" "$B/flush.log" | sed 's/^\[FLUSH\] /  /'
else
  FALHOU=1; grep "^\[FLUSH\]" "$B/flush.log" | sed 's/^/  /'
fi

echo "=== 6. Mutacao: $(grep MUTACAO "$B/costura_mut.txt" | cut -d' ' -f2-) ==="
if [ $FALHOU -ne 0 ]; then
  echo "  versao correta falhou: mutacao nao e avaliada"
elif flush flush_mut "$B/isfft_scan_mut.v"; then
  echo "  NAO DETECTADA -- o flush nao enxerga cadeia quebrada"; FALHOU=1
else
  ruins=$(grep -E "^\[FLUSH\] cadeia [0-9]+ \(L" "$B/flush_mut.log" | grep "ERRO" | sed -E 's/.*cadeia ([0-9]+).*/\1/' | tr '\n' ' ')
  echo "  detectada: cadeias com erro = [ ${ruins}] (esperado: so a 0)"
  grep -m2 "ciclo" "$B/flush_mut.log" | sed 's/^/    /'
  [ "$ruins" = "0 " ] || FALHOU=1
fi

echo
[ $FALHOU -eq 0 ] && echo "=== RESULTADO: TUDO OK ===" || echo "=== RESULTADO: FALHOU ==="
exit $FALHOU
