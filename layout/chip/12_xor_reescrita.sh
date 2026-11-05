#!/usr/bin/env bash
#=============================================================================
# 12_xor_reescrita.sh -- a reescrita pelo KLayout muda a GEOMETRIA? (L94)
#
#   O 12_drc_reescrita.sh mostrou: o mesmo GDS, so lido e gravado pelo
#   KLayout, da 316073 caixas no DRC do Magic (305262 no original). Ou a
#   geometria mudou (arredondamento: o GDS final estaria errado), ou so a
#   estrutura (ordem/forma das celulas, que o DRC hierarquico do Magic le de
#   outro jeito). O XOR do KLayout (o mesmo xor.drc do passo KLayout.XOR do
#   LibreLane) entre o original e o reescrito decide: 0 = mesma geometria.
#
#   Uso (nix-shell):  bash layout/chip/12_xor_reescrita.sh [rodada_12reesc]
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
st="$(estado_11 magic-streamout)"
gds="$( [ -n "$st" ] && vista "$st" gds )"
RE="${1:-$(ls -d "$CHIP"/runs/*_12reesc 2>/dev/null | sort | tail -1)}"
re="$RE/chip_top.gds"
[ -f "$gds" ] && [ -f "$re" ] || { echo "ERRO: falta $gds ou $re (rode o 12_drc_reescrita.sh)"; exit 1; }
PY="$(py_klayout)"
XOR="$("$PY" -c "import librelane,os; print(os.path.join(os.path.dirname(librelane.__file__),'scripts','klayout','xor.drc'))")"
DEST="$REPO/resultados/$(basename "$RE")_layout_chip"
mkdir -p "$DEST"
echo ">>> XOR: $gds"
echo "         x $re"
klayout -b -r "$XOR" -rd top_cell=chip_top -rd a="$gds" -rd b="$re" -rd jobs="$(nproc)" \
  -rd rdb_out="$RE/xor.xml" -rd ignore= -rd tilesize= > "$RE/xor.log" 2>&1 || true
{ grep -E "Running XOR for layer|XOR differences" "$RE/xor.log" | paste - - | awk '$NF != 0' || true
  grep -E "Total XOR differences" "$RE/xor.log" || echo "(sem total: veja xor.log)"; } > "$DEST/12_xor_reescrita.txt"
sed 's/^/    /' "$DEST/12_xor_reescrita.txt"
gzip -c "$RE/xor.log" > "$DEST/12_xor_reescrita.log.gz"
manda_git "$DEST"
