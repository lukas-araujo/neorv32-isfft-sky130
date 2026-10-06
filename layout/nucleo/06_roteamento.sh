#!/usr/bin/env bash
#=============================================================================
# 06_roteamento.sh -- ETAPA 6: roteamento global e detalhado
#
#   Continua a rodada atual, do fim da etapa 5 (OpenROAD.STAMidPNR-2):
#     OpenROAD.GlobalRouting        FastRoute: divide o chip em ladrilhos e
#                                   escolhe por quais ladrilhos/camadas cada
#                                   rede passa. GRT_ALLOW_CONGESTION = false:
#                                   se faltar trilha, PARA aqui (L24)
#     OpenROAD.CheckAntennas        antena com o roteamento global
#     OpenROAD.RepairDesignPostGRT  reparo de slew/cap com o fio do GRT
#                                   (desligado por padrao no LibreLane;
#                                   ligado no config.json, L32)
#     Odb.DiodesOnPorts, Odb.HeuristicDiodeInsertion, OpenROAD.RepairAntennas
#     OpenROAD.ResizerTimingPostGRT reparo de timing (desligado por padrao:
#                                   RUN_POST_GRT_RESIZER_TIMING; o setup do TT
#                                   ja fecha, entao fica desligado)
#     OpenROAD.STAMidPNR-3          STA com o fio do roteamento global
#     ---- ate aqui: ATE_GLOBAL=1 para parar e olhar a congestao ----
#     OpenROAD.DetailedRouting      TritonRoute: desenha cada fio e cada via
#                                   nas trilhas (o passo MAIS LENTO do fluxo)
#     Odb.RemoveRoutingObstructions, OpenROAD.CheckAntennas-1
#     Checker.TrDRC                 0 violacoes de roteamento (DRV) exigidas
#     Odb.ReportDisconnectedPins, Checker.DisconnectedPins
#     Odb.ReportWireLength, Checker.WireLength
#
#   IDs repetidos ganham sufixo (-1, -2, ...): STAMidPNR e o 4o do fluxo
#   (-3), CheckAntennas o 2o (-1). Lista conferida em librelane/flows/
#   classic.py, tag 3.0.14.
#
#   Imagens: mapa de congestao do roteamento, chip roteado, zoom no canal
#   IMEM/DMEM com os fios.
#
# Uso:  bash layout/nucleo/06_roteamento.sh   (SO_GUI=1 / SEM_GUI=1 como no 02)
#       ATE_GLOBAL=1 bash layout/nucleo/06_roteamento.sh   so o roteamento global
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${ATE_GLOBAL:-0}" = 1 ]; then
  FIM=OpenROAD.STAMidPNR-3; NOME=06_roteamento_global
else
  FIM=Checker.WireLength;   NOME=06_roteamento
fi

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho OpenROAD.STAMidPNR-2 OpenROAD.GlobalRouting "$FIM"
  echo ">>> metricas do fim do trecho:"
  guarda_metricas "$FIM" "$NOME"

  resumo="$(pasta_resultados)/$NOME.txt"
  : > "$resumo"
  for passo in OpenROAD.GlobalRouting OpenROAD.RepairDesignPostGRT \
               OpenROAD.RepairAntennas OpenROAD.ResizerTimingPostGRT \
               OpenROAD.STAMidPNR-3 OpenROAD.DetailedRouting \
               OpenROAD.CheckAntennas-1 Checker.TrDRC Checker.DisconnectedPins \
               Checker.WireLength; do
    st="$(estado_de "$passo")"
    [ -n "$st" ] || continue
    d="$(dirname "$st")"
    {
      echo "== $passo ($(basename "$d"))"
      # GRT: congestao/overflow; RSZ: reparos; DRT: violacoes por iteracao;
      # antena; tempo de execucao
      grep -hE "GRT-0(018|096|097|101|102|103|104)|[Oo]verflow|RSZ-00|ANT-|DRT-0(195|199)|[Nn]umber of violations|Total wire length|ERROR|WARNING (GRT|DRT|RSZ)" \
        "$d"/*.log 2>/dev/null | sort | uniq -c | head -40 || true
      [ -f "$d/runtime.txt" ] && echo "   tempo: $(cat "$d/runtime.txt")"
      if [ -f "$d/or_metrics_out.json" ]; then
        python3 - "$d/or_metrics_out.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))
for k in sorted(m):
    if any(s in k for s in ("setup__ws", "hold__ws", "vio__count", "route__",
                            "antenna", "wirelength", "max_slew", "max_cap")) \
       and "corner" not in k:
        print(f"   {k:45s} {m[k]}")
PY
      fi
      echo
    } >> "$resumo"
  done
  echo ">>> resumo dos logs (tambem em ${resumo#$REPO/}):"
  sed 's/^/    /' "$resumo"
fi
abre_gui "$FIM" roteamento "$NOME"

echo
echo "Conferir: GRT sem overflow (senao, L24: baixar PL_TARGET_DENSITY_PCT);"
echo "no detalhado, 'Number of violations = 0' na ultima iteracao do"
echo "TritonRoute; setup/hold do TT >= 0 no STAMidPNR-3."
echo "Depois: bash layout/nucleo/junta_logs.sh e push."
