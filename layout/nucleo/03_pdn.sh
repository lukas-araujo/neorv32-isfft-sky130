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

# Zoom no PRIMEIRO aviso PDN-0110 ("No via inserted between met4 and met5"),
# se houver: janela de 60 x 40 um em volta do ponto que o log aponta.
# Vira a imagem 03_pdn_zoom_pdn0110.png (ver tcl/imagem.tcl).
P="$(dirname "$(estado_de OpenROAD.GeneratePDN)")"
IMG_ZOOM="$(grep -hm1 "PDN-0110" "$P"/*.log 2>/dev/null \
  | sed -E 's/.*at \(([0-9.]+), ([0-9.]+)\) - \(([0-9.]+), ([0-9.]+)\).*/\1 \2 \3 \4/' \
  | awk '{printf "%.2f %.2f %.2f %.2f", $1-30, $2-20, $3+30, $4+20}')" || true
export IMG_ZOOM
[ -n "$IMG_ZOOM" ] && echo ">>> zoom no 1o PDN-0110: $IMG_ZOOM"

abre_gui OpenROAD.GeneratePDN pdn 03_pdn

echo
echo "Conferir: anel em volta do nucleo; tiras verticais (met4) param antes"
echo "das macros; as horizontais (met5) passam por cima delas; no zoom, vias"
echo "entre a met5 e o anel met4 da macro. Nenhum 'ERROR PDN' acima."
echo "Se houve PDN-0110: ver imagens/03_pdn_zoom_pdn0110.png (DIARIO_GDSII, L22)."
echo "Proximo: bash layout/nucleo/04_posicionamento.sh"
