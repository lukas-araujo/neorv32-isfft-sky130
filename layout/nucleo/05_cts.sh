#!/usr/bin/env bash
#=============================================================================
# 05_cts.sh -- ETAPA 5: arvore de relogio (CTS) e reparo de timing
#
#   Continua a rodada atual, do fim da etapa 4 (OpenROAD.DetailedPlacement):
#     OpenROAD.CTS                 TritonCTS: troca o fio unico do clk_i
#                                  (19.829 pinos de relogio: flip-flops e as
#                                  6 entradas de relogio das macros) por uma
#                                  arvore de buffers clkbuf_16/8/4/2
#     OpenROAD.STAMidPNR-1         STA com o relogio PROPAGADO pela arvore
#     OpenROAD.ResizerTimingPostCTS  repair_timing: conserta setup e hold
#                                  (hold com buffers de atraso)
#     OpenROAD.STAMidPNR-2         STA de novo, depois do reparo
#
#   IDs repetidos no fluxo ganham sufixo: o STAMidPNR depois do posiciona-
#   mento e "OpenROAD.STAMidPNR", o depois da CTS "-1", o depois do reparo
#   "-2" (librelane/flows/sequential.py, __normalize_step_ids).
#
#   O STA no meio do fluxo so usa o corner TT (DEFAULT_CORNER); os corners
#   SS e FF so voltam no STA final (etapa 7).
#
#   Imagens: arvore de relogio (visualizador do OpenROAD) + chip com os
#   buffers de relogio destacados.
#
# Uso:  bash layout/nucleo/05_cts.sh   (SO_GUI=1 / SEM_GUI=1 como no 02)
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho OpenROAD.DetailedPlacement OpenROAD.CTS OpenROAD.STAMidPNR-2
  echo ">>> metricas depois da CTS e do reparo:"
  guarda_metricas OpenROAD.STAMidPNR-2 05_cts

  resumo="$(pasta_resultados)/05_cts.txt"
  : > "$resumo"
  for passo in OpenROAD.CTS OpenROAD.STAMidPNR-1 \
               OpenROAD.ResizerTimingPostCTS OpenROAD.STAMidPNR-2; do
    st="$(estado_de "$passo")"
    [ -n "$st" ] || continue
    d="$(dirname "$st")"
    {
      echo "== $passo ($(basename "$d"))"
      grep -hE "CTS-00|[Cc]lock roots|[Bb]uffers inserted|[Ss]inks|[Ll]evel|RSZ-00|[Ii]nserted|[Rr]esized|WNS|TNS|ERROR|WARNING (CTS|RSZ)" \
        "$d"/*.log 2>/dev/null | sort | uniq -c | head -40 || true
      # latencia e skew do relogio (so nos passos de STA)
      if [ -f "$d/clock.rpt" ]; then
        grep -A8 "report_clock_latency" "$d/clock.rpt" | grep -E "latency|skew" | head -6 || true
      fi
      # numeros de timing que o passo escreveu
      if [ -f "$d/or_metrics_out.json" ]; then
        python3 - "$d/or_metrics_out.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for k in sorted(m):
    if any(s in k for s in ("setup__ws", "hold__ws", "setup__tns", "hold__tns",
                            "vio__count", "clock__skew", "max_slew", "max_cap",
                            "max_fanout")) and "corner" not in k:
        print(f"   {k:45s} {m[k]}")
PY
      fi
      echo
    } >> "$resumo"
  done
  echo ">>> resumo dos logs (tambem em ${resumo#$REPO/}):"
  sed 's/^/    /' "$resumo"
fi
abre_gui OpenROAD.STAMidPNR-2 cts 05_cts

echo
echo "Conferir: no resumo, o skew do relogio (latencia max - min) em fracao"
echo "de ns, e nao os ~26 ns do fio unico; setup e hold do TT >= 0 depois do"
echo "reparo. Na imagem da arvore: as folhas com latencias parecidas."
echo "Proximo: etapa 6 (roteamento) -- script ainda nao escrito."
