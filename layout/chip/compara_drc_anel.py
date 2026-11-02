#!/usr/bin/env python3
"""compara_drc_anel.py -- DRC do chip x DRC das celulas sozinhas, GEOMETRICO (L83).

Etapa 12 (DIARIO_GDSII, 38a sessao). Substitui a comparacao por area total
(L81), que nao separava duas coisas:
  - caixas repetidas/recortadas pelos ladrilhos do Magic (a mesma caixa sai
    duas vezes; o recorte em x/y = 1100,96 e borda de ladrilho);
  - erros de INTERACAO entre subcelulas ("Can't overlap those layers",
    "can't abut or partially overlap between subcells"), que so existem com
    as celulas encostadas.

Metodo: cada caixa de erro de cada celula sozinha (ref) e levada para o lugar
de CADA instancia no chip (posicao e orientacao do DEF, tamanho do LEF).
Por regra, com regioes (uniao de caixas, sem repeticao):
    so_chip = erros do chip na faixa dos pads - erros levados das celulas
    so_ref  = erros das celulas que somem no chip (normal: o vizinho completa
              o desenho, ex. area minima de met5 de uma fatia de 1 um)
O que sobra em so_chip e listado com a instancia onde cai e a distancia ate a
borda dela (encosto = perto da borda). Regras separadas por CAMADA:
    metal/via   o que o nosso desenho poderia ter causado no anel
    dispositivo difusao, poco, poly, implantes: so existem DENTRO das celulas
                da foundry (no anel nao pusemos nenhuma dessas camadas)

Precisa do modulo de geometria do KLayout (klayout.db). No nix-shell do
LibreLane:  klayout -b -r compara_drc_anel.py   (entradas por variavel de
ambiente, ver main); fora dele: pip install klayout e python3.
"""
import os
import re
import sys

try:
    import klayout.db as db
except ImportError:  # dentro do "klayout -b -r"
    import pya as db

DBU = 0.001  # um por unidade das regioes (1 nm)
DIE = (2700.0, 2201.0)
FAIXA_PADS = 205.0

METAL = re.compile(r"\b(met[1-5]|metal[1-5]|via[1-4]?|mcon|li|local interconnect|v[1-4])\b", re.I)


def classe(regra):
    r = regra.lower()
    if any(k in r for k in ("diff", "tap", "nwell", "poly", "licon", "hvntm", "nsd", "psd",
                            "lu.", "transistor", "implant", "diffusion", "n-well", "deep n")):
        return "dispositivo"
    if METAL.search(r):
        return "metal/via"
    return "outra"


def caixa(x0, y0, x1, y1):
    return db.Box(int(round(x0 / DBU)), int(round(y0 / DBU)), int(round(x1 / DBU)), int(round(y1 / DBU)))


def na_faixa(x0, y0, x1, y1):
    cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
    return cx < FAIXA_PADS or cy < FAIXA_PADS or cx > DIE[0] - FAIXA_PADS or cy > DIE[1] - FAIXA_PADS


def le_rpt(caminho):
    linhas = open(caminho).read().splitlines()
    num = re.compile(r"^\s*(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um\s+(-?[\d.]+)um")
    regra, r = None, {}
    for i, l in enumerate(linhas):
        m = num.match(l)
        if m:
            if regra:
                b = tuple(map(float, m.groups()))
                if na_faixa(*b):
                    r.setdefault(regra, []).append(b)
        elif (l.strip() and not l.startswith("---") and 0 < i < len(linhas) - 1
              and linhas[i - 1].startswith("---") and linhas[i + 1].startswith("---")):
            regra = l.strip()
    return r


def le_ref(caminho):
    """BOX<tab>celula<tab>regra<tab>x0<tab>y0<tab>x1<tab>y1 (coordenadas da celula, um)"""
    r = {}
    for l in open(caminho):
        p = l.rstrip("\n").split("\t")
        if len(p) == 7 and p[0] == "BOX":
            r.setdefault(p[1], {}).setdefault(p[2], []).append(tuple(map(float, p[3:])))
    return r


def le_tamanhos(lefs):
    t = {}
    for f in lefs:
        txt = open(f, errors="replace").read()
        for m in re.finditer(r"^MACRO\s+(\S+)(.*?)^END\s+\1", txt, re.S | re.M):
            s = re.search(r"SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", m.group(2))
            if s:
                t[m.group(1)] = (float(s.group(1)), float(s.group(2)))
    return t


def le_def(caminho, celulas):
    txt = open(caminho).read()
    dbu = int(re.search(r"UNITS DISTANCE MICRONS (\d+)", txt).group(1))
    sec = re.search(r"\nCOMPONENTS \d+ ;(.*?)\nEND COMPONENTS", txt, re.S).group(1)
    inst = []
    for m in re.finditer(r"-\s+(\S+)\s+(\S+)(.*?);", sec, re.S):
        if m.group(2) not in celulas:
            continue
        p = re.search(r"\+\s+(?:PLACED|FIXED)\s+\(\s*(-?\d+)\s+(-?\d+)\s*\)\s+(\S+)", m.group(3))
        if p:
            inst.append((m.group(1), m.group(2), int(p.group(1)) / dbu, int(p.group(2)) / dbu, p.group(3)))
    return inst


def leva(b, W, H, px, py, ori):
    """caixa (x0,y0,x1,y1) da celula -> chip, com a orientacao DEF e o canto em (px,py)"""
    pts = [(b[0], b[1]), (b[2], b[3])]
    f = {
        "N": lambda x, y: (x, y),
        "S": lambda x, y: (W - x, H - y),
        "W": lambda x, y: (H - y, x),
        "E": lambda x, y: (y, W - x),
        "FN": lambda x, y: (W - x, y),
        "FS": lambda x, y: (x, H - y),
        "FW": lambda x, y: (y, x),
        "FE": lambda x, y: (H - y, W - x),
    }[ori]
    (ax, ay), (bx, by) = [f(x, y) for x, y in pts]
    return (px + min(ax, bx), py + min(ay, by), px + max(ax, bx), py + max(ay, by))


def contorno(W, H, px, py, ori):
    return leva((0, 0, W, H), W, H, px, py, ori)


def main():
    rpt, ref, deff = os.environ["CDA_RPT"], os.environ["CDA_REF"], os.environ["CDA_DEF"]
    lefs = [x for x in os.environ["CDA_LEFS"].split(":") if x]
    chip = le_rpt(rpt)
    refs = le_ref(ref)
    tam = le_tamanhos(lefs)
    inst = le_def(deff, set(refs) | set(tam))
    falta = sorted({c for _, c, *_ in inst if c not in tam})
    if falta:
        print("AVISO: sem SIZE no LEF para:", ", ".join(falta))
    contornos = [(n, c, contorno(*tam[c], px, py, o)) for n, c, px, py, o in inst if c in tam]
    print(f"DRC do chip: {rpt}")
    print(f"instancias do anel no DEF: {len(contornos)}; celulas com DRC sozinhas: {len(refs)}")

    # erros das celulas levados para o chip
    levado = {}
    for n, c, px, py, o in inst:
        if c not in tam or c not in refs:
            continue
        W, H = tam[c]
        for regra, bs in refs[c].items():
            reg = levado.setdefault(regra, db.Region())
            for b in bs:
                reg.insert(caixa(*leva(b, W, H, px, py, o)))

    def area(reg):
        return reg.area() * DBU * DBU

    linhas, sobras = [], []
    for regra in sorted(set(chip) | set(levado)):
        rc = db.Region()
        for b in chip.get(regra, []):
            rc.insert(caixa(*b))
        rc.merge()
        rr = levado.get(regra, db.Region())
        rr.merge()
        so_chip = (rc - rr).merged()
        so_ref = (rr - rc).merged()
        linhas.append((classe(regra), regra, area(rc), area(rr), area(so_chip), area(so_ref)))
        if area(so_chip) > 1e-6:
            sobras.append((classe(regra), regra, so_chip))

    print(f"\n{'classe':12s} {'chip um2':>11s} {'celulas um2':>11s} {'so chip':>9s} {'so celula':>9s}  regra")
    for cl in ("metal/via", "outra", "dispositivo"):
        for c, regra, a, b, sc, sr in sorted([x for x in linhas if x[0] == cl], key=lambda x: -x[4]):
            print(f"{c:12s} {a:11.4f} {b:11.4f} {sc:9.4f} {sr:9.4f}  {regra}")

    print("\nOnde cai o que so existe no chip (por regra; ate 6 trechos):")
    for cl, regra, reg in sorted(sobras, key=lambda x: (x[0] != "metal/via", -x[2].area())):
        print(f"\n[{cl}] {regra}: {area(reg):.4f} um2 em {reg.count()} trecho(s)")
        trechos = sorted(reg.each_merged(), key=lambda p: -p.area())[:6]
        for p in trechos:
            bb = p.bbox()
            x0, y0, x1, y1 = bb.left * DBU, bb.bottom * DBU, bb.right * DBU, bb.top * DBU
            cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
            onde = [(n, c, k) for n, c, k in contornos if k[0] <= cx <= k[2] and k[1] <= cy <= k[3]]
            if onde:
                n, c, k = onde[0]
                borda = min(cx - k[0], k[2] - cx, cy - k[1], k[3] - cy)
                txt = f"em {n} ({c.replace('sky130_ef_io__', '')}), a {borda:.2f} um da borda"
            else:
                txt = "fora de todas as celulas do anel"
            print(f"   {x0:9.3f} {y0:9.3f} {x1:9.3f} {y1:9.3f}  {txt}")

    tem_metal = [s for s in sobras if s[0] == "metal/via"]
    print("\nVeredito:")
    if not tem_metal:
        print("  metal/via: nada so no chip -- o encosto com o nosso metal nao criou erro de DRC no anel.")
    else:
        print(f"  metal/via: {len(tem_metal)} regra(s) com erro so no chip -- olhar os trechos acima.")
    nd = [s for s in sobras if s[0] != "metal/via"]
    print(f"  dispositivo/outra: {len(nd)} regra(s) com erro so no chip (camadas que so existem dentro"
          " das celulas da foundry: ver os trechos e a distancia ate a borda).")


if __name__ == "__main__" or "pya" in sys.modules:   # python3, ou "klayout -b -r"
    main()
