#!/usr/bin/env bash
#=============================================================================
# run_uvm_verilator.sh -- roda o ambiente UVM do IP da ISFFT no Verilator
#                         (sem Cadence), antes de ir para a VM
#
# Conferencia aberta, como o run_gls_yosys.sh fez com a sintese. Usa o
# MESMO isfft_uvm.f e o MESMO gera_dut_f.sh do run_first_uvm.tcl.
#
# Pasta do projeto que ele simula (PROJECT_DIR):
#   - padrao: um espelho minimo da pasta da VM em build/uvm_verilator/vm,
#     montado aqui com a mesma regra do sim/monta_vm.sh (frontend/ = rtl/,
#     tech/verilog/ = macros/, verification/ = vm/verification/). Nao
#     precisa do GHDL: o UVM so usa a ISFFT.
#   - PASTA_VM=<pasta>: uma pasta da VM ja montada (sim/monta_vm.sh) ou
#     copiada da VM.
#
#   Verilator >= 5.052 (primeira versao com UVM 2020-3.2) + z3 (randomize)
#   UVM_SRC: pasta com uvm_pkg_all_v2020_3_2_dpi.svh e v2020_3_2/dpi (vem no
#            test_regress/t/uvm do proprio Verilator)
#
# Uso:
#   UVM_SRC=<pasta> bash sim/run_uvm_verilator.sh [teste ...]
#   sem teste: roda a regressao inteira
#   SEMENTE=<n>  semente (padrao 1)       ONDA=1  grava VCD
#   MUTA=<arquivo.v>  compila com este arquivo no lugar do arquivo do DUT
#                     de mesmo nome (isfft_axi_v4.v ou um do nucleo)
#   EXTRA="+N_MAT=400 +SEM_CHECA_NUM"   plusargs a mais para o teste
#   SO_RODA=1  nao recompila (usa o binario da rodada anterior)
#   JOBS=1     compila com 1 processo (maquina com pouca memoria: o C++
#              do UVM passa de 2,5 GB por arquivo)
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
UVM_SRC="${UVM_SRC:-}"
[ -f "$UVM_SRC/uvm_pkg_all_v2020_3_2_dpi.svh" ] || { echo "UVM_SRC sem uvm_pkg_all_v2020_3_2_dpi.svh"; exit 1; }
command -v verilator >/dev/null || { echo "verilator fora do PATH"; exit 1; }

TESTES="${*:-isfft_fumaca_test isfft_registradores_test isfft_kria_test isfft_aleatorio_test isfft_truncado_test isfft_contrapressao_test isfft_soft_reset_test isfft_kria_regressao_test}"
B="${BUILD:-$PROJ/build/uvm_verilator}"
mkdir -p "$B"

#-----------------------------------------------------------------------------
# PROJECT_DIR: pasta da VM ou espelho minimo
#-----------------------------------------------------------------------------
if [ -n "${PASTA_VM:-}" ]; then
  P="$(cd "$PASTA_VM" && pwd)" || exit 1
else
  P="$B/vm"
  rm -rf "$P"
  mkdir -p "$P/frontend/isfft" "$P/tech/verilog"
  cp "$PROJ/rtl/isfft/isfft_axi_v4.v" "$P/frontend/"
  for f in "$PROJ"/rtl/isfft/core/*.v; do
    [ "$(basename "$f")" = isfft_axi_v3.v ] || cp "$f" "$P/frontend/isfft/"   # regra do monta_vm.sh
  done
  for m in sram_1rw1r_64x64_wpr2 sram_1rw1r_64x256; do cp "$PROJ/macros/$m/$m.v" "$P/tech/verilog/"; done
  cp -r "$PROJ/vm/verification" "$P/"
fi
export PROJECT_DIR="$P" UVM_DIR="$P/verification/uvm_isfft" UVM_WORK="$B"
mkdir -p "$UVM_DIR/reports"

# A referencia na pasta do UVM e copia do wrapper da etapa 1
cmp -s "$UVM_DIR/ref/isfft_axi_wrapper.v" "$PROJ/rtl/isfft/ref/isfft_axi_wrapper.v" \
  || echo "AVISO: ref/isfft_axi_wrapper.v difere de rtl/isfft/ref/isfft_axi_wrapper.v"

bash "$UVM_DIR/scripts/gera_dut_f.sh" "$PROJECT_DIR" "$UVM_DIR" "$B/isfft_dut.f" || exit 1
if [ -n "${MUTA:-}" ]; then
  # troca o arquivo do DUT que tem o mesmo nome (wrapper ou nucleo)
  sed -i "s|^.*/$(basename "$MUTA")$|$MUTA|" "$B/isfft_dut.f"
  grep -q "^$MUTA$" "$B/isfft_dut.f" || { echo "MUTA: troca falhou"; exit 1; }
fi
# O Verilator nao expande variaveis dentro do .f: expande aqui
sed -e "s|\${UVM_DIR}|$UVM_DIR|g" -e "s|\${UVM_WORK}|$UVM_WORK|g" \
    "$UVM_DIR/scripts/isfft_uvm.f" > "$B/uvm.f"
mkdir -p "$B/shim"
echo '// macros do UVM ja definidas no uvm_pkg_all (arquivo de apoio)' > "$B/shim/uvm_macros.svh"

if [ -z "${SO_RODA:-}" ]; then
echo "=== Compilando (Verilator $(verilator --version | cut -d' ' -f2)) ==="
t0=$(date +%s)
verilator --binary --timing --assert --vpi -j "${JOBS:-$(nproc)}" \
  -Wno-fatal -Wno-lint -Wno-style -Wno-SYMRSVDWORD -Wno-MULTITOP \
  --error-limit 200 \
  --top-module isfft_tb_top -timescale 1ns/1ps \
  -CFLAGS -O1 \
  --Mdir "$B/obj" \
  +incdir+"$B/shim" +incdir+"$UVM_SRC" \
  "$UVM_SRC/uvm_pkg_all_v2020_3_2_dpi.svh" \
  -f "$B/uvm.f" \
  "$UVM_SRC/v2020_3_2/dpi/uvm_dpi.cc" \
  -o Vtb > "$B/compila.log" 2>&1
r=$?
echo "  $(( $(date +%s) - t0 )) s  (log: $B/compila.log)"
if [ $r -ne 0 ]; then grep -E "%Error" "$B/compila.log" | head -30; exit 2; fi
fi

FALHOU=0
for t in $TESTES; do
  s="${SEMENTE:-1}"
  t0=$(date +%s)
  L="$UVM_DIR/reports/${t}_verilator.log"
  ( cd "$B" && "$B/obj/Vtb" +UVM_TESTNAME=$t +verilator+seed+$s +UVM_NO_RELNOTES \
     ${ONDA:+ +ONDA} ${VERB:+ +UVM_VERBOSITY=$VERB} ${EXTRA:-} ) > "$L" 2>&1
  if grep -q "TESTE PASSOU" "$L"; then res="PASSOU"; else res="FALHOU"; FALHOU=1; fi
  printf "  %-28s %s  (%3d s)\n" "$t" "$res" "$(( $(date +%s) - t0 ))"
  grep -E "SB_RESUMO|COBERTURA|KRIA\]|UVM_ERROR .*@|UVM_FATAL .*@|%Error|Assertion failed" "$L" | head -${LINHAS:-12} | sed 's/^/      /'
done
echo "Logs: $UVM_DIR/reports/"
[ $FALHOU -eq 0 ] && echo "=== RESULTADO: TUDO OK ===" || echo "=== RESULTADO: HA FALHAS ==="
exit $FALHOU
