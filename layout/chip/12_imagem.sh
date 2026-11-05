#!/usr/bin/env bash
#=============================================================================
# 12_imagem.sh -- imagem do chip inteiro (anel de pads + nucleo), em alta
#                 resolucao, a partir do GDS final
#
#   O PNG que o LibreLane gera (KLayout.Render) tem 1000 px de largura: bom
#   para conferir, ruim para slide. Aqui o mesmo render.py do LibreLane, com
#   a tecnologia e as cores do sky130 (KLAYOUT_TECH/PROPERTIES da rodada),
#   mas com a resolucao que se quiser.
#
#   Uso (nix-shell do LibreLane):
#     bash layout/chip/12_imagem.sh                PNG de 6000 px, fundo preto
#     LARGURA=10000 FUNDO=white bash layout/chip/12_imagem.sh
#     GDS=<arquivo.gds> bash ...                   outro GDS (ex.: o preenchido)
#     GUI=1 bash layout/chip/12_imagem.sh          abre o KLayout (zoom, camadas,
#                                                  File > Screenshot)
#
#   Sem GDS=, usa o GDS do Magic.StreamOut da rodada atual da etapa 11.
#   Saida: resultados/<rodada>_layout_chip/imagens/12_chip_<largura>px.png
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
LARGURA="${LARGURA:-6000}"
FUNDO="${FUNDO:-black}"
if [ -z "${GDS:-}" ]; then
  st="$(estado_11 magic-streamout)"
  GDS="$( [ -n "$st" ] && vista "$st" gds )"
fi
[ -f "$GDS" ] || { echo "ERRO: GDS nao encontrado ($GDS)"; exit 1; }
read -r lyt lyp lym < <(python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print(r['KLAYOUT_TECH'], r['KLAYOUT_PROPERTIES'], r['KLAYOUT_DEF_LAYER_MAP'])" "$RUN11/resolved.json")
echo ">>> GDS: $GDS ($(du -h "$GDS" | cut -f1))"

if [ "${GUI:-0}" = 1 ]; then
  echo ">>> abrindo o KLayout (tecnologia: $lyt)"
  echo "    dica: Display > Full Hierarchy (ou tecla *) para ver dentro das celulas;"
  echo "          File > Screenshot para salvar a vista atual"
  klayout -nn "$lyt" -l "$lyp" "$GDS" &
  exit 0
fi

PY="$(py_klayout)"
[ -n "$PY" ] || { echo "ERRO: sem python com klayout.db/pya"; exit 1; }
RENDER="$("$PY" -c "import librelane,os; print(os.path.join(os.path.dirname(librelane.__file__),'scripts','klayout','render.py'))")"
DEST="$REPO/resultados/${TAG11}_layout_chip/imagens"
mkdir -p "$DEST"
out="$DEST/12_chip_${LARGURA}px$( [ "$FUNDO" = white ] && echo _branco).png"
echo ">>> render ${LARGURA} px, fundo $FUNDO (pode levar alguns minutos: o GDS tem o nucleo inteiro)"
"$PY" "$RENDER" "$GDS" --output "$out" --lyt "$lyt" --lyp "$lyp" --lym "$lym" \
  --resolution "$LARGURA" --oversampling 2 --background-color "$FUNDO" \
  || { echo "ERRO: render falhou"; exit 1; }
echo ">>> $out ($(du -h "$out" | cut -f1))"
echo
echo "Para mandar pelo git (PNG grande: confira o tamanho antes):"
echo "  git add ${out#$REPO/}"
echo "  git commit -m 'gdsii: imagem do chip'"
echo "  git pull --rebase origin main && git push"
