#!/usr/bin/env bash
#=============================================================================
# monta_vm.sh -- monta a pasta do projeto para a VM (Genus/Xcelium/Conformal)
#
# Mesmo formato do neorv32_sram_soc (projeto anterior):
#   frontend/  sw/  tech/{lib,lef,verilog}/  backend/synthesis/{scripts,
#   constraints,work,reports,deliverables,sim_rtl,sim_postsyn}/
#
# Uso:
#   bash sim/monta_vm.sh [destino]
#
#   TECH_SRC: onde estao as celulas sky130 (lib/, lef/, verilog/).
#             Padrao: tech/sky130/ do repositorio (copia do PDK).
#   destino : padrao build/vm/neorv32_isfft_soc (+ .tgz ao lado)
#
# Antes: build/neorv32_asic.v atualizado (sim/convert.sh) e os firmwares
# compilados (run_tb_evm.sh / run_tb_soc.sh ja fazem as duas coisas).
#
# Fonte de verdade dos scripts da VM: vm/ (este projeto). Nao edite a
# pasta montada -- edite vm/ e rode de novo.
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${1:-$PROJ/build/vm/neorv32_isfft_soc}"
TECH_SRC="${TECH_SRC:-$PROJ/tech/sky130}"
MACROS="sram_8kbyte_1rw_32x2048_8 sram_4kbyte_1rw_32x1024_8 sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2"

falta () { echo "FALTA: $1"; exit 1; }

#-----------------------------------------------------------------------------
# Conferencias antes de montar
#-----------------------------------------------------------------------------
[ -n "$TECH_SRC" ] || { echo "Defina TECH_SRC=<pasta tech/ com lib/ lef/ verilog/ do sky130>"; exit 1; }
for f in lib/sky130_fd_sc_hd__tt_025C_1v80.lib lef/sky130_fd_sc_hd.lef lef/sky130_ef_sc_hd.lef \
         verilog/primitives.v verilog/sky130_fd_sc_hd.v; do
  [ -f "$TECH_SRC/$f" ] || falta "$TECH_SRC/$f"
done
for m in $MACROS; do
  for e in .v .lef _TT_1p8V_25C.lib; do
    [ -f "$PROJ/macros/$m/${m}${e}" ] || falta "macros/$m/${m}${e}"
  done
done
[ -f "$PROJ/build/neorv32_asic.v" ] || falta "build/neorv32_asic.v (rode sim/convert.sh)"
grep -A2 "^ *neorv32_imem #(" "$PROJ/build/neorv32_asic.v" | grep -q "AWIDTH(31'b0000000000000000000000000001101)" \
  || { echo "ERRO: build/neorv32_asic.v nao tem a IMEM de 8 kB (AWIDTH 13). Rode sim/convert.sh."; exit 1; }
for a in isfft_evm hello; do
  [ -f "$PROJ/sw/$a/neorv32_raw_exe.hex" ] || falta "sw/$a/neorv32_raw_exe.hex (compile o firmware)"
done
[ -f "$PROJ/sw/isfft_evm/chk_rtl.txt" ] || falta "sw/isfft_evm/chk_rtl.txt"

#-----------------------------------------------------------------------------
# Estrutura
#-----------------------------------------------------------------------------
rm -rf "$DEST"
S="$DEST/backend/synthesis"
mkdir -p "$DEST"/frontend/isfft "$DEST"/sw/isfft_evm "$DEST"/sw/hello \
         "$DEST"/tech/lib "$DEST"/tech/lef "$DEST"/tech/verilog \
         "$S"/scripts/common "$S"/constraints "$S"/work "$S"/reports \
         "$S"/deliverables "$S"/sim_rtl "$S"/sim_postsyn

#-----------------------------------------------------------------------------
# frontend/: RTL do chip (so o que vai para a sintese)
#-----------------------------------------------------------------------------
GHDL_VER="$(ghdl --version 2>/dev/null | head -1)"
{
  echo "//============================================================================="
  echo "// neorv32_asic.v -- NEORV32 + ponte XBUS->AXI4 convertidos para Verilog"
  echo "//"
  echo "// GERADO pelo GHDL (sim/convert.sh do projeto). NAO EDITE: mude"
  echo "// rtl/soc/neorv32_asic.vhd e converta de novo."
  echo "//   NEORV32: commit 8bdbe48 (v1.13.5.6)   GHDL: ${GHDL_VER:-?}"
  echo "//   montado em: $(date '+%Y-%m-%d %H:%M')"
  echo "// IMEM/DMEM sao caixas-pretas aqui (neorv32_imem.v / neorv32_dmem.v)."
  echo "//============================================================================="
  cat "$PROJ/build/neorv32_asic.v"
} > "$DEST/frontend/neorv32_asic.v"

RTL_TOP="rtl/soc/asic_top.v rtl/neorv32_imem.v rtl/neorv32_dmem.v rtl/mem/sram8k_1rw.v
         rtl/mem/sram4k_1rw.v rtl/isfft/stream_32to64.v rtl/isfft/stream_64to32.v
         rtl/isfft/isfft_axi_v4.v"
for f in $RTL_TOP; do cp "$PROJ/$f" "$DEST/frontend/"; done
for f in "$PROJ"/rtl/isfft/core/*.v; do
  [ "$(basename "$f")" = isfft_axi_v3.v ] || cp "$f" "$DEST/frontend/isfft/"
done

#-----------------------------------------------------------------------------
# rtl_files.tcl: gerado da lista acima (Genus)
#-----------------------------------------------------------------------------
{
  echo "#-----------------------------------------------------------------------------"
  echo "# rtl_files.tcl -- fontes do chip para o Genus"
  echo "#"
  echo "# GERADO por sim/monta_vm.sh. TUDO Verilog: o NEORV32 ja vem convertido"
  echo "# (neorv32_asic.v, GHDL) -- sem biblioteca VHDL, sem ordem de analise."
  echo "#"
  echo "# NAO entram: modelos .v das macros (a macro vem do .lib, caixa-preta),"
  echo "# isfft_axi_v3 (referencia de simulacao), testbenches."
  echo "#-----------------------------------------------------------------------------"
  echo "set RTL_FILES [list \\"
  echo "  \${FRONTEND_DIR}/neorv32_asic.v \\"
  for f in $RTL_TOP; do echo "  \${FRONTEND_DIR}/$(basename "$f") \\"; done
  for f in "$DEST"/frontend/isfft/*.v; do echo "  \${ISFFT_RTL_DIR}/$(basename "$f") \\"; done
  echo "]"
} > "$S/scripts/rtl_files.tcl"

#-----------------------------------------------------------------------------
# sw/: firmwares (hex = 1 palavra de 32 bits por linha) e somas do RTL
#-----------------------------------------------------------------------------
cp "$PROJ/sw/isfft_evm/neorv32_raw_exe.hex" "$PROJ/sw/isfft_evm/chk_rtl.txt" "$DEST/sw/isfft_evm/"
cp "$PROJ/sw/hello/neorv32_raw_exe.hex" "$DEST/sw/hello/"

#-----------------------------------------------------------------------------
# tech/: celulas sky130 + 4 macros OpenRAM
#-----------------------------------------------------------------------------
cp "$TECH_SRC/lib/sky130_fd_sc_hd__tt_025C_1v80.lib" "$DEST/tech/lib/"
cp "$TECH_SRC/lef/sky130_fd_sc_hd.lef" "$TECH_SRC/lef/sky130_ef_sc_hd.lef" "$DEST/tech/lef/"
cp "$TECH_SRC/verilog/primitives.v" "$TECH_SRC/verilog/sky130_fd_sc_hd.v" "$DEST/tech/verilog/"
# Celulas proibidas no layout (lista do PDK do LibreLane; lida pelo tech.tcl)
cp "$PROJ/tech/sky130/drc_exclude.cells" "$DEST/tech/"
for m in $MACROS; do
  cp "$PROJ/macros/$m/${m}_TT_1p8V_25C.lib" "$DEST/tech/lib/"
  cp "$PROJ/macros/$m/${m}.lef" "$DEST/tech/lef/"
  cp "$PROJ/macros/$m/${m}.v" "$DEST/tech/verilog/"
done

# Correcao de 1 linha no arquivo do PDK: `endif sem // (so aparece com
# FUNCTIONAL, que a simulacao de portas precisa). Idempotente.
sed -i 's|^`endif SKY130_FD_SC_HD__LPFLOW_BLEEDER_FUNCTIONAL_V$|`endif  // SKY130_FD_SC_HD__LPFLOW_BLEEDER_FUNCTIONAL_V  (corrigido: faltava // -- ver DIARIO)|' \
    "$DEST/tech/verilog/sky130_fd_sc_hd.v"
if grep -q '^`endif [A-Z]' "$DEST/tech/verilog/sky130_fd_sc_hd.v"; then
  echo "ERRO: sobrou \`endif sem // no sky130_fd_sc_hd.v:"; grep -n '^`endif [A-Z]' "$DEST/tech/verilog/sky130_fd_sc_hd.v"; exit 1
fi

#-----------------------------------------------------------------------------
# scripts, SDC, LEIAME, DIARIO
#-----------------------------------------------------------------------------
# Tudo o que esta em vm/ vai para a pasta, na mesma posicao:
#   vm/backend/synthesis/   -> sintese do chip       (chat GDSII)
#   vm/backend/dft_isfft/   -> DFT so no IP da ISFFT (chat DFT)
#   vm/verification/        -> UVM do IP da ISFFT    (chat UVM)
# Cada chat so cria/edita a propria subpasta; este script nao muda.
cp -r "$PROJ"/vm/. "$DEST/"
cp "$PROJ"/DIARIO*.md "$DEST/"

#-----------------------------------------------------------------------------
# Pacote
#-----------------------------------------------------------------------------
( cd "$(dirname "$DEST")" && tar czf "$(basename "$DEST").tgz" "$(basename "$DEST")" )
echo "Pasta:  $DEST"
echo "Pacote: $DEST.tgz ($(du -h "$DEST.tgz" | cut -f1))"
echo "Arquivos: $(find "$DEST" -type f | wc -l)   RTL: $(ls "$DEST"/frontend/*.v "$DEST"/frontend/isfft/*.v | wc -l)"
