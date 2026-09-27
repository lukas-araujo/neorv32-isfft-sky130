#!/usr/bin/env bash
#=============================================================================
# traz_vm.sh -- traz os resultados de uma rodada da VM para resultados/
#
# Projeto: NEORV32 + ISFFT em ASIC (sky130)
#
# A VM nao tem git. Fluxo:
#   1. na VM, rodou os blocos do run_first.tcl;
#   2. copia a pasta neorv32_isfft_soc/ (ou so backend/) da VM para o
#      notebook, do jeito de sempre;
#   3. no notebook, na raiz do repositorio:
#        bash sim/traz_vm.sh <pasta_copiada> <etapa>
#      ex.: bash sim/traz_vm.sh ~/Downloads/neorv32_isfft_soc sintese_layout
#   4. git add resultados/<data>_<etapa> && git commit && git push
#
# O que vem (so o que e resultado; o resto a VM refaz):
#   reports/*.rpt           relatorios do Genus e do LEC
#   deliverables/*.v .sdc .do   netlist, SDC escrito pelo Genus, dofile do LEC
#   logs: genus.log, xrun_*.log (RTL e pos-sintese), *_lec*.log
# O que NAO vem: .sdf (27 MB, o Genus refaz), xcelium.d/, work/fv*,
# bancos do LEC -- ver .gitignore.
# Arquivo acima de 500 kB e compactado (.gz): o netlist tem 8 MB, o
# genus.log ~4 MB. 'zcat' ou 'zless' para ler.
#
# Data da pasta: a do netlist (quando o Genus rodou), nao a de hoje.
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="${1:-}"
ETAPA="${2:-}"

[ -n "$ORIG" ] && [ -n "$ETAPA" ] || {
  echo "Uso: bash sim/traz_vm.sh <pasta_da_vm_copiada> <etapa>"
  echo "  ex.: bash sim/traz_vm.sh ~/Downloads/neorv32_isfft_soc sintese_layout"
  exit 1; }

# Aceita a pasta do projeto inteira ou so backend/synthesis
if   [ -d "$ORIG/backend/synthesis" ]; then S="$ORIG/backend/synthesis"
elif [ -d "$ORIG/reports" ];           then S="$ORIG"
else echo "ERRO: nao achei backend/synthesis/ nem reports/ em $ORIG"; exit 1; fi

NET=$(ls "$S"/deliverables/*.v 2>/dev/null | head -1)
[ -n "$NET" ] || { echo "ERRO: sem netlist em $S/deliverables/ -- o Genus rodou?"; exit 1; }
DATA=$(date -r "$NET" +%Y-%m-%d)
DEST="$PROJ/resultados/${DATA}_${ETAPA}"

if [ -e "$DEST" ]; then
  echo "ERRO: $DEST ja existe. Apague ou escolha outra etapa."; exit 1
fi
mkdir -p "$DEST"/reports "$DEST"/deliverables "$DEST"/logs

copia () {  # copia $1 para a pasta $2, compactando se > 500 kB
  local f="$1" d="$2"
  [ -f "$f" ] || return 0
  if [ "$(stat -c %s "$f")" -gt 512000 ]; then
    gzip -9c "$f" > "$d/$(basename "$f").gz"
  else
    cp "$f" "$d/"
  fi
}

for f in "$S"/reports/*.rpt;                  do copia "$f" "$DEST/reports"; done
for f in "$S"/deliverables/*.v "$S"/deliverables/*.sdc "$S"/deliverables/*.do; do
  copia "$f" "$DEST/deliverables"; done
copia "$S/work/genus.log"                        "$DEST/logs"
for f in "$S"/sim_rtl/xrun_*.log "$S"/sim_postsyn/xrun_*.log \
         "$S"/reports/*lec*.log "$S"/work/*lec*.log; do
  copia "$f" "$DEST/logs"; done
# xrun.log: o proprio xrun grava em cada pasta de simulacao. Tem o mesmo
# conteudo do log do tee MAIS a linha de comando completa (defines e
# arquivos). Vem renomeado para nao sobrescrever um ao outro.
for p in sim_rtl sim_postsyn; do
  [ -f "$S/$p/xrun.log" ] || continue
  cp "$S/$p/xrun.log" "$DEST/logs/xrun_${p#sim_}_comando.log"
done

# Resumo para conferir antes do commit
echo "Destino: resultados/${DATA}_${ETAPA}"
( cd "$DEST" && find . -type f | sort | sed 's|^\./|  |' )
echo "Tamanho: $(du -sh "$DEST" | cut -f1)"
echo
Q="$S/reports/$(basename "${NET%.v}")_qor.rpt"
[ -f "$Q" ] && grep -E "clk_i +[-0-9]|Cell Area|Leaf Instance Count" "$Q" | sed 's/^/  /'
echo
echo "Proximo:"
echo "  git add resultados/${DATA}_${ETAPA}"
echo "  git commit -m \"gdsii: resultados da VM -- ${ETAPA}\""
echo "  git push"
