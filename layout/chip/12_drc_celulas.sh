#!/usr/bin/env bash
#=============================================================================
# 12_drc_celulas.sh -- ETAPA 12: DRC de referencia das celulas do anel (L81)
#
#   O DRC do chip (12_verifica.sh) achou ~305 mil caixas, TODAS na faixa dos
#   pads (nenhuma no metal desenhado nas etapas 11/12). Pergunta: sao erros
#   de DENTRO das celulas de I/O da foundry (desenhadas com regras proprias)
#   ou do ENCOSTO entre elas / com o nosso metal?
#
#   Metodo: o Magic le o MESMO GDS do chip (o do Magic.StreamOut da etapa
#   11), carrega cada celula do anel SOZINHA e roda o mesmo DRC
#   (drc(full), euclidiano). Depois o resume_verifica.py (modo "anel") soma,
#   por regra, a AREA de erro de cada celula x numero de instancias no chip
#   e compara com a area de erro do chip na faixa dos pads.
#     area igual            -> erro interno da celula (da foundry)
#     chip com area a mais  -> erro de encosto (olhar as coordenadas)
#   Area, e nao numero de caixas: o Magic quebra cada erro na grade de
#   ladrilhos dele, e a mesma celula pode cair em ladrilhos diferentes.
#
#   So Magic (sem LibreLane). Uso, no nix-shell do LibreLane:
#     bash layout/chip/12_drc_celulas.sh [rodada_da_etapa_11] [rodada_12]
#=============================================================================
source "$(dirname "$0")/../nucleo/comum.sh"
confere_ambiente
CHIP="$REPO/layout/chip"
TAG11="${1:-$(cat "$CHIP/.rodada_atual" 2>/dev/null || true)}"
TAG12="${2:-$(cat "$CHIP/.rodada_12" 2>/dev/null || true)}"
RUN11="$CHIP/runs/$TAG11"
RUN12="$CHIP/runs/$TAG12"
DEST="$REPO/resultados/${TAG12}_layout_chip"
[ -d "$RUN11" ] && [ -d "$RUN12" ] || { echo "ERRO: rodadas $TAG11 / $TAG12 nao encontradas"; exit 1; }
mkdir -p "$DEST"

gds="$(ls "$RUN11"/[0-9]*-magic-streamout/chip_top.gds 2>/dev/null | sort -V | tail -1 || true)"
[ -f "$gds" ] || { echo "ERRO: sem chip_top.gds do Magic.StreamOut em $RUN11"; exit 1; }
drc="$(ls "$RUN12"/[0-9]*-magic-drc/reports/drc.magic.rpt 2>/dev/null | sort -V | tail -1 || true)"
spice="$(ls "$RUN12"/[0-9]*-magic-spiceextraction/*.spice 2>/dev/null | sort -V | tail -1 || true)"
[ -f "$drc" ] && [ -f "$spice" ] || { echo "ERRO: falta o drc.magic.rpt ou a netlist extraida em $RUN12"; exit 1; }
rc="$(find -L "$PDK_ROOT" -name sky130A.magicrc -path '*8afc8346*' 2>/dev/null | head -1 || true)"
[ -n "$rc" ] || { echo "ERRO: sky130A.magicrc da versao 8afc8346 nao encontrado (L75)"; exit 1; }

# celulas do anel = as que aparecem no chip_top extraido e nao sao celula-padrao nem o nucleo
celulas="$(python3 "$CHIP/resume_verifica.py" celulas "$spice")"
echo ">>> GDS: ${gds#$CHIP/}"
echo ">>> celulas do anel:"; echo "$celulas" | sed 's/^/    /'

W="$CHIP/runs/$TAG12/drc_celulas"
mkdir -p "$W"
tcl="$W/drc_celulas.tcl"
{
  echo 'crashbackups disable'
  echo 'locking disable'
  echo 'units internal'
  echo 'gds noduplicates true'
  echo 'gds readonly true'
  echo "gds read $gds"
  echo 'set oscale [cif scale out]'
  echo "set fout [open $W/ref.tsv w]"
  echo 'drc euclidean on'
  echo 'drc style drc(full)'
  for c in $(echo "$celulas" | awk '{print $2}'); do
    cat <<EOF
load $c
select top cell
drc check
set n 0
foreach {why coords} [drc listall why] {
    set a 0.0
    set k 0
    foreach co \$coords {
        set w [expr {\$oscale * ([lindex \$co 2] - [lindex \$co 0])}]
        set h [expr {\$oscale * ([lindex \$co 3] - [lindex \$co 1])}]
        set a [expr {\$a + \$w * \$h}]
        incr k
    }
    puts \$fout "$c\t\$why\t\$k\t\$a"
    foreach co \$coords {
        puts \$fout [format "BOX\t%s\t%s\t%.3f\t%.3f\t%.3f\t%.3f" $c \$why \
            [expr {\$oscale * [lindex \$co 0]}] [expr {\$oscale * [lindex \$co 1]}] \
            [expr {\$oscale * [lindex \$co 2]}] [expr {\$oscale * [lindex \$co 3]}]]
    }
    incr n \$k
}
puts stdout "\[INFO\] $c: \$n caixas"
flush stdout
EOF
  done
  echo 'close $fout'
  echo 'quit -noprompt'
} > "$tcl"

echo ">>> Magic: DRC de cada celula (pode levar alguns minutos)"
( cd "$W" && magic -dnull -noconsole -rcfile "$rc" "$tcl" > "$W/drc_celulas.log" 2>&1 ) || true
grep "\[INFO\]" "$W/drc_celulas.log" | sed 's/^/    /'
[ -s "$W/ref.tsv" ] || { echo "ERRO: ref.tsv vazio (veja $W/drc_celulas.log)"; exit 1; }
gzip -c "$W/ref.tsv" > "$DEST/12_drc_ref_celulas.tsv.gz"
gzip -c "$W/drc_celulas.log" > "$DEST/12_drc_celulas.log.gz"

python3 "$CHIP/resume_verifica.py" anel "$drc" "$W/ref.tsv" "$spice" > "$DEST/12_drc_anel_area.txt" 2>&1 || true
# comparacao geometrica (L83): erros das celulas levados para cada instancia pelo DEF
deff="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('def') or '')" \
        "$(dirname "$(dirname "$drc")")/state_in.json")"
lefs="$(python3 -c "import json,sys; print(':'.join(json.load(open(sys.argv[1]))['PAD_LEFS']))" "$RUN12/resolved.json")"
export CDA_RPT="$drc" CDA_REF="$W/ref.tsv" CDA_DEF="$deff" CDA_LEFS="$lefs"
# posicoes das celulas do anel no DEF (para conferir orientacoes fora daqui, L84)
awk '/^COMPONENTS/{f=1} /^END COMPONENTS/{f=0} f' "$deff" | tr '\n' ' ' | sed 's/ ;/ ;\n/g' \
  | grep -E 'sky130_ef_io__|sky130_fd_io__' > "$DEST/12_anel_posicoes.txt" || true
echo ">>> $(wc -l < "$DEST/12_anel_posicoes.txt") celulas do anel no DEF (12_anel_posicoes.txt)"
if python3 -c "import klayout.db" 2>/dev/null; then
  python3 "$CHIP/compara_drc_anel.py" > "$DEST/12_drc_anel.txt" 2>&1 || true
else
  klayout -b -r "$CHIP/compara_drc_anel.py" > "$DEST/12_drc_anel.txt" 2>&1 || true
fi
sed 's/^/    /' "$DEST/12_drc_anel.txt" | head -70 || true
echo
echo "Resultados em ${DEST#$REPO/}: 12_drc_anel.txt (geometrico, L83), 12_drc_anel_area.txt (L81), 12_drc_ref_celulas.tsv"
echo "  git add resultados/${TAG12}_layout_chip"
echo "  git commit -m 'gdsii: etapa 12, DRC das celulas do anel'"
echo "  git pull --rebase origin main && git push"
