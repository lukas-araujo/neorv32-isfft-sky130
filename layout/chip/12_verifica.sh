#!/usr/bin/env bash
#=============================================================================
# 12_verifica.sh -- ETAPA 12: DRC e LVS do chip
#
#   Continua da rodada da etapa 11 que terminou com "Flow complete."
#   (layout/chip/.rodada_atual, ou a rodada passada como 1o argumento), numa
#   rodada NOVA (runs/<data>_12), com --with-initial-state no estado do
#   passo anterior ao Magic.DRC. Roda de Magic.DRC ate o fim do fluxo:
#
#     Magic.DRC + Checker.MagicDRC  no GDS do Magic (MAGIC_DRC_USE_GDS),
#                                   com o NUCLEO como caixa-preta pela vista
#                                   abstrata (maglef) -- o miolo ja passou na
#                                   etapa 8 (L42, L78). Os pads e as fatias
#                                   do anel entram com o GDS REAL.
#     Magic.SpiceExtraction         netlist SPICE do layout, pelo DEF + LEF
#                                   (abstrato): pads, fatias e nucleo viram
#                                   caixas-pretas com os pinos do LEF (L79)
#     Checker.IllegalOverlap        as 24 de sempre (L77, so aviso)
#     Netgen.LVS + Checker.LVS      layout x netlist do Verilog (chip_top)
#     Checker.Setup/Hold/Slew/Cap, Misc.ReportManufacturability
#
#   ERROR_ON_MAGIC_DRC e ERROR_ON_LVS_ERROR = false em config_verifica.json:
#   a 1a rodada e para LER os erros (classificados por regiao do chip pelo
#   resume_verifica.py), nao para parar no 1o.
#
#   Resultado: resultados/<data>_12_layout_chip/ (12_drc.txt, 12_lvs.txt,
#   relatorios completos .gz, netlists extraida e do Verilog .gz, logs).
#
# Uso (no nix-shell do LibreLane):
#   bash layout/chip/12_verifica.sh [rodada_da_etapa_11]
#=============================================================================
source "$(dirname "$0")/../nucleo/comum.sh"     # confere_ambiente, resume_drc_magic
confere_ambiente
CHIP="$REPO/layout/chip"
ENT="$CHIP/entrada"

#-----------------------------------------------------------------------------
# 1. De onde continuar: a rodada da etapa 11 e o passo antes do Magic.DRC
#-----------------------------------------------------------------------------
TAG11="${1:-$(cat "$CHIP/.rodada_atual" 2>/dev/null || true)}"
RUN11="$CHIP/runs/$TAG11"
[ -n "$TAG11" ] && [ -d "$RUN11" ] || { echo "ERRO: rodada da etapa 11 nao encontrada ($RUN11)"; exit 1; }
grep -q "Flow complete" "$RUN11/flow.log" 2>/dev/null \
  || echo "AVISO: $TAG11 nao termina em 'Flow complete.' (continuo mesmo assim)"
ini=""
for p in checker-klayoutdensity klayout-density checker-klayoutantenna klayout-antenna checker-xor klayout-xor; do
  d="$(ls -d "$RUN11"/[0-9]*-"$p" 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$d" ] && [ -f "$d/state_out.json" ]; then ini="$d/state_out.json"; break; fi
done
[ -n "$ini" ] || { echo "ERRO: nenhum passo antes do Magic.DRC com state_out.json em $RUN11"; exit 1; }
echo ">>> continua de: ${ini#$CHIP/}"
python3 - "$ini" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
for k in ("gds", "def", "pnl", "spef"):
    v = s.get(k)
    print(f"    {k:5s} {v if not isinstance(v, dict) else '(por corner)'}")
PY

#-----------------------------------------------------------------------------
# 2. Vista abstrata do nucleo para o DRC (L42/L78): maglef a partir do LEF
#    que o chip usou (entrada/asic_top.lef, copiado pelo 11_anel.sh)
#-----------------------------------------------------------------------------
command -v magic >/dev/null || { echo "ERRO: magic fora do PATH"; exit 1; }
rc="$(find -L "$PDK_ROOT" -name sky130A.magicrc -path '*8afc8346*' 2>/dev/null | head -1 || true)"
[ -n "$rc" ] || { echo "ERRO: nao achei sky130A.magicrc da versao 8afc8346 em $PDK_ROOT (L75)"; exit 1; }
[ -f "$ENT/asic_top.lef" ] || { echo "ERRO: falta $ENT/asic_top.lef (rode o 11_anel.sh)"; exit 1; }
ml="$ENT/maglef"
mkdir -p "$ml"
rm -f "$ml"/*.mag "$ml"/*.lef
# O Magic.WriteLEF poe na OBS do nucleo um retangulo de NWELL (39,83..1959,79 x
# 40,715..1458,11 um); no maglef ele vira nwell de verdade, sem tap -> 37 caixas
# de nwell.4 (rodada 1717_12). O abstrato nao precisa de nwell: tira (L82).
python3 - "$ENT/asic_top.lef" "$ml/asic_top_sem_nwell.lef" <<'PY'
import sys
saida, pula, tirados = [], False, 0
for l in open(sys.argv[1]):
    t = l.split()
    if t[:1] == ["LAYER"]:
        pula = len(t) > 1 and t[1] == "nwell"
        if pula:
            continue
    elif t[:1] in (["END"], ["PIN"], ["OBS"]):
        pula = False
    if pula:
        tirados += 1
        continue
    saida.append(l)
open(sys.argv[2], "w").writelines(saida)
print(f"    LEF do nucleo sem nwell: {tirados} retangulo(s) de nwell tirado(s)")
PY
printf 'lef read %s\nload asic_top\nsave %s/asic_top.mag\nquit -noprompt\n' "$ml/asic_top_sem_nwell.lef" "$ml" > "$ml/gera.tcl"
( cd "$ml" && magic -dnull -noconsole -rcfile "$rc" "$ml/gera.tcl" > "$ml/gera.log" 2>&1 ) || true
[ -f "$ml/asic_top.mag" ] || { echo "ERRO: maglef do nucleo nao saiu (veja $ml/gera.log)"; exit 1; }
echo ">>> maglef do nucleo: ${ml#$REPO/}/asic_top.mag ($(grep -c '^rect' "$ml/asic_top.mag") retangulos)"

#-----------------------------------------------------------------------------
# 3. LibreLane: de Magic.DRC ate o fim, rodada nova
#-----------------------------------------------------------------------------
TAG="$(date +%Y-%m-%d_%H%M)_12"
echo "$TAG" > "$CHIP/.rodada_12"
r=0
( cd "$CHIP" && librelane --pdk-root "$PDK_ROOT" --run-tag "$TAG" \
    --with-initial-state "$ini" --from Magic.DRC --to Misc.ReportManufacturability \
    config.json config_verifica.json ) || r=$?
echo ">>> librelane terminou com codigo $r"

#-----------------------------------------------------------------------------
# 4. Resultados
#-----------------------------------------------------------------------------
RUN="$CHIP/runs/$TAG"
DEST="$REPO/resultados/${TAG}_layout_chip"
mkdir -p "$DEST"
passo () { ls -d "$RUN"/[0-9]*-"$1" 2>/dev/null | sort -V | tail -1 || true; }

ultimo="$(ls -d "$RUN"/[0-9]*/ 2>/dev/null | while read -r d; do
           [ -f "$d/state_out.json" ] && echo "$d"; done | sort -V | tail -1 || true)"
if [ -n "$ultimo" ]; then
  python3 - "$ultimo/state_out.json" "$DEST/12_metricas.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("metrics", {})
json.dump(m, open(sys.argv[2], "w"), indent=1, sort_keys=True)
for k in sorted(m):
    if any(s in k for s in ("drc_error", "lvs_", "illegal_overlap", "xor_difference")):
        print(f"  {k:44s} {m[k]}")
PY
fi

d="$(passo magic-drc)"
if [ -n "$d" ] && [ -f "$d/reports/drc.magic.rpt" ]; then
  { echo "== Magic.DRC ($(basename "$d")), tempo: $(cat "$d/runtime.txt" 2>/dev/null || echo '?')"
    python3 "$CHIP/resume_verifica.py" drc "$d/reports/drc.magic.rpt"
    echo
    echo "== Linhas de leitura do GDS que o LibreLane trata como fatais (MAGIC_CAPTURE_ERRORS)"
    grep -h "Error while reading cell" "$d"/*.log 2>/dev/null | grep -v "Warning:" \
      | sed 's/(byte position [0-9]*)//' | sort | uniq -c | sort -rn | head -20 || true
  } > "$DEST/12_drc.txt" 2>&1
  gzip -c "$d/reports/drc.magic.rpt" > "$DEST/12_drc_magic.rpt.gz"
  echo ">>> DRC:"; sed 's/^/    /' "$DEST/12_drc.txt" | head -40 || true
else
  echo ">>> Magic.DRC nao gerou relatorio"
fi

d="$(passo netgen-lvs)"
if [ -n "$d" ] && [ -f "$d/reports/lvs.netgen.rpt" ]; then
  python3 "$CHIP/resume_verifica.py" lvs "$d/reports/lvs.netgen.rpt" > "$DEST/12_lvs.txt" 2>&1
  gzip -c "$d/reports/lvs.netgen.rpt" > "$DEST/12_lvs_netgen.rpt.gz"
  echo ">>> LVS:"; sed 's/^/    /' "$DEST/12_lvs.txt" | head -40 || true
else
  echo ">>> Netgen.LVS nao gerou relatorio"
fi
# as duas netlists que o LVS compara (pequenas no chip: ~4 mil instancias)
d="$(passo magic-spiceextraction)"
[ -n "$d" ] && ls "$d"/*.spice >/dev/null 2>&1 && gzip -c "$(ls "$d"/*.spice | head -1)" > "$DEST/12_extraida.spice.gz"
# ligacao de topo, sem nomes (L89): netlist extraida x Verilog do chip
pnl="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('pnl') or '')" "$ini")"
if [ -f "$DEST/12_extraida.spice.gz" ] && [ -f "$pnl" ]; then
  python3 "$CHIP/compara_ligacao.py" "$DEST/12_extraida.spice.gz" "$pnl" > "$DEST/12_ligacao.txt" 2>&1 || true
  echo ">>> ligacao de topo:"; tail -4 "$DEST/12_ligacao.txt" | sed 's/^/    /'
fi
pnl="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('pnl') or '')" "$ini")"
[ -n "$pnl" ] && [ -f "$pnl" ] && gzip -c "$pnl" > "$DEST/12_chip_top.pnl.v.gz"

( cd "$CHIP/runs" && find "$TAG" -type f \
    \( -name '*.log' -o -name '*.rpt' -o -name '*.txt' -o -name '*.json' \
       -o -name '*.tcl' -o -name '*.lvs' \) -size -20M -print0 \
  | tar czf "$DEST/logs_12.tar.gz" --null -T - )
cp -f "$ml/gera.log" "$DEST/12_maglef_gera.log" 2>/dev/null || true

echo
echo "Resultados: ${DEST#$REPO/}"
ls -1 "$DEST" | sed 's/^/    /'
echo
echo "Para mandar pelo git:"
echo "  git add resultados/${TAG}_layout_chip"
echo "  git commit -m 'gdsii: etapa 12, DRC e LVS do chip'"
echo "  git pull --rebase origin main && git push"
exit "$r"
