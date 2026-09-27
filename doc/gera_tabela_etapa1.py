#!/usr/bin/env python3
"""
gera_tabela_etapa1.py -- resultado da etapa 1 do layout (leitura do netlist)
Saida: doc/tabela_etapa1.svg  (PNG: python3 render_png.py tabela_etapa1.svg)
Numeros: resultados/2026-09-27_1932_layout_nucleo/ (01_leitura.txt e
metricas) e DIARIO_GDSII.md, 9a e 10a sessoes.
"""
import os
LINHAS = [
    ("Entrada", "netlist do Genus: 60.038 células, 4 macros, 10 conb_1", "ok"),
    ("Achatar a hierarquia", "25.960 → 0 assign; 247.493 pinos com a mesma ligação", "ok"),
    ("Checagens do LibreLane", "0 problemas · 0 células não mapeadas · 4/4 macros", "ok"),
    ("Células proibidas no layout", "227 instâncias de 5 células _0 (drc_exclude)", "atencao"),
    ("Timing sem fios nem árvore de clock", "não conclusivo: vale depois do CTS (etapa 5)", "info"),
]
FONT = "Roboto, Arial, sans-serif"
C = dict(fundo="#FFFFFF", faixa="#F1EEE8", borda="#8C8C8C", linha="#D9D5CC", txt="#2C2C2A", txt2="#444441",
         g_fill="#E1F3EE", g_stroke="#0F6E56", g_t="#0B4F3E",
         a_fill="#FBF0DC", a_stroke="#A8660A", a_t="#7A4A06",
         n_fill="#FFFFFF", n_stroke="#8C8C8C", n_t="#6B6B66")
SIT = {"ok": ("OK", "g", False), "atencao": ("Corrigir", "a", False), "info": ("Informativo", "n", True)}
W = 2400; X0, X1 = 118, W - 118
COL = [X0 + 40, 930, X1 - 250]
RH, HH = 96, 96
H = 60 + HH + len(LINHAS) * RH + 60
o = []; e = o.append
e(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
e(f'<rect width="{W}" height="{H}" fill="{C["fundo"]}"/>')
top = 60; alt = HH + len(LINHAS) * RH
e(f'<rect x="{X0}" y="{top}" width="{X1-X0}" height="{alt}" rx="36" fill="{C["fundo"]}" stroke="{C["borda"]}" stroke-width="2"/>')
e(f'<path d="M {X0} {top+HH} L {X0} {top+36} Q {X0} {top} {X0+36} {top} L {X1-36} {top} Q {X1} {top} {X1} {top+36} L {X1} {top+HH} Z" fill="{C["faixa"]}" stroke="{C["borda"]}" stroke-width="2"/>')
for x, t in zip(COL, ["Etapa 1 — leitura do netlist", "Resultado", "Situação"]):
    e(f'<text x="{x}" y="{top+HH/2+13}" font-size="36" font-weight="500" fill="{C["txt2"]}">{t}</text>')
y = top + HH
for i, (a, b, s) in enumerate(LINHAS):
    if i: e(f'<line x1="{X0+30}" y1="{y}" x2="{X1-30}" y2="{y}" stroke="{C["linha"]}" stroke-width="2"/>')
    cy = y + RH/2 + 12
    e(f'<text x="{COL[0]}" y="{cy}" font-size="34" fill="{C["txt"]}">{a}</text>')
    e(f'<text x="{COL[1]}" y="{cy}" font-size="34" fill="{C["txt"]}">{b}</text>')
    rot, t, tr = SIT[s]; dash = ' stroke-dasharray="10 7"' if tr else ""
    e(f'<rect x="{COL[2]}" y="{y+18}" width="210" height="{RH-36}" rx="30" fill="{C[t+"_fill"]}" stroke="{C[t+"_stroke"]}" stroke-width="2"{dash}/>')
    e(f'<text x="{COL[2]+105}" y="{y+RH/2+11}" font-size="31" fill="{C[t+"_t"]}" text-anchor="middle">{rot}</text>')
    y += RH
e('</svg>')
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "tabela_etapa1.svg"), "w").write("\n".join(o))
print("tabela_etapa1.svg")
