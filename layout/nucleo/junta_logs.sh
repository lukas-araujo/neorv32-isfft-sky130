#!/usr/bin/env bash
#=============================================================================
# junta_logs.sh -- junta os LOGS e RELATORIOS da rodada atual num .tar.gz
#                  dentro de resultados/, para ir pelo git
#
# A pasta layout/nucleo/runs/ fica fora do git (tem .odb, .def, GDS:
# pesados e refeitos a cada rodada). Quando algo da errado -- ou para
# guardar a prova de uma etapa -- rode:
#
#   bash layout/nucleo/junta_logs.sh
#   (ele imprime o git add / git commit prontos, com a data de hoje e a
#    ultima etapa que rodou)
#
# Entra: *.log, *.rpt, *.txt, *.json, *.csv, *.tcl, *.sdc de todas as
# etapas + o flow.log da rodada. NAO entra: .odb, .def, .v, .gds, .spef,
# .lef, .mag (layout e netlists; o LibreLane refaz).
# Nao precisa estar no nix-shell.
#=============================================================================
set -euo pipefail
NUCLEO="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$NUCLEO/../.." && pwd)"
[ -f "$NUCLEO/.rodada_atual" ] || { echo "ERRO: nenhuma rodada (rode o 01_leitura.sh)"; exit 1; }
TAG="$(cat "$NUCLEO/.rodada_atual")"
RUN="$NUCLEO/runs/$TAG"
[ -d "$RUN" ] || { echo "ERRO: pasta da rodada nao existe: $RUN"; exit 1; }

DEST="$REPO/resultados/${TAG}_layout_nucleo"
mkdir -p "$DEST"
# Nome = data e hora EM QUE os logs foram juntados (a rodada pode durar
# dias: a pasta leva a data de quando a rodada COMECOU, o .tar.gz a de hoje)
AGORA="$(date +%Y-%m-%d_%H%M)"
ARQ="$DEST/logs_${AGORA}.tar.gz"
ULTIMA="$(ls "$RUN" | grep '^[0-9]' | sort -n | tail -1)"

( cd "$NUCLEO/runs" && find "$TAG" -type f \
    \( -name '*.log' -o -name '*.rpt' -o -name '*.txt' -o -name '*.json' \
       -o -name '*.csv' -o -name '*.tcl' -o -name '*.sdc' \) \
    -size -20M -print0 | tar czf "$ARQ" --null -T - )

echo "Arquivo: ${ARQ#$REPO/} ($(du -h "$ARQ" | cut -f1), $(tar tzf "$ARQ" | wc -l) arquivos)"
echo "Etapas na rodada:"
ls "$RUN" | grep '^[0-9]' | sort -n | sed 's/^/  /'
echo
echo "Proximo:"
echo "  git add resultados/${TAG}_layout_nucleo"
echo "  git commit -m \"gdsii: logs do layout ate ${ULTIMA} (juntados em ${AGORA}, rodada ${TAG})\" && git push"
