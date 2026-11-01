#!/usr/bin/env python3
"""resume_verifica.py -- resumo do DRC (Magic) e do LVS (Netgen) do chip.

Etapa 12 (DIARIO_GDSII, 38a sessao). Le so texto; nao precisa do nix-shell.

  python3 resume_verifica.py drc <drc.magic.rpt>
      erros por regra e por REGIAO do chip:
        nucleo  dentro da caixa da macro u_core (350..2350 x 350..1850 um):
                so o abstrato (maglef) do nucleo, o miolo ja passou na etapa 8
        anel    a faixa dos pads (ate 205 um da borda do die 2700 x 2201)
        chip    o resto: PDN do chip, pontes, ligacao pad -> anel, roteamento
                pad <-> nucleo (o que foi desenhado nas etapas 11 e 12)

  python3 resume_verifica.py celulas <netlist extraida .spice>
      celulas do anel (pads, cantos, fatias) e quantas instancias de cada.

  python3 resume_verifica.py anel <drc.magic.rpt> <ref.tsv> <netlist .spice>
      compara, por regra, a AREA de erro na faixa dos pads com a soma do DRC
      de cada celula sozinha (ref.tsv do 12_drc_celulas.sh) x instancias (L81).

  python3 resume_verifica.py lvs <lvs.netgen.rpt>
      resultado final, numero de dispositivos/redes dos dois lados e as
      linhas de diferenca (as marcadas com "**Mismatch**" e as de pinos).
"""
import re
import sys

DIE = (2700.0, 2201.0)
NUCLEO = (350.0, 350.0, 2350.0, 1850.0)
FAIXA_PADS = 205.0


def regiao(x0, y0, x1, y1):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    if NUCLEO[0] <= cx <= NUCLEO[2] and NUCLEO[1] <= cy <= NUCLEO[3]:
        return "nucleo"
    if cx < FAIXA_PADS or cy < FAIXA_PADS or cx > DIE[0] - FAIXA_PADS or cy > DIE[1] - FAIXA_PADS:
        return "anel"
    return "chip"


def drc(caminho):
    linhas = open(caminho).read().splitlines()
    regra, cont, exemplo = None, {}, {}
    num = re.compile(r"^\s*(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um")
    for i, l in enumerate(linhas):
        m = num.match(l)
        if m:
            if regra:
                caixa = tuple(map(float, m.groups()))
                chave = (regra, regiao(*caixa))
                cont[chave] = cont.get(chave, 0) + 1
                exemplo.setdefault(chave, caixa)
        elif (l.strip() and not l.startswith("---") and 0 < i < len(linhas) - 1
              and linhas[i - 1].startswith("---") and linhas[i + 1].startswith("---")):
            regra = l.strip()   # cabecalho: "----" / "<regra>" / "----"
    total = sum(cont.values())
    print(f"DRC: {caminho}")
    print(f"total de caixas: {total}")
    for reg in ("chip", "anel", "nucleo"):
        sub = {k: v for k, v in cont.items() if k[1] == reg}
        print(f"\n[{reg}] {sum(sub.values())} caixas")
        for (r, _), v in sorted(sub.items(), key=lambda kv: -kv[1]):
            e = exemplo[(r, reg)]
            print(f"  {v:6d}  {r}   (ex.: {e[0]:.3f} {e[1]:.3f} {e[2]:.3f} {e[3]:.3f})")


def lvs(caminho):
    txt = open(caminho, errors="replace").read()
    print(f"LVS: {caminho}")
    finais = re.findall(r"Final result: (.*)", txt)
    print("resultado final:", finais[-1] if finais else "(nao achei 'Final result')")
    for chave in ("Number of devices", "Number of nets"):
        for l in re.findall(rf"{chave}:.*", txt)[-1:]:
            print("  " + re.sub(r"\s+", " ", l))
    for padrao in ("Netlists do not match", "Netlists match", "Cell pin lists",
                   "Top level cell failed pin matching", "has no matching", "disconnected pin",
                   "Mismatch", "Circuit 1 contains", "Circuit 2 contains", "flattened",
                   "black-box", "blackbox"):
        ls = [l.strip() for l in txt.splitlines() if padrao.lower() in l.lower()]
        if ls:
            print(f"\n'{padrao}': {len(ls)} linha(s)")
            unicas = {}
            for l in ls:
                l = re.sub(r"\s+", " ", l)[:200]
                unicas[l] = unicas.get(l, 0) + 1
            for l, n in list(unicas.items())[:15]:
                print(f"   {n:4d}x {l}")


def instancias(spice):
    """{celula: n} das instancias no .subckt chip_top da netlist extraida."""
    txt = open(spice, errors="replace").read().replace("\n+", " ")
    subs = set(re.findall(r"^\.subckt (\S+)", txt, re.M))
    top = re.search(r"\.subckt chip_top.*?\n(.*?)\n\.ends", txt, re.S).group(1)
    n = {}
    for l in top.splitlines():
        if l.startswith("X"):
            cel = [t for t in l.split() if t in subs]
            if cel:
                n[cel[-1]] = n.get(cel[-1], 0) + 1
    return n


def do_anel(n):
    return {c: k for c, k in n.items()
            if not c.startswith(("sky130_fd_sc_hd", "sky130_ef_sc_hd")) and c != "asic_top"}


def celulas(spice):
    for c, k in sorted(do_anel(instancias(spice)).items()):
        print(f"{k:5d} {c}")


def caixas_drc(caminho):
    """[(regra, x0, y0, x1, y1)] do drc.magic.rpt"""
    linhas = open(caminho).read().splitlines()
    num = re.compile(r"^\s*(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um")
    regra, r = None, []
    for i, l in enumerate(linhas):
        m = num.match(l)
        if m:
            if regra:
                r.append((regra,) + tuple(map(float, m.groups())))
        elif (l.strip() and not l.startswith("---") and 0 < i < len(linhas) - 1
              and linhas[i - 1].startswith("---") and linhas[i + 1].startswith("---")):
            regra = l.strip()
    return r


def anel(rpt, ref_tsv, spice):
    """area de erro por regra: chip (faixa dos pads) x soma das celulas sozinhas"""
    n = do_anel(instancias(spice))
    chip, exemplo = {}, {}
    for regra, x0, y0, x1, y1 in caixas_drc(rpt):
        if regiao(x0, y0, x1, y1) != "anel":
            continue
        chip[regra] = chip.get(regra, 0.0) + (x1 - x0) * (y1 - y0)
        exemplo.setdefault(regra, []).append((x0, y0, x1, y1))
    esperado, origem = {}, {}
    for l in open(ref_tsv):
        p = l.rstrip("\n").split("\t")
        if len(p) != 4:
            continue
        cel, regra, _k, area = p[0], p[1], int(p[2]), float(p[3])
        esperado[regra] = esperado.get(regra, 0.0) + area * n.get(cel, 0)
        origem.setdefault(regra, set()).add(cel.replace("sky130_ef_io__", "").replace("sky130_fd_io__", ""))
    print("Instancias do anel (netlist extraida):")
    for c, k in sorted(n.items()):
        print(f"  {k:5d} {c}")
    print(f"\n{'area chip (um2)':>16s} {'soma celulas':>14s} {'dif. %':>7s}  regra  [celulas onde aparece sozinha]")
    tot_c = tot_e = 0.0
    sobra = []
    for regra in sorted(set(chip) | set(esperado), key=lambda r: -max(chip.get(r, 0), esperado.get(r, 0))):
        c, e = chip.get(regra, 0.0), esperado.get(regra, 0.0)
        tot_c += c
        tot_e += e
        dif = 100.0 * (c - e) / e if e else float("inf")
        marca = "" if abs(c - e) <= max(1e-6, 0.001 * max(c, e)) else "  <-- DIFERENTE"
        cels = ",".join(sorted(origem.get(regra, [])))[:60]
        print(f"{c:16.4f} {e:14.4f} {dif:7.2f}  {regra}  [{cels}]{marca}")
        if marca:
            sobra.append(regra)
    print(f"{tot_c:16.4f} {tot_e:14.4f}  TOTAL")
    if not sobra:
        print("\nVeredito: todo erro da faixa dos pads aparece nas celulas SOZINHAS, na mesma area:"
              " erro interno das celulas da foundry, nenhum de encosto.")
    else:
        print(f"\nVeredito: {len(sobra)} regra(s) com area diferente -- olhar as caixas abaixo:")
        for regra in sobra:
            print(f"  {regra}")
            for cx in exemplo.get(regra, [])[:8]:
                print("     %.3f %.3f %.3f %.3f" % cx)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "celulas":
        celulas(sys.argv[2])
        return
    if len(sys.argv) == 5 and sys.argv[1] == "anel":
        anel(sys.argv[2], sys.argv[3], sys.argv[4])
        return
    if len(sys.argv) == 3 and sys.argv[1] == "drc":
        drc(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "lvs":
        lvs(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
