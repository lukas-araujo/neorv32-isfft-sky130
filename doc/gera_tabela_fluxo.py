#!/usr/bin/env python3
"""
gera_tabela_fluxo.py -- tabela do fluxo RTL -> layout (mesmo padrao do diagrama)
Saida: doc/tabela_fluxo.svg  (PNG: python3 render_png.py tabela_fluxo.svg)
Para atualizar a situacao, mude a ultima coluna de ETAPAS e rode de novo.
"""
import os

FASES = [
    ("Front-end — RTL e simulação", [
        ("1", "Gerar as macros SRAM", "OpenRAM", "Notebook", "feito"),
        ("2", "Converter o NEORV32 para Verilog", "GHDL", "Notebook", "feito"),
        ("3", "RTL novo: memórias, conversores, ISFFT, topo", "Verilog", "Notebook", "feito"),
        ("4", "Firmware com DMA + SLINK", "riscv-none-elf-gcc", "Notebook", "feito"),
        ("5", "Simulação do chip (EVM igual à Kria)", "Icarus Verilog", "Notebook", "feito"),
    ]),
    ("Síntese e verificação", [
        ("6", "Síntese lógica", "Genus", "VM", "proximo"),
        ("7", "Equivalência RTL × netlist", "Conformal LEC", "VM", "afazer"),
        ("8", "Simulação pós-síntese", "Xcelium", "VM", "afazer"),
    ]),
    ("Back-end — layout", [
        ("9", "Floorplan, place, CTS e roteamento", "LibreLane (OpenROAD)", "Notebook", "afazer"),
        ("10", "DRC, LVS e GDSII", "Magic · Netgen · KLayout", "Notebook", "afazer"),
    ]),
]
NOTA = "Se der tempo: STA com parasitas extraídos (Tempus) e potência (Joules)."

FONT = "Roboto, Arial, sans-serif"
C = dict(fundo="#FFFFFF", faixa="#F1EEE8", borda="#8C8C8C", linha="#D9D5CC",
         txt="#2C2C2A", txt2="#444441", fase="#444441",
         g_fill="#E1F3EE", g_stroke="#0F6E56", g_t="#0B4F3E",
         p_fill="#EEEDFB", p_stroke="#534AB7", p_t="#3C3489",
         n_fill="#FFFFFF", n_stroke="#8C8C8C", n_t="#6B6B66")
SIT = {"feito": ("Feito", "g", False), "proximo": ("Próximo", "p", False), "afazer": ("A fazer", "n", True)}

W = 2000
X0, X1 = 118, 1882                       # mesma margem do diagrama
COL = [X0 + 40, X0 + 130, 1045, 1482, 1662]   # #, etapa, ferramenta, onde, situacao
RH, FH, HH = 96, 84, 96                  # linha, faixa de fase, cabecalho
n_linhas = sum(len(f[1]) for f in FASES)
H = 60 + HH + len(FASES) * FH + n_linhas * RH + 150

o = []
e = o.append
e(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
e(f'<rect width="{W}" height="{H}" fill="{C["fundo"]}"/>')
top = 60
alt = HH + len(FASES) * FH + n_linhas * RH
e(f'<rect x="{X0}" y="{top}" width="{X1-X0}" height="{alt}" rx="36" fill="{C["fundo"]}" stroke="{C["borda"]}" stroke-width="2"/>')
# cabecalho
e(f'<path d="M {X0} {top+HH} L {X0} {top+36} Q {X0} {top} {X0+36} {top} L {X1-36} {top} Q {X1} {top} {X1} {top+36} L {X1} {top+HH} Z" fill="{C["faixa"]}" stroke="{C["borda"]}" stroke-width="2"/>')
for x, t in zip(COL, ["#", "Etapa", "Ferramenta", "Onde", "Situação"]):
    e(f'<text x="{x}" y="{top+HH/2+13}" font-size="36" font-weight="500" fill="{C["txt2"]}">{t}</text>')
y = top + HH
for fase, linhas in FASES:
    e(f'<rect x="{X0+1}" y="{y}" width="{X1-X0-2}" height="{FH}" fill="{C["faixa"]}"/>')
    e(f'<line x1="{X0}" y1="{y}" x2="{X1}" y2="{y}" stroke="{C["borda"]}" stroke-width="2"/>')
    e(f'<text x="{COL[0]}" y="{y+FH/2+12}" font-size="34" fill="{C["fase"]}">{fase}</text>')
    y += FH
    for i, (n, etapa, ferr, onde, sit) in enumerate(linhas):
        if i:
            e(f'<line x1="{X0+30}" y1="{y}" x2="{X1-30}" y2="{y}" stroke="{C["linha"]}" stroke-width="2"/>')
        cy = y + RH/2 + 12
        e(f'<text x="{COL[0]}" y="{cy}" font-size="36" fill="{C["txt2"]}">{n}</text>')
        e(f'<text x="{COL[1]}" y="{cy}" font-size="36" fill="{C["txt"]}">{etapa}</text>')
        e(f'<text x="{COL[2]}" y="{cy}" font-size="36" font-weight="500" fill="{C["txt"]}">{ferr}</text>')
        e(f'<text x="{COL[3]}" y="{cy}" font-size="36" fill="{C["txt2"]}">{onde}</text>')
        rot, tipo, tr = SIT[sit]
        dash = ' stroke-dasharray="10 7"' if tr else ""
        e(f'<rect x="{COL[4]}" y="{y+18}" width="190" height="{RH-36}" rx="30" fill="{C[tipo+"_fill"]}" stroke="{C[tipo+"_stroke"]}" stroke-width="2"{dash}/>')
        e(f'<text x="{COL[4]+95}" y="{y+RH/2+11}" font-size="32" fill="{C[tipo+"_t"]}" text-anchor="middle">{rot}</text>')
        y += RH
e(f'<text x="{X0+40}" y="{y+80}" font-size="34" fill="{C["txt2"]}">{NOTA}</text>')
e('</svg>')
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tabela_fluxo.svg"), "w").write("\n".join(o))
print("tabela_fluxo.svg")
