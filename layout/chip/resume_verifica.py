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


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "drc":
        drc(sys.argv[2])
    elif len(sys.argv) == 3 and sys.argv[1] == "lvs":
        lvs(sys.argv[2])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
