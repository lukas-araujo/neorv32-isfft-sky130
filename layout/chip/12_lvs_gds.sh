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
ls "$IO"/spice/*.spice "$IO"/cdl/*.cdl >/dev/null 2>&1 || { echo "ERRO: sem SPICE/CDL em $IO"; exit 1; }
python3 - "$IO" "$CHIP/config.json" "$CHIP/.config_lvs_gds.json" "$DEST/12_lvs_gds_spice.txt" <<'PY'
import glob, json, os, re, sys
io, cfg, saida, rel = sys.argv[1:5]
c = json.load(open(cfg))
v = open(os.path.join(os.path.dirname(cfg), "chip_top.v")).read()
precisa = set(re.findall(r"^\s*(sky130_ef_io__\w+)\s", v, re.M))
precisa |= set(c.get("PAD_CORNER") or []) | set(c.get("PAD_FILLERS") or [])

def subckts(f):
    """{nome: [celulas instanciadas]} de um arquivo SPICE/CDL"""
    txt = open(f, errors="replace").read().replace("\n+", " ")
    r, atual = {}, None
    for l in txt.splitlines():
        t = l.split()
        if not t:
            continue
        if t[0].lower() == ".subckt":
            atual = t[1]
            r[atual] = []
        elif t[0].lower() == ".ends":
            atual = None
        elif atual and t[0][0] in "Xx":
            nomes = [x for x in t[1:] if "=" not in x]
            if nomes:
                r[atual].append(nomes[-1].lstrip("/"))
    return r

arquivos = sorted(glob.glob(os.path.join(io, "spice", "*.spice")) + glob.glob(os.path.join(io, "cdl", "*.cdl")))
tab = {f: subckts(f) for f in arquivos}
# O PDK traz as celulas sky130_ef_io (pads "embrulhados", fatias, canto) so no CDL
# custom do open_pdks; as sky130_fd_io de dentro delas, no SPICE da SkyWater.
escolha = []
for nome in ("cdl/sky130_ef_io.cdl", "spice/sky130_fd_io.spice"):
    p = os.path.join(io, nome)
    if p in tab:
        escolha.append(p)
def define(cel, fs):
    return [f for f in fs if cel in tab[f]]
# fecho: tudo o que as celulas do anel instanciam tem de estar definido
falta, vistos, fila = set(), set(), sorted(precisa)
while fila:
    cel = fila.pop()
    if cel in vistos:
        continue
    vistos.add(cel)
    fs = define(cel, escolha)
    if not fs:
        outros = define(cel, arquivos)
        if outros:
            escolha.append(outros[0])
            fs = [outros[0]]
        elif not cel.startswith("sky130_fd_pr__"):
            falta.add(cel)
            continue
        else:
            continue
    fila += [x for x in tab[fs[0]][cel] if not x.startswith("sky130_fd_pr__")]
linhas = []
for cel in sorted(precisa):
    fs = define(cel, escolha)
    linhas.append(f"  {cel:62s} {os.path.relpath(fs[0], io) if fs else 'SEM DEFINICAO'}")
json.dump({"meta": c["meta"],
           "MAGIC_EXT_USE_GDS": True,
           "MAGIC_EXT_ABSTRACT_CELLS": ["^asic_top$"],
           "MAGIC_CAPTURE_ERRORS": False,
           "RUN_LVS": True,
           "ERROR_ON_LVS_ERROR": False,
           "ERROR_ON_ILLEGAL_OVERLAPS": False,
           "PAD_SPICE_MODELS": escolha}, open(saida, "w"), indent=2)
txt = ("SPICE/CDL dos pads (PAD_SPICE_MODELS):\n" + "\n".join("  " + os.path.relpath(f, io) for f in escolha)
       + "\n\nCelulas do anel -> onde esta o .subckt:\n" + "\n".join(linhas)
       + f"\n\nSubcelulas (fecho) sem definicao em nenhum arquivo: {', '.join(sorted(falta)) or 'nenhuma'}\n"
       + f"Subcircuitos conferidos no fecho: {len(vistos)}\n")
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
roda_librelane "$TAG" Magic.SpiceExtraction Checker.LVS "$ini" "$CHIP/.config_lvs_gds.json" || r=$?

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
