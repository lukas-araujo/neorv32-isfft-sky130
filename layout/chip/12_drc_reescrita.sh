#!/usr/bin/env bash
#=============================================================================
# 12_drc_reescrita.sh -- o DRC muda so por o KLayout reescrever o GDS? (L93)
#
#   O DRC do chip preenchido deu 316073 caixas nas duas rodadas (com e sem
#   fill na faixa dos pads), contra 305262 sem fill: as 10811 a mais ficam
#   DENTRO dos pads do sul (y 70-90 um), onde a 2a rodada nao tinha fill.
#   O que as duas rodadas com fill tem em comum: o GDS do chip foi LIDO E
#   REESCRITO pelo KLayout na juncao chip + fill.
#
#   Teste: o mesmo DRC (Magic, nucleo caixa-preta) no GDS do chip SEM fill,
#   so reescrito pelo KLayout (le e grava, nada mais). Se der ~316073, a
#   diferenca e da reescrita (o Magic ve a hierarquia dos pads de outro
#   jeito), nao do fill. ~15 min.
#
#   Uso (nix-shell do LibreLane):  bash layout/chip/12_drc_reescrita.sh
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
st="$(estado_11 magic-streamout)"
gds="$( [ -n "$st" ] && vista "$st" gds )"
[ -f "$gds" ] || { echo "ERRO: sem o GDS do Magic.StreamOut em $RUN11"; exit 1; }
PY="$(py_klayout)"
[ -n "$PY" ] || { echo "ERRO: sem python com klayout.db"; exit 1; }
TAG="$(date +%Y-%m-%d_%H%M)_12reesc"
W="$CHIP/runs/$TAG"
DEST="$REPO/resultados/${TAG}_layout_chip"
mkdir -p "$W/drc" "$DEST"

echo ">>> KLayout: le e reescreve $gds"
"$PY" - "$gds" "$W/chip_top.gds" <<'PY' | tee "$DEST/12_reescrita.txt"
import sys
import klayout.db as db
ly = db.Layout()
ly.read(sys.argv[1])
n0 = sum(1 for _ in ly.each_cell())
ly.write(sys.argv[2])
l2 = db.Layout()
l2.read(sys.argv[2])
print(f"celulas: original {n0}, reescrito {sum(1 for _ in l2.each_cell())}")
PY
echo ">>> DRC (Magic) no GDS reescrito (~15 min)"
if drc_magic "$W/chip_top.gds" "$W/drc/drc.magic.rpt"; then
  python3 "$CHIP/resume_verifica.py" drc "$W/drc/drc.magic.rpt" >> "$DEST/12_reescrita.txt" 2>&1
  gzip -c "$W/drc/drc.magic.rpt" > "$DEST/12_drc_reescrita.rpt.gz"
  sed 's/^/    /' "$DEST/12_reescrita.txt" | head -12 || true
else
  echo "    DRC nao gerou relatorio (veja $W/drc/drc.log)"
fi
manda_git "$DEST"
