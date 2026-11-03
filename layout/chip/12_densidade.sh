#!/usr/bin/env bash
#=============================================================================
# 12_densidade.sh -- ETAPA 12: densidade de metal e preenchimento (L86)
#
#   Regra de fabrica: cada camada (difusao, li, met1..met5) tem densidade
#   MINIMA e MAXIMA em cada janela de 700 x 700 um (passo de 70 um). Sem
#   isso o polimento quimico-mecanico (CMP) deixa a superficie ondulada:
#   onde ha pouco metal o polimento "afunda". O preenchimento (fill) poe
#   quadradinhos soltos, sem ligacao eletrica, nos vazios de cada camada.
#
#   Os passos KLayout.Filler/Density do LibreLane pularam (o PDK nao traz os
#   runsets do KLayout). Aqui usamos os scripts do proprio open_pdks para o
#   Magic, instalados em sky130A/libs.tech/magic/ (os mesmos do Caravel):
#
#     1. check_density.py  no GDS do chip (Magic.StreamOut da etapa 11): ANTES
#     2. generate_fill.py  gera chip_top_fill_pattern.gds.gz (so o fill,
#                          estilo "wafflefill" do Magic, respeitando as regras
#                          de espacamento com o desenho existente)
#     3. KLayout           junta chip + fill num GDS so (instancia do fill
#                          dentro do chip_top)
#     4. check_density.py  no GDS preenchido: DEPOIS
#     5. Magic DRC         no GDS preenchido, nucleo caixa-preta (como no
#                          12_verifica.sh): o fill nao pode criar erro
#                          (DRC=0 pula, ~20 min)
#     6. KLayout.Render    imagem do GDS final
#
#   Leva tempo: o generate_fill achata o chip em ladrilhos de 700 um (com o
#   nucleo inteiro dentro). Usa varios nucleos (-dist).
#
#   Uso (nix-shell do LibreLane):  bash layout/chip/12_densidade.sh
#     FILL=<...fill_pattern.gds.gz>  reaproveita um fill ja gerado (pula o passo 2)
#     ANTES=0                        pula a medida antes do fill
#     FAIXA=205                      largura (um) da faixa dos pads sem fill (L90)
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip

st="$(estado_11 magic-streamout)"
gds="$( [ -n "$st" ] && vista "$st" gds )"
[ -f "$gds" ] || { echo "ERRO: sem o GDS do Magic.StreamOut em $RUN11"; exit 1; }
MAGD="$PDKV/sky130A/libs.tech/magic"
for f in check_density.py generate_fill.py; do
  [ -f "$MAGD/$f" ] || { echo "ERRO: falta $MAGD/$f (scripts do open_pdks)"; exit 1; }
done
PY="$(py_klayout)"
[ -n "$PY" ] || { echo "ERRO: nenhum python com klayout.db (nix-shell do LibreLane?)"; exit 1; }

TAG="$(date +%Y-%m-%d_%H%M)_12dens"
W="$CHIP/runs/$TAG"
DEST="$REPO/resultados/${TAG}_layout_chip"
mkdir -p "$W/antes" "$W/fill" "$W/depois" "$DEST/imagens"
# os scripts do open_pdks carregam a celula com o nome do arquivo: chip_top.gds
ln -sf "$gds" "$W/antes/chip_top.gds"
ln -sf "$gds" "$W/fill/chip_top.gds"
export PDK=sky130A
echo ">>> GDS: $gds ($(du -h "$gds" | cut -f1))"

#--- 1. densidade antes --------------------------------------------------------
if [ "${ANTES:-1}" = 1 ]; then
  echo ">>> 1. check_density (antes do preenchimento)"
  ( cd "$W/antes" && PDK_ROOT="$PDKV" python3 "$MAGD/check_density.py" chip_top.gds ) \
    > "$DEST/12_densidade_antes.txt" 2>&1 || true
  python3 "$CHIP/resume_verifica.py" densidade "$DEST/12_densidade_antes.txt" | sed 's/^/    /'
else
  echo ">>> 1. (ANTES=0: sem a medida antes do fill)"
fi

#--- 2. preenchimento ----------------------------------------------------------
# FILL=<chip_top_fill_pattern.gds.gz de uma rodada anterior> reaproveita (29 min)
if [ -n "${FILL:-}" ]; then
  fill="$(readlink -f "$FILL")"
  [ -f "$fill" ] || { echo "ERRO: FILL=$FILL nao existe"; exit 1; }
  echo ">>> 2. preenchimento reaproveitado: $fill"
else
  echo ">>> 2. generate_fill (demora)"
  t0=$(date +%s)
  ( cd "$W/fill" && PDK_ROOT="$PDKV" python3 "$MAGD/generate_fill.py" chip_top.gds -dist ) \
    > "$W/fill/generate_fill.log" 2>&1 || true
  fill="$W/fill/chip_top_fill_pattern.gds.gz"
  echo "    $(( ($(date +%s) - t0) / 60 )) min"
  [ -f "$fill" ] || { echo "ERRO: o generate_fill nao gerou $fill (veja $W/fill/generate_fill.log)"; tail -20 "$W/fill/generate_fill.log"; exit 1; }
fi
echo "    fill: $(du -h "$fill" | cut -f1)"

#--- 3. junta chip + fill (sem fill na faixa dos pads, L90) ---------------------
# O fill de difusao/poly/metal dentro das celulas de I/O criou 10811 erros de
# DRC de difusao/tap/latch-up (1a rodada). As celulas de I/O vem completas da
# foundry: so fica o fill INTEIRAMENTE a mais de FAIXA um da borda do die.
FAIXA="${FAIXA:-205}"
echo ">>> 3. KLayout: chip_top + fill (sem fill a menos de $FAIXA um da borda)"
"$PY" - "$gds" "$fill" "$W/depois/chip_top.gds" "$FAIXA" <<'PY'
import sys
import klayout.db as db
chip, fill, saida, faixa = sys.argv[1], sys.argv[2], sys.argv[3], float(sys.argv[4])
ly = db.Layout()
ly.read(chip)
ly.read(fill)
top = ly.cell("chip_top")
fp = ly.cell("chip_top_fill_pattern")
if top is None or fp is None:
    sys.exit(f"ERRO: chip_top={top} chip_top_fill_pattern={fp}")
bb = top.dbbox()            # contorno do chip (um)
dbu = ly.dbu
janela = db.Region(db.Box(int((bb.left + faixa) / dbu), int((bb.bottom + faixa) / dbu),
                          int((bb.right - faixa) / dbu), int((bb.top - faixa) / dbu)))
novo = ly.create_cell("chip_top_fill")
tot = fica = 0
for li in ly.layer_indexes():
    r = db.Region(fp.begin_shapes_rec(li))
    n = r.count()
    if n == 0:
        continue
    dentro = r.inside(janela)          # so os quadrados inteiros dentro da janela
    novo.shapes(li).insert(dentro)
    tot += n
    fica += dentro.count()
    info = ly.get_info(li)
    print(f"    camada {info.layer}/{info.datatype}: {n} formas de fill, ficam {dentro.count()}")
top.insert(db.CellInstArray(novo.cell_index(), db.Trans()))
# a celula do fill original (com a faixa) sai do GDS
fp.prune_cell()
ly.write(saida)
print(f"    fill: {tot} formas, ficam {fica} ({100.0 * fica / max(tot, 1):.1f} %); chip_top instancia chip_top_fill em (0, 0)")
PY

#--- 4. densidade depois -------------------------------------------------------
echo ">>> 4. check_density (depois do preenchimento)"
( cd "$W/depois" && PDK_ROOT="$PDKV" python3 "$MAGD/check_density.py" chip_top.gds ) \
  > "$DEST/12_densidade_depois.txt" 2>&1 || true
python3 "$CHIP/resume_verifica.py" densidade "$DEST/12_densidade_antes.txt" "$DEST/12_densidade_depois.txt" \
  > "$DEST/12_densidade.txt"
sed 's/^/    /' "$DEST/12_densidade.txt"

#--- 5. DRC no GDS preenchido ---------------------------------------------------
if [ "${DRC:-1}" = 1 ]; then
  echo ">>> 5. DRC (Magic) no GDS preenchido, nucleo caixa-preta (~20 min)"
  mkdir -p "$W/drc"
  if drc_magic "$W/depois/chip_top.gds" "$W/drc/drc.magic.rpt"; then
    python3 "$CHIP/resume_verifica.py" drc "$W/drc/drc.magic.rpt" > "$DEST/12_drc_preenchido.txt" 2>&1
    gzip -c "$W/drc/drc.magic.rpt" > "$DEST/12_drc_preenchido.rpt.gz"
    sed 's/^/    /' "$DEST/12_drc_preenchido.txt" | head -25 || true
  else
    echo "    DRC nao gerou relatorio (veja $W/drc/drc.log)"
  fi
fi

#--- 6. imagem do GDS final -----------------------------------------------------
echo ">>> 6. imagem do GDS preenchido"
read -r lyt lyp lym < <(python3 -c "import json,sys; r=json.load(open(sys.argv[1])); print(r['KLAYOUT_TECH'], r['KLAYOUT_PROPERTIES'], r['KLAYOUT_DEF_LAYER_MAP'])" "$RUN11/resolved.json")
RENDER="$("$PY" -c "import librelane,os; print(os.path.join(os.path.dirname(librelane.__file__),'scripts','klayout','render.py'))")"
"$PY" "$RENDER" \
  "$W/depois/chip_top.gds" --output "$DEST/imagens/12_chip_preenchido.png" \
  --lyt "$lyt" --lyp "$lyp" --lym "$lym" > "$W/render.log" 2>&1 \
  && echo "    imagens/12_chip_preenchido.png" || echo "    render falhou (veja $W/render.log)"

cp -f "$W/fill/generate_fill.log" "$DEST/" 2>/dev/null || true
gzip -f "$DEST/generate_fill.log" 2>/dev/null || true
echo
echo "GDS final (fora do git): $W/depois/chip_top.gds ($(du -h "$W/depois/chip_top.gds" | cut -f1))"
echo "Resultados: ${DEST#$REPO/}"
ls -1 "$DEST" | sed 's/^/    /'
manda_git "$DEST"
