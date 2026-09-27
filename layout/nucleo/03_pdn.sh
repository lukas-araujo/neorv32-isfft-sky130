#!/usr/bin/env bash
#=============================================================================
# 03_pdn.sh -- ETAPA 3: rede de alimentacao (PDN)
#
#   Continua a rodada atual, do fim da etapa 2:
#     Odb.AddPDNObstructions     (nenhuma definida por nos)
#     OpenROAD.GeneratePDN       anel do nucleo; tiras de met4 (verticais) e
#                                met5 (horizontais); met1 nas linhas de celula;
#                                met5 sobre as macros descendo no anel met4
#                                delas (PDN_MACRO_CONNECTIONS)
#     Odb.RemovePDNObstructions
#
#   Imagens: malha inteira (so met4/met5) + zoom no anel de uma macro +
#   zoom no canto do anel do nucleo.
#
# Uso:  bash layout/nucleo/03_pdn.sh      (SO_GUI=1 / SEM_GUI=1 como no 02)
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho OpenROAD.TapEndcapInsertion Odb.AddPDNObstructions Odb.RemovePDNObstructions
  echo ">>> metricas depois da PDN:"
  guarda_metricas OpenROAD.GeneratePDN 03_pdn
  P="$(dirname "$(estado_de OpenROAD.GeneratePDN)")"
  echo ">>> avisos/erros do pdngen:"
  grep -hE "\[(WARNING|ERROR) PDN" "$P"/*.log 2>/dev/null | sort | uniq -c | head -20 || true
fi
abre_gui OpenROAD.GeneratePDN pdn 03_pdn

echo
echo "Conferir: anel em volta do nucleo; tiras verticais (met4) param antes"
echo "das macros; as horizontais (met5) passam por cima delas; no zoom, vias"
echo "entre a met5 e o anel met4 da macro. Nenhum 'ERROR PDN' acima."
echo "Proximo: etapa 4 (posicionamento) -- script ainda nao escrito."
