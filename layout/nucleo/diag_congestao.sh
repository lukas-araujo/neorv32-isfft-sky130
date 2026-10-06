#!/usr/bin/env bash
#=============================================================================
# diag_congestao.sh -- ONDE esta a congestao do roteamento global?
#
# Quando o OpenROAD.GlobalRouting para com GRT-0116, o passo nao grava
# estado nem imagem. Este script refaz o mesmo roteamento global fora do
# fluxo (mesmo .odb de entrada e mesmas opcoes, lidas do _env.tcl do passo),
# deixando terminar com congestao, e salva em resultados/:
#   06_congestao.rpt   regioes congestionadas (formato do DRC Viewer)
#   06_congestao.txt   resumo: excesso por camada e por regiao de 100 um
#   imagens/06_congestao_mapa.png  mapa de calor
# Nao mexe na rodada. ~5 min.
#
# Uso:  bash layout/nucleo/diag_congestao.sh   (SEM_GUI=1 fecha sozinho)
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

d="$(for x in "$RUNS/$(rodada)"/[0-9]*-openroad-globalrouting; do
       [ -d "$x" ] && echo "$(basename "$x" | cut -d- -f1 | sed 's/^0*//') $x"
     done | sort -n | tail -1 | cut -d' ' -f2-)"
[ -n "$d" ] && [ -f "$d/_env.tcl" ] || { echo "ERRO: nenhum passo OpenROAD.GlobalRouting na rodada"; exit 1; }
R="$(pasta_resultados)"
export DIAG_ENV="$d/_env.tcl" DIAG_RPT="$R/06_congestao.rpt" DIAG_PNG="$R/imagens/06_congestao_mapa.png"
echo ">>> diagnostico do roteamento global a partir de $(basename "$d")"
if [ "${SEM_GUI:-0}" = 1 ]; then
  QT_QPA_PLATFORM=offscreen openroad -no_splash -exit -gui "$NUCLEO/tcl/diag_congestao.tcl" | tee "$R/06_congestao.log"
else
  openroad -no_splash -gui "$NUCLEO/tcl/diag_congestao.tcl" | tee "$R/06_congestao.log"
fi

python3 "$NUCLEO/resume_congestao.py" "$DIAG_RPT" "$CONFIG" | tee "$R/06_congestao.txt"
echo ">>> em ${R#$REPO/}: 06_congestao.rpt, 06_congestao.txt, imagens/06_congestao_mapa.png"
echo "Depois: git add resultados/ && git commit -m 'gdsii: diagnostico da congestao' && git push"
