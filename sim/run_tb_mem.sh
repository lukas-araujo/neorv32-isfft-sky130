#!/usr/bin/env bash
#=============================================================================
# run_tb_mem.sh -- verifica os substitutos IMEM/DMEM com macro OpenRAM
#
# 1. Converte o VHDL OFICIAL (neorv32_dmem.vhd, neorv32_imem.vhd) para
#    Verilog com 'ghdl synth' -- vira a referencia de ouro.
# 2. Simula DUT x referencia no Icarus Verilog em 3 configuracoes:
#    DMEM 4 kB (AWIDTH 12), IMEM 8 kB (AWIDTH 13) como RAM e como ROM.
# 3. Roda 5 MUTACOES do DUT (copias alteradas por sed, fora da arvore rtl/).
#    Cada mutacao TEM que falhar; se passar, o testbench nao enxerga o defeito.
#
# Uso:   NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_mem.sh
# Precisa: ghdl (>= 4, com synth), iverilog
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
NEORV32_HOME="${NEORV32_HOME:-$HOME/Projects/neorv32}"
CORE="$NEORV32_HOME/rtl/core"
MACRO_V="$PROJ/macros/sram_4kbyte_1rw_32x1024_8/sram_4kbyte_1rw_32x1024_8.v $PROJ/macros/sram_8kbyte_1rw_32x2048_8/sram_8kbyte_1rw_32x2048_8.v"
B="$PROJ/sim/build_mem"
rm -rf "$B"; mkdir -p "$B"

# Ferramentas. No notebook elas vem do OSS CAD Suite: rode num terminal
# NOVO -- o env_openram.sh tira o OSS CAD Suite do PATH de proposito.
for t in ghdl iverilog vvp; do
  command -v $t >/dev/null || {
    echo "ERRO: '$t' nao encontrado no PATH."
    echo "  Abra um terminal novo (sem env_openram.sh) ou:"
    echo "  export PATH=/tools/oss-cad-suite/bin:\$PATH"
    exit 1; }
done
ghdl --help 2>&1 | grep -q "^ *synth" || { echo "ERRO: este ghdl nao tem 'synth'"; exit 1; }
echo "ghdl:     $(command -v ghdl)"
echo "iverilog: $(command -v iverilog)"
echo

for f in "$CORE/neorv32_dmem.vhd" $MACRO_V; do
  [ -f "$f" ] || { echo "FALTA: $f"; exit 1; }
done

#-----------------------------------------------------------------------------
# 1. Referencias pelo GHDL
#-----------------------------------------------------------------------------
echo "=== 1. Referencias: VHDL oficial -> Verilog (ghdl synth) ==="
cd "$B"
ghdl -a --std=08 --work=neorv32 \
  "$CORE/neorv32_package.vhd" "$CORE/neorv32_prim.vhd" \
  "$CORE/neorv32_imem_image.vhd" \
  "$CORE/neorv32_dmem.vhd" "$CORE/neorv32_imem.vhd" || exit 1

ref () {  # entidade  arquivo_saida  generics...
  local ent="$1" out="$2"; shift 2
  ghdl synth --std=08 --work=neorv32 "$@" --out=verilog "$ent" 2>/dev/null \
    | sed "s/^module ${ent}\b/module ref_mem/" > "$out"
  grep -q "^module ref_mem" "$out" || { echo "ghdl synth falhou: $ent $*"; exit 1; }
  echo "  $out  ($(grep -c '^module' "$out") modulos)"
}
ref neorv32_dmem ref_dmem.v     -gAWIDTH=12 -gOUTREG=false
ref neorv32_imem ref_imem_ram.v -gAWIDTH=13 -gINITROM=false -gOUTREG=false
ref neorv32_imem ref_imem_rom.v -gAWIDTH=13 -gINITROM=true  -gOUTREG=false

# Imagem da ROM: extraida do MESMO pacote VHDL que a referencia usou
grep -oE 'x"[0-9a-fA-F]{8}"' "$CORE/neorv32_imem_image.vhd" | tr -d 'x"' > rom_image.hex
ROM_BYTES=$(grep -oE 'image_size_c *: *natural *:= *[0-9]+' "$CORE/neorv32_imem_image.vhd" | grep -oE '[0-9]+$')
ROM_WORDS=$(( ROM_BYTES / 4 ))
echo "  imagem da ROM: $ROM_BYTES bytes = $ROM_WORDS palavras"

#-----------------------------------------------------------------------------
# 2. Simulacoes
#-----------------------------------------------------------------------------
RTL="$PROJ/rtl/mem/sram4k_1rw.v $PROJ/rtl/mem/sram8k_1rw.v $PROJ/rtl/neorv32_dmem.v $PROJ/rtl/neorv32_imem.v"

roda () {  # nome  define  ref  [arquivos_rtl]
  local nome="$1" def="$2" rf="$3"; shift 3
  local aw=13; [ "$def" = DUT_DMEM ] && aw=12     # DMEM 4 kB, IMEM 8 kB
  local rtl="${*:-$RTL}"
  iverilog -g2012 -o "$nome.vvp" -D"$def" \
      -DROM_HEX="\"$B/rom_image.hex\"" -DROM_WORDS=$ROM_WORDS -DMEM_AWIDTH=$aw \
      -Ptb_mem_equiv.N_ACC=20000 \
      $rtl $MACRO_V "$B/$rf" "$PROJ/tb/tb_mem_equiv.v" 2> "$nome.compile.log" \
    || { echo "  $nome: ERRO DE COMPILACAO"; cat "$nome.compile.log"; return 2; }
  # o modelo da OpenRAM imprime cada acesso (VERBOSE=1): filtra
  vvp -n "$nome.vvp" | grep -E "^\[TB\]|ERRO" > "$nome.log"
  if grep -q "PASSOU" "$nome.log"; then return 0; else return 1; fi
}

echo
echo "=== 2. DUT x referencia ==="
FALHOU=0
for cfg in "dmem DUT_DMEM ref_dmem.v" \
           "imem_ram DUT_IMEM ref_imem_ram.v" \
           "imem_rom DUT_IMEM_ROM ref_imem_rom.v"; do
  set -- $cfg
  if roda "$1" "$2" "$3"; then r="PASSOU"; else r="FALHOU"; FALHOU=1; fi
  echo "--- $1: $r"
  [ -f "$1.log" ] && sed 's/^/    /' "$1.log" | grep -v "PASSOU\|FALHOU"
done

#-----------------------------------------------------------------------------
# 3. Mutacoes -- cada uma TEM que ser pega
#-----------------------------------------------------------------------------
echo
echo "=== 3. Mutacoes (esperado: todas DETECTADAS) ==="
mkdir -p mut
muta () {  # nome  arquivo_origem  sed  config
  local nome="$1" src="$2" expr="$3" def="$4" rf="$5"
  mkdir -p "mut/$nome"
  cp "$PROJ/rtl/mem/sram4k_1rw.v" "$PROJ/rtl/mem/sram8k_1rw.v" "$PROJ/rtl/neorv32_dmem.v" "$PROJ/rtl/neorv32_imem.v" "mut/$nome/"
  sed -i "$expr" "mut/$nome/$src"
  if cmp -s "mut/$nome/$src" "$PROJ/rtl/$(case $src in sram*) echo mem/;; esac)$src"; then
    echo "  $nome: sed nao alterou nada -- mutacao invalida"; FALHOU=1; return
  fi
  roda "mut_$nome" "$def" "$rf" mut/$nome/sram4k_1rw.v mut/$nome/sram8k_1rw.v mut/$nome/neorv32_dmem.v mut/$nome/neorv32_imem.v
  case $? in
    0) echo "  $nome: NAO DETECTADA  <-- o testbench tem um ponto cego"; FALHOU=1 ;;
    1) echo "  $nome: detectada -> $(grep -m1 ERRO mut_$nome.log | sed 's/^\[[0-9]*\] //' | cut -c1-70)" ;;
    *) echo "  $nome: nao compilou -- mutacao invalida"; FALHOU=1 ;;
  esac
}
muta sem_wrack     neorv32_dmem.v 's/assign rsp_ack_o  = rdack | wrack;/assign rsp_ack_o  = rdack;/' DUT_DMEM ref_dmem.v
muta ignora_ben    neorv32_dmem.v 's/\.ben_i   (req_ben_i)/.ben_i   (4'"'"'hF)/'                   DUT_DMEM ref_dmem.v
muta sem_portao    neorv32_dmem.v 's/rdack ? rdata : 32'"'"'h0000_0000/rdata/'                      DUT_DMEM ref_dmem.v
muta imem_4k_addr neorv32_imem.v 's/\.addr_i  (req_addr_i\[12:2\])/.addr_i  ({1'"'"'b0, req_addr_i[11:2]})/' DUT_IMEM ref_imem_ram.v
muta rom_escreve   neorv32_imem.v 's/acesso = req_stb_i & ~(ROM & req_rw_i)/acesso = req_stb_i/' DUT_IMEM_ROM ref_imem_rom.v

echo
if [ $FALHOU -eq 0 ]; then echo "=== RESULTADO: TUDO OK ==="; else echo "=== RESULTADO: HA FALHAS ==="; fi
exit $FALHOU
