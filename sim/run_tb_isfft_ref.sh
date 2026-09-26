#!/usr/bin/env bash
#=============================================================================
# run_tb_isfft_ref.sh -- regressao da Kria: ISFFT x wrapper da etapa 1
#
# O tb_isfft_axi_v3.v e o mesmo da Kria (nao e alterado). A referencia e o
# isfft_axi_wrapper da etapa 1 (rtl/isfft/ref/, fora do chip). Roda:
#   1. isfft_axi_v3  (flip-flops, a da Kria)
#   2. isfft_axi_v4  (in_mem e out_mem em macro OpenRAM -- a do chip)
#   3. mutacoes da v4 (so se 1 e 2 passarem)
#   4. nucleo original (Kria) x nucleo com a correcao do ASIC (D34):
#      todas as palavras de saida identicas
# Para a v4, o tb e copiado para build/ com o nome do modulo trocado e o
# VERBOSE das macros desligado.
#
# Uso: bash sim/run_tb_isfft_ref.sh          (precisa de iverilog)
#      SO=v3 ou SO=v4 roda so uma versao, sem mutacoes
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/sim/build_isfft_ref"
rm -rf "$B"; mkdir -p "$B/mut"
command -v iverilog >/dev/null || { echo "ERRO: iverilog fora do PATH"; exit 1; }

CORE="$PROJ/rtl/isfft/core"
V4="$PROJ/rtl/isfft/isfft_axi_v4.v"
MACROS="$PROJ/macros/sram_1rw1r_64x64_wpr2/sram_1rw1r_64x64_wpr2.v $PROJ/macros/sram_1rw1r_64x256/sram_1rw1r_64x256.v"
for f in $V4 $MACROS; do [ -f "$f" ] || { echo "FALTA: $f"; exit 1; }; done

# tb da v4: mesmo arquivo da Kria, so o modulo do DUT trocado
sed -e 's/^\(\s*\)isfft_axi_v3 dut (/\1isfft_axi_v4 dut (/' \
    -e 's/^endmodule/    defparam dut.u_in_mem.VERBOSE = 0;\n    defparam dut.u_out_mem.VERBOSE = 0;\nendmodule/' \
    "$PROJ/tb/ref/tb_isfft_axi_v3.v" > "$B/tb_isfft_axi_v4.v"
grep -q "isfft_axi_v4 dut" "$B/tb_isfft_axi_v4.v" || { echo "ERRO: sed do tb da v4"; exit 1; }

roda () {  # nome tb arquivos...
  local nome="$1" tb="$2"; shift 2
  iverilog -g2012 -o "$B/$nome.vvp" "$CORE"/*.v "$@" \
    "$PROJ/rtl/isfft/ref/isfft_axi_wrapper.v" "$tb" 2> "$B/$nome.compile.log" \
    || { echo "  $nome: ERRO DE COMPILACAO"; cat "$B/$nome.compile.log"; return 2; }
  # limite de tempo: mutacao pode travar o fluxo (travar tambem e detectar)
  timeout "${LIMITE:-30}" vvp -n "$B/$nome.vvp" > "$B/$nome.log"
  [ $? -eq 124 ] && echo "ERRO: travou (limite de ${LIMITE:-30} s)" >> "$B/$nome.log"
  grep -q "^PASSOU" "$B/$nome.log"
}

FALHOU=0
for v in v3 v4; do
  [ -n "${SO:-}" ] && [ "$SO" != "$v" ] && continue
  if [ $v = v3 ]; then roda v3 "$PROJ/tb/ref/tb_isfft_axi_v3.v"
  else                 roda v4 "$B/tb_isfft_axi_v4.v" "$V4" $MACROS; fi
  r=$?
  echo "=== isfft_axi_$v: $([ $r -eq 0 ] && echo PASSOU || echo FALHOU)"
  grep -E "^(Fase|  |PASSOU|FALHOU|ERRO)" "$B/$v.log" | head -12 | sed 's/^/    /'
  [ $r -eq 0 ] || FALHOU=1
done
[ -n "${SO:-}" ] && exit $FALHOU
[ $FALHOU -eq 0 ] || { echo "Versao correta falhou: mutacoes nao sao avaliadas."; exit 1; }

#-----------------------------------------------------------------------------
# Mutacoes da v4 -- cada uma TEM que falhar
#-----------------------------------------------------------------------------
echo
echo "=== Mutacoes da v4 (esperado: todas DETECTADAS) ==="
muta () {  # nome sed
  local nome="$1" expr="$2" f="$B/mut/$1.v"
  sed "$expr" "$V4" > "$f"
  cmp -s "$f" "$V4" && { echo "  $nome: sed nao alterou nada"; FALHOU=1; return; }
  roda "mut_$nome" "$B/tb_isfft_axi_v4.v" "$f" $MACROS
  case $? in
    0) echo "  $nome: NAO DETECTADA  <-- ponto cego"; FALHOU=1 ;;
    1) echo "  $nome: detectada -> $(grep -m1 -E 'ERRO|FALHA|travou' "$B/mut_$nome.log" | cut -c1-70)" ;;
    *) echo "  $nome: nao compilou"; FALHOU=1 ;;
  esac
}
# next_in fora de fase com o dado (so o dado atrasado, o next_in nao)
muta next_in_sem_atraso  's/else        core_next_in <= launch_active \& (launch_cnt\[1:0\] == 2.d0);/else        core_next_in <= launch_active \& (launch_cnt[1:0] == 2'"'"'d3);/'
# pre-busca ignora a ocupacao do buffer: sobrescreve palavra ainda nao entregue
muta busca_sem_limite    's/((ob_ocup != 2.d2) | out_hs)/1'"'"'b1/'
# buffer de saida perde a ordem: chegada com 1 palavra vai para q0
muta buffer_ordem        's/else              ob_q1 <= out_rdata;/else              ob_q0 <= out_rdata;/'
# busca pelo ponteiro de ENTREGA em vez do ponteiro de busca
muta ponteiro_errado     's/\.addr1 (ram_rd_ptr\[OUT_AW-1:0\]),/.addr1 (out_rd_ptr[OUT_AW-1:0]),/'
# in_mem lida sem esperar a macro: core_x pega o dado 1 ciclo cedo demais
muta in_mem_sem_espera   's/        if (in_rd_v)$/        if (in_rd_en)/'

#-----------------------------------------------------------------------------
# Nucleo original (Kria) x nucleo com a correcao do ASIC (D34)
#
# O nucleo em rtl/isfft/core tem 1 linha a mais em 10 codeBlocks
# (next <= 0 no reset). Aqui o original e reconstruido tirando essa linha,
# e as duas versoes da v4 rodam o mesmo tb gravando TODAS as palavras de
# saida: os dois arquivos tem que ser identicos.
#-----------------------------------------------------------------------------
echo
echo "=== Nucleo original (Kria) x corrigido (D34): saidas identicas? ==="
mkdir -p "$B/core_orig" "$B/eq_orig" "$B/eq_novo"
for f in "$CORE"/*.v; do sed '/ASIC: frame sync limpo no reset/d' "$f" > "$B/core_orig/$(basename "$f")"; done
n=$(cat "$CORE"/*.v | grep -c "ASIC: frame sync limpo no reset")
m=$(diff -r "$CORE" "$B/core_orig" | grep -c "^<")
echo "  linhas da correcao: $n no nucleo, $m removidas para o original"
sed -e 's/^endmodule/    integer fdump; initial fdump = $fopen("saida_dut.txt", "w");\n    always @(posedge clk) if (check_on \&\& d_m_tvalid \&\& d_m_tready) $fdisplay(fdump, "%h %b", d_m_tdata, d_m_tlast);\nendmodule/' \
    "$B/tb_isfft_axi_v4.v" > "$B/tb_dump.v"
for v in orig novo; do
  c="$CORE"; [ $v = orig ] && c="$B/core_orig"
  ( cd "$B/eq_$v" && iverilog -g2012 -o tb.vvp "$c"/*.v "$V4" $MACROS "$PROJ/rtl/isfft/ref/isfft_axi_wrapper.v" "$B/tb_dump.v" 2> compile.log \
      && timeout "${LIMITE:-30}" vvp -n tb.vvp > sim.log )
done
if [ -s "$B/eq_orig/saida_dut.txt" ] && cmp -s "$B/eq_orig/saida_dut.txt" "$B/eq_novo/saida_dut.txt"; then
  echo "  identicas: $(wc -l < "$B/eq_novo/saida_dut.txt") palavras"
else
  echo "  DIFERENTES (ou nao rodou) -- ver $B/eq_*"; FALHOU=1
fi

echo
[ $FALHOU -eq 0 ] && echo "=== RESULTADO: TUDO OK ===" || echo "=== RESULTADO: HA FALHAS ==="
exit $FALHOU
