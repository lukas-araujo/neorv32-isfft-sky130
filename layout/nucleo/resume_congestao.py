#!/usr/bin/env python3
"""resume_congestao.py -- resume o relatorio de congestao do roteamento global

Uso: python3 resume_congestao.py <06_congestao.rpt> <config.json>

Le o arquivo que o `global_route -congestion_report_file` escreve (formato
do DRC Viewer: uma regiao por vez, com capacidade, uso, excesso e a caixa
na camada) e imprime:
  - excesso por camada;
  - as regioes de 100 x 100 um com mais excesso, e onde ficam em relacao
    as macros (posicao do config.json + tamanho do LEF).
Chamado pelo diag_congestao.sh.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

rpt, cfg_path = Path(sys.argv[1]), Path(sys.argv[2])
texto = rpt.read_text(errors="replace")

# bbox = (x1, y1) - (x2, y2) on Layer met2
re_bbox = re.compile(r"bbox\s*=\s*\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)\s*-\s*"
                     r"\(\s*([-\d.]+)\s*,\s*([-\d.]+)\s*\)\s*on\s+Layer\s+(\S+)")
re_over = re.compile(r"overflow\s*[:=]\s*(-?\d+)")

regioes = []          # (x, y, camada, excesso)
excesso = None
for linha in texto.splitlines():
    m = re_over.search(linha)
    if m:
        excesso = int(m.group(1))
    m = re_bbox.search(linha)
    if m:
        x1, y1, x2, y2 = (float(v) for v in m.groups()[:4])
        regioes.append(((x1 + x2) / 2, (y1 + y2) / 2, m.group(5),
                        excesso if excesso is not None else 1))
        excesso = None

if not regioes:
    print("Nao reconheci o formato do relatorio. Primeiras linhas:")
    print("\n".join(texto.splitlines()[:20]))
    sys.exit(0)

# Caixas das macros: canto do config + SIZE do LEF (N/S/FN/FS nao giram)
cfg = json.loads(cfg_path.read_text())
macros = {}
for nome, m in cfg.get("MACROS", {}).items():
    lef = Path(m["lef"][0].replace("dir::", str(cfg_path.parent) + "/"))
    w = h = 0.0
    for l in lef.read_text(errors="replace").splitlines():
        s = re.match(r"\s*SIZE\s+([\d.]+)\s+BY\s+([\d.]+)", l)
        if s:
            w, h = float(s.group(1)), float(s.group(2))
            break
    for inst, d in m["instances"].items():
        x0, y0 = d["location"]
        apelido = {"sram_8kbyte_1rw_32x2048_8": "IMEM", "sram_4kbyte_1rw_32x1024_8": "DMEM",
                   "sram_1rw1r_64x256": "out_mem", "sram_1rw1r_64x64_wpr2": "in_mem"}.get(nome, nome)
        macros[apelido] = (x0, y0, x0 + w, y0 + h)


def onde(x, y):
    perto = []
    for n, (a, b, c, d) in macros.items():
        dx = max(a - x, 0, x - c)
        dy = max(b - y, 0, y - d)
        if dx == 0 and dy == 0:
            return f"sobre {n}"
        dist = (dx * dx + dy * dy) ** 0.5
        if dist <= 60:
            lado = ("acima" if y > d else "abaixo" if y < b else
                    "a direita" if x > c else "a esquerda")
            perto.append((dist, f"{lado} de {n} ({dist:.0f} um)"))
    if perto:
        return min(perto)[1]
    return "logica (longe das macros)"


por_camada = defaultdict(lambda: [0, 0])
por_celula = defaultdict(lambda: [0, 0, defaultdict(int)])
for x, y, cam, ov in regioes:
    por_camada[cam][0] += 1
    por_camada[cam][1] += ov
    k = (int(x // 100) * 100, int(y // 100) * 100)
    por_celula[k][0] += 1
    por_celula[k][1] += ov
    por_celula[k][2][cam] += ov

total = sum(v[1] for v in por_camada.values())
print(f"Regioes congestionadas no relatorio: {len(regioes)}; excesso somado: {total}")
print()
print("| Camada | Regioes | Excesso |")
print("|---|---|---|")
for cam in sorted(por_camada):
    print(f"| {cam} | {por_camada[cam][0]} | {por_camada[cam][1]} |")
print()
print("Regioes de 100 x 100 um com mais excesso:")
print()
print("| x (um) | y (um) | Excesso | % do total | Camadas | Onde |")
print("|---|---|---|---|---|---|")
for (x, y), (n, ov, cams) in sorted(por_celula.items(), key=lambda kv: -kv[1][1])[:15]:
    c = ", ".join(f"{k} {v}" for k, v in sorted(cams.items(), key=lambda kv: -kv[1]))
    print(f"| {x}-{x+100} | {y}-{y+100} | {ov} | {100*ov/max(total,1):.1f} % | {c} | {onde(x+50, y+50)} |")

# Quanto do excesso esta a ate 60 um de alguma macro
perto = sum(ov for x, y, _, ov in regioes if not onde(x, y).startswith("logica"))
print()
print(f"Excesso a ate 60 um de alguma macro (ou sobre ela): {perto} de {total} "
      f"({100*perto/max(total,1):.0f} %)")
