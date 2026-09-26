#!/usr/bin/env python3
"""
gera_diagrama.py -- diagrama de blocos do chip (mesmo padrao do diagrama da Kria)
Saida: doc/diagrama_chip.svg  (e .png via render_png.py)

  python3 gera_diagrama.py            versao completa (ISFFT v4 com in_mem/out_mem)
  python3 gera_diagrama.py simples    versao para slide: ISFFT sem detalhe interno,
                                      rotulos enxutos -> diagrama_chip_simples.svg
"""
import sys
SIMPLES = len(sys.argv) > 1 and sys.argv[1] == "simples"
W = 2000
H = 1650 if SIMPLES else 1800
FONT = "Roboto, Arial, sans-serif"
C = dict(
    cont_fill="#F1EEE8", cont_stroke="#8C8C8C", cont_text="#444441",
    g_fill="#E1F3EE", g_stroke="#0F6E56", g_t="#0B4F3E", g_s="#0F6E56",
    p_fill="#EEEDFB", p_stroke="#534AB7", p_t="#3C3489", p_s="#534AB7",
    n_fill="#FFFFFF", n_stroke="#8C8C8C", n_t="#444441", n_s="#6B6B66",
    seta="#8A8A86", rot="#444441",
)
out = []
def e(s): out.append(s)

# setas dentro do texto: Roboto nao tem os glifos; usa DejaVu so neles
SETA = {"→": '<tspan font-family="DejaVu Sans" font-size="0.85em">→</tspan>',
        "↔": '<tspan font-family="DejaVu Sans" font-size="0.85em">↔</tspan>'}
def txt(t):
    for k, v in SETA.items(): t = t.replace(k, v)
    return t

def cont(x, y, w, h, titulo, ancora="start"):
    e(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="48" fill="{C["cont_fill"]}" stroke="{C["cont_stroke"]}" stroke-width="2"/>')
    tx = {"start": x + 58, "end": x + w - 58, "middle": x + w/2}[ancora]
    e(f'<text x="{tx}" y="{y+80}" font-size="40" fill="{C["cont_text"]}" text-anchor="{ancora}">{titulo}</text>')

def caixa(x, y, w, h, t, s, tipo, tam=40, tam_s=34, tracejada=False):
    f, st, ct, cs = C[tipo+"_fill"], C[tipo+"_stroke"], C[tipo+"_t"], C[tipo+"_s"]
    dash = ' stroke-dasharray="12 8"' if tracejada else ""
    e(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="22" fill="{f}" stroke="{st}" stroke-width="2"{dash}/>')
    cx = x + w/2
    if s:
        e(f'<text x="{cx}" y="{y+h/2-6}" font-size="{tam}" fill="{ct}" text-anchor="middle">{txt(t)}</text>')
        e(f'<text x="{cx}" y="{y+h/2+46}" font-size="{tam_s}" fill="{cs}" text-anchor="middle">{txt(s)}</text>')
    else:
        e(f'<text x="{cx}" y="{y+h/2+14}" font-size="{tam}" fill="{ct}" text-anchor="middle">{t}</text>')

def linha(pts, seta_fim=True, seta_ini=False, tracejada=False):
    d = "M " + " L ".join(f"{x} {y}" for x, y in pts)
    m = ' marker-end="url(#seta)"' if seta_fim else ""
    m += ' marker-start="url(#seta_ini)"' if seta_ini else ""
    dash = ' stroke-dasharray="14 10"' if tracejada else ""
    e(f'<path d="{d}" fill="none" stroke="{C["seta"]}" stroke-width="4"{dash}{m}/>')

def rotulo(x, y, t, ancora="start", tam=34):
    e(f'<text x="{x}" y="{y}" font-size="{tam}" fill="{C["rot"]}" text-anchor="{ancora}">{t}</text>')

e(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}" font-family="{FONT}">')
e(f'''<defs>
<marker id="seta" viewBox="0 0 20 20" refX="17" refY="10" markerWidth="7" markerHeight="7" orient="auto">
  <path d="M 2 2 L 17 10 L 2 18" fill="none" stroke="{C["seta"]}" stroke-width="3"/></marker>
<marker id="seta_ini" viewBox="0 0 20 20" refX="3" refY="10" markerWidth="7" markerHeight="7" orient="auto">
  <path d="M 18 2 L 3 10 L 18 18" fill="none" stroke="{C["seta"]}" stroke-width="3"/></marker>
</defs>''')
e(f'<rect width="{W}" height="{H}" fill="#FFFFFF"/>')

# colunas (mesmas da Kria)
L0, L1 = 176, 646          # esquerda
M0, M1 = 765, 1235         # centro
R0, R1 = 1353, 1823        # direita
xl, xm, xr = (L0+L1)//2, (M0+M1)//2, (R0+R1)//2   # 411, 1000, 1588

# ---------------- testbench ----------------
cont(118, 58, 1764, 330, "Testbench — só na simulação" if SIMPLES else "Testbench — só na simulação (Icarus / Xcelium)")
caixa(176, 176, 706, 165, "Carga do firmware", "$readmemh direto na macro da IMEM", "n", tracejada=True)
caixa(1118, 176, 706, 165, "Monitor da UART", None if SIMPLES else "Log, CHK e EVM (numpy)", "n", tracejada=True)

# ---------------- chip ----------------
cont(118, 500, 1764, 970 if SIMPLES else 1120, "Chip — SkyWater 130 nm", ancora="middle")

yA0, yA1 = 640, 800
yB0, yB1 = 950, 1110
yC0 = 1250
caixa(L0, yA0, L1-L0, yA1-yA0, "IMEM 8 kB", "Programa (ROM)", "g")
caixa(M0, yA0, M1-M0, yA1-yA0, "NEORV32", "CPU RISC-V rv32imc", "p")
caixa(R0, yA0, R1-R0, yA1-yA0, "UART0", "Log (printf)", "p")

caixa(L0, yB0, L1-L0, yB1-yB0, "Ponte XBUS → AXI", "AXI4 → AXI4-Lite", "p")
caixa(M0, yB0, M1-M0, yB1-yB0, "DMEM 4 kB", "Dados e matrizes", "g")
caixa(R0, yB0, R1-R0, yB1-yB0, "DMA", "DMEM ↔ SLINK", "p")

# ISFFT com as duas macros dentro
IS0, IS1, ISy1 = 176, 706, 1560
if SIMPLES:
    caixa(IS0, yC0, IS1-IS0, 1410-yC0, "ISFFT", "Acelerador 8×8", "p")
else:
  e(f'<rect x="{IS0}" y="{yC0}" width="{IS1-IS0}" height="{ISy1-yC0}" rx="22" fill="{C["p_fill"]}" stroke="{C["p_stroke"]}" stroke-width="2"/>')
  e(f'<text x="{(IS0+IS1)/2}" y="{yC0+62}" font-size="40" fill="{C["p_t"]}" text-anchor="middle">ISFFT v4</text>')
  e(f'<text x="{(IS0+IS1)/2}" y="{yC0+110}" font-size="34" fill="{C["p_s"]}" text-anchor="middle">Acelerador 8×8</text>')
  caixa(IS0+30, yC0+145, 220, 130, "in_mem", "64 × 64", "g", tam=34, tam_s=30)
  caixa(IS1-250, yC0+145, 220, 130, "out_mem", "256 × 64", "g", tam=34, tam_s=30)

SL0, SL1, SLy1 = 1294, 1824, 1410
caixa(SL0, yC0, SL1-SL0, SLy1-yC0, "SLINK", "FIFOs 64 · conv. 32 ↔ 64", "p")

# ---------------- ligacoes ----------------
# testbench
linha([(xl, 341), (xl, yA0-8)], tracejada=True)
rotulo(xl+30, 452, "Carga direta" if SIMPLES else "Carga direta (backdoor)")
linha([(xr, yA0), (xr, 349)])
rotulo(xr+30, 452, "uart0_txd")
# CPU -> IMEM / UART
linha([(M0, 720), (L1+8, 720)])
linha([(M1, 720), (R0-8, 720)])
# barramento
yb = 880
linha([(xm, yA1), (xm, yb)], seta_fim=False)
linha([(xl, yb), (xr, yb)], seta_fim=False)
for x in (xl, xm, xr):
    linha([(x, yb), (x, yB0-8)])
rotulo(xm+30, 855, "Barramento NEORV32")
# DMA -> DMEM
linha([(R0, 1030), (M1+8, 1030)])
# ponte -> ISFFT
linha([(xl, yB1), (xl, yC0-8)])
rotulo(xl+30, 1195, "AXI4-Lite")
# DMA -> SLINK
linha([(xr, yB1), (xr, yC0-8)])
# stream
linha([(SL0, 1295), (IS1+8, 1295)])
linha([(IS1, 1370), (SL0-8, 1370)])
rotulo((IS1+SL0)/2, 1346, "Stream 64 bits", ancora="middle")

# ---------------- legenda ----------------
ly = 1560 if SIMPLES else 1700
def leg(x, tipo, texto, tracejada=False):
    dash = ' stroke-dasharray="8 6"' if tracejada else ""
    e(f'<rect x="{x}" y="{ly-30}" width="40" height="40" rx="8" fill="{C[tipo+"_fill"]}" stroke="{C[tipo+"_stroke"]}" stroke-width="2"{dash}/>')
    e(f'<text x="{x+64}" y="{ly+3}" font-size="36" fill="{C["cont_text"]}">{texto}</text>')
leg(176, "g", "Macro SRAM (OpenRAM)")
leg(760, "p", "Lógica (células sky130)")
leg(1330, "n", "Só no testbench", tracejada=True)

e('</svg>')
nome = "diagrama_chip_simples.svg" if SIMPLES else "diagrama_chip.svg"
open(__import__("os").path.join(__import__("os").path.dirname(__file__), nome), "w").write("\n".join(out))
print(nome)
