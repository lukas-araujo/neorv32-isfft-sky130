#!/usr/bin/env bash
#=============================================================================
# 01_leitura.sh -- ETAPA 1: o LibreLane le o netlist do Genus
#
#   Inicia uma RODADA NOVA (nome = data e hora) e roda do comeco do fluxo
#   ate a STA antes do layout:
#     Yosys.Synthesis      com SYNTH_ELABORATE_ONLY: so le e achata o
#                          netlist, sem ressintetizar (L4)
#     Checker.*            celulas nao mapeadas, checagens de sintese,
#                          'assign' no netlist
#     OpenROAD.CheckSDCFiles / CheckMacroInstances (as 4 macros existem?)
#     OpenROAD.STAPrePNR   timing sem fios: tem que dar parecido com o Genus
#
#   Sem imagem: ainda nao ha layout. Sai um resumo em texto + metricas.
#
# Uso (dentro do nix-shell do LibreLane):
#   bash layout/nucleo/01_leitura.sh
#   NETLIST=<outro .v ou .v.gz> bash layout/nucleo/01_leitura.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

NETLIST="${NETLIST:-$REPO/resultados/2026-09-27_sintese_layout/deliverables/neorv32_isfft_soc.v.gz}"
[ -f "$NETLIST" ] || { echo "ERRO: netlist nao encontrado: $NETLIST"; exit 1; }

# Rodada nova
date +%Y-%m-%d_%H%M > "$ARQ_TAG"
echo ">>> rodada nova: $(rodada)"

# Netlist de entrada (o LibreLane nao le .gz no VERILOG_FILES)
mkdir -p "$NUCLEO/entrada"
case "$NETLIST" in
  *.gz) zcat "$NETLIST" > "$NUCLEO/entrada/asic_top.v" ;;
  *)    cp "$NETLIST" "$NUCLEO/entrada/asic_top.v" ;;
esac
N="$NUCLEO/entrada/asic_top.v"
echo ">>> netlist: ${NETLIST#$REPO/}"
echo "    constantes soltas (esperado 0): $(grep -oE "1'b[01]" "$N" | wc -l)"
echo "    celulas conb_1   (esperado 10): $(grep -c 'sky130_fd_sc_hd__conb_1 ' "$N")"
echo "    spare_wen0 ligado (esperado 2): $(grep -c '\.spare_wen0' "$N")"

roda_trecho - - OpenROAD.STAPrePNR

R="$(pasta_resultados)"
{
  echo "ETAPA 1 -- leitura do netlist ($(rodada))"
  echo "netlist: ${NETLIST#$REPO/}"
  S="$(dirname "$(estado_de Yosys.Synthesis)")"
  # (if, e nao '[ ] &&': com set -e, um teste falso no fim do bloco
  #  encerraria o script)
  if [ -f "$S/reports/stat.rpt" ]; then grep -E "Chip area|Number of cells" "$S/reports/stat.rpt" | head -3 || true; fi
  if [ -f "$S/reports/chk.rpt" ];  then grep -E "Found and reported" "$S/reports/chk.rpt" || true; fi
  ls "$S/reports" 2>/dev/null | sed 's/^/  relatorio: /' || true
} | tee "$R/01_leitura.txt"
echo ">>> metricas depois da STA sem fios:"
guarda_metricas OpenROAD.STAPrePNR 01_leitura

echo
echo "Esperado: 'Found and reported 0 problems', area da logica ~730.163 um2"
echo "(so celulas; as macros ficam fora), slack de setup positivo."
echo "Proximo: bash layout/nucleo/02_floorplan.sh"
