#!/usr/bin/env bash
#=============================================================================
# traz_dft.sh -- traz os resultados da frente de DFT da VM para resultados/
#
# DIARIO_DFT. Mesmo fluxo do traz_vm.sh (sintese do chip) e do traz_uvm.sh:
#   1. na VM, rodou os blocos do run_first_dft.tcl;
#   2. copia a pasta neorv32_isfft_soc/ (ou so backend/dft_isfft/) para o
#      notebook;
#   3. na raiz do repositorio:
#        bash sim/traz_dft.sh <pasta_copiada> <etapa>
#      ex.: bash sim/traz_dft.sh ~/Downloads/neorv32_isfft_soc scan
#   4. git add resultados/<data>_dft_<etapa> && git commit && git push
#
# O que vem: reports/ (Genus, LEC, log do Modus), deliverables/ (netlist,
# SDC, scandef, dofile), logs (genus.log, xrun, lec), e de modus_work/ so o
# que e texto pequeno (scripts e pinassign que o Genus escreveu, logs do
# Modus). O banco do Modus (tbdata/, testresults/ grandes) NAO vem: refaz.
# Arquivo acima de 500 kB vai compactado (.gz).
# Data da pasta: a do netlist (quando o Genus rodou).
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="${1:-}"; ETAPA="${2:-}"
[ -n "$ORIG" ] && [ -n "$ETAPA" ] || {
  echo "Uso: bash sim/traz_dft.sh <pasta_da_vm_copiada> <etapa>"; exit 1; }

if   [ -d "$ORIG/backend/dft_isfft" ]; then S="$ORIG/backend/dft_isfft"
elif [ -d "$ORIG/reports" ] && [ -d "$ORIG/scripts" ]; then S="$ORIG"
else echo "ERRO: nao achei backend/dft_isfft/ em $ORIG"; exit 1; fi

NET="$S/deliverables/isfft_dft.v"
[ -f "$NET" ] || { echo "ERRO: sem $NET -- o Genus (bloco 1) rodou?"; exit 1; }
DATA=$(date -r "$NET" +%Y-%m-%d)
DEST="$PROJ/resultados/${DATA}_dft_${ETAPA}"
[ -e "$DEST" ] && { echo "ERRO: $DEST ja existe. Apague ou escolha outra etapa."; exit 1; }
mkdir -p "$DEST"/reports "$DEST"/deliverables "$DEST"/logs "$DEST"/modus

copia () {  # $1 -> pasta $2, compactando se > 500 kB
  [ -f "$1" ] || return 0
  if [ "$(stat -c %s "$1")" -gt 512000 ]; then gzip -9c "$1" > "$2/$(basename "$1").gz"
  else cp "$1" "$2/"; fi
}

for f in "$S"/reports/*; do copia "$f" "$DEST/reports"; done
for f in "$S"/deliverables/*; do copia "$f" "$DEST/deliverables"; done
copia "$S/work/genus.log" "$DEST/logs"
for f in "$S"/work/*lec*.log "$S"/sim_kria/*.log; do copia "$f" "$DEST/logs"; done
# modus_work: so arquivos de texto do nivel de cima e logs (sem os bancos)
if [ -d "$S/modus_work" ]; then
  find "$S/modus_work" -maxdepth 1 -type f -size -5M | while read -r f; do
    file -b "$f" | grep -qi text && copia "$f" "$DEST/modus"; done
  find "$S/modus_work" -type f \( -name "*.log" -o -name "log_*" \) -size -20M | while read -r f; do
    copia "$f" "$DEST/modus"; done
  ls "$S/modus_work" > "$DEST/modus/conteudo_modus_work.txt"
fi

echo "Trazido para: resultados/${DATA}_dft_${ETAPA}/"
find "$DEST" -type f | sed "s|$PROJ/||" | sort
echo
echo "git add resultados/${DATA}_dft_${ETAPA} && git commit -m \"dft: resultados da VM -- $ETAPA\" && git push"
