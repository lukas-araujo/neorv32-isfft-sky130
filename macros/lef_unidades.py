#!/usr/bin/env python3
"""
lef_unidades.py -- LEF das macros com UNITS DATABASE MICRONS 1000 (L21)

Projeto: NEORV32 + ISFFT em ASIC (sky130) -- ver DIARIO_GDSII.md, 13a sessao

O PROBLEMA
    A OpenRAM escreve os LEF com   UNITS DATABASE MICRONS 2000 ;
    O tech LEF do sky130 usa 1000 (1 unidade = 0,001 um). O OpenROAD nao
    aceita LEF de macro com resolucao MAIS FINA que a da tecnologia:
      [WARNING ODB-0205] ... convert factor (2000) is greater than the
                         database units per micron (1000)
      [ERROR ODB-0292] LEF data from ... is discarded due to errors

O QUE ESTE SCRIPT FAZ (no proprio arquivo, em macros/<m>/)
    1. confere que TODA coordenada do LEF tem no maximo 3 casas e cai na
       grade de fabricacao do sky130 (0,005 um) -- se nao cair, para;
    2. troca 2000 por 1000. Como as coordenadas estao em micrometros no
       arquivo, nenhum numero muda: so a resolucao declarada.

    Idempotente. O original fica no historico do git.

USO
    python3 macros/lef_unidades.py            # corrige as 4 macros
    python3 macros/lef_unidades.py --check    # so confere (sai 1 se faltar)
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
GRADE_NM = 5   # grade de fabricacao do sky130: 0,005 um


def main():
    so_confere = "--check" in sys.argv
    falhou = False
    for lef in sorted(AQUI.glob("*/*.lef")):
        t = lef.read_text()
        m = re.search(r"DATABASE MICRONS (\d+)\s*;", t)
        nome = lef.relative_to(AQUI.parent)
        if not m:
            print(f"ERRO: sem UNITS em {nome}"); falhou = True; continue
        if m.group(1) == "1000":
            print(f"ok (ja em 1000): {nome}"); continue
        if so_confere:
            print(f"FALTA corrigir ({m.group(1)}): {nome}"); falhou = True; continue
        nums = re.findall(r"(?<![\w.])-?\d+\.\d+", t)
        ruins = [n for n in nums
                 if len(n.split(".")[1].rstrip("0")) > 3
                 or round(abs(float(n)) * 1000) % GRADE_NM != 0]
        if ruins:
            print(f"ERRO: {nome}: {len(ruins)} coordenadas fora da grade, ex. {ruins[:5]}")
            falhou = True; continue
        lef.write_text(t[:m.start(1)] + "1000" + t[m.end(1):])
        print(f"corrigido (2000 -> 1000, {len(nums)} coordenadas na grade): {nome}")
    sys.exit(1 if falhou else 0)


if __name__ == "__main__":
    main()
