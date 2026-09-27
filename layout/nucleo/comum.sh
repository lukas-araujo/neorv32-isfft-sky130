#!/usr/bin/env bash
#=============================================================================
# comum.sh -- funcoes usadas por todos os scripts de etapa do nucleo
#
# Nao rode este arquivo: ele e lido (source) pelos NN_*.sh.
#
# O LibreLane roda o fluxo inteiro de uma vez por padrao. Aqui ele roda por
# TRECHOS, sempre na MESMA rodada (--run-tag), cada trecho continuando do
# estado em que o anterior parou (--with-initial-state). Cada NN_*.sh:
#   1. roda um trecho do fluxo (--from ... --to ...);
#   2. guarda as metricas do trecho em resultados/;
#   3. abre o OpenROAD com GUI no estado final do trecho e salva as imagens.
#
# Variaveis que o usuario pode mudar na linha de comando:
#   SEM_GUI=1   so salva as imagens e fecha (sem abrir janela)
#   SO_GUI=1    nao roda o LibreLane: so reabre a GUI da etapa ja rodada
#=============================================================================
set -euo pipefail

NUCLEO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$NUCLEO/../.." && pwd)"
CONFIG="$NUCLEO/config.json"
RUNS="$NUCLEO/runs"
ARQ_TAG="$NUCLEO/.rodada_atual"

#-----------------------------------------------------------------------------
# Ambiente: tem que estar dentro do nix-shell do LibreLane
#-----------------------------------------------------------------------------
confere_ambiente () {
  if ! command -v librelane >/dev/null || ! command -v openroad >/dev/null; then
    echo "ERRO: librelane/openroad fora do PATH. Entre no ambiente antes:"
    echo "  nix-shell ~/Projects/librelane/shell.nix"
    exit 1
  fi
  export PDK_ROOT="${PDK_ROOT:-$HOME/Projects/pdks/librelane}"
}

#-----------------------------------------------------------------------------
# Rodada atual: criada pelo 01, lida pelos outros
#-----------------------------------------------------------------------------
rodada () {
  [ -f "$ARQ_TAG" ] || { echo "ERRO: nenhuma rodada iniciada. Rode antes: bash $NUCLEO/01_leitura.sh"; exit 1; }
  cat "$ARQ_TAG"
}

pasta_resultados () {   # resultados/<AAAA-MM-DD_HHMM>_layout_nucleo
  local r="$REPO/resultados/$(rodada)_layout_nucleo"
  mkdir -p "$r/imagens"
  echo "$r"
}

#-----------------------------------------------------------------------------
# estado_de <id_da_etapa>: state_out.json da execucao MAIS RECENTE dessa
# etapa na rodada atual. Pasta de etapa = "<NN>-<id em minusculas, . -> ->".
# Ex.: OpenROAD.Floorplan -> NN-openroad-floorplan
#-----------------------------------------------------------------------------
estado_de () {
  local slug d
  slug="$(echo "$1" | tr 'A-Z' 'a-z' | tr '.' '-')"
  # a pasta de maior numero (a execucao mais recente, se a etapa rodou 2x)
  d="$(for x in "$RUNS/$(rodada)"/[0-9]*-"$slug"; do
         [ -d "$x" ] && echo "$(basename "$x" | cut -d- -f1 | sed 's/^0*//') $x"
       done | sort -n | tail -1 | cut -d' ' -f2-)"
  [ -n "$d" ] && [ -f "$d/state_out.json" ] || { echo ""; return; }
  echo "$d/state_out.json"
}

visao_de () {   # visao_de <state_out.json> <odb|def|nl|...>
  python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get(sys.argv[2]) or '')" "$1" "$2"
}

#-----------------------------------------------------------------------------
# roda_trecho <etapa_anterior|-> <de> <ate>
#   etapa_anterior: de onde vem o estado inicial ("-" = do zero)
#-----------------------------------------------------------------------------
roda_trecho () {
  local anterior="$1" de="$2" ate="$3" extra=()
  if [ "$anterior" != "-" ]; then
    local ini; ini="$(estado_de "$anterior")"
    [ -n "$ini" ] || { echo "ERRO: a etapa $anterior ainda nao rodou nesta rodada ($(rodada))."; exit 1; }
    extra+=(--with-initial-state "$ini")
  fi
  [ "$de" = "-" ] || extra+=(--from "$de")
  echo ">>> LibreLane: rodada $(rodada), de ${de} ate ${ate}"
  librelane --pdk-root "$PDK_ROOT" --run-tag "$(rodada)" "${extra[@]}" --to "$ate" "$CONFIG"
}

#-----------------------------------------------------------------------------
# guarda_metricas <etapa> <nome_arquivo>: metricas do state_out em JSON
#-----------------------------------------------------------------------------
guarda_metricas () {
  local st; st="$(estado_de "$1")"
  local dest="$(pasta_resultados)/$2_metricas.json"
  python3 - "$st" "$dest" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("metrics", {})
json.dump(m, open(sys.argv[2], "w"), indent=1, sort_keys=True)
chaves = ["design__instance__count", "design__instance__area",
          "design__instance__count__macros", "design__die__area",
          "design__core__area", "design__instance__utilization",
          "timing__setup__ws", "timing__hold__ws",
          "timing__setup_vio__count", "timing__hold_vio__count"]
for k in chaves:
    if k in m:
        print(f"  {k:36s} {m[k]}")
print(f"  ({len(m)} metricas em {sys.argv[2].split('/resultados/')[-1]})")
PY
}

#-----------------------------------------------------------------------------
# abre_gui <etapa> <modo> <prefixo_das_imagens>
#   Abre o .odb do fim da etapa no OpenROAD, ajusta a visao para o <modo>
#   (ver tcl/imagem.tcl), salva as imagens e deixa a janela aberta.
#-----------------------------------------------------------------------------
abre_gui () {
  local st odb
  st="$(estado_de "$1")"
  odb="$(visao_de "$st" odb)"
  [ -n "$odb" ] && [ -f "$odb" ] || { echo "ERRO: sem .odb na etapa $1"; exit 1; }
  export IMG_ODB="$odb" IMG_MODO="$2" IMG_PREFIXO="$3"
  export IMG_DIR="$(pasta_resultados)/imagens"
  echo ">>> OpenROAD: $2 ($odb)"
  if [ "${SEM_GUI:-0}" = 1 ]; then
    QT_QPA_PLATFORM=offscreen openroad -no_splash -exit -gui "$NUCLEO/tcl/imagem.tcl"
  else
    openroad -no_splash -gui "$NUCLEO/tcl/imagem.tcl"
  fi
  echo ">>> imagens em: ${IMG_DIR#$REPO/}"
  ls -1 "$IMG_DIR" | grep "^$3" | sed 's/^/    /' || true
}
