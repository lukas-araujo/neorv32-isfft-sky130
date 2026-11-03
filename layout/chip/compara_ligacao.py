#!/usr/bin/env python3
"""compara_ligacao.py -- LVS so da ligacao de topo, sem nomes (L89).

Etapa 12. O LVS pelo GDS com os pads inteiros (12_lvs_gds.sh) reprova DENTRO
dos pads: o SPICE/CDL da SkyWater nao descreve os pads do mesmo jeito que o
Magic extrai o GDS (resistor do bond pad, diodos, dedos de ESD). Isso nao diz
nada sobre a pergunta da L77: ha CURTO entre redes do anel (a sobra de met4
dos pads lvc encostando no vizinho)?

Aqui so a ligacao do chip_top: cada rede do topo vira uma ASSINATURA, o
multiconjunto de (celula, pino) que encostam nela. Compara-se o multiconjunto
de assinaturas do layout (netlist extraida, metal real do GDS) com o do
Verilog (chip_top.pnl.v). Nomes de instancia nao entram (o GDS nao os
guarda), nomes de rede tambem nao.
    curto  -> duas assinaturas do Verilog aparecem SOMADAS numa rede do layout
    aberto -> uma assinatura do Verilog aparece PARTIDA em duas no layout
Celulas so de alimentacao (decap, fill, tap) ficam de fora (milhares, sem
sinal); as redes de alimentacao continuam aparecendo pelos pads e pelo nucleo.

Uso: python3 compara_ligacao.py <netlist extraida .spice[.gz]> <chip_top.pnl.v[.gz]>
"""
import collections
import gzip
import re
import sys

FORA = re.compile(r"^sky130_(fd|ef)_sc_hd__(decap|fill|tapvpwrvgnd|tap)")


def abre(caminho):
    return gzip.open(caminho, "rt", errors="replace") if caminho.endswith(".gz") else open(caminho, errors="replace")


PORTAS = {}   # celula -> pinos, da netlist extraida (para completar o Verilog)


def layout(caminho):
    """[(celula, {pino: rede})] das instancias do .subckt chip_top"""
    txt = abre(caminho).read().replace("\n+", " ")
    portas = PORTAS
    for m in re.finditer(r"^\.subckt\s+(\S+)\s*(.*)$", txt, re.M | re.I):
        portas[m.group(1)] = [p for p in m.group(2).split() if "=" not in p]
    topo = re.search(r"^\.subckt\s+chip_top\b.*?\n(.*?)^\.ends", txt, re.S | re.M | re.I).group(1)
    r = []
    for l in topo.splitlines():
        t = [x for x in l.split() if "=" not in x]
        if not t or t[0][0] not in "Xx":
            continue
        cel = t[-1]
        redes = t[1:-1]
        if cel not in portas or len(portas[cel]) != len(redes):
            continue   # dispositivo solto no topo, ou celula sem cabecalho
        r.append((cel, dict(zip(portas[cel], redes))))
    return r


def verilog(caminho):
    """[(celula, {pino: rede})] das instancias do modulo chip_top"""
    txt = abre(caminho).read()
    txt = re.sub(r"//.*", "", txt)
    corpo = re.search(r"\bmodule\s+chip_top\b.*?;(.*?)\bendmodule", txt, re.S).group(1)
    r = []
    for m in re.finditer(r"\b([A-Za-z_][\w$]*)\s+(\\\S+|[A-Za-z_][\w$\[\]\.]*)\s*\((\s*\..*?)\)\s*;", corpo, re.S):
        cel = m.group(1)
        if cel in ("wire", "input", "output", "inout", "assign", "reg"):
            continue
        pinos = {}
        for p in re.finditer(r"\.(\w+)\s*\(\s*([^()]*?)\s*\)", m.group(3)):
            v = p.group(2).strip()
            if not v:
                continue
            if v.startswith("{"):
                # barramento concatenado: {msb, ..., lsb} -> PINO[n-1] ... PINO[0]
                partes = [x.strip() for x in v.strip("{}").split(",")]
                for i, x in enumerate(partes):
                    if x:
                        pinos[f"{p.group(1)}[{len(partes) - 1 - i}]"] = x
            else:
                pinos[p.group(1)] = v
        # pino sem ligacao no Verilog = rede de um pino so (como sai na extracao)
        for i, pino in enumerate(PORTAS.get(cel, [])):
            if pino not in pinos:
                pinos[pino] = f"__solto_{len(r)}_{i}"
        r.append((cel, pinos))
    return r


def assinaturas(insts):
    redes = collections.defaultdict(collections.Counter)
    for cel, pinos in insts:
        if FORA.match(cel):
            continue
        for pino, rede in pinos.items():
            redes[rede][(cel, pino)] += 1
    return {rede: frozenset(c.items()) for rede, c in redes.items()}


def fmt(ass, n=6):
    itens = sorted(ass, key=lambda x: (-x[1], x[0]))
    s = ", ".join(f"{k}x {c.replace('sky130_ef_io__', '').replace('sky130_fd_sc_hd__', '')}.{p}"
                  for (c, p), k in itens[:n])
    return s + (f", ... (+{len(itens) - n})" if len(itens) > n else "")


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    L, V = layout(sys.argv[1]), verilog(sys.argv[2])
    cl = collections.Counter(c for c, _ in L if not FORA.match(c))
    cv = collections.Counter(c for c, _ in V if not FORA.match(c))
    print(f"layout:  {sys.argv[1]}\nverilog: {sys.argv[2]}\n")
    print(f"{'celula':60s} {'layout':>7s} {'verilog':>7s}")
    for c in sorted(set(cl) | set(cv)):
        print(f"{c:60s} {cl[c]:7d} {cv[c]:7d}" + ("" if cl[c] == cv[c] else "   <-- diferente"))
    al, av = assinaturas(L), assinaturas(V)
    ml, mv = collections.Counter(al.values()), collections.Counter(av.values())
    so_l, so_v = ml - mv, mv - ml
    print(f"\nredes de topo (sem decap/fill/tap): layout {len(al)}, verilog {len(av)}")
    print(f"assinaturas iguais: {sum((ml & mv).values())}; so no layout: {sum(so_l.values())}; so no verilog: {sum(so_v.values())}")

    # diagnostico: uma assinatura do layout = soma de varias do verilog? (curto)
    sv = list(so_v.elements())
    for a in so_l.elements():
        ca = collections.Counter(dict(a))
        partes = [b for b in sv if not (collections.Counter(dict(b)) - ca)]
        soma = sum((collections.Counter(dict(b)) for b in partes), collections.Counter())
        if partes and soma == ca and len(partes) > 1:
            print(f"\n  CURTO? uma rede do layout junta {len(partes)} redes do verilog:")
            for b in partes:
                print(f"     {fmt(b)}")
        else:
            print(f"\n  so no layout: {fmt(a)}")
    for b in so_v.elements():
        print(f"\n  so no verilog: {fmt(b)}")

    # o anel: em quantas redes do layout cai cada barramento, e quais se juntam
    barr = ["AMUXBUS_A", "AMUXBUS_B", "VSSA", "VDDA", "VSWITCH", "VDDIO_Q", "VCCHIB", "VDDIO",
            "VCCD", "VSSIO", "VSSD", "VSSIO_Q"]
    print("\nAnel (pinos de barramento de todas as celulas sky130_ef_io):")
    for nome, insts in (("layout", L), ("verilog", V)):
        rede_de = collections.defaultdict(set)
        for cel, pinos in insts:
            if cel.startswith("sky130_ef_io__"):
                for b in barr:
                    if b in pinos:
                        rede_de[b].add(pinos[b])
        grupos = collections.defaultdict(list)
        for b in barr:
            grupos[frozenset(rede_de[b])].append(b)
        txt = "; ".join("=".join(g) + (f" ({len(k)} redes!)" if len(k) != 1 else "") for k, g in grupos.items())
        print(f"  {nome:8s} {len(grupos)} redes: {txt}")
    print("\nVeredito: " + ("ligacao de topo IGUAL (nenhum curto nem aberto entre celulas)"
                             if not so_l and not so_v else "ha diferencas (ver acima)"))


if __name__ == "__main__":
    main()
