#!/usr/bin/env bash
#=============================================================================
# traz_uvm.sh -- traz os resultados do UVM (VM) para resultados/
#
# Mesmo fluxo do traz_vm.sh (que cuida da sintese):
#   1. na VM, rodou os blocos do verification/uvm_isfft/scripts/run_first_uvm.tcl
#   2. copia a pasta neorv32_isfft_soc/ (ou so verification/uvm_isfft/) para
#      o notebook
#   3. no notebook, na raiz do repositorio:
#        bash sim/traz_uvm.sh <pasta_copiada> [etapa]
#      ex.: bash sim/traz_uvm.sh ~/Downloads/neorv32_isfft_soc uvm_regressao
#   4. git add resultados/<data>_<etapa> && git commit && git push
#
# O que vem: reports/ inteiro (um log por teste, regressao.txt, cobertura,
# imc.log) e o work/isfft_dut.f (lista exata do DUT da rodada).
# O que NAO vem: work/xcelium.d, work/cov_work, work/cov_merged (o xrun e
# o IMC refazem; o que importa esta nos relatorios de texto).
# Arquivo acima de 500 kB vai compactado (.gz).
#
# Data da pasta: a do log mais novo (quando rodou), nao a de hoje.
# Etapa padrao: uvm.
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
ORIG="${1:-}"
ETAPA="${2:-uvm}"
[ -n "$ORIG" ] || { echo "Uso: bash sim/traz_uvm.sh <pasta_da_vm_copiada> [etapa]"; exit 1; }

if   [ -d "$ORIG/verification/uvm_isfft/reports" ]; then U="$ORIG/verification/uvm_isfft"
elif [ -d "$ORIG/reports" ] && [ -d "$ORIG/scripts" ]; then U="$ORIG"
else echo "ERRO: nao achei verification/uvm_isfft/reports/ em $ORIG"; exit 1; fi

ls "$U"/reports/* >/dev/null 2>&1 || { echo "ERRO: $U/reports/ vazio"; exit 1; }
NOVO="$(ls -t "$U"/reports/* | head -1)"
DATA="$(date -r "$NOVO" +%Y-%m-%d)"
DEST="$PROJ/resultados/${DATA}_${ETAPA}"
[ -e "$DEST" ] && { echo "ERRO: $DEST ja existe (nao sobrescrevo; use outra etapa)"; exit 1; }
mkdir -p "$DEST/reports"

cp -p "$U"/reports/* "$DEST/reports/"
[ -f "$U/work/isfft_dut.f" ] && cp -p "$U/work/isfft_dut.f" "$DEST/"
for f in "$DEST"/reports/*; do
  [ "$(stat -c %s "$f")" -gt 512000 ] && gzip -9 "$f"
done

echo "Destino: $DEST ($(find "$DEST" -type f | wc -l) arquivos, $(du -sh "$DEST" | cut -f1))"
if [ -f "$DEST/reports/regressao.txt" ]; then
  echo "Regressao: $(grep -c PASSOU "$DEST/reports/regressao.txt") PASSOU, $(grep -c FALHOU "$DEST/reports/regressao.txt") FALHOU"
fi
for L in "$DEST"/reports/*_test*.log; do
  [ -f "$L" ] || continue
  if grep -q "TESTE PASSOU" "$L"; then r=PASSOU; else r=FALHOU; fi
  printf "  %-40s %s\n" "$(basename "$L")" "$r"
done
grep -h "UVM: " "$DEST"/reports/*.log 2>/dev/null | head -1 | sed 's/^/Versao do UVM: /'
echo
echo "git add resultados/${DATA}_${ETAPA} && git commit -m \"uvm: resultados da VM -- ${ETAPA}\" && git push"
