#!/usr/bin/env bash
#=============================================================================
# 12_extrai_celulas.sh -- extracao das celulas do anel SOZINHAS (L91)
#
#   Na extracao do chip pelo GDS (12_lvs_gds.sh) os barramentos VDDIO, VSSA,
#   VSSIO, VSSD e VSWITCH viraram UMA rede, e o gpiov2_pad_wrapped extraido
#   ja vem sem a porta VDDIO (o Magic so guarda um nome quando duas portas
#   sao o mesmo no dentro da celula). Pergunta: a fusao acontece dentro das
#   celulas da foundry (extracao do GDS delas, independente do nosso chip)
#   ou na ligacao entre elas (o que a L77 temia)?
#
#   Aqui o Magic le os GDS dos pads (os mesmos do PAD_GDS, na ordem da L73),
#   extrai cada celula do anel SOZINHA e o script mostra, para cada uma:
#   portas que existem, barramentos que sumiram (fundidos em outra porta) e
#   o no de substrato (VSUBS). So Magic, poucos minutos.
#
#   Uso (nix-shell do LibreLane):  bash layout/chip/12_extrai_celulas.sh
#=============================================================================
source "$(dirname "$0")/comum_chip.sh"
confere_chip
TAG="$(date +%Y-%m-%d_%H%M)_12cel"
W="$CHIP/runs/$TAG"
DEST="$REPO/resultados/${TAG}_layout_chip"
mkdir -p "$W" "$DEST"

gdss=("$ENT/sky130_fd_io.gds" "$IO/gds/sky130_ef_io.gds" "$IO/gds/sky130_ef_io__gpiov2_pad_wrapped.gds"
      "$IO/gds/sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um.gds")
for g in "${gdss[@]}"; do [ -f "$g" ] || { echo "ERRO: falta $g (rode o 11_anel.sh para a copia da L74)"; exit 1; }; done
CELULAS="sky130_ef_io__gpiov2_pad_wrapped sky130_ef_io__vccd_lvc_clamped_pad sky130_ef_io__vssd_lvc_clamped_pad
sky130_ef_io__vddio_hvc_clamped_pad sky130_ef_io__vssio_hvc_clamped_pad sky130_ef_io__vdda_hvc_clamped_pad
sky130_ef_io__vssa_hvc_clamped_pad sky130_ef_io__corner_pad sky130_ef_io__com_bus_slice_20um
sky130_ef_io__connect_vcchib_vccd_and_vswitch_vddio_slice_20um"

{
  echo 'crashbackups disable'
  echo 'locking disable'
  echo 'drc off'
  echo 'gds noduplicates true'
  for g in "${gdss[@]}"; do echo "gds read $g"; done
  for c in $CELULAS; do
    cat <<EOF
load $c
select top cell
extract do local
extract no capacitance
extract all
ext2spice lvs
ext2spice -o $W/$c.spice
puts stdout "\[INFO\] extraida: $c"
EOF
  done
  echo 'quit -noprompt'
} > "$W/extrai.tcl"
echo ">>> Magic: extracao de $(echo $CELULAS | wc -w) celulas"
( cd "$W" && magic -dnull -noconsole -rcfile "$RC" "$W/extrai.tcl" > "$W/extrai.log" 2>&1 ) || true
grep "\[INFO\] extraida" "$W/extrai.log" | sed 's/^/    /' || true

python3 - "$W" $CELULAS > "$DEST/12_extrai_celulas.txt" <<'PY'
import os, re, sys
w, cels = sys.argv[1], sys.argv[2:]
barr = ["AMUXBUS_A", "AMUXBUS_B", "VSSA", "VDDA", "VSWITCH", "VDDIO_Q", "VCCHIB", "VDDIO",
        "VCCD", "VSSIO", "VSSD", "VSSIO_Q"]
print("Extracao de cada celula do anel SOZINHA (Magic, GDS do PDK)\n")
print("Barramento ausente = fundido com outra porta dentro da celula (o Magic guarda um nome so).\n")
for c in cels:
    f = os.path.join(w, c + ".spice")
    if not os.path.exists(f):
        print(f"{c}: sem netlist (veja extrai.log)")
        continue
    txt = open(f, errors="replace").read().replace("\n+", " ")
    m = re.search(rf"^\.subckt\s+{re.escape(c)}\s+(.*)$", txt, re.M)
    portas = m.group(1).split() if m else []
    nomes = {p.split("/")[-1].split("_uq")[0] for p in portas}
    falta = [b for b in barr if b not in nomes]
    dup = sorted({p for p in portas if "_uq" in p})
    print(f"{c}")
    print(f"   {len(portas)} portas; barramentos ausentes: {', '.join(falta) or 'nenhum'}")
    if dup:
        print(f"   portas repetidas com sufixo _uq (mesmo rotulo em nos diferentes): {', '.join(dup)}")
    if "VSUBS" in txt:
        print("   tem no de substrato VSUBS")
PY
sed 's/^/    /' "$DEST/12_extrai_celulas.txt"
for c in $CELULAS; do [ -f "$W/$c.spice" ] && gzip -c "$W/$c.spice" > "$DEST/$c.spice.gz"; done
gzip -c "$W/extrai.log" > "$DEST/12_extrai_celulas.log.gz"
manda_git "$DEST"
