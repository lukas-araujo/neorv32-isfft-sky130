#!/usr/bin/env bash
#=============================================================================
# 08_drc_gds.sh -- ETAPA 8, DRC de novo: no GDS, com as macros como caixa-preta
#
# Na 28a sessao o Magic.DRC rodou sobre o DEF + LEF (MAGIC_DRC_USE_GDS
# false). Nesse modo as celulas padrao entram como ABSTRATO (LEF): tem
# nwell (pino VPB) mas nao tem a difusao do tap -> 1.052 erros nwell.4
# ("nwell sem tap N+") em todas as linhas. Alarme falso do abstrato.
#
# Aqui (L42):
#   1. gera a vista abstrata (.mag "maglef") das 4 macros a partir do LEF
#      (layout/nucleo/maglef/, fora do git)
#   2. MAGIC_DRC_USE_GDS = true + MAGIC_DRC_MAGLEFS = essas 4 vistas: o
#      Magic le o GDS do chip (celulas padrao REAIS, com os taps) e as
#      macros continuam caixa-preta (L3) -- o drc.tcl do LibreLane carrega
#      as maglef antes e o "gds noduplicates" ignora o miolo da OpenRAM
#   3. roda so Magic.DRC + Checker.MagicDRC, a partir do Checker.XOR
#
# O que se espera: nwell.4 some; sobram os 130 de area minima nos pinos de
# saida sem uso das macros (dout0 das 1rw1r e o bit 33 das 1rw), que sao
# quadradinhos do LEF (L43).
#
# Uso:  bash layout/nucleo/08_drc_gds.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente
command -v magic >/dev/null || { echo "ERRO: magic fora do PATH (nix-shell do LibreLane)"; exit 1; }

#--- 1. maglef das macros ----------------------------------------------------
RC="$(find -L "$PDK_ROOT" -name sky130A.magicrc -path '*8afc8346*' 2>/dev/null | head -1 || true)"
[ -n "$RC" ] || RC="$(find -L "$PDK_ROOT" -name sky130A.magicrc 2>/dev/null | head -1 || true)"
[ -n "$RC" ] || { echo "ERRO: nao achei sky130A.magicrc em $PDK_ROOT"; exit 1; }
ML="$NUCLEO/maglef"
mkdir -p "$ML"
tcl="$ML/gera.tcl"
{
  for m in $(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['MACROS']))" "$CONFIG"); do
    echo "lef read $REPO/macros/$m/$m.lef"
    echo "load $m"
    echo "save $ML/$m.mag"
  done
  echo "quit -noprompt"
} > "$tcl"
echo ">>> maglef das macros (Magic, $RC)"
( cd "$ML" && magic -dnull -noconsole -rcfile "$RC" "$tcl" > "$ML/gera.log" 2>&1 ) || true
ls -1 "$ML"/*.mag | sed 's/^/    /'
n="$(ls "$ML"/*.mag 2>/dev/null | wc -l)"
[ "$n" -eq 4 ] || { echo "ERRO: esperava 4 .mag em $ML (veja $ML/gera.log)"; exit 1; }

#--- 2 e 3. DRC no GDS -------------------------------------------------------
grep -q '"MAGIC_DRC_USE_GDS": true' "$CONFIG" && grep -q MAGIC_DRC_MAGLEFS "$CONFIG" \
  || { echo "ERRO: config.json sem MAGIC_DRC_USE_GDS true / MAGIC_DRC_MAGLEFS (git pull?)"; exit 1; }
r=0
roda_trecho Checker.XOR Magic.DRC Checker.MagicDRC || r=$?
echo ">>> librelane terminou com codigo $r (o checker reprovando da != 0)"

s="$(estado_de Magic.DRC)"
[ -n "$s" ] || { echo "ERRO: Magic.DRC nao gravou estado"; exit 1; }
d="$(dirname "$s")"
RES="$(pasta_resultados)"
out="$RES/08_drc_gds.txt"
{
  echo "== Magic.DRC no GDS ($(basename "$d")), tempo: $(cat "$d/runtime.txt" 2>/dev/null || echo '?')"
  python3 - "$s" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["metrics"]
print(f"   magic__drc_error__count  {m.get('magic__drc_error__count')}")
PY
  echo
  echo "== Erros por regra (caixas no relatorio)"
  awk '/^[A-Za-z].*\(.*\)$/{r=$0;next} /um /{c[r]++} END{for(k in c) printf "%6d  %s\n", c[k], k}' \
    "$d/reports/drc.magic.rpt" | sort -rn
  echo
  echo "== Avisos de leitura do GDS (resumo)"
  grep -hoE "Unknown layer/datatype[^,]*|placed on top of itself|Warning: [^\"]{0,60}" "$d"/*.log 2>/dev/null \
    | sort | uniq -c | sort -rn | head -10 || true
} > "$out"
cp "$d/reports/drc.magic.rpt" "$RES/08_drc_gds_magic.rpt"
sed 's/^/    /' "$out"
echo ">>> em ${RES#$REPO/}: 08_drc_gds.txt, 08_drc_gds_magic.rpt"
echo "Depois: bash layout/nucleo/junta_logs.sh e o git add/commit que ele imprime."
