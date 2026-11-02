#!/usr/bin/env bash
#=============================================================================
# 12_sta.sh -- ETAPA 12: STA do chip com um modelo de tempo do nucleo (L87)
#
#   Ate aqui o STA do chip dava folga 1e39 ("sem caminho restrito"): o
#   nucleo e uma macro sem .lib, o relogio chega no pino clk_i e para.
#
#   A. MODELO DO NUCLEO (OpenROAD/OpenSTA, write_timing_model)
#      Le o layout final do nucleo (rodada da etapa 7/8 em layout/nucleo,
#      .odb + SPEF "nom" do RCX), as libs TT (celulas + 4 SRAM) e o
#      nucleo.sdc; confere o STA TT do nucleo; e escreve um .lib "caixa-preta"
#      do asic_top: atrasos de clk_i -> saidas e restricoes de setup/hold das
#      entradas, ja com a arvore de relogio e os fios extraidos dentro.
#      So TT, como as SRAM (.lib so TT, chave "*").
#
#   B. STA DO CHIP (LibreLane, OpenROAD.STAPostPNR)
#      config_sta.json (gerado em entrada/, caminhos absolutos) = MACROS do
#      chip com o .lib do nucleo; parte do estado do RCX da etapa 11 (SPEF do
#      chip) e roda so o STAPostPNR, nos 9 corners. Os caminhos agora
#      atravessam os pads: clk_pad -> pad -> clk_i; rx_pad -> pad -> nucleo;
#      nucleo -> pad -> tx_pad (chip.sdc: 20 ns, 6 ns de entrada/saida).
#
#   Uso (nix-shell do LibreLane):  bash layout/chip/12_sta.sh
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
TAG="$(date +%Y-%m-%d_%H%M)_12sta"
DEST="$REPO/resultados/${TAG}_layout_chip"
W="$CHIP/runs/$TAG"
mkdir -p "$DEST" "$W/modelo"

#--- A. modelo do nucleo -------------------------------------------------------
NUC="$REPO/layout/nucleo"
TAGN="$(cat "$NUC/.rodada_atual" 2>/dev/null || true)"
RUNN="$NUC/runs/$TAGN"
[ -d "$RUNN" ] || { echo "ERRO: rodada do nucleo nao encontrada ($RUNN)"; exit 1; }
stn="$(ls -d "$RUNN"/[0-9]*-openroad-stapostpnr* 2>/dev/null | sort -V | while read -r d; do
        [ -f "$d/state_out.json" ] && echo "$d/state_out.json"; done | tail -1 || true)"
[ -n "$stn" ] || { echo "ERRO: sem OpenROAD.STAPostPNR com estado em $RUNN"; exit 1; }
echo ">>> nucleo: $TAGN, estado ${stn#$NUC/}"
python3 - "$stn" "$RUNN/resolved.json" "$W/modelo/env.tcl" "$NUC/nucleo.sdc" <<'PY'
import json, re, sys
st = json.load(open(sys.argv[1]))
r = json.load(open(sys.argv[2]))
# todas as variaveis ::env(X) que o nucleo.sdc le, com o valor da rodada do nucleo
vars_sdc = sorted(set(re.findall(r"::env\((\w+)\)", open(sys.argv[4]).read())))
odb = st["odb"]
spef = st.get("spef") or {}
nom = [v for k, v in spef.items() if k.startswith("nom")]
if not nom:
    sys.exit(f"ERRO: sem SPEF 'nom' no estado ({list(spef)})")
libs = []
for k, v in r["LIB"].items():
    if "tt_025C_1v80" in k:
        libs += v
for m, d in r["MACROS"].items():
    for k, v in (d.get("lib") or {}).items():
        libs += v
def tcl(x):
    return "{" + str(x) + "}"
with open(sys.argv[3], "w") as f:
    f.write(f"set ODB {tcl(odb)}\nset SPEF {tcl(nom[0])}\nset LIBS [list {' '.join(tcl(l) for l in libs)}]\n")
    for k in vars_sdc:
        v = r.get(k)
        if v is not None:
            if isinstance(v, list):
                v = " ".join(map(str, v))
            f.write(f"set ::env({k}) {tcl(v)}\n")
print(f"    odb  {odb}\n    spef {nom[0]}\n    {len(libs)} libs TT")
print("    variaveis do nucleo.sdc: " + ", ".join(f"{k}={r.get(k)!r}" for k in vars_sdc))
PY
MODELO="$ENT/asic_top_tt.lib"
cat > "$W/modelo/modelo.tcl" <<TCL
source $W/modelo/env.tcl
foreach l \$LIBS { read_liberty \$l }
read_db \$ODB
read_sdc $NUC/nucleo.sdc
read_spef \$SPEF
set_propagated_clock [all_clocks]
puts "== STA TT do nucleo (conferencia: tem de bater com a etapa 7)"
report_wns
report_tns
report_worst_slack -max
report_worst_slack -min
report_checks -path_delay max -fields {slew cap input_pins} -digits 3 > $W/modelo/nucleo_max.rpt
report_checks -path_delay min -digits 3 > $W/modelo/nucleo_min.rpt
write_timing_model -library_name asic_top_tt -cell_name asic_top $MODELO
puts "== modelo escrito: $MODELO"
exit
TCL
echo ">>> A. OpenROAD: STA do nucleo + write_timing_model"
openroad -no_init -no_splash -exit "$W/modelo/modelo.tcl" > "$W/modelo/modelo.log" 2>&1 || true
grep -E "^==|wns|tns|worst slack|Error|ERROR" "$W/modelo/modelo.log" | sed 's/^/    /' | head -20
[ -s "$MODELO" ] || { echo "ERRO: o modelo nao saiu (veja $W/modelo/modelo.log)"; tail -20 "$W/modelo/modelo.log"; exit 1; }
python3 - "$MODELO" <<'PY' | tee "$DEST/12_modelo_nucleo.txt" | sed 's/^/    /'
import re, sys
t = open(sys.argv[1]).read()
print(f"modelo: {sys.argv[1]} ({len(t)} bytes)")
# pinos e, para cada um, os arcos (timing_type) e o pino relacionado
pos = [(m.start(), m.group(1)) for m in re.finditer(r"\bpin\s*\(\s*\"?([\w\[\]]+)\"?\s*\)", t)]
for i, (ini, nome) in enumerate(pos):
    corpo = t[ini:pos[i + 1][0] if i + 1 < len(pos) else len(t)]
    dirc = re.search(r"direction\s*:\s*\"?(\w+)", corpo)
    tipos = sorted(set(re.findall(r"timing_type\s*:\s*\"?(\w+)", corpo)))
    rel = sorted(set(re.findall(r"related_pin\s*:\s*\"?([\w\[\]]+)", corpo)))
    clk = "clock" if re.search(r"\bclock\s*:\s*true", corpo) else ""
    print(f"  {nome:14s} {dirc.group(1) if dirc else '?':7s} {clk:5s} arcos: {', '.join(tipos) or '-'}"
          + (f"  (rel. {', '.join(rel)})" if rel else ""))
PY
cp -f "$W/modelo/modelo.log" "$W/modelo/nucleo_max.rpt" "$W/modelo/nucleo_min.rpt" "$DEST/" 2>/dev/null || true
gzip -c "$MODELO" > "$DEST/asic_top_tt.lib.gz"

#--- B. STA do chip --------------------------------------------------------------
python3 - "$CHIP/config.json" "$CHIP" "$MODELO" "$CHIP/.config_sta.json" <<'PY'
import json, os, sys
c = json.load(open(sys.argv[1]))
base, modelo, saida = sys.argv[2], sys.argv[3], sys.argv[4]
def abs_(p):
    return os.path.join(base, p[len("dir::"):]) if isinstance(p, str) and p.startswith("dir::") else p
m = json.loads(json.dumps(c["MACROS"]))
for nome, d in m.items():
    for k in ("lef", "gds"):
        if k in d:
            d[k] = [abs_(x) for x in d[k]] if isinstance(d[k], list) else abs_(d[k])
m["asic_top"]["lib"] = {"*": [modelo]}
json.dump({"meta": c["meta"], "MACROS": m}, open(saida, "w"), indent=2)
print(f"    {saida}: MACROS.asic_top.lib = {modelo}")
PY
ini="$(estado_11 openroad-rcx)"
[ -n "$ini" ] || { echo "ERRO: sem estado do OpenROAD.RCX em $RUN11"; exit 1; }
echo ">>> B. STA do chip (OpenROAD.STAPostPNR), a partir de ${ini#$CHIP/}"
r=0
roda_librelane "$TAG" OpenROAD.STAPostPNR OpenROAD.STAPostPNR "$ini" "$CHIP/.config_sta.json" || r=$?

d="$(ls -d "$W"/[0-9]*-openroad-stapostpnr 2>/dev/null | sort -V | tail -1 || true)"
if [ -n "$d" ] && [ -f "$d/state_out.json" ]; then
  python3 - "$d/state_out.json" "$DEST/12_sta_metricas.json" <<'PY' | tee "$DEST/12_sta.txt" | sed 's/^/    /'
import json, re, sys
m = json.load(open(sys.argv[1])).get("metrics", {})
json.dump(m, open(sys.argv[2], "w"), indent=1, sort_keys=True)
print("STA do chip com o modelo do nucleo (folga em ns; 1e39 = sem caminho)")
print(f"  {'corner':22s} {'setup ws':>9s} {'setup tns':>9s} {'vio':>4s} {'hold ws':>9s} {'hold tns':>9s} {'vio':>4s}")
cs = sorted({k.split("corner:")[1] for k in m if "corner:" in k and k.startswith("timing__setup__ws")})
for c in cs:
    g = lambda k: m.get(f"{k}__corner:{c}")
    f = lambda v: "-" if v is None else (f"{v:9.3f}" if abs(v) < 1e30 else "     1e39")
    print(f"  {c:22s} {f(g('timing__setup__ws')):>9s} {f(g('timing__setup__tns')):>9s} {str(g('timing__setup_vio__count')):>4s} "
          f"{f(g('timing__hold__ws')):>9s} {f(g('timing__hold__tns')):>9s} {str(g('timing__hold_vio__count')):>4s}")
for k in ("timing__setup__ws", "timing__hold__ws", "timing__setup_vio__count", "timing__hold_vio__count"):
    print(f"  {k:28s} {m.get(k)}")
PY
  # relatorios do corner TT (caminhos completos) e o resumo de todos
  for f in "$d"/summary.rpt "$d"/nom_tt_025C_1v80/*.rpt; do
    [ -f "$f" ] && cp -f "$f" "$DEST/12_sta_$(basename "$(dirname "$f")")_$(basename "$f")"
  done
fi
junta_logs "$TAG" "$DEST"
echo
echo "Resultados: ${DEST#$REPO/}"
ls -1 "$DEST" | sed 's/^/    /'
manda_git "$DEST"
exit "$r"
