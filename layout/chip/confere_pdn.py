#!/usr/bin/env python3
"""confere_pdn.py -- o PDN do chip liga mesmo nos pads e no nucleo?

Etapa 11 parte 2a (DIARIO_GDSII, 37a sessao). O check_power_grid do OpenROAD
nao funciona no chip (PSM-0025: a rede vccd nao tem pino de topo, a
alimentacao entra pelo pad; L68). Este script olha a geometria no DEF do passo
de PDN e conta, para vccd e vssd:

  1. fios e vias na faixa entre cada pad de alimentacao e o anel
     (o que o -connect_to_pads deveria ter criado);
  2. as pontes met5 ate o nucleo (pdn_chip.tcl, L65);
  3. o anel (fios de 5 um de largura).

Uso:
  python3 layout/chip/confere_pdn.py <run>/NN-openroad-generatepdn/chip_top.def
Le so o DEF (texto); nao precisa do nix-shell.
"""
import re
import sys

REDES = ("vccd", "vssd")


def le_def(caminho):
    txt = open(caminho).read()
    dbu = int(re.search(r"UNITS DISTANCE MICRONS (\d+)", txt).group(1))
    # instancias (para achar os pads): - nome celula + PLACED ( x y ) ORIENT
    comps = {}
    sec = re.search(r"\nCOMPONENTS \d+ ;(.*?)\nEND COMPONENTS", txt, re.S)
    for m in re.finditer(r"-\s+(\S+)\s+(\S+)(.*?);", sec.group(1), re.S):
        p = re.search(r"\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", m.group(3))
        if p:
            comps[m.group(1)] = (m.group(2), int(p.group(1)), int(p.group(2)), p.group(3))
    sec = re.search(r"\nSPECIALNETS \d+ ;(.*?)\nEND SPECIALNETS", txt, re.S)
    formas = {r: [] for r in REDES}  # (tipo, camada/via, x0, y0, x1, y1)
    for bloco in re.split(r"\n\s*-\s+", "\n" + sec.group(1))[1:]:
        nome = bloco.split()[0]
        if nome not in REDES:
            continue
        toks = re.findall(r"\(|\)|[^\s()]+", bloco)
        i, camada, larg, pts = 0, None, 0, []

        def fecha():
            for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
                h = larg // 2
                if ya == yb:
                    formas[nome].append(("fio", camada, min(xa, xb), ya - h, max(xa, xb), ya + h))
                else:
                    formas[nome].append(("fio", camada, xa - h, min(ya, yb), xa + h, max(ya, yb)))

        while i < len(toks):
            t = toks[i]
            if t in ("ROUTED", "NEW", "FIXED", "COVER") and i + 2 < len(toks):
                fecha()
                camada, larg, pts = toks[i + 1], int(toks[i + 2]), []
                i += 3
                continue
            if t == "RECT" and toks[i + 1] != "(":
                c = toks[i + 1]
                x0, y0, x1, y1 = (int(toks[i + 3]), int(toks[i + 4]), int(toks[i + 7]), int(toks[i + 8]))
                formas[nome].append(("fio", c, min(x0, x1), min(y0, y1), max(x0, x1), max(y0, y1)))
                i += 10
                continue
            if t == "(" and camada is None:  # ( * VPWR ) do cabecalho da rede
                i = toks.index(")", i) + 1
                continue
            if t == "(":
                x = toks[i + 1]
                y = toks[i + 2]
                j = i + 3
                if toks[j] != ")":  # extensao opcional
                    j += 1
                xp = pts[-1][0] if x == "*" else int(x)
                yp = pts[-1][1] if y == "*" else int(y)
                pts.append((xp, yp))
                i = j + 1
                # via logo depois do ponto
                if i < len(toks) and toks[i] not in ("(", "NEW", "+", ";") and not toks[i].startswith("+"):
                    formas[nome].append(("via", toks[i], xp, yp, xp, yp))
                    i += 1
                continue
            i += 1
        fecha()
    return dbu, comps, formas


def cruza(f, x0, y0, x1, y1):
    return f[2] <= x1 and f[4] >= x0 and f[3] <= y1 and f[5] >= y0


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    dbu, comps, formas = le_def(sys.argv[1])
    um = lambda v: v / dbu
    print(f"DEF: {sys.argv[1]}")
    print(f"formas especiais: vccd {len(formas['vccd'])}, vssd {len(formas['vssd'])}")

    # 1. pads de alimentacao: faixa entre a borda interna do pad e o anel
    print("\n1. Ligacao pad -> anel (fios/vias em y = 150-280 um: entre o pad e o anel, ~283-295)")
    print(f"   {'pad':10s} {'celula':38s} {'rede':5s} {'fios':>5s} {'vias':>5s}  camadas")
    for inst, rede in (("pad_vccd", "vccd"), ("pad_vssd", "vssd")):
        if inst not in comps:
            print(f"   {inst}: nao achei no DEF")
            continue
        cel, x, y, ori = comps[inst]
        # pads do lado sul (R180 no DEF fica como "S"): ~200 um de altura, 75 de largura
        x0, x1 = x, x + 75 * dbu
        y0, y1 = y + 150 * dbu, y + 280 * dbu
        sel = [f for f in formas[rede] if cruza(f, x0, y0, x1, y1)]
        fios = [f for f in sel if f[0] == "fio"]
        vias = [f for f in sel if f[0] == "via"]
        cams = sorted({f[1] for f in fios})
        print(f"   {inst:10s} {cel:38s} {rede:5s} {len(fios):5d} {len(vias):5d}  {','.join(cams)}  "
              f"(pad em x={um(x):.1f} y={um(y):.1f} {ori})")

    # 2. pontes ate o nucleo
    print("\n2. Pontes met5 ate o nucleo (sobrepoem a borda direita da macro)")
    if "u_core" in comps:
        _, mx, my, _ = comps["u_core"]
        borda = mx + 2000 * dbu
        for rede in REDES:
            p = [f for f in formas[rede] if f[0] == "fio" and f[1] == "met5"
                 and f[2] < borda < f[4] and f[2] > borda - 40 * dbu]
            ys = ", ".join(f"{um((f[3] + f[5]) / 2):.2f}" for f in sorted(p, key=lambda f: f[3])[:3])
            print(f"   {rede}: {len(p)} pontes (centros y: {ys} ...)")

    # 3. anel (largura 5 um)
    print("\n3. Anel do chip (fios met4/met5 com 5 um de largura)")
    for rede in REDES:
        a = [f for f in formas[rede] if f[0] == "fio" and min(f[4] - f[2], f[5] - f[3]) == 5 * dbu]
        if a:
            bx = (um(min(f[2] for f in a)), um(min(f[3] for f in a)),
                  um(max(f[4] for f in a)), um(max(f[5] for f in a)))
            print(f"   {rede}: {len(a)} lados, caixa ({bx[0]:.1f}, {bx[1]:.1f}) - ({bx[2]:.1f}, {bx[3]:.1f})")
        else:
            print(f"   {rede}: nenhum fio de 5 um")


if __name__ == "__main__":
    main()
