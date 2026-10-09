#!/usr/bin/env bash
#=============================================================================
# diag_xor.sh -- POR QUE os GDS do Magic e do KLayout diferem (etapa 8)?
#
# O KLayout.XOR da 28a sessao achou 15.679.857 diferencas, quase todas em
# camadas que so existem dentro das macros da OpenRAM (22/21, 33/42,
# 115/42...) e com o Magic tendo MAIS formas que o KLayout. Este script
# conta as formas por camada nos dois GDS, separando "dentro das 4 macros"
# de "resto do chip", e salva em resultados/:
#   08_xor_diag.txt
# Se a diferenca estiver toda dentro das macros, o nosso desenho (celulas
# padrao + fios) e igual nos dois e o XOR acusa so a leitura das macros.
# Nao mexe na rodada. Poucos minutos.
#
# Uso:  bash layout/nucleo/diag_xor.sh
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente
command -v klayout >/dev/null || { echo "ERRO: klayout fora do PATH (nix-shell do LibreLane)"; exit 1; }

sm="$(estado_de Magic.StreamOut)"; sk="$(estado_de KLayout.StreamOut)"
[ -n "$sm" ] && [ -n "$sk" ] || { echo "ERRO: rode antes a etapa 8 (08_verificacao.sh)"; exit 1; }
export GDS_A="$(ls "$(dirname "$sm")"/*.gds | head -1)"
export GDS_B="$(ls "$(dirname "$sk")"/*.gds | head -1)"
export MACROS="$(python3 -c "import json,sys; print(' '.join(json.load(open(sys.argv[1]))['MACROS']))" "$CONFIG")"
R="$(pasta_resultados)"
export SAIDA="$R/08_xor_diag.txt"
echo ">>> A = Magic:   $GDS_A"
echo ">>> B = KLayout: $GDS_B"
klayout -b -r "$NUCLEO/tcl/conta_gds.py"
cat "$SAIDA"
echo ">>> em ${SAIDA#$REPO/}"
echo "Depois: git add resultados/ && git commit -m 'gdsii: diagnostico do XOR' && git push"
