#!/usr/bin/env bash
#=============================================================================
# 08_drc_gds.sh -- ETAPA 8, DRC de novo: no GDS, com as macros como caixa-preta
#
# Na 28a sessao o Magic.DRC rodou sobre o DEF + LEF (MAGIC_DRC_USE_GDS
# false). Nesse modo as celulas padrao entram como ABSTRATO (LEF): tem
# nwell (pino VPB) mas nao tem a difusao do tap -> 1.052 erros nwell.4
# ("nwell sem tap N+") em todas as linhas. Alarme falso do abstrato.
#
# Aqui (L42):
#   1. gera a vista abstrata (.mag "maglef") das 4 macros a partir do LEF
#      (layout/nucleo/maglef/, fora do git)
#   2. MAGIC_DRC_USE_GDS = true + MAGIC_DRC_MAGLEFS = essas 4 vistas: o
#      Magic le o GDS do chip (celulas padrao REAIS, com os taps) e as
#      macros continuam caixa-preta (L3) -- o drc.tcl do LibreLane carrega
#      as maglef antes e o "gds noduplicates" ignora o miolo da OpenRAM
#   3. roda so Magic.DRC + Checker.MagicDRC, a partir do KLayout.XOR
#
# O que se espera: nwell.4 some; sobram os 130 de area minima nos pinos de
# saida sem uso das macros (dout0 das 1rw1r e o bit 33 das 1rw), que sao
# quadradinhos do LEF (L43).
#
# O 08_verificacao.sh ja faz tudo isso (gera as maglef e roda a etapa 8
# inteira com o config novo). Este script e para refazer SO o DRC.
#
# Uso:  bash layout/nucleo/08_drc_gds.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente
gera_maglef

#--- 2 e 3. DRC no GDS -------------------------------------------------------
grep -q '"MAGIC_DRC_USE_GDS": true' "$CONFIG" && grep -q MAGIC_DRC_MAGLEFS "$CONFIG" \
  || { echo "ERRO: config.json sem MAGIC_DRC_USE_GDS true / MAGIC_DRC_MAGLEFS (git pull?)"; exit 1; }
r=0
# parte do KLayout.XOR: o Checker.XOR reprovou (erro adiado) e por isso nao
# grava state_out (29a sessao)
roda_trecho KLayout.XOR Magic.DRC Checker.MagicDRC || r=$?
echo ">>> librelane terminou com codigo $r (o checker reprovando da != 0)"

s="$(estado_de Magic.DRC)"
[ -n "$s" ] || { echo "ERRO: Magic.DRC nao gravou estado"; exit 1; }
d="$(dirname "$s")"
RES="$(pasta_resultados)"
out="$RES/08_drc_gds.txt"
{
  echo "== Magic.DRC no GDS ($(basename "$d")), tempo: $(cat "$d/runtime.txt" 2>/dev/null || echo '?')"
  python3 - "$s" <<'PY'
import json, sys
m = json.load(open(sys.argv[1]))["metrics"]
print(f"   magic__drc_error__count  {m.get('magic__drc_error__count')}")
PY
  echo
  echo "== Erros por regra (caixas no relatorio)"
  resume_drc_magic "$d/reports/drc.magic.rpt"
  echo
  echo "== Avisos de leitura do GDS (resumo)"
  grep -hoE "Unknown layer/datatype[^,]*|placed on top of itself|Warning: [^\"]{0,60}" "$d"/*.log 2>/dev/null \
    | sort | uniq -c | sort -rn | head -10 || true
} > "$out"
cp "$d/reports/drc.magic.rpt" "$RES/08_drc_gds_magic.rpt"
sed 's/^/    /' "$out"
echo ">>> em ${RES#$REPO/}: 08_drc_gds.txt, 08_drc_gds_magic.rpt"
echo "Depois: bash layout/nucleo/junta_logs.sh e o git add/commit que ele imprime."
