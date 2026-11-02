#!/usr/bin/env bash
#=============================================================================
# comum_chip.sh -- funcoes dos scripts da etapa 12 do chip (lido com source)
#
#   confere_chip       nix-shell, PDK 8afc8346 (L75), rodada da etapa 11
#   estado_11 <passo>  state_out.json do passo (slug, ex. openroad-rcx) na
#                      rodada da etapa 11 (o de maior numero)
#   roda_librelane <tag> <de> <ate> <estado_inicial> <config extra...>
#   junta_logs <tag> <destino>
#
# Variaveis depois do confere_chip:
#   CHIP ENT TAG11 RUN11 PDKV (raiz da versao, contem sky130A/) RC IO
#=============================================================================
source "$(dirname "${BASH_SOURCE[0]}")/../nucleo/comum.sh"   # REPO, confere_ambiente...
CHIP="$REPO/layout/chip"
ENT="$CHIP/entrada"

confere_chip () {
  confere_ambiente
  TAG11="${TAG11:-$(cat "$CHIP/.rodada_atual" 2>/dev/null || true)}"
  RUN11="$CHIP/runs/$TAG11"
  [ -n "$TAG11" ] && [ -d "$RUN11" ] || { echo "ERRO: rodada da etapa 11 nao encontrada ($RUN11)"; exit 1; }
  grep -q "Flow complete" "$RUN11/flow.log" 2>/dev/null \
    || echo "AVISO: $TAG11 nao termina em 'Flow complete.'"
  RC="$(find -L "$PDK_ROOT" -name sky130A.magicrc -path '*8afc8346*' 2>/dev/null | head -1 || true)"
  [ -n "$RC" ] || { echo "ERRO: sky130A.magicrc da versao 8afc8346 nao encontrado em $PDK_ROOT (L75)"; exit 1; }
  # .../versions/8afc.../sky130A/libs.tech/magic/sky130A.magicrc -> .../versions/8afc...
  PDKV="$(dirname "$(dirname "$(dirname "$(dirname "$RC")")")")"
  IO="$PDKV/sky130A/libs.ref/sky130_fd_io"
  [ -d "$IO" ] || { echo "ERRO: $IO nao existe"; exit 1; }
  echo ">>> etapa 11: $TAG11 | PDK: $PDKV"
}

estado_11 () {
  local d
  d="$(ls -d "$RUN11"/[0-9]*-"$1" 2>/dev/null | sort -V | tail -1 || true)"
  if [ -n "$d" ] && [ -f "$d/state_out.json" ]; then echo "$d/state_out.json"; else echo ""; fi
}

vista () {   # vista <state_out.json> <chave>  (gds, def, odb, pnl ...)
  python3 -c "import json,sys; v=json.load(open(sys.argv[1])).get(sys.argv[2]); print(v if isinstance(v,str) else '')" "$1" "$2"
}

roda_librelane () {   # tag de ate estado_inicial config_extra...
  local tag="$1" de="$2" ate="$3" ini="$4"; shift 4
  local r=0
  ( cd "$CHIP" && librelane --pdk-root "$PDK_ROOT" --run-tag "$tag" \
      --with-initial-state "$ini" --from "$de" --to "$ate" config.json "$@" ) || r=$?
  echo ">>> librelane ($de .. $ate) terminou com codigo $r"
  return $r
}

junta_logs () {   # tag destino
  ( cd "$CHIP/runs" && find "$1" -type f \
      \( -name '*.log' -o -name '*.rpt' -o -name '*.txt' -o -name '*.json' \
         -o -name '*.tcl' -o -name '*.lvs' -o -name '*.sdc' \) -size -20M -print0 \
    | tar czf "$2/logs_$(basename "$1").tar.gz" --null -T - ) || true
}

linhas_fatais_magic () {   # <arquivo de log>: as que o MAGIC_CAPTURE_ERRORS trataria como fatais
  grep -h -E "Error while reading cell|DEF read.*\(Error\)|LEF read.*\(Error\)" "$1" 2>/dev/null \
    | grep -v "Warning:" | sed 's/(byte position [0-9]*)//' \
    | sed 's/cell "[^"]*"/cell "..."/' | sort | uniq -c | sort -rn | head -20 || true
}

manda_git () {   # pasta
  echo
  echo "Para mandar pelo git:"
  echo "  git add ${1#$REPO/}"
  echo "  git commit -m 'gdsii: etapa 12, $(basename "$1")'"
  echo "  git pull --rebase origin main && git push"
}

# Python do LibreLane (tem o modulo do KLayout: klayout.db / pya)
py_klayout () {
  local p
  # o librelane pode ser script (#!python) ou executavel binario (wrapper do Nix)
  p="$(head -c 300 "$(command -v librelane)" | tr -d '\000' | head -1)"
  case "$p" in '#!'*) p="${p#\#!}"; p="${p# }"; case "$p" in */env\ *) p="${p##* }";; esac;; *) p="";; esac
  for c in ${p:+"$p"} python3; do
    if "$c" -c "import klayout.db" 2>/dev/null; then echo "$c"; return; fi
  done
  echo ""
}

# drc_magic <gds> <rpt>: o mesmo DRC do Magic.DRC do LibreLane (drc(full),
# euclidiano), nucleo caixa-preta pelo maglef da L82 (gerado pelo 12_verifica.sh)
drc_magic () {
  local gds="$1" rpt="$2" w
  w="$(dirname "$rpt")"
  [ -f "$ENT/maglef/asic_top.mag" ] || { echo "ERRO: falta $ENT/maglef/asic_top.mag (rode o 12_verifica.sh)"; return 1; }
  cat > "$w/drc.tcl" <<TCL
crashbackups disable
locking disable
units internal
load $ENT/maglef/asic_top.mag
gds noduplicates true
gds readonly true
gds read $gds
set fout [open $rpt w]
set oscale [cif scale out]
load chip_top
select top cell
drc euclidean on
drc style drc(full)
drc check
puts \$fout "chip_top"
puts \$fout "----------------------------------------"
foreach {why coords} [drc listall why] {
    puts \$fout \$why
    puts \$fout "----------------------------------------"
    foreach co \$coords {
        puts \$fout [format " %.3fum %.3fum %.3fum %.3fum" [expr {\$oscale*[lindex \$co 0]}] [expr {\$oscale*[lindex \$co 1]}] [expr {\$oscale*[lindex \$co 2]}] [expr {\$oscale*[lindex \$co 3]}]]
    }
    puts \$fout "----------------------------------------"
}
close \$fout
quit -noprompt
TCL
  ( cd "$w" && magic -dnull -noconsole -rcfile "$RC" "$w/drc.tcl" > "$w/drc.log" 2>&1 ) || true
  [ -s "$rpt" ]
}
