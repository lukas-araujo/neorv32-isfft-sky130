#!/usr/bin/env bash
#=============================================================================
# 09_netlist.sh -- ETAPA 9 (parte do notebook): netlist do layout para a VM
#
#   A etapa 9 prova, na VM, que o layout e o MESMO circuito que saiu da
#   sintese e que ele FUNCIONA:
#     LEC (Conformal)   netlist do Genus (achatado) x netlist do layout
#                       e, de quebra, RTL x netlist do layout
#     Simulacao (Xcelium) netlist do layout com o firmware das 3 matrizes:
#                       as somas tem de ser as do RTL
#
#   Este script so prepara os arquivos (nao precisa do nix-shell):
#     1. pega o netlist final da rodada (asic_top.nl.v, o do FillInsertion,
#        o mesmo que o LVS conferiu contra o GDS)
#     2. tira as celulas so fisicas (fill/decap/tap/diodo): tira_fisicas.py
#     3. confere flip-flops e macros contra o golden (tem de bater)
#     4. poe os dois netlists, compactados, em
#          vm/backend/synthesis/netlist_layout/
#            asic_top_layout.v.gz      revised do LEC e DUT da simulacao
#            asic_top_genus_flat.v.gz  golden do LEC (o netlist do Genus
#                                      que ENTROU no layout, achatado pelo
#                                      01_leitura.sh -- mesmos nomes)
#     5. resumo em resultados/<rodada>_layout_nucleo/09_netlist.txt
#
#   Depois: git add/commit/push, bash sim/monta_vm.sh e, na VM, os blocos
#   4a/4b/4c do run_first.tcl.
#
#   SIM_ICARUS=1: tambem simula o netlist do layout no Icarus antes da VM
#   (sim/run_gls_yosys.sh com NETLIST=...; ~30 min, precisa da pasta da VM
#   montada em build/vm/).
#
# Uso:  bash layout/nucleo/09_netlist.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"

ult=""
for p in Misc.ReportManufacturability Checker.LVS Netgen.LVS OpenROAD.IRDropReport OpenROAD.STAPostPNR; do
  if [ -n "$(estado_de "$p")" ]; then ult="$p"; break; fi
done
[ -n "$ult" ] || { echo "ERRO: a rodada $(rodada) nao chegou ao fim da etapa 7/8"; exit 1; }
NL="$(visao_de "$(estado_de "$ult")" nl)"
[ -f "$NL" ] || { echo "ERRO: netlist final nao encontrado ($NL)"; exit 1; }
GOLD="$NUCLEO/entrada/asic_top.v"
[ -f "$GOLD" ] || { echo "ERRO: falta $GOLD (o netlist achatado do 01_leitura.sh)"; exit 1; }

D="$REPO/vm/backend/synthesis/netlist_layout"
mkdir -p "$D"
RES="$(pasta_resultados)"
T="$(mktemp -d)"
echo ">>> netlist do layout: ${NL#$REPO/}  (estado de $ult)"
echo ">>> golden:            ${GOLD#$REPO/}"

r=0
python3 "$NUCLEO/tira_fisicas.py" "$NL" "$T/asic_top_layout.v" "$GOLD" > "$T/resumo.md" || r=$?
gzip -9c "$T/asic_top_layout.v" > "$D/asic_top_layout.v.gz"
gzip -9c "$GOLD" > "$D/asic_top_genus_flat.v.gz"
{
  echo "== Etapa 9: netlists para a VM (rodada $(rodada))"
  echo "   layout: ${NL#$REPO/} ($(du -h "$NL" | cut -f1))"
  echo "   golden: ${GOLD#$REPO/} ($(du -h "$GOLD" | cut -f1))"
  echo "   saida:  ${D#$REPO/}/ ($(du -ch "$D"/*.gz | tail -1 | cut -f1) compactados)"
  echo
  cat "$T/resumo.md"
  echo
  echo "   portas do topo (layout): $(grep -m1 -A4 '^module asic_top' "$T/asic_top_layout.v" | tr -s ' \n' ' ')"
  echo "   assign no layout: $(grep -c '^\s*assign' "$T/asic_top_layout.v" || true)"
} > "$RES/09_netlist.txt"
sed 's/^/    /' "$RES/09_netlist.txt"
[ $r -eq 0 ] || { echo "ERRO: flip-flops ou macros nao batem (veja a tabela)"; exit 1; }

if [ "${SIM_ICARUS:-0}" = 1 ]; then
  echo ">>> simulacao do netlist do layout no Icarus (sim/run_gls_yosys.sh)"
  NETLIST="$T/asic_top_layout.v" bash "$REPO/sim/run_gls_yosys.sh" \
    | tee "$RES/09_icarus.txt" || true
fi
rm -rf "$T"

echo
echo "Depois:"
echo "  git add vm/backend/synthesis/netlist_layout ${RES#$REPO/}/09_netlist.txt"
echo "  git commit -m 'gdsii: netlist do layout para a VM (etapa 9)' && git push"
echo "  bash sim/monta_vm.sh   e leve para a VM: backend/synthesis/scripts/ e backend/synthesis/netlist_layout/"
