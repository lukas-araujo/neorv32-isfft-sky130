#!/usr/bin/env bash
#=============================================================================
# run_tb_stream.sh -- conversores 32<->64 (SLINK <-> ISFFT) + mutacoes
#
# Uso: bash sim/run_tb_stream.sh      (precisa de iverilog)
#=============================================================================
set -u
PROJ="$(cd "$(dirname "$0")/.." && pwd)"
B="$PROJ/sim/build_stream"
rm -rf "$B"; mkdir -p "$B/mut"
command -v iverilog >/dev/null || { echo "ERRO: iverilog fora do PATH"; exit 1; }

roda () {  # nome arquivos...
  local nome="$1"; shift
  iverilog -g2012 -o "$B/$nome.vvp" "$@" "$PROJ/tb/tb_stream.v" 2> "$B/$nome.compile.log" \
    || { echo "  $nome: ERRO DE COMPILACAO"; cat "$B/$nome.compile.log"; return 2; }
  vvp -n "$B/$nome.vvp" > "$B/$nome.log"
  grep -q "\[TB\] PASSOU" "$B/$nome.log"
}

A="$PROJ/rtl/isfft/stream_32to64.v"
C="$PROJ/rtl/isfft/stream_64to32.v"

echo "=== Conversores ==="
FALHOU=0
if roda ok "$A" "$C"; then echo "--- PASSOU"; else echo "--- FALHOU"; FALHOU=1; fi
grep "^\[TB\]\|ERRO" "$B/ok.log" | sed 's/^/    /'
# Mutacao so prova algo se a versao CORRETA passa (licao do DIARIO)
[ $FALHOU -eq 0 ] || { echo "Versao correta falhou: mutacoes nao sao avaliadas."; exit 1; }

echo
echo "=== Mutacoes (esperado: todas DETECTADAS) ==="
muta () {  # nome arquivo sed
  local nome="$1" src="$2" expr="$3"
  mkdir -p "$B/mut/$nome"
  cp "$A" "$C" "$B/mut/$nome/"
  local f="$B/mut/$nome/$(basename "$src")"
  sed -i "$expr" "$f"
  cmp -s "$f" "$src" && { echo "  $nome: sed nao alterou nada"; FALHOU=1; return; }
  roda "mut_$nome" "$B/mut/$nome/stream_32to64.v" "$B/mut/$nome/stream_64to32.v"
  case $? in
    0) echo "  $nome: NAO DETECTADA  <-- ponto cego"; FALHOU=1 ;;
    1) echo "  $nome: detectada -> $(grep -m1 -E 'ERRO|travou' "$B/mut_$nome.log" | sed 's/^\[[0-9]*\] //' | cut -c1-60)" ;;
    *) echo "  $nome: nao compilou"; FALHOU=1 ;;
  esac
}
muta metades_trocadas  "$A" 's/{s_data_i, baixa}/{baixa, s_data_i}/'
muta ignora_ready_saida "$A" 's/wire saida_livre = ~m_valid_o | m_ready_i;/wire saida_livre = 1'"'"'b1;/'
muta last_na_1a_metade  "$C" 's/assign m_last_o  = cheio \& fase \& ultimo;/assign m_last_o  = cheio \& ultimo;/'
muta bolha_perde_dado   "$C" 's/assign s_ready_o = ~cheio | fim_palavra;/assign s_ready_o = ~cheio | sai;/'

echo
if [ $FALHOU -eq 0 ]; then echo "=== RESULTADO: TUDO OK ==="; else echo "=== RESULTADO: HA FALHAS ==="; fi
exit $FALHOU
