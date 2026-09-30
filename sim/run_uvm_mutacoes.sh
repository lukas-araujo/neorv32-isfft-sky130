#!/usr/bin/env bash
#=============================================================================
# run_uvm_mutacoes.sh -- o ambiente UVM pega defeitos de verdade?
#
# Cada mutacao e um defeito plantado no DUT (wrapper ou nucleo). O ambiente
# TEM que falhar em pelo menos um dos testes indicados. Roda so se a versao
# correta passou antes (senao "detectada" nao prova nada -- licao do DIARIO,
# 8a sessao).
#
# W*: wrapper isfft_axi_v4.v (so no DUT; a referencia e o wrapper da etapa 1)
# N*: nucleo (top_isfft.v) -- o MESMO modulo esta no DUT e na referencia,
#     entao a comparacao bit a bit nao ve; so a checagem numerica pode ver.
#
# O arquivo mutado sai do RTL do repositorio (rtl/isfft/); o resto do DUT
# e o espelho da pasta da VM que o run_uvm_verilator.sh monta.
#
# Uso: UVM_SRC=<pasta> bash sim/run_uvm_mutacoes.sh [mutacao ...]
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
M="$PROJ/build/uvm_mutacoes"
LOGS="$M/build/vm/verification/uvm_isfft/reports"
mkdir -p "$M"

# nome # arquivo # texto original # texto mutado # testes
# (separador '#': o texto do Verilog pode ter '|')
MUTACOES=$(cat <<'EOF'
W1_next_in_sem_atraso#isfft_axi_v4.v#else        core_next_in <= launch_active & (launch_cnt[1:0] == 2'd0);#else        core_next_in <= launch_active & (launch_cnt[1:0] == 2'd3);#isfft_fumaca_test
W2_busca_sem_limite#isfft_axi_v4.v#((ob_ocup != 2'd2) | out_hs)#1'b1#isfft_aleatorio_test
W3_buffer_ordem#isfft_axi_v4.v#else              ob_q1 <= out_rdata;#else              ob_q0 <= out_rdata;#isfft_aleatorio_test
W4_ponteiro_errado#isfft_axi_v4.v#.addr1 (ram_rd_ptr[OUT_AW-1:0]),#.addr1 (out_rd_ptr[OUT_AW-1:0]),#isfft_aleatorio_test
W5_in_mem_sem_espera#isfft_axi_v4.v#if (in_rd_v)#if (in_rd_en)#isfft_fumaca_test
W6_tlast_uma_matriz_depois#isfft_axi_v4.v#(out_pkt_cnt >= pkt_eff - 1'b1);#(out_pkt_cnt >= pkt_eff);#isfft_aleatorio_test isfft_kria_test
W7_rollback_quebrado#isfft_axi_v4.v#                in_wr_ptr <= in_wr_commit;#                in_wr_ptr <= in_wr_ptr;#isfft_truncado_test
W8_clr_err_ignorado#isfft_axi_v4.v#if (~aresetn | clr_err) begin#if (~aresetn) begin#isfft_truncado_test isfft_kria_regressao_test
W9_soft_reset_nao_zera_mat_in#isfft_axi_v4.v#mat_in_cnt  <= 32'd0;#mat_in_cnt  <= mat_in_cnt;#isfft_soft_reset_test
W10_id_errado#isfft_axi_v4.v#6'h14:   s_axi_rdata <= 32'h15FF0300;#6'h14:   s_axi_rdata <= 32'h15FF0301;#isfft_registradores_test
N1_nucleo_pingpong_linha#top_isfft.v#ping_pong_ram[rd_bank_sel][rd_row_pair_cnt * 2 + 1][rd_col_cnt];#ping_pong_ram[rd_bank_sel][rd_row_pair_cnt * 2][rd_col_cnt];#isfft_aleatorio_test
N2_nucleo_re_im#top_isfft.v#<= {ifft_Y0, ifft_Y1};#<= {ifft_Y1, ifft_Y0};#isfft_kria_test
EOF
)

origem () {  # arquivo -> caminho no repositorio
  if [ "$1" = isfft_axi_v4.v ]; then echo "$PROJ/rtl/isfft/$1"; else echo "$PROJ/rtl/isfft/core/$1"; fi
}

echo "=== Versao correta (referencia para as mutacoes) ==="
bash "$PROJ/sim/run_uvm_verilator.sh" isfft_fumaca_test > "$M/correta.log" 2>&1 \
  || { cat "$M/correta.log"; echo "Versao correta FALHOU: mutacoes nao sao avaliadas."; exit 1; }
echo "  PASSOU"

FALHOU=0
echo
echo "=== Mutacoes (esperado: todas DETECTADAS) ==="
while IFS='#' read -r nome arq velho novo testes; do
  [ -z "$nome" ] && continue
  [ $# -gt 0 ] && ! printf '%s\n' "$@" | grep -qx "$nome" && continue
  src="$(origem "$arq")"; dst="$M/$nome/$arq"
  mkdir -p "$M/$nome"
  VELHO="$velho" NOVO="$novo" python3 - "$src" "$dst" <<'PY' || { echo "  $nome: texto original nao encontrado"; FALHOU=1; continue; }
import os, sys
s = open(sys.argv[1]).read()
v, n = os.environ["VELHO"].replace("\\n", "\n"), os.environ["NOVO"].replace("\\n", "\n")
if s.count(v) != 1: sys.exit(1)
open(sys.argv[2], "w").write(s.replace(v, n))
PY
  MUTA="$dst" BUILD="$M/build" LINHAS=40 bash "$PROJ/sim/run_uvm_verilator.sh" $testes > "$M/$nome.log" 2>&1
  r=$?
  if [ $r -eq 2 ]; then echo "  $nome: nao compilou"; FALHOU=1; continue; fi
  if [ $r -eq 0 ]; then echo "  $nome: NAO DETECTADA  <-- ponto cego"; FALHOU=1; continue; fi
  # quem pegou: ids dos UVM_ERROR/FATAL nos logs dos testes
  quem=$(for t in $testes; do cat "$LOGS/${t}_verilator.log"; done 2>/dev/null \
         | grep -oE "UVM_(ERROR|FATAL) [^@]*@ [0-9]+: [^[]*\[[A-Za-z_]+\]" \
         | sed -E 's/.*\[([A-Za-z_]+)\]$/\1/' | sort | uniq -c | sort -rn | awk '{printf "%s(%s) ", $2, $1}')
  echo "  $nome: detectada -> $quem"
done <<< "$MUTACOES"
echo
[ $FALHOU -eq 0 ] && echo "=== RESULTADO: TODAS DETECTADAS ===" || echo "=== RESULTADO: HA PONTOS CEGOS ==="
exit $FALHOU
