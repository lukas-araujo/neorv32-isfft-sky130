#!/usr/bin/env bash
#=============================================================================
# 12_lvs_gds.sh -- ETAPA 12: LVS pelo GDS, com os pads INTEIROS (L88)
#
#   O LVS do 12_verifica.sh extraiu pelo DEF + LEF (abstrato): pads, fatias e
#   nucleo eram caixas-pretas casadas pelos pinos. Ele confere a nossa
#   ligacao, mas nao enxerga o metal de dentro das celulas do anel -- e la
#   que estao as 24 sobreposicoes "obsm4 x metal4" da L77 (a sobra de met4 do
#   LEF dos pads lvc).
#
#   Aqui o Magic.SpiceExtraction le o GDS do chip (MAGIC_EXT_USE_GDS):
#     - pads, cantos e fatias extraidos do desenho REAL (transistores, ESD,
#       resistores, barramentos de metal);
#     - nucleo abstraido (MAGIC_EXT_ABSTRACT_CELLS = asic_top): o miolo ja
#       passou no LVS da etapa 8;
#     - o lado "esquematico" do Netgen ganha o SPICE dos pads do PDK
#       (PAD_SPICE_MODELS), para comparar transistor com transistor.
#   MAGIC_CAPTURE_ERRORS = false: ler o GDS do nucleo sem "readonly" acusa as
#   camadas proprias da OpenRAM (as mesmas da L44); o script lista as linhas.
#   Se houvesse curto entre redes no anel (L77), o LVS mostraria redes
#   fundidas.
#
#   Uso (nix-shell do LibreLane):  bash layout/chip/12_lvs_gds.sh
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
TAG="$(date +%Y-%m-%d_%H%M)_12lvs"
DEST="$REPO/resultados/${TAG}_layout_chip"
W="$CHIP/runs/$TAG"
mkdir -p "$DEST"

#--- 1. SPICE dos pads: em que arquivo esta cada celula do anel -----------------
ls "$IO"/spice/*.spice >/dev/null 2>&1 || { echo "ERRO: sem $IO/spice/*.spice"; exit 1; }
python3 - "$IO/spice" "$CHIP/config.json" "$ENT/config_lvs_gds.json" "$DEST/12_lvs_gds_spice.txt" <<'PY'
import glob, json, os, re, sys
pasta, cfg, saida, rel = sys.argv[1:5]
c = json.load(open(cfg))
# celulas do anel: pads (pelo chip_top.v: modulos sky130_ef_io__*), cantos, fatias
v = open(os.path.join(os.path.dirname(cfg), "chip_top.v")).read()
precisa = set(re.findall(r"^\s*(sky130_e[f]_io__\w+)\s", v, re.M))
precisa |= set(c.get("PAD_CORNER") or []) | set(c.get("PAD_FILLERS") or [])
define = {}
for f in sorted(glob.glob(os.path.join(pasta, "*.spice"))):
    for m in re.finditer(r"^\s*\.subckt\s+(\S+)", open(f, errors="replace").read(), re.M | re.I):
        define.setdefault(m.group(1), []).append(f)
# preferencia: os arquivos combinados; depois o arquivo proprio da celula
escolha, linhas = [], []
for comb in ("sky130_ef_io.spice", "sky130_fd_io.spice"):
    p = os.path.join(pasta, comb)
    if os.path.exists(p):
        escolha.append(p)
for cel in sorted(precisa):
    fs = define.get(cel, [])
    if any(f in escolha for f in fs):
        onde = [os.path.basename(f) for f in fs if f in escolha][0]
    elif fs:
        escolha.append(fs[0])
        onde = os.path.basename(fs[0]) + " (arquivo proprio)"
    else:
        onde = "SEM SPICE -> caixa-preta do lado do esquematico"
    linhas.append(f"  {cel:62s} {onde}")
json.dump({"meta": c["meta"],
           "MAGIC_EXT_USE_GDS": True,
           "MAGIC_EXT_ABSTRACT_CELLS": ["^asic_top$"],
           "MAGIC_CAPTURE_ERRORS": False,
           "RUN_LVS": True,
           "ERROR_ON_LVS_ERROR": False,
           "ERROR_ON_ILLEGAL_OVERLAPS": False,
           "PAD_SPICE_MODELS": escolha}, open(saida, "w"), indent=2)
txt = "SPICE dos pads (PAD_SPICE_MODELS):\n" + "\n".join("  " + f for f in escolha) + \
      "\n\nCelulas do anel -> onde esta o .subckt:\n" + "\n".join(linhas) + "\n"
open(rel, "w").write(txt)
print(txt)
PY

#--- 2. extracao pelo GDS + LVS ---------------------------------------------------
ini=""
for p in checker-klayoutdensity klayout-density checker-xor klayout-xor; do
  ini="$(estado_11 "$p")"; [ -n "$ini" ] && break
done
[ -n "$ini" ] || { echo "ERRO: nenhum passo antes da extracao com estado em $RUN11"; exit 1; }
echo ">>> extracao pelo GDS + LVS, a partir de ${ini#$CHIP/} (demora: pads com transistores)"
r=0
roda_librelane "$TAG" Magic.SpiceExtraction Checker.LVS "$ini" "$ENT/config_lvs_gds.json" || r=$?

#--- 3. resultados ------------------------------------------------------------------
d="$(ls -d "$W"/[0-9]*-magic-spiceextraction 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$d" ]; then
  { echo "== Magic.SpiceExtraction pelo GDS ($(basename "$d")), tempo: $(cat "$d/runtime.txt" 2>/dev/null || echo '?')"
    grep -h "matched with the expression\|Failed to match" "$d"/*.log 2>/dev/null | head -5
    echo
    echo "== Linhas que o MAGIC_CAPTURE_ERRORS trataria como fatais (desligado aqui)"
    linhas_fatais_magic "$(ls "$d"/*.log | head -1)"
    sp="$(ls "$d"/*.spice 2>/dev/null | head -1)"
    if [ -n "$sp" ]; then
      echo
      echo "== Netlist extraida: dispositivos por modelo (todas as subcelulas)"
      grep -hoE "^[XM][^ ]* .* sky130_fd_pr__[a-z0-9_]+" "$sp" | grep -oE "sky130_fd_pr__[a-z0-9_]+" \
        | sort | uniq -c | sort -rn | head -15
      gzip -c "$sp" > "$DEST/12_extraida_gds.spice.gz"
    fi
  } > "$DEST/12_extracao_gds.txt" 2>&1
  sed 's/^/    /' "$DEST/12_extracao_gds.txt" | head -40
fi
d="$(ls -d "$W"/[0-9]*-netgen-lvs 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$d" ] && [ -f "$d/reports/lvs.netgen.rpt" ]; then
  python3 "$CHIP/resume_verifica.py" lvs "$d/reports/lvs.netgen.rpt" > "$DEST/12_lvs_gds.txt" 2>&1
  gzip -c "$d/reports/lvs.netgen.rpt" > "$DEST/12_lvs_gds_netgen.rpt.gz"
  echo ">>> LVS pelo GDS:"; sed 's/^/    /' "$DEST/12_lvs_gds.txt" | head -40
else
  echo ">>> Netgen.LVS nao gerou relatorio"
fi
st="$(ls -d "$W"/[0-9]*/ 2>/dev/null | while read -r x; do [ -f "$x/state_out.json" ] && echo "$x"; done | sort -V | tail -1 || true)"
[ -n "$st" ] && python3 -c "
import json,sys; m=json.load(open(sys.argv[1]))['metrics']
json.dump(m, open(sys.argv[2],'w'), indent=1, sort_keys=True)
[print(f'    {k:44s} {v}') for k,v in sorted(m.items()) if 'lvs' in k or 'illegal_overlap' in k]" \
  "$st/state_out.json" "$DEST/12_lvs_gds_metricas.json"
junta_logs "$TAG" "$DEST"
echo
echo "Resultados: ${DEST#$REPO/}"
ls -1 "$DEST" | sed 's/^/    /'
manda_git "$DEST"
exit "$r"
