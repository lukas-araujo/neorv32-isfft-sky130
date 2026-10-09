#!/usr/bin/env bash
#=============================================================================
# 07_sta.sh -- ETAPA 7: preenchimento, extracao de parasitas e STA final
#
#   Continua a rodada atual, do fim da etapa 6 (Checker.WireLength):
#     OpenROAD.FillInsertion       celulas de preenchimento (fill/decap) nos
#                                  buracos das linhas
#     Odb.CellFrequencyTables      tabelas de quantas celulas de cada tipo
#     OpenROAD.RCX                 OpenRCX: extrai R e C de cada fio JA
#                                  DESENHADO (SPEF), um arquivo por corner
#                                  de RC (min/nom/max)
#     OpenROAD.STAPostPNR          STA com os parasitas extraidos, nos 9
#                                  corners (TT/SS/FF x RC min/nom/max)
#     OpenROAD.IRDropReport        queda de tensao na rede de alimentacao
#                                  (indicativa: sem pads, L6)
#
#   E aqui que se decide a L27 (hold no FF): o checker de hold reprova em
#   qualquer corner (DIARIO_GDSII, 17a sessao). A tabela por corner sai no
#   07_sta.txt.
#
#   REPARO=1 (24a sessao, L27 + L36): volta ao fim do reparo de antena
#   (OpenROAD.RepairAntennas) e roda de novo, ate o IRDropReport:
#     OpenROAD.ResizerTimingPostGRT  hold nos corners TT e FF (RSZ_CORNERS)
#                                    e setup com margem de 1,5 ns; hold com
#                                    margem 0,02 ns (L39: com 0,1 e 0,05 ns
#                                    o reparo nao converge -- a pior folga
#                                    trava em +0,028 ns -- e enche o chip
#                                    de buffers ate o GRT-0232)
#     OpenROAD.STAMidPNR-3, OpenROAD.DetailedRouting (~5 h) e as checagens
#     da etapa 6; depois a etapa 7 inteira
#   Os arquivos saem com "_reparo" no nome; os da 1a rodada ficam para
#   comparar (antes x depois).
#
# Uso:  bash layout/nucleo/07_sta.sh   (SO_GUI=1 / SEM_GUI=1 como no 02)
#       REPARO=1 bash layout/nucleo/07_sta.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${REPARO:-0}" = 1 ]; then
  ANTES=OpenROAD.RepairAntennas; DE=OpenROAD.ResizerTimingPostGRT; NOME=07_sta_reparo
else
  ANTES=Checker.WireLength;      DE=OpenROAD.FillInsertion;        NOME=07_sta
fi

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho "$ANTES" "$DE" OpenROAD.IRDropReport
  echo ">>> metricas do fim da etapa:"
  guarda_metricas OpenROAD.IRDropReport "$NOME"

  resumo="$(pasta_resultados)/$NOME.txt"
  st="$(estado_de OpenROAD.STAPostPNR)"
  {
    echo "== Timing por corner (OpenROAD.STAPostPNR, parasitas extraidos)"
    python3 - "$st" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["metrics"]
cs = sorted({k.split("corner:")[1] for k in m if "corner:" in k and k.startswith("timing__setup__ws")})
print(f"| Corner | Setup WS (ns) | Viol. setup | Hold WS (ns) | Viol. hold | Transicao | Capacit. |")
print(f"|---|---|---|---|---|---|---|")
for c in cs:
    g = lambda b: m.get(f"{b}__corner:{c}", "-")
    print(f"| {c} | {g('timing__setup__ws')} | {g('timing__setup_vio__count')} | "
          f"{g('timing__hold__ws')} | {g('timing__hold_vio__count')} | "
          f"{g('design__max_slew_violation__count')} | {g('design__max_cap_violation__count')} |")
PY
    echo
    PASSOS="OpenROAD.FillInsertion OpenROAD.RCX OpenROAD.STAPostPNR OpenROAD.IRDropReport"
    [ "${REPARO:-0}" = 1 ] && PASSOS="OpenROAD.ResizerTimingPostGRT OpenROAD.STAMidPNR-3 \
      OpenROAD.DetailedRouting OpenROAD.CheckAntennas-1 Checker.TrDRC \
      Checker.DisconnectedPins $PASSOS"
    for passo in $PASSOS; do
      s="$(estado_de "$passo")"; [ -n "$s" ] || continue
      d="$(dirname "$s")"
      echo "== $passo ($(basename "$d"))"
      grep -hE "RCX-0|DPL-|[Ff]iller|ERROR|WARNING (RCX|PSM|STA-0|RSZ|DRT)|PSM-00(69|70|71|72|73)|[Ww]orst|[Aa]verage|RSZ-00(32|33|39|40|41|59|62)|[Ii]nserted|[Rr]esized|[Nn]umber of violations|ANT-" \
        "$d"/*.log 2>/dev/null | sort | uniq -c | head -20 || true
      [ -f "$d/runtime.txt" ] && echo "   tempo: $(cat "$d/runtime.txt")"
      python3 - "$s" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["metrics"]
for k in sorted(m):
    if any(x in k for x in ("ir__", "power__", "design__instance__count__class:fill",
                            "hold_buffer", "setup_buffer", "route__drc_errors", "route__wirelength",
                            "antenna_violation", "disconnected_pin", "setup__ws", "hold__ws")) \
       and "corner" not in k and "iter:" not in k:
        print(f"   {k:45s} {m[k]}")
PY
      echo
    done
  } > "$resumo"
  echo ">>> resumo (tambem em ${resumo#$REPO/}):"
  sed 's/^/    /' "$resumo"
fi
abre_gui OpenROAD.IRDropReport final "${NOME%_sta*}${NOME#07_sta}_final"

echo
echo "Conferir: setup e hold >= 0 nos corners TT; e ver o hold do FF (L27)."
echo "Depois: bash layout/nucleo/junta_logs.sh e o git add/commit que ele imprime."
