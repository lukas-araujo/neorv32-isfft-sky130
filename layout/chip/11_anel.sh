#!/usr/bin/env bash
#=============================================================================
# 11_anel.sh -- ETAPA 11 (parte 1): o ANEL DE PADS em volta do nucleo
#
#   Fluxo Chip do LibreLane = Classic + OpenROAD.PadRing. Esta parte roda
#   so ate o anel (config_anel.json corta o fluxo), para conferir o
#   desenho ANTES de gastar horas com PDN, roteamento e verificacao:
#
#     Yosys.Synthesis       so ELABORA o chip_top.v (SYNTH_ELABORATE_ONLY):
#                           ja e estrutural; nucleo e fatia sao caixa-preta
#                           (caixas_pretas.v)
#     OpenROAD.Floorplan    die 2700 x 2201 um, area de nucleo 300..2400
#     OpenROAD.PadRing      sitios falsos, pads nos 4 lados (PAD_SOUTH...),
#                           cantos, enchimento com com_bus_slice, terminais
#                           de pino no PAD (pad_cfg.tcl: rotacao R180)
#     Odb.ManualMacroPlacement  o nucleo (macro asic_top) em (350, 350)
#     KLayout.StreamOut/Render  GDS e PNG do chip
#
#   Antes de rodar, traz as vistas do nucleo da rodada do layout/nucleo
#   (a etapa 8 gerou o LEF pelo Magic.WriteLEF e o GDS pelo Magic.StreamOut)
#   para layout/chip/entrada/ (fora do git) e mostra os pinos do LEF.
#
#   Resultado: resultados/<AAAA-MM-DD_HHMM>_layout_chip/ (metricas, PNG,
#   logs). Uso, dentro do nix-shell do LibreLane:
#     bash layout/chip/11_anel.sh
#=============================================================================
source "$(dirname "$0")/../nucleo/comum.sh"     # estado_de, visao_de...
confere_ambiente
CHIP="$REPO/layout/chip"
ENT="$CHIP/entrada"
mkdir -p "$ENT"

#-----------------------------------------------------------------------------
# 1. Vistas do nucleo (da rodada atual do layout/nucleo)
#-----------------------------------------------------------------------------
st_lef="$(estado_de Magic.WriteLEF)"
st_gds="$(estado_de Magic.StreamOut)"
[ -n "$st_lef" ] && [ -n "$st_gds" ] \
  || { echo "ERRO: a rodada $(rodada) do nucleo nao tem Magic.WriteLEF/StreamOut (rode a etapa 8)"; exit 1; }
lef="$(visao_de "$st_lef" lef)"
gds="$(visao_de "$st_gds" gds)"
cp -f "$lef" "$ENT/asic_top.lef"
cp -f "$gds" "$ENT/asic_top.gds"
echo ">>> nucleo: $lef"
echo "            $gds ($(du -h "$gds" | cut -f1))"

echo ">>> pinos do LEF do nucleo (nome, USE, camadas)"
python3 - "$ENT/asic_top.lef" <<'PY'
import re, sys
txt = open(sys.argv[1]).read()
m = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", txt)
print(f"    tamanho: {m.group(1)} x {m.group(2)} um")
for p in re.finditer(r"\n\s*PIN (\S+)(.*?)\n\s*END \1", txt, re.S):
    corpo = p.group(2)
    uso = re.search(r"USE (\w+)", corpo)
    cam = sorted(set(re.findall(r"LAYER (\w+)", corpo)))
    n = len(re.findall(r"RECT", corpo))
    print(f"    {p.group(1):14s} {uso.group(1) if uso else '-':8s} {','.join(cam):12s} {n} retangulos")
PY

#-----------------------------------------------------------------------------
# 2. Arquivos dos pads no PDK (sky130_fd_io: LEF/GDS da Efabless e da SkyWater)
#-----------------------------------------------------------------------------
io="$(find -L "$PDK_ROOT" -maxdepth 4 -type d -path '*sky130A/libs.ref/sky130_fd_io' 2>/dev/null | head -1 || true)"
[ -n "$io" ] || { echo "ERRO: nao achei sky130A/libs.ref/sky130_fd_io em $PDK_ROOT"; exit 1; }
# O GDS combinado sky130_ef_io.gds NAO tem o gpiov2_pad_wrapped nem a fatia
# VCCHIB (o LEF combinado tem): vem cada um no seu arquivo (37a sessao, L64)
for f in lef/sky130_ef_io.lef lef/sky130_fd_io.lef gds/sky130_ef_io.gds gds/sky130_fd_io.gds \
         gds/sky130_ef_io__gpiov2_pad_wrapped.gds \
         gds/sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.gds; do
  [ -f "$io/$f" ] || { echo "ERRO: falta $io/$f"; exit 1; }
done
echo ">>> pads: $io (LEF e GDS ok)"
# O PDK pode trazer uma config de pads pronta para o LibreLane (valores
# padrao das PAD_*); a nossa config.json sobrepoe. So mostramos, para comparar.
pc="$(dirname "$(dirname "$io")")/libs.tech/librelane/sky130_fd_io/config.tcl"
if [ -f "$pc" ]; then echo ">>> o PDK traz $pc:"; grep -E 'PAD_' "$pc" | sed 's/^/    /'
else echo ">>> o PDK nao traz config de pads para o LibreLane (tudo vem da nossa config.json)"; fi

#-----------------------------------------------------------------------------
# 3. LibreLane: config.json + config_anel.json (o segundo so troca o fluxo)
#-----------------------------------------------------------------------------
TAG="$(date +%Y-%m-%d_%H%M)"
echo "$TAG" > "$CHIP/.rodada_atual"
r=0
( cd "$CHIP" && librelane --pdk-root "$PDK_ROOT" --run-tag "$TAG" \
    config.json config_anel.json ) || r=$?
echo ">>> librelane terminou com codigo $r"

#-----------------------------------------------------------------------------
# 4. Resultados
#-----------------------------------------------------------------------------
RUN="$CHIP/runs/$TAG"
DEST="$REPO/resultados/${TAG}_layout_chip"
mkdir -p "$DEST/imagens"
ultimo="$(ls -d "$RUN"/[0-9]*/ 2>/dev/null | while read -r d; do
           [ -f "$d/state_out.json" ] && echo "$d"; done | sort -V | tail -1 || true)"
if [ -n "$ultimo" ]; then
  echo ">>> ultimo passo com estado: $(basename "$ultimo")"
  python3 - "$ultimo/state_out.json" "$DEST/11_anel_metricas.json" <<'PY'
import json, sys
m = json.load(open(sys.argv[1])).get("metrics", {})
json.dump(m, open(sys.argv[2], "w"), indent=1, sort_keys=True)
for k in ["design__die__area", "design__core__area",
          "design__instance__count", "design__instance__count__macros",
          "design__io"]:
    if k in m: print(f"  {k:36s} {m[k]}")
PY
fi
find "$RUN" -name '*.png' -path '*klayout-render*' -exec cp -f {} "$DEST/imagens/11_anel.png" \; 2>/dev/null || true
( cd "$CHIP/runs" && find "$TAG" -type f \
    \( -name '*.log' -o -name '*.rpt' -o -name '*.txt' -o -name '*.json' \
       -o -name '*.tcl' -o -name '*.sdc' \) -size -20M -print0 \
  | tar czf "$DEST/logs_anel.tar.gz" --null -T - )
# o PadRing escreve o que fez no log: pads, cantos, enchimento
pr="$(ls -d "$RUN"/*-openroad-padring 2>/dev/null | tail -1 || true)"
if [ -n "$pr" ]; then
  grep -hiE 'error|warn|\[INFO PAD' "$pr"/*.log 2>/dev/null | sort | uniq -c | sort -rn | head -30 \
    > "$DEST/11_padring_resumo.txt" || true
  echo ">>> PadRing (mensagens, contagem):"; sed 's/^/    /' "$DEST/11_padring_resumo.txt"
fi
echo
echo "Resultados: ${DEST#$REPO/}"
ls -1 "$DEST" "$DEST/imagens" | sed 's/^/    /'
echo
echo "Para mandar pelo git:"
echo "  git add resultados/${TAG}_layout_chip && git commit -m 'gdsii: etapa 11, anel de pads' && git push"
exit "$r"
