#!/usr/bin/env bash
#=============================================================================
# 08_verificacao.sh -- ETAPA 8: GDS, DRC, LVS e o veredito do fluxo
#
#   Continua a rodada atual, do fim da etapa 7 (OpenROAD.IRDropReport) ate o
#   fim do fluxo Classic:
#     Magic.StreamOut              GDS do chip pelo Magic (o GDS "oficial")
#     KLayout.StreamOut            GDS do chip pelo KLayout (segunda opiniao)
#     KLayout.Render               PNG do GDS (vai para imagens/)
#     Magic.WriteLEF               LEF do nucleo (para o padring, etapa 11)
#     Odb.CheckDesignAntennaProperties
#     KLayout.XOR, Checker.XOR     os dois GDS tem de ser iguais
#     Magic.DRC, Checker.MagicDRC  regras de desenho; MAGIC_DRC_USE_GDS =
#                                  false: le o DEF + LEF, entao as macros
#                                  entram como caixa-preta (L3)
#     KLayout.DRC                  DESLIGADO (RUN_KLAYOUT_DRC = false, L41):
#                                  le o GDS com o miolo das macros da
#                                  OpenRAM, que tem ~1,2 milhao de erros
#                                  conhecidos (L3)
#     Magic.SpiceExtraction        netlist SPICE extraida do layout (macros
#                                  como caixa-preta: MAGIC_EXT_USE_GDS false)
#     Checker.IllegalOverlap       celulas sobrepostas
#     Netgen.LVS, Checker.LVS      layout x netlist do Verilog
#     Checker.SetupViolations      setup nos corners TT
#     Checker.HoldViolations       hold em TODOS os corners: vai REPROVAR
#                                  com as 15 violacoes do FF (<= 28 ps, L40)
#     Checker.MaxSlew/MaxCap       so relatam
#     Misc.ReportManufacturability resumo DRC/LVS/antena
#
#   Os checkers sao "adiados": o fluxo roda ate o fim e so entao diz que
#   reprovou, com a lista. O hold do FF ja e esperado (L40); o que importa
#   aqui e DRC, LVS e XOR.
#
# Uso:  bash layout/nucleo/08_verificacao.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

r=0
roda_trecho OpenROAD.IRDropReport Magic.StreamOut Misc.ReportManufacturability || r=$?
echo ">>> librelane terminou com codigo $r (checker adiado reprovando da != 0)"

# metricas: o ultimo passo que rodou e gravou state_out
ultimo=""
for p in Misc.ReportManufacturability Checker.LVS Netgen.LVS Magic.SpiceExtraction \
         Checker.MagicDRC Magic.DRC KLayout.XOR Magic.WriteLEF KLayout.Render Magic.StreamOut; do
  if [ -n "$(estado_de "$p")" ]; then ultimo="$p"; break; fi
done
[ -n "$ultimo" ] || { echo "ERRO: nenhum passo da etapa 8 gravou estado"; exit 1; }
echo ">>> metricas do fim da etapa ($ultimo):"
guarda_metricas "$ultimo" 08_verificacao

RES="$(pasta_resultados)"
resumo="$RES/08_verificacao.txt"
{
  echo "== Metricas de verificacao ($ultimo)"
  python3 - "$(estado_de "$ultimo")" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["metrics"]
for k in sorted(m):
    if any(x in k for x in ("drc_error", "lvs_", "xor_", "illegal_overlap", "antenna",
                            "disconnected_pin", "power_grid")) and "iter:" not in k:
        print(f"   {k:45s} {m[k]}")
PY
  echo
  for passo in Magic.StreamOut KLayout.StreamOut KLayout.XOR Magic.DRC \
               Magic.SpiceExtraction Netgen.LVS Checker.IllegalOverlap \
               Misc.ReportManufacturability; do
    s="$(estado_de "$passo")"; [ -n "$s" ] || continue
    d="$(dirname "$s")"
    echo "== $passo ($(basename "$d"))"
    grep -hiE "error|violation|mismatch|match uniquely|netlists match|total|differen|\[ERROR" \
      "$d"/*.log 2>/dev/null | sort | uniq -c | sort -rn | head -15 || true
    if [ -f "$d/runtime.txt" ]; then echo "   tempo: $(cat "$d/runtime.txt")"; fi
    echo
  done
  m="$(dirname "$(estado_de Misc.ReportManufacturability)")/manufacturability.rpt"
  if [ -f "$m" ]; then echo "== manufacturability.rpt"; cat "$m"; echo; fi
  # checkers que reprovaram (adiados): ficam no error.log da rodada
  e="$RUNS/$(rodada)/error.log"
  if [ -f "$e" ]; then echo "== error.log (ultimas linhas)"; tail -30 "$e"; fi
} > "$resumo"
echo ">>> resumo (tambem em ${resumo#$REPO/}):"
sed 's/^/    /' "$resumo"

# imagem: o PNG que o KLayout.Render gera do GDS
s="$(estado_de KLayout.Render)"
if [ -n "$s" ]; then
  png="$(ls "$(dirname "$s")"/*.png 2>/dev/null | head -1 || true)"
  if [ -n "$png" ]; then
    cp "$png" "$RES/imagens/08_gds_klayout.png" && echo ">>> imagem: imagens/08_gds_klayout.png"
  fi
fi

echo
echo "Conferir: magic__drc_error__count = 0, design__lvs_error__count = 0,"
echo "design__xor_difference__count = 0. O hold do FF reprovando e esperado (L40)."
echo "Depois: bash layout/nucleo/junta_logs.sh e o git add/commit que ele imprime."
