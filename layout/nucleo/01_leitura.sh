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

# Netlist do Genus, descompactado
E="$NUCLEO/entrada"
mkdir -p "$E"
case "$NETLIST" in
  *.gz) zcat "$NETLIST" > "$E/asic_top_genus.v" ;;
  *)    cp "$NETLIST" "$E/asic_top_genus.v" ;;
esac
N="$E/asic_top_genus.v"
echo ">>> netlist: ${NETLIST#$REPO/}"
echo "    constantes soltas (esperado 0): $(grep -oE "1'b[01]" "$N" | wc -l)"
echo "    celulas conb_1   (esperado 10): $(grep -c 'sky130_fd_sc_hd__conb_1 ' "$N")"
echo "    spare_wen0 ligado (esperado 2): $(grep -c '\.spare_wen0' "$N")"

#-----------------------------------------------------------------------------
# Achatar ANTES do LibreLane (L19 -- DIARIO_GDSII, 9a sessao)
#
# O netlist do Genus e hierarquico (200 modulos). O LibreLane achata e marca
# todo fio com 'keep': cada porta de submodulo vira um 'assign' entre o nome
# de fora e o de dentro (25.960!) e o Checker.NetlistAssignStatements para
# o fluxo. Achatando aqui SEM 'keep', o opt_clean funde os nomes duplicados:
#   flatten -> splitnets (1 bit por fio) -> opt_clean -purge  => 0 assign
# So renomeia/funde fios; a conferencia abaixo prova (pino a pino) que a
# ligacao e a mesma do netlist do Genus.
#-----------------------------------------------------------------------------
LIBS="read_liberty -lib $REPO/tech/sky130/lib/sky130_fd_sc_hd__tt_025C_1v80.lib"
for m in "$REPO"/macros/*/*_TT_1p8V_25C.lib; do LIBS="$LIBS
read_liberty -lib $m"; done

echo ">>> achatando o netlist do Genus (Yosys)..."
yosys -q -l "$E/achata.log" -p "$LIBS
read_verilog $E/asic_top_genus.v
hierarchy -check -top asic_top
flatten -noscopeinfo
splitnets
opt_clean -purge
tee -q -o $E/achata_stat.rpt stat -liberty $REPO/tech/sky130/lib/sky130_fd_sc_hd__tt_025C_1v80.lib
write_verilog -noattr -noexpr -nohex -nodec $E/asic_top.v" > /dev/null
echo "    assign no netlist achatado (esperado 0): $(grep -c '^\s*assign' "$E/asic_top.v" || true)"
grep -E "Chip area" "$E/achata_stat.rpt" | sed 's/^ */    /'

echo ">>> celulas proibidas no layout (tech/sky130/drc_exclude.cells):"
python3 - "$REPO/tech/sky130/drc_exclude.cells" "$E/asic_top.v" <<'PY' | tee "$E/proibidas.txt"
import re, sys, collections
pats = [re.compile("^" + l.strip().replace("*", ".*") + "$")
        for l in open(sys.argv[1]) if l.strip() and not l.startswith("#")]
usadas = collections.Counter(re.findall(r"^\s*(sky130_fd_sc_hd__\w+)\s", open(sys.argv[2]).read(), re.M))
ruins = {c: n for c, n in usadas.items() if any(p.match(c) for p in pats)}
for c, n in sorted(ruins.items(), key=lambda x: -x[1]):
    print(f"    {c:34s} {n}")
print(f"    total: {sum(ruins.values())} instancias (esperado 0; L20: avoid no Genus)")
PY

echo ">>> conferindo: mesma ligacao em todos os pinos?"
for x in genus:asic_top_genus.v plano:asic_top.v; do
  yosys -q -p "$LIBS
read_verilog $E/${x#*:}
hierarchy -top asic_top
flatten -noscopeinfo
splitnets -ports
write_verilog -noattr -noexpr -nohex -nodec $E/bits_${x%%:*}.v" > /dev/null
done
python3 "$NUCLEO/compara_ligacoes.py" "$E/bits_genus.v" "$E/bits_plano.v" | tee "$E/compara.txt" | sed 's/^/    /'
grep -q "RESULTADO: IGUAIS" "$E/compara.txt" || { echo "ERRO: o achatamento mudou alguma ligacao. Nao sigo."; exit 1; }
rm -f "$E"/bits_*.v

roda_trecho - - OpenROAD.STAPrePNR

R="$(pasta_resultados)"
{
  echo "ETAPA 1 -- leitura do netlist ($(rodada))"
  echo "netlist: ${NETLIST#$REPO/}"
  echo "achatamento (L19):"; sed 's/^/  /' "$E/compara.txt"
  echo "celulas proibidas no layout (L20):"; sed 's/^ */  /' "$E/proibidas.txt"
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
