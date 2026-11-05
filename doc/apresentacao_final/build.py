# Monta a apresentação final a partir do deck do PC4 (template CI Digital).
import copy
from PIL import Image
from lxml import etree
from pptx import Presentation
from pptx.util import Inches, Pt, Emu
from pptx.dml.color import RGBColor
from pptx.enum.shapes import MSO_SHAPE, MSO_CONNECTOR, MSO_SHAPE_TYPE
from pptx.enum.text import PP_ALIGN, MSO_ANCHOR
from pptx.chart.data import CategoryChartData
from pptx.enum.chart import XL_CHART_TYPE, XL_LABEL_POSITION
from pptx.oxml.ns import qn

SRC = "/home/claude/apres/pc4.pptx"
OUT = "/home/claude/apres/apresentacao_final.pptx"
IMG = "/home/claude/apres/img/"
MED = "/home/claude/apres/u/ppt/media/"

HEAD = "Proxima Nova Heavy"
BODY = "Proxima Nova"
MONO = "Courier New"
WHITE = "FFFFFF"
AMBER = "FFC94D"
CYAN = "6FE3EA"
NAVY = "1B1446"
PURPLE = "3B2A8F"
LIGHT = "E9E6FA"

prs = Presentation(SRC)
orig = list(prs.slides)          # índice 0 = slide 1 do deck original
LAYOUT = orig[1].slide_layout     # o "Blank" usado em todos


def rgb(h):
    return RGBColor.from_string(h)


def set_alpha(fill_fmt_elm_parent, alpha):
    """alpha em % de opacidade (0-100) no primeiro srgbClr do spPr."""
    clr = fill_fmt_elm_parent.find(".//" + qn("a:srgbClr"))
    a = etree.SubElement(clr, qn("a:alpha"))
    a.set("val", str(int(alpha * 1000)))


# ---------------------------------------------------------------- slides
def bg_picture(s):
    p = s.shapes.add_picture(IMG + "bg.png", 0, 0, prs.slide_width, prs.slide_height)
    p.name = "Fundo"
    return p


def new_slide():
    s = prs.slides.add_slide(LAYOUT)
    bg_picture(s)
    return s


def strip_text(s, keep_names=()):
    for sh in list(s.shapes):
        if sh.shape_type == MSO_SHAPE_TYPE.TEXT_BOX and sh.name not in keep_names:
            sh._element.getparent().remove(sh._element)


def content_shapes(s):
    return [sh for sh in s.shapes if sh.name not in ("Freeform 2", "Fundo")
            and sh.shape_type != MSO_SHAPE_TYPE.TEXT_BOX]


def fit_content(s, x, y, w, h, align="center"):
    """Escala e move juntos os shapes de conteúdo (imagens) para caber na caixa."""
    shs = content_shapes(s)
    l = min(sh.left for sh in shs); t = min(sh.top for sh in shs)
    r = max(sh.left + sh.width for sh in shs); b = max(sh.top + sh.height for sh in shs)
    bw, bh = r - l, b - t
    k = min(Inches(w) / bw, Inches(h) / bh)
    nw, nh = bw * k, bh * k
    ox = Inches(x) + (Inches(w) - nw) / 2 if align == "center" else Inches(x)
    oy = Inches(y) + (Inches(h) - nh) / 2
    for sh in shs:
        sh.left = int(ox + (sh.left - l) * k); sh.top = int(oy + (sh.top - t) * k)
        sh.width = int(sh.width * k); sh.height = int(sh.height * k)
    return (ox / 914400, oy / 914400, nw / 914400, nh / 914400)


# ---------------------------------------------------------------- texto
def _run(p, text, size, color, bold, font, italic=False):
    r = p.add_run()
    r.text = text
    f = r.font
    f.size = Pt(size); f.bold = bold; f.italic = italic
    f.color.rgb = rgb(color); f.name = font
    rpr = r._r.get_or_add_rPr()
    for tag in ("a:ea", "a:cs"):
        e = etree.SubElement(rpr, qn(tag)); e.set("typeface", font)
    return r


def text(s, x, y, w, h, paras, size=24, color=WHITE, bold=False, font=BODY,
         align=PP_ALIGN.LEFT, anchor=MSO_ANCHOR.TOP, bullet=False, space=6,
         line=None, name=None):
    """paras: lista; cada item é str ou lista de (texto, dict) runs."""
    tb = s.shapes.add_textbox(Inches(x), Inches(y), Inches(w), Inches(h))
    if name:
        tb.name = name
    tf = tb.text_frame
    tf.word_wrap = True
    tf.auto_size = None
    tf.margin_left = tf.margin_right = Inches(0.05)
    tf.margin_top = tf.margin_bottom = Inches(0.03)
    tf.vertical_anchor = anchor
    if isinstance(paras, str):
        paras = [paras]
    for i, para in enumerate(paras):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.alignment = align
        p.space_after = Pt(space)
        if line:
            p.line_spacing = line
        if bullet:
            pPr = p._p.get_or_add_pPr()
            pPr.set("marL", str(int(Inches(0.38)))); pPr.set("indent", str(int(-Inches(0.38))))
            bc = etree.SubElement(pPr, qn("a:buClr")); c = etree.SubElement(bc, qn("a:srgbClr")); c.set("val", AMBER)
            bf = etree.SubElement(pPr, qn("a:buFont")); bf.set("typeface", "Arial")
            bu = etree.SubElement(pPr, qn("a:buChar")); bu.set("char", "•")
        runs = [(para, {})] if isinstance(para, str) else para
        for t, o in runs:
            _run(p, t, o.get("size", size), o.get("color", color), o.get("bold", bold),
                 o.get("font", font), o.get("italic", False))
    return tb


def title(s, t):
    text(s, 5.6, 0.62, 13.8, 1.1, t, size=50, bold=True, font=HEAD,
         anchor=MSO_ANCHOR.MIDDLE, name="Título")


def caption(s, x, y, w, t, align=PP_ALIGN.LEFT):
    text(s, x, y, w, 0.42, [[(t, {"italic": True})]], size=16, color="D8D4F0", align=align)


def notes(s, t):
    s.notes_slide.notes_text_frame.text = t


# ---------------------------------------------------------------- formas
def card(s, x, y, w, h, fill=WHITE, alpha=13, line=True, radius=0.06, name=None):
    sh = s.shapes.add_shape(MSO_SHAPE.ROUNDED_RECTANGLE, Inches(x), Inches(y), Inches(w), Inches(h))
    sh.adjustments[0] = radius
    sh.fill.solid(); sh.fill.fore_color.rgb = rgb(fill)
    if alpha < 100:
        set_alpha(sh._element.spPr, alpha)
    if line:
        sh.line.color.rgb = rgb(WHITE); sh.line.width = Pt(1.25)
        ln = sh._element.spPr.find(qn("a:ln"))
        set_alpha(ln, 40)
    else:
        sh.line.fill.background()
    sh.shadow.inherit = False
    if name:
        sh.name = name
    sh.text_frame.text = ""
    return sh


def box(s, x, y, w, h, t, fill=WHITE, alpha=16, color=WHITE, size=20, bold=True,
        sub=None, subsize=16, subcolor=None):
    card(s, x, y, w, h, fill=fill, alpha=alpha)
    paras = [[(t, {"bold": bold})]]
    if sub:
        paras.append([(sub, {"size": subsize, "bold": False, "color": subcolor or color})])
    text(s, x + 0.08, y + 0.05, w - 0.16, h - 0.1, paras, size=size, color=color,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.MIDDLE, space=2)


def arrow(s, x1, y1, x2, y2, color=WHITE, width=2.5):
    c = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(x1), Inches(y1), Inches(x2), Inches(y2))
    c.line.color.rgb = rgb(color); c.line.width = Pt(width)
    ln = c.line._get_or_add_ln()
    te = etree.SubElement(ln, qn("a:tailEnd")); te.set("type", "triangle"); te.set("w", "med"); te.set("len", "med")
    return c


def chain(s, labels, y, h, x0=0.8, total=18.4, gap=0.62, highlight=(), size=19, subs=None):
    n = len(labels)
    w = (total - gap * (n - 1)) / n
    xs = []
    for i, lab in enumerate(labels):
        x = x0 + i * (w + gap)
        xs.append(x)
        if i in highlight:
            box(s, x, y, w, h, lab, fill=AMBER, alpha=100, color=NAVY, size=size + 2,
                sub=subs[i] if subs else None)
        else:
            box(s, x, y, w, h, lab, size=size, sub=subs[i] if subs else None)
        if i < n - 1:
            arrow(s, x + w + 0.07, y + h / 2, x + w + gap - 0.07, y + h / 2)
    return xs, w


def stat(s, x, y, w, h, num, label, numsize=54, labsize=20, numcolor=AMBER):
    card(s, x, y, w, h)
    text(s, x + 0.15, y + 0.15, w - 0.3, h * 0.5, [[(num, {"bold": True, "font": HEAD})]],
         size=numsize, color=numcolor, align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.BOTTOM)
    text(s, x + 0.2, y + h * 0.5 + 0.12, w - 0.4, h * 0.5 - 0.22, label.split("\n"), size=labsize,
         align=PP_ALIGN.CENTER, anchor=MSO_ANCHOR.TOP, space=0)


def picture(s, path, x, y, w, h, white_card=False, pad=0.12, max_px=1500):
    im = Image.open(path)
    if im.width > max_px:
        r = max_px / im.width
        im = im.resize((max_px, int(im.height * r)), Image.LANCZOS)
        path = path.replace(".png", "_s.jpg").replace("/u/ppt/media/", "/img/")
        im.convert("RGB").save(path, quality=90)
    ar = im.width / im.height
    iw, ih = (w, w / ar) if w / h < ar else (h * ar, h)
    ix, iy = x + (w - iw) / 2, y + (h - ih) / 2
    if white_card:
        card(s, ix - pad, iy - pad, iw + 2 * pad, ih + 2 * pad, fill=WHITE, alpha=100, line=False, radius=0.03)
    p = s.shapes.add_picture(path, Inches(ix), Inches(iy), Inches(iw), Inches(ih))
    return ix, iy, iw, ih


def table(s, x, y, w, rows, colw, rowh=0.55, size=18, head_fill=PURPLE, bold_first_col=False,
          aligns=None, highlight_last=False):
    nr, nc = len(rows), len(rows[0])
    gt = s.shapes.add_table(nr, nc, Inches(x), Inches(y), Inches(w), Inches(rowh * nr))
    tbl = gt.table
    tot = sum(colw)
    for j, cw in enumerate(colw):
        tbl.columns[j].width = int(Inches(w) * cw / tot)
    for i in range(nr):
        tbl.rows[i].height = Inches(rowh)
        for j in range(nc):
            c = tbl.cell(i, j)
            c.margin_left = c.margin_right = Inches(0.1)
            c.margin_top = c.margin_bottom = Inches(0.03)
            c.vertical_anchor = MSO_ANCHOR.MIDDLE
            c.fill.solid()
            if i == 0:
                c.fill.fore_color.rgb = rgb(head_fill)
            elif highlight_last and i == nr - 1:
                c.fill.fore_color.rgb = rgb("FFF1C7")
            else:
                c.fill.fore_color.rgb = rgb(WHITE if i % 2 else LIGHT)
            tf = c.text_frame
            tf.word_wrap = True
            p = tf.paragraphs[0]
            val = rows[i][j]
            p.alignment = (aligns[j] if aligns else PP_ALIGN.LEFT) if i else PP_ALIGN.CENTER
            b = (i == 0) or (bold_first_col and j == 0) or (highlight_last and i == nr - 1)
            _run(p, str(val), size, WHITE if i == 0 else NAVY, b, BODY)
    # tira o estilo com bandas do tema
    tblPr = tbl._tbl.tblPr
    tblPr.set("bandRow", "0"); tblPr.set("firstRow", "1")
    return gt


C, L, R = PP_ALIGN.CENTER, PP_ALIGN.LEFT, PP_ALIGN.RIGHT
final = []   # ordem final dos slides

# =====================================================================
# 1. CAPA (original 1)
s = orig[0]
for sh in s.shapes:
    if sh.has_text_frame and sh.text_frame.text.strip() == "21/10/2026":
        rs = sh.text_frame.paragraphs[0].runs
        rs[0].text = "Nov. 2026"
        for r in rs[1:]:
            r.text = ""
notes(s, "Capa (15 s). Apresentar o tema: IP ISFFT, o primeiro bloco do modulador OTFS, "
         "integrado ao processador RISC-V NEORV32, levado à FPGA e ao fluxo ASIC.")
final.append(s)

# =====================================================================
# 2. O PROBLEMA
s = new_slide(); title(s, "O PROBLEMA: DOPPLER EM LEO")
text(s, 0.8, 2.05, 18.4, 0.9,
     "New Space: constelações de satélites em órbita baixa (LEO) levam conectividade a qualquer "
     "lugar — mas o satélite passa muito rápido sobre quem está no chão.", size=26)
for i, (n, lab) in enumerate([
        ("~7,5 km/s", "velocidade de um satélite em LEO"),
        ("até ~50 kHz", "desvio Doppler a 2 GHz\n(f_d = v · f / c)"),
        ("15 kHz", "espaçamento entre subportadoras\ndo OFDM (LTE/5G)")]):
    stat(s, 0.8 + i * 6.4, 3.3, 5.6, 3.3, n, lab, numsize=60, labsize=22)
card(s, 0.8, 6.95, 18.4, 2.2, fill=AMBER, alpha=22)
text(s, 1.1, 7.0, 17.8, 2.1, [
    [("Doppler maior que o espaçamento entre subportadoras: ", {"bold": True, "color": AMBER}),
     ("as subportadoras do OFDM se misturam (ICI) e o canal muda dentro do quadro.", {})],
    [("Precisamos de uma modulação que trate atraso e Doppler como parte do canal.", {"bold": True})]],
    size=26, anchor=MSO_ANCHOR.MIDDLE)
caption(s, 0.8, 9.2, 18.4, "Contas de ordem de grandeza: f_d = 7,5 km/s × 2 GHz / (3×10⁸ m/s) ≈ 50 kHz.")
notes(s, "(1 min) Satélite em LEO a ~7,5 km/s. Em 2 GHz isso dá dezenas de kHz de Doppler, mais que os "
         "15 kHz entre subportadoras do OFDM: as subportadoras interferem entre si. É esse o problema "
         "que o OTFS ataca.")
final.append(s)

# =====================================================================
# 3. OTFS (original 4)
s = orig[3]; strip_text(s); title(s, "OTFS: O DOMÍNIO ATRASO-DOPPLER")
ix, iy, iw, ih = fit_content(s, 10.4, 2.3, 8.8, 6.6)
caption(s, ix, iy + ih + 0.1, iw, "Fonte: MATLAB — OTFS Modulation")
text(s, 0.8, 2.25, 9.2, 7.2, [
    "Os símbolos ficam numa grade 2D: eixo de atraso (tempo de chegada) × eixo Doppler (velocidade relativa).",
    "Cada caminho do canal vira um ponto (atraso, Doppler): o canal fica esparso e quase constante durante o quadro.",
    "Cada símbolo se espalha por todo o quadro tempo-frequência e enxerga o canal inteiro: robusto a multipercurso e a alto Doppler.",
    "Modulação recente: primeira patente em 2010."], size=24, bullet=True, space=14)
notes(s, "(1 min) No OTFS a informação é colocada no domínio atraso-Doppler. Nesse domínio cada reflexão "
         "é um ponto e o canal quase não muda durante o quadro. O OTFS não evita o Doppler: ele o "
         "representa de forma esparsa.")
final.append(s)

# =====================================================================
# 4. ONDE ENTRA A ISFFT
s = new_slide(); title(s, "ONDE ENTRA A ISFFT")
text(s, 0.8, 2.05, 18.4, 0.6, "Transmissor OTFS", size=24, bold=True, color=AMBER)
xs, w = chain(s, ["Bits", "Mapeamento QAM", "Grade atraso-Doppler N × M", "ISFFT",
                  "Transformada de Heisenberg (IFFT + CP)", "Canal LEO"],
              y=2.85, h=1.9, highlight=(3,), size=20)
text(s, xs[3], 4.85, w, 0.5, "este trabalho", size=20, bold=True, color=AMBER, align=C)
# faixas de domínio
for (a, b, lab) in [(1, 2, "domínio atraso-Doppler"), (4, 5, "tempo-frequência → tempo")]:
    x1 = xs[a]; x2 = xs[b] + w
    card(s, x1, 5.45, x2 - x1, 0.55, fill=CYAN, alpha=25, line=False, radius=0.5)
    text(s, x1, 5.45, x2 - x1, 0.55, lab, size=18, align=C, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.8, 6.45, 18.4, 3.0, [
    [("ISFFT: ", {"bold": True, "color": AMBER}),
     ("leva a matriz de símbolos do domínio atraso-Doppler para o domínio tempo-frequência.", {})],
    [("Depois dela, a cadeia é parecida com a de um OFDM: ", {"bold": True, "color": AMBER}),
     ("o OTFS pode reaproveitar moduladores que já existem.", {})],
    [("Neste trabalho: ", {"bold": True, "color": AMBER}),
     ("matriz 8 × 8 de complexos em ponto fixo de 16 bits — o ponto de partida do transceptor completo.", {})]],
    size=24, bullet=True, space=12)
notes(s, "(45 s) A cadeia do transmissor. A ISFFT é o bloco que tira os símbolos do domínio "
         "atraso-Doppler e leva para tempo-frequência; daí em diante é como um OFDM. É esse o bloco "
         "que eu fiz em hardware.")
final.append(s)

# =====================================================================
# 5. OBJETIVO (original 2)
s = orig[1]; strip_text(s); title(s, "OBJETIVO")
text(s, 0.8, 2.15, 18.4, 2.3,
     [[("Implementar o ", {}), ("IP ISFFT", {"bold": True}),
       (" desenvolvido no estudo dirigido 1 como periférico do processador ", {}),
       ("NEORV32 (RISC-V)", {"bold": True}),
       (", validando o IP com UVM e DFT, o sistema na FPGA Kria KR260 e o fluxo ASIC até o layout.", {})]],
     size=30, line=1.1)
metas = [("1", "IP verificado", "UVM no IP ISFFT: funcionalidade e cobertura"),
         ("2", "IP testável", "DFT no IP ISFFT: scan + ATPG"),
         ("3", "Sistema em FPGA", "NEORV32 + ISFFT na Kria KR260, resultado igual ao modelo"),
         ("4", "Sistema em silício", "Síntese no Cadence e layout em software livre até o GDSII (extra)")]
for i, (n, t, d) in enumerate(metas):
    x = 0.8 + i * 4.72
    card(s, x, 4.9, 4.25, 4.4)
    c = s.shapes.add_shape(MSO_SHAPE.OVAL, Inches(x + 1.68), Inches(5.15), Inches(0.9), Inches(0.9))
    c.fill.solid(); c.fill.fore_color.rgb = rgb(AMBER); c.line.fill.background()
    text(s, x + 1.68, 5.15, 0.9, 0.9, [[(n, {"bold": True, "font": HEAD})]], size=30, color=NAVY,
         align=C, anchor=MSO_ANCHOR.MIDDLE)
    text(s, x + 0.2, 6.25, 3.85, 0.7, t, size=26, bold=True, align=C)
    text(s, x + 0.25, 7.0, 3.75, 2.1, d, size=21, align=C)
notes(s, "(30 s) Objetivo e as quatro metas. As duas primeiras são só do IP; as duas últimas são do "
         "sistema com o RISC-V. A apresentação segue essa ordem.")
final.append(s)

# =====================================================================
# 6. IP: A CONTA
s = new_slide(); title(s, "IP ISFFT: O QUE ELE CALCULA")
im = Image.open(IMG + "formula.png"); fw = 1.35 * im.width / im.height
s.shapes.add_picture(IMG + "formula.png", Inches(10 - fw / 2), Inches(2.05), Inches(fw), Inches(1.35))
labs = ["Entrada 8 × 8\n(atraso × Doppler)", "IFFT de 8 pontos\nem cada linha",
        "FFT de 8 pontos\nem cada coluna", "Saída 8 × 8\n(tempo × frequência)"]
bw, gap, by, bh = 3.6, 1.33, 3.75, 2.55
for i, lab in enumerate(labs):
    x = 0.8 + i * (bw + gap)
    card(s, x, by, bw, bh, alpha=10)
    gx, gy, gs = x + bw / 2 - 1.05, by + 0.2, 2.1
    cell = gs / 8
    if i == 1:
        for r in range(8):
            b = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(gx), Inches(gy + r * cell + 0.03),
                                   Inches(gs), Inches(cell - 0.06))
            b.fill.solid(); b.fill.fore_color.rgb = rgb(CYAN); b.line.fill.background()
    elif i == 2:
        for r in range(8):
            b = s.shapes.add_shape(MSO_SHAPE.RECTANGLE, Inches(gx + r * cell + 0.03), Inches(gy),
                                   Inches(cell - 0.06), Inches(gs))
            b.fill.solid(); b.fill.fore_color.rgb = rgb(AMBER); b.line.fill.background()
    else:
        for k in range(9):
            for (a1, b1, a2, b2) in [(gx, gy + k * cell, gx + gs, gy + k * cell),
                                     (gx + k * cell, gy, gx + k * cell, gy + gs)]:
                ln = s.shapes.add_connector(MSO_CONNECTOR.STRAIGHT, Inches(a1), Inches(b1), Inches(a2), Inches(b2))
                ln.line.color.rgb = rgb(WHITE); ln.line.width = Pt(1.25)
    text(s, x - 0.3, by + bh + 0.08, bw + 0.6, 0.95, lab, size=19, bold=True, align=C, space=0)
    if i < 3:
        arrow(s, x + bw + 0.12, by + bh / 2, x + bw + gap - 0.12, by + bh / 2)
text(s, 0.8, 7.45, 18.4, 2.0, [
    [("Separável: ", {"bold": True, "color": AMBER}),
     ("a transformada 2D vira duas passadas 1D — IFFT nas linhas, FFT nas colunas.", {})],
    [("Em hardware: ", {"bold": True, "color": AMBER}),
     ("dois núcleos de 8 pontos e uma memória de transposição entre eles.", {})],
    [("Referência: ", {"bold": True, "color": AMBER}),
     ("modelo numpy da etapa 1 — ifft nas linhas, fft nas colunas, escala de 1/8 em cada passada.", {})]],
    size=22, bullet=True, space=8)
notes(s, "(1 min) A ISFFT é uma transformada 2D separável: IFFT ao longo das linhas e FFT ao longo das "
         "colunas. Por isso o hardware tem dois núcleos 1D e uma memória que transpõe a matriz entre eles.")
final.append(s)

# =====================================================================
# 7. BLOCO OPERACIONAL (original 6)
s = orig[5]; strip_text(s); title(s, "IP ISFFT: BLOCO OPERACIONAL")
ix, iy, iw, ih = fit_content(s, 0.8, 2.15, 18.4, 3.6)
caption(s, ix, iy + ih + 0.05, 6, "Fonte: Autor")
for i, (t, d) in enumerate([
        ("IFFT 1D", "Núcleo Spiral (DFT de 8 pontos) em ponto fixo de 16 bits: processa as linhas."),
        ("Banco ping-pong", "2 × 8×8 × 32 bits: escreve por linha e lê por coluna (a transposição). "
                            "Enquanto um banco enche, o outro esvazia."),
        ("FFT 1D", "Núcleo Spiral (DFT de 8 pontos): processa as colunas. "
                   "Duas FSMs controlam escrita e leitura.")]):
    x = 0.8 + i * 6.3
    card(s, x, 6.25, 5.8, 3.2)
    text(s, x + 0.25, 6.4, 5.3, 0.6, t, size=26, bold=True, color=AMBER)
    text(s, x + 0.25, 7.05, 5.3, 2.3, d, size=21)
notes(s, "(1 min) O datapath: IFFT 1D, banco ping-pong que faz a transposição e FFT 1D. Os núcleos de "
         "8 pontos foram gerados pelo Spiral (latência de 41 ciclos, gap de 4). O ping-pong deixa "
         "uma matriz entrar enquanto a anterior sai.")
final.append(s)

# =====================================================================
# 8. INTERFACES AXI
s = new_slide(); title(s, "IP ISFFT: INTERFACES AXI")
xs, w = chain(s, ["AXI-Stream de entrada", "Buffer de entrada (64 palavras)", "Liberador",
                  "Núcleo ISFFT", "FIFO de saída (256 palavras)", "AXI-Stream de saída"],
              y=2.15, h=1.65, highlight=(3,), size=19)
for i, t in [(0, "64 bits = 2 complexos int16; 32 palavras por matriz"),
             (1, "commit a cada 32 palavras; rollback se o tlast chega no meio"),
             (2, "só entrega com 32 palavras e espaço reservado na saída"),
             (4, "tlast a cada PKT_MAT matrizes"),
             (5, "respeita o tready (contrapressão)")]:
    text(s, xs[i] - 0.2, 3.9, w + 0.4, 1.4, t, size=17, align=C, color="E4E0FA", space=0)
rows = [["Offset", "Registrador", "Função"],
        ["0x00", "CTRL (R/W)", "enable, soft reset, limpa erros"],
        ["0x04", "STATUS (RO)", "ocupado, matriz na entrada, FIFO cheia/com dados, erros"],
        ["0x08", "MAT_IN (RO)", "matrizes confirmadas na entrada"],
        ["0x0C", "MAT_OUT (RO)", "matrizes entregues na saída"],
        ["0x10", "ERR_CNT (RO)", "erros de tlast"],
        ["0x14", "ID (RO)", "0x15FF0300"],
        ["0x18", "PKT_MAT (R/W)", "matrizes por pacote de saída"]]
table(s, 0.8, 5.55, 11.6, rows, [1.1, 2.1, 5.6], rowh=0.48, size=17, aligns=[C, L, L])
card(s, 12.9, 5.55, 6.3, 3.84)
text(s, 13.15, 5.7, 5.8, 3.6, [
    [("Controle × dados", {"bold": True, "color": AMBER, "size": 24})],
    "A CPU liga, reseta e lê status e contadores pelo AXI4-Lite.",
    "A matriz nunca passa pela CPU: entra e sai pelo AXI-Stream.",
    "Matriz truncada é descartada sem travar o núcleo."], size=20, space=10)
notes(s, "(1 min) Em volta do núcleo há o wrapper AXI: buffer com commit/rollback (descarta matriz "
         "truncada), liberador por crédito (o núcleo nunca perde saída) e FIFO de saída que respeita "
         "o tready. São exatamente esses comportamentos que o UVM vai estressar.")
final.append(s)

# =====================================================================
# 9. AS 3 MATRIZES
s = new_slide(); title(s, "AS 3 MATRIZES DE TESTE")
ix, iy, iw, ih = picture(s, IMG + "entrada.png", 0.95, 2.2, 10.1, 3.55, white_card=True)
for i, t in enumerate(["Impulso em [3,3] (amplitude 1000)", "Senoide 2D (500 · sen)", "Rampa (10 × índice)"]):
    text(s, ix + i * iw / 3, iy + ih + 0.2, iw / 3, 0.75, t, size=18, bold=True, align=C, space=0)
text(s, 0.8, 6.85, 10.5, 2.7, [
    [("O mesmo trio de matrizes do notebook da etapa 1 roda em todas as etapas.", {"bold": True})],
    "Qualquer diferença aparece na hora — por isso o EVM se repete ao longo da apresentação.",
    [("EVM = √( média|erro|² / média|referência|² ), contra o modelo numpy.", {"size": 18, "color": "D8D4F0"})]],
    size=22, space=10)
rows = [["Etapa", "Resultado com as 3 matrizes"],
        ["Kria KR260 (placa)", "EVM 3,4122 / 0,7822 / 0,5965 %"],
        ["Simulação RTL do chip", "EVM idêntico à placa"],
        ["UVM — teste kria", "EVM idêntico à placa"],
        ["Pós-síntese (netlist do Genus)", "3 somas = RTL"],
        ["Netlist do layout", "3 somas = RTL"],
        ["Chip com os pads", "3 somas = RTL"]]
table(s, 11.8, 2.2, 7.4, rows, [3.4, 4.0], rowh=0.78, size=18, bold_first_col=True)
caption(s, 11.8, 7.8, 7.4, "Somas: assinaturas das 3 saídas calculadas pelo firmware do NEORV32.")
notes(s, "(45 s) Desde a etapa 1 eu sempre testo as mesmas 3 matrizes: impulso, senoide e rampa. "
         "Por isso o mesmo EVM aparece na placa, na simulação do chip e no UVM, e as mesmas somas "
         "aparecem do RTL até o layout.")
final.append(s)

# =====================================================================
# 10. UVM: AMBIENTE (original 7)
s = orig[6]; strip_text(s); title(s, "UVM: AMBIENTE DO IP")
ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 8.0, 7.0)
caption(s, ix, iy + ih + 0.05, 4, "Fonte: Autor")
text(s, 9.3, 2.2, 9.9, 7.3, [
    [("DUT: ", {"bold": True, "color": AMBER}),
     ("isfft_axi_v4 — o mesmo RTL que vai para o Cadence, com as 2 macros SRAM (sem o RISC-V).", {})],
    [("Agentes ", {"bold": True, "color": AMBER}),
     ("AXI4-Lite e AXI-Stream com atrasos, pausas e contrapressão sorteados.", {})],
    [("RAL ", {"bold": True, "color": AMBER}), ("com os 7 registradores; contadores previstos pelo modelo.", {})],
    [("Scoreboard com 2 checagens: ", {"bold": True, "color": AMBER}),
     ("bit a bit contra o wrapper da etapa 1 e numérica contra a ISFFT em ponto flutuante (≤ 4 LSB).", {})],
    [("8 asserções ", {"bold": True, "color": AMBER}), ("por bind + protocolo AXI nas interfaces.", {})],
    [("Xcelium 26.03, UVM 1.1d. ", {"bold": True, "color": AMBER}),
     ("Conferido antes no Verilator: 12/12 mutações detectadas.", {})]],
    size=22, bullet=True, space=12)
notes(s, "(1 min) O UVM é só do IP. O DUT é o mesmo RTL que vai para a síntese. Cada matriz é "
         "checada duas vezes: bit a bit contra a referência da etapa 1 e numericamente contra a "
         "ISFFT em ponto flutuante. Antes da VM, conferi no Verilator plantando 12 defeitos.")
final.append(s)

# =====================================================================
# 11. UVM: FUNCIONALIDADE
s = new_slide(); title(s, "UVM: FUNCIONALIDADE")
rows = [["Teste", "Cenário", "Palavras", "Resultado"],
        ["fumaca", "1 matriz", "32", "PASSOU"],
        ["registradores", "reset, leitura/escrita, escrita em RO", "—", "PASSOU"],
        ["kria", "3 matrizes da placa (EVM = placa)", "96", "PASSOU"],
        ["aleatorio", "40 matrizes, 5 tipos × 4 amplitudes", "1.280", "PASSOU"],
        ["truncado", "pacotes truncados (pontas dirigidas)", "1.280", "PASSOU"],
        ["contrapressao", "60 matrizes, tready 50 % + paradas longas", "1.920", "PASSOU"],
        ["soft_reset", "2 soft resets, um com o núcleo calculando", "200", "PASSOU"],
        ["kria_regressao", "testbench da Kria reescrito em UVM", "1.280", "PASSOU"],
        ["vazao", "80 matrizes sem pausa, tready 100 %", "2.560", "PASSOU"],
        ["estouro", "40 matrizes acima da faixa válida", "1.280", "PASSOU"],
        ["Total", "10 testes", "9.928", "10/10"]]
table(s, 0.8, 2.1, 13.4, rows, [2.6, 6.6, 1.6, 1.8], rowh=0.58, size=17, bold_first_col=True,
      aligns=[L, L, R, C], highlight_last=True)
for i, (n, lab) in enumerate([("10/10", "testes passaram"),
                              ("9.928", "palavras comparadas bit a bit"),
                              ("0", "UVM_ERROR, UVM_WARNING ou asserção falhando")]):
    stat(s, 14.7, 2.1 + i * 2.43, 4.5, 2.2, n, lab, numsize=46, labsize=18)
caption(s, 0.8, 9.15, 13.4, "Fonte: regressão de 28/10/2026 no Xcelium 26.03 (semente 1).")
notes(s, "(1 min) Dez testes, do teste de fumaça até estouro de faixa. Destaque: truncado, "
         "contrapressão e soft reset com o núcleo trabalhando, que exercitam o wrapper. "
         "Quase 10 mil palavras comparadas bit a bit, zero erros.")
final.append(s)

# =====================================================================
# 12. UVM: COBERTURA
s = new_slide(); title(s, "UVM: COBERTURA")
for i, (n, lab) in enumerate([("100 %", "cobertura funcional\n(54/54 bins)"),
                              ("8/8", "asserções passaram,\n0 falhas"),
                              ("100 %", "código do núcleo ISFFT\n(280/280)"),
                              ("73,5 %", "código do wrapper\n(975/1.326)")]):
    stat(s, 0.8 + i * 4.72, 2.1, 4.25, 2.9, n, lab, numsize=52, labsize=20,
         numcolor=AMBER if i < 3 else CYAN)
rows = [["Métrica", "30/09 (8 testes)", "28/10 (10 testes)"],
        ["Funcional", "94,4 %", "100 %"],
        ["Código do núcleo", "99,6 %", "100 %"],
        ["Código do wrapper", "70,7 %", "73,5 %"],
        ["FSMs de escrita / leitura", "90,0 / 89,7 %", "92,5 / 92,3 %"]]
table(s, 0.8, 5.5, 10.6, rows, [4.2, 3.2, 3.2], rowh=0.62, size=18, bold_first_col=True, aligns=[L, C, C])
card(s, 11.9, 5.5, 7.3, 3.9)
text(s, 12.15, 5.62, 6.85, 3.7, [
    [("Por que o wrapper fica em 73,5 %?", {"bold": True, "color": CYAN, "size": 22})],
    "A medição passou a contar expressões (&, |, assign): +126 itens.",
    "Um bloco é inalcançável: o liberador gasta 33 ciclos por matriz.",
    "Macros da OpenRAM e asserções ficam fora da cobertura de código."], size=19, space=8)
notes(s, "(1 min) Funcional 100 %, asserções 8 de 8, núcleo 100 %. O wrapper fica em 73,5 % e eu "
         "explico o porquê: a métrica ficou mais rigorosa (expressões) e há um bloco inalcançável. "
         "A tabela mostra a evolução entre as duas rodadas.")
final.append(s)

# =====================================================================
# 13. UVM: IMC (original 10)
s = orig[9]; strip_text(s); title(s, "UVM: COBERTURA NO IMC")
ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 18.4, 7.15)
caption(s, ix, iy + ih + 0.05, 8, "Fonte: Autor — Cadence IMC")
notes(s, "(15 s) Evidência da ferramenta: o relatório do IMC com o merge das rodadas.")
final.append(s)

# =====================================================================
# 14. DFT: FLUXO
s = new_slide(); title(s, "DFT: SCAN E ATPG NO IP ISFFT")
text(s, 0.8, 2.05, 18.4, 1.25, [
    [("Scan: ", {"bold": True, "color": AMBER}),
     ("cada flip-flop ganha um mux e vira um elo de uma cadeia de deslocamento. No teste: carrega um padrão "
      "pela cadeia, captura 1 ciclo de funcionamento, descarrega e compara.", {})]], size=23)
xs, w = chain(s, ["Síntese com scan", "LEC: RTL × netlist com scan", "Regressão da Kria (scan_en = 0)",
                  "ATPG stuck-at", "Padrões simulados no netlist"],
              y=3.6, h=1.75, gap=0.6, size=20,
              subs=["Genus", "Conformal", "Xcelium", "Modus", "Xcelium"], )
for i, t in enumerate(["12.552 FF, 100 % com scan, 16 cadeias de ~785",
                       "PASS, 0 não-equivalentes",
                       "PASSOU: 40 matrizes",
                       "170 padrões, 99,65 %",
                       "170/170, 0 divergências em 2.156.112 comparações"]):
    text(s, xs[i] - 0.1, 5.5, w + 0.2, 1.6, t, size=20, bold=True, color=AMBER, align=C, space=0)
card(s, 0.8, 7.45, 18.4, 1.95)
text(s, 1.05, 7.55, 17.9, 1.8, [
    [("Escolhas: ", {"bold": True, "color": CYAN}),
     ("scan completo (muxed scan) com 16 cadeias; sem test_mode, porque o IP não tem reset assíncrono, "
      "clock gating nem latch; macros SRAM como caixa-preta (sem shadow logic).", {})]], size=21,
     anchor=MSO_ANCHOR.MIDDLE)
notes(s, "(1 min) A DFT também é só do IP. Cinco passos: síntese com scan, equivalência, a regressão "
         "funcional com o scan desligado, ATPG no Modus e simulação dos padrões. Todos passaram.")
final.append(s)

# =====================================================================
# 15. DFT: COBERTURA E CUSTO
s = new_slide(); title(s, "DFT: COBERTURA E CUSTO")
stat(s, 0.8, 2.1, 5.3, 3.0, "99,65 %", "cobertura stuck-at ajustada\n(modo FULLSCAN)", numsize=54)
rows = [["", "Falhas", "Testadas", "Possíveis", "Redund.", "Não test.", "ATCov"],
        ["FULLSCAN", "341.871", "340.510", "214", "151", "996", "99,65 %"],
        ["Global", "343.063", "340.510", "214", "151", "2.188", "99,30 %"]]
table(s, 6.6, 2.1, 12.6, rows, [1.9, 1.8, 1.8, 1.6, 1.5, 1.5, 1.6], rowh=0.6, size=18,
      bold_first_col=True, aligns=[L, R, R, R, R, R, R])
text(s, 6.6, 4.05, 12.6, 1.2, [
    "Possíveis: o padrão gera X perto das macros caixa-preta. Redundantes: lógica sem efeito — nenhum padrão detecta."],
    size=18, color="E4E0FA")
rows = [["", "IP sem scan", "IP com scan", "Diferença"],
        ["Área total (com 2 macros)", "897.901 µm²", "974.849 µm²", "+8,6 %"],
        ["Só lógica", "448.030 µm²", "524.977 µm²", "+17,2 %"],
        ["Instâncias", "36.375", "35.962", "−413"]]
table(s, 0.8, 5.6, 11.6, rows, [3.8, 2.6, 2.6, 1.8], rowh=0.62, size=18, bold_first_col=True,
      aligns=[L, R, R, R])
card(s, 12.9, 5.6, 6.3, 3.8)
text(s, 13.15, 5.72, 5.8, 3.6, [
    [("Leitura", {"bold": True, "color": CYAN, "size": 22})],
    "O custo vem da célula: o flip-flop de scan tem o mux embutido.",
    "IP sem scan = o da síntese do chip (mesma biblioteca e RTL).",
    "Slack não se compara: o SDC do IP isolado é outro."], size=19, space=8)
notes(s, "(1 min) 170 padrões chegam a 99,65 %. O que sobra está em volta das macros, tratadas como "
         "caixa-preta. O custo: 17 % a mais de lógica, porque cada flip-flop vira um flip-flop de scan.")
final.append(s)

# =====================================================================
# 16-17. DFT: telas do Modus (originais 30 e 31)
for idx, t, n in [(29, "DFT: FULLSCAN NO MODUS", "(15 s) Esquemático do modo de teste FULLSCAN no Modus."),
                  (30, "DFT: ATPG NO MODUS", "(15 s) Janela principal do Modus com o ATPG concluído.")]:
    s = orig[idx]; strip_text(s); title(s, t)
    ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 18.4, 7.15)
    caption(s, ix, iy + ih + 0.05, 8, "Fonte: Autor — Cadence Modus")
    notes(s, n)
    final.append(s)

# =====================================================================
# 18. FPGA: FLUXO
s = new_slide(); title(s, "FPGA: FLUXO NA KRIA")
chain(s, ["RTL", "Vivado", "Firmware RISC-V", "PYNQ / Jupyter", "Execução e EVM"],
      y=2.2, h=2.6, gap=0.6, size=22,
      subs=["NEORV32 (VHDL) + ISFFT (Verilog)", "block design, síntese, implementação, bitstream",
            "riscv-none-elf-gcc", "carrega o .bit e grava o firmware na BRAM",
            "NEORV32 programa DMA e ISFFT; Python compara com o modelo"], )
for i, (t, d) in enumerate([
        ("ARM (Zynq PS)", "Só carrega o sistema, aloca os buffers na DDR e escreve os endereços na caixa de correio: é o depurador."),
        ("NEORV32 (RISC-V)", "Programa o AXI DMA e a ISFFT, mede os ciclos e devolve o status pela caixa de correio.")]):
    x = 0.8 + i * 9.45
    card(s, x, 5.4, 8.95, 3.4)
    text(s, x + 0.3, 5.6, 8.35, 0.7, t, size=30, bold=True, color=AMBER)
    text(s, x + 0.3, 6.45, 8.35, 2.2, d, size=25)
notes(s, "(45 s) Agora o sistema com o RISC-V. Na Kria, o ARM só carrega e depura; quem controla a "
         "ISFFT e o DMA é o NEORV32.")
final.append(s)

# =====================================================================
# 19. KRIA KR260 (original 14)
s = orig[13]; strip_text(s); title(s, "FPGA: KRIA KR260")
ix, iy, iw, ih = fit_content(s, 4.0, 2.2, 12.0, 6.8)
caption(s, ix, iy + ih + 0.05, iw, "Kria KR260 Robotics Starter Kit (Zynq UltraScale+). Fonte: AMD", align=C)
notes(s, "(10 s) A placa: Kria KR260, com um Zynq UltraScale+.")
final.append(s)

# =====================================================================
# 20. ARQUITETURA KRIA (original 15)
s = orig[14]; strip_text(s); title(s, "FPGA: NEORV32 (RISC-V) + ISFFT")
ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 9.0, 7.1)
caption(s, ix, iy + ih + 0.05, 4, "Fonte: Autor")
text(s, 10.3, 2.2, 8.9, 7.3, [
    [("PS: ", {"bold": True, "color": AMBER}), ("ARM + Ubuntu/PYNQ carrega bitstream e firmware e serve de depurador.", {})],
    [("PL: ", {"bold": True, "color": AMBER}), ("o NEORV32 é o controlador do SoC.", {})],
    [("Controle: ", {"bold": True, "color": AMBER}), ("NEORV32 → AXI4-Lite → registradores da ISFFT.", {})],
    [("Dados: ", {"bold": True, "color": AMBER}), ("AXI DMA lê a matriz da DDR, passa pela ISFFT no AXI-Stream e grava o resultado.", {})],
    [("BRAM de 64 kB: ", {"bold": True, "color": AMBER}), ("firmware do NEORV32 + caixa de correio com o Jupyter.", {})],
    [("Relógio da PL: ", {"bold": True, "color": AMBER}), ("100 MHz.", {})]],
    size=22, bullet=True, space=12)
notes(s, "(1 min) Arquitetura na Kria: item de arquitetura com RISC-V. Controle pelo AXI4-Lite, dados "
         "pelo AXI DMA e AXI-Stream, firmware e caixa de correio na BRAM.")
final.append(s)

# =====================================================================
# 21. BLOCK DESIGN (original 16)
s = orig[15]; strip_text(s); title(s, "FPGA: BLOCK DESIGN NO VIVADO")
ix, iy, iw, ih = fit_content(s, 0.8, 2.4, 18.4, 6.6)
caption(s, ix, iy + ih + 0.1, 6, "Fonte: Autor — Vivado")
notes(s, "(15 s) O block design do Vivado com o NEORV32, a ISFFT e o AXI DMA.")
final.append(s)

# =====================================================================
# 22. IMPLEMENTAÇÃO
s = new_slide(); title(s, "FPGA: IMPLEMENTAÇÃO")
ix, iy, iw, ih = picture(s, MED + "image28.png", 0.8, 2.1, 7.6, 7.0)
caption(s, ix, iy + ih + 0.05, iw, "Posicionamento no dispositivo. Fonte: Autor — Vivado")
for i, (n, lab) in enumerate([("+3,903 ns", "WNS a 100 MHz\n(hold +0,010 ns)"),
                              ("25 %", "das BRAMs\n(36,5 de 144)"),
                              ("2,85 W", "potência total\n(94 % da dinâmica é o ARM)")]):
    stat(s, 9.0 + i * 3.45, 2.1, 3.2, 2.75, n, lab, numsize=40, labsize=18)
rows = [["Recurso", "Usado", "Disponível", "%"],
        ["LUT", "10.376", "117.120", "8,86 %"],
        ["LUTRAM", "1.301", "57.600", "2,26 %"],
        ["FF", "15.080", "234.240", "6,44 %"],
        ["BRAM", "36,5", "144", "25,35 %"],
        ["DSP", "16", "1.248", "1,28 %"]]
table(s, 9.0, 5.2, 10.2, rows, [2.2, 2.4, 2.8, 2.0], rowh=0.55, size=18, bold_first_col=True,
      aligns=[L, R, R, R])
text(s, 9.0, 8.6, 10.2, 0.9, "0 caminhos violando (49.570 pontos de chegada). ISFFT sozinha: 9,5 BRAMs.",
     size=18, color="E4E0FA")
notes(s, "(45 s) Timing fecha a 100 MHz com 3,9 ns de folga. A FPGA está folgada: 9 % das LUTs e 25 % "
         "das BRAMs. Quase toda a potência é do ARM, não da lógica.")
final.append(s)

# =====================================================================
# 23. JUPYTER
s = new_slide(); title(s, "FPGA: RESULTADO NO JUPYTER")
ix, iy, iw, ih = picture(s, IMG + "saida.png", 0.95, 2.2, 10.1, 3.55, white_card=True)
caption(s, ix - 0.12, iy + ih + 0.18, iw, "Saída do hardware (domínio tempo-frequência) — notebook processamento_otfs")
rows = [["Matriz", "EVM", "Erro médio", "Ciclos"],
        ["Impulso", "3,4122 %", "0,40", "506"],
        ["Senoide", "0,7822 %", "0,10", "507"],
        ["Rampa", "0,5965 %", "0,09", "506"]]
table(s, 0.8, 6.55, 10.4, rows, [2.6, 2.6, 2.6, 2.6], rowh=0.7, size=20, bold_first_col=True,
      aligns=[L, R, R, R])
for i, (n, lab) in enumerate([("5,06 µs", "latência do hardware por matriz\n(506 ciclos a 100 MHz)"),
                              ("6,87 µs", "incluindo a programação do DMA\npelo NEORV32 (687 ciclos)"),
                              ("= modelo", "EVM igual ao do modelo numpy\nda etapa 1")]):
    stat(s, 11.8, 2.2 + i * 2.43, 7.4, 2.2, n, lab, numsize=44, labsize=18)
notes(s, "(1 min) Aqui eu mostro o notebook (PDF). O NEORV32 processa as 3 matrizes sozinho; o EVM "
         "bate com o modelo. Cada matriz leva 5 µs no hardware, 6,9 µs contando a programação do DMA.")
final.append(s)

# =====================================================================
# 24. RTL -> GDSII
s = new_slide(); title(s, "FLUXO RTL → GDSII")
for k, (head, sub, items) in enumerate([
        ("PARTE 1 — CADENCE", "VM do curso", [("Genus", "síntese lógica a 50 MHz"),
                                                ("Xcelium", "simulação RTL e pós-síntese"),
                                                ("Conformal", "equivalência RTL × netlist"),
                                                ("Genus + Modus", "DFT do IP (já visto)")]),
        ("PARTE 2 — SOFTWARE LIVRE", "notebook (extra)", [("OpenRAM", "macros SRAM"),
                                                          ("GHDL", "NEORV32: VHDL → Verilog"),
                                                          ("LibreLane / OpenROAD", "floorplan, PDN, posicionamento, CTS, roteamento"),
                                                          ("Magic, Netgen, KLayout", "DRC, LVS e GDSII")])]):
    x = 0.8 + k * 9.85
    card(s, x, 2.1, 8.55, 6.3)
    text(s, x + 0.3, 2.2, 8.0, 0.7, head, size=28, bold=True, color=AMBER)
    text(s, x + 0.3, 2.85, 8.0, 0.5, sub, size=19, color="D8D4F0")
    for i, (tool, what) in enumerate(items):
        y = 3.55 + i * 1.18
        card(s, x + 0.3, y, 7.95, 1.0, alpha=12, line=False)
        text(s, x + 0.45, y, 3.1, 1.0, tool, size=21, bold=True, anchor=MSO_ANCHOR.MIDDLE, space=0)
        text(s, x + 3.55, y, 4.6, 1.0, what, size=19, anchor=MSO_ANCHOR.MIDDLE, space=0)
arrow(s, 9.42, 5.25, 10.58, 5.25, color=AMBER, width=4)
text(s, 9.1, 4.25, 1.8, 0.9, "netlist do Genus", size=16, bold=True, color=AMBER, align=C, space=0)
text(s, 0.8, 8.6, 18.4, 0.9,
     [[("Por que dois mundos: ", {"bold": True, "color": CYAN}),
       ("o Cadence da VM não tem as regras físicas do sky130 (sem PVS/Pegasus/Quantus); o layout fecha no fluxo aberto.", {})]],
     size=21)
notes(s, "(45 s) O fluxo ASIC tem duas partes. A parte 1 é no Cadence e cobre síntese, pós-síntese e "
         "LEC. A parte 2, extra, leva o netlist do Genus ao GDSII com ferramentas abertas, porque a VM "
         "não tem as regras físicas do SkyWater 130.")
final.append(s)

# =====================================================================
# 25. ARQUITETURA ASIC (original 23)
s = orig[22]; strip_text(s); title(s, "ASIC: NEORV32 (RISC-V) + ISFFT")
ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 8.8, 7.1)
caption(s, ix, iy + ih + 0.05, 4, "Fonte: Autor")
text(s, 10.1, 2.2, 9.1, 7.3, [
    [("Sem Zynq: ", {"bold": True, "color": AMBER}), ("o NEORV32 (rv32imc) é o único processador.", {})],
    [("Dados: ", {"bold": True, "color": AMBER}), ("DMA + SLINK do próprio NEORV32 no lugar do AXI DMA; a FIFO do SLINK cabe uma matriz.", {})],
    [("Conversores 32 ↔ 64 bits ", {"bold": True, "color": AMBER}), ("entre o SLINK e a ISFFT, com tlast.", {})],
    [("Controle: ", {"bold": True, "color": AMBER}), ("ponte XBUS → AXI4-Lite para os registradores.", {})],
    [("Memórias: ", {"bold": True, "color": AMBER}), ("IMEM 8 kB e DMEM 4 kB em macro OpenRAM; buffers da ISFFT também.", {})],
    [("SkyWater 130 nm a 50 MHz.", {"bold": True, "color": AMBER})]],
    size=22, bullet=True, space=12)
notes(s, "(1 min) A arquitetura do ASIC, segundo diagrama com o RISC-V. Sem Zynq, o NEORV32 usa o "
         "próprio DMA e o SLINK para mover os dados; as memórias grandes viram macros da OpenRAM.")
final.append(s)

# =====================================================================
# 26. MACRO OU FLIP-FLOP
s = new_slide(); title(s, "ASIC: MACRO SRAM OU FLIP-FLOP?")
rows = [["Memória", "Tamanho", "Implementação", "Macro ÷ FF"],
        ["IMEM (programa)", "2048 × 32", "Macro 1rw 8 kB", "0,16×"],
        ["DMEM (dados)", "1024 × 32", "Macro 1rw 4 kB", "0,20×"],
        ["FIFO de saída da ISFFT", "256 × 64", "Macro 1rw1r", "0,41×"],
        ["Buffer de entrada da ISFFT", "64 × 64", "Macro 1rw1r", "0,85×"],
        ["Ping-pong da ISFFT", "2 × 8 × 8 × 32", "Flip-flop", "1,42×"],
        ["Memórias do Spiral", "16 × (4 ou 8) × 32", "Flip-flop", "6,0×"],
        ["FIFOs do SLINK, DMA, UART", "≤ 64 × 37", "Flip-flop", "~1,27×"]]
table(s, 0.8, 2.1, 12.6, rows, [4.3, 3.0, 3.0, 1.9], rowh=0.62, size=18, bold_first_col=True,
      aligns=[L, C, L, R])
card(s, 13.9, 2.1, 5.3, 4.96, fill=AMBER, alpha=22)
text(s, 14.15, 2.25, 4.8, 4.7, [
    [("Regra medida", {"bold": True, "color": AMBER, "size": 26})],
    "Macro 1rw1r de 64 bits: ≈ 103.900 µm² fixos + 11,8 µm²/bit.",
    "Flip-flop: ≈ 43,9 µm²/bit.",
    [("Macro só compensa acima de ~3.200 bits.", {"bold": True})]], size=21, space=10)
text(s, 0.8, 7.45, 18.4, 2.0, [
    [("Resultado: ", {"bold": True, "color": AMBER}),
     ("4 macros no chip (em vez de 20+) e memórias da ISFFT com 0,64× a área de tudo em flip-flop.", {})],
    [("O número de macros é ditado pelos acessos por ciclo, não pelos bits: ", {"bold": True, "color": AMBER}),
     ("o ping-pong faz 2 leituras + 2 escritas por ciclo.", {})]], size=22, bullet=True, space=10)
notes(s, "(45 s) Uma decisão de engenharia medida: gerei macros de vários tamanhos e comparei com "
         "flip-flop. Macro só compensa acima de ~3.200 bits, então só 4 memórias viraram macro.")
final.append(s)

# =====================================================================
# 27. SÍNTESE
s = new_slide(); title(s, "PARTE 1 — SÍNTESE NO GENUS")
for i, (n, lab) in enumerate([("1,91 mm²", "área total\n(62 % em macros SRAM)"),
                              ("+2,41 ns", "folga de setup a 50 MHz,\n0 caminhos violando"),
                              ("60.026", "instâncias\n(19.823 flip-flops + 4 macros)"),
                              ("0", "violações de transição,\ncapacitância e fanout")]):
    stat(s, 0.8 + i * 4.72, 2.1, 4.25, 2.6, n, lab, numsize=46, labsize=19)
cd = CategoryChartData()
cd.categories = ["Conversores 32↔64", "Lógica do NEORV32", "Lógica da ISFFT", "Macros SRAM (4)"]
cd.add_series("Área (%)", (0.3, 14.4, 23.4, 61.8))
card(s, 0.8, 5.05, 10.9, 4.4)
gf = s.shapes.add_chart(XL_CHART_TYPE.BAR_CLUSTERED, Inches(1.0), Inches(5.15), Inches(10.5), Inches(4.2), cd)
ch = gf.chart
ch.has_legend = False
ch.has_title = True
ch.chart_title.text_frame.text = "Onde está a área (% do chip)"
tp = ch.chart_title.text_frame.paragraphs[0]
for r in tp.runs:
    r.font.size = Pt(20); r.font.bold = True; r.font.color.rgb = rgb(WHITE); r.font.name = BODY
ch.font.size = Pt(18); ch.font.color.rgb = rgb(WHITE); ch.font.name = BODY
pl = ch.plots[0]
pl.gap_width = 60
pl.has_data_labels = True
dl = pl.data_labels
dl.number_format = '0.0"%"'; dl.number_format_is_linked = False
dl.position = XL_LABEL_POSITION.OUTSIDE_END
dl.font.size = Pt(18); dl.font.bold = True; dl.font.color.rgb = rgb(AMBER)
ser = pl.series[0]
ser.format.fill.solid(); ser.format.fill.fore_color.rgb = rgb(AMBER)
va = ch.value_axis
va.visible = False; va.has_major_gridlines = False; va.maximum_scale = 75
ca = ch.category_axis
ca.format.line.fill.background(); ca.tick_labels.font.size = Pt(18); ca.tick_labels.font.color.rgb = rgb(WHITE)
card(s, 12.2, 5.05, 7.0, 4.4)
text(s, 12.45, 5.2, 6.5, 4.1, [
    [("Ficha da rodada", {"bold": True, "color": AMBER, "size": 24})],
    "Genus 22.1 (VM do curso)",
    "sky130_fd_sc_hd, TT 25 °C 1,80 V + .lib das 4 macros",
    "Relógio de 20 ns (50 MHz)",
    "Células de scan evitadas no chip (DFT só no IP)",
    "~10 min de síntese"], size=19, space=6)
notes(s, "(1 min) Síntese: 1,91 mm², 62 % em macros, fecha 50 MHz com 2,4 ns de folga. Da lógica, "
         "a ISFFT é maior que o próprio processador.")
final.append(s)

# =====================================================================
# 28. NETLIST NO GENUS (original 24)
s = orig[23]; strip_text(s); title(s, "PARTE 1 — NETLIST NO GENUS")
ix, iy, iw, ih = fit_content(s, 0.8, 2.05, 18.4, 7.15)
caption(s, ix, iy + ih + 0.05, 8, "Fonte: Autor — Cadence Genus")
notes(s, "(15 s) Vista do netlist sintetizado no Genus.")
final.append(s)

# =====================================================================
# 29. PÓS-SÍNTESE E LEC
s = new_slide(); title(s, "PARTE 1 — PÓS-SÍNTESE E LEC")
card(s, 0.8, 2.1, 11.2, 3.55, fill="120C33", alpha=88, line=False, radius=0.03)
text(s, 1.05, 2.22, 10.8, 3.35, [
    "[UART] CHK 0 0xeb88508e ciclos 0x00000a3e",
    "[UART] CHK 1 0xba7fc58e ciclos 0x00000a3e",
    "[UART] CHK 2 0xb29c0211 ciclos 0x00000a3e",
    "[UART] MAT_IN 0x00000003 MAT_OUT 0x00000003 ERR 0x00000000",
    "[UART] RESULTADO: OK",
    "[TB] fim em 3.764 ms (188195 ciclos)",
    [("[TB] PASSOU", {"color": AMBER, "bold": True})]], size=16, font=MONO, color="B9F5C8", space=2)
caption(s, 0.8, 5.72, 11.2, "Xcelium: o firmware completo roda no netlist do Genus; as 3 somas são iguais às do RTL (31 s).")
for i, (n, lab) in enumerate([("169/169", "módulos equivalentes\nRTL × netlist (Conformal)"),
                              ("19.828", "pontos comparados,\n0 diferenças")]):
    stat(s, 12.5, 2.1 + i * 1.9, 6.7, 1.75, n, lab, numsize=38, labsize=17)
rows = [["Verificação", "Pergunta", "Resposta"],
        ["Genus", "Sintetiza e fecha timing?", "Sim: +2,41 ns a 50 MHz, 1,91 mm²"],
        ["Conformal LEC", "O netlist é o mesmo circuito do RTL?", "Sim: 169/169 módulos, 19.828 pontos"],
        ["Xcelium pós-síntese", "O netlist funciona (reset, sem X)?", "Sim: 3 somas = RTL, PASSOU"],
        ["Simulação RTL", "A matemática está certa?", "Sim: EVM = placa"]]
table(s, 0.8, 6.3, 18.4, rows, [3.6, 7.0, 7.8], rowh=0.62, size=18, bold_first_col=True)
notes(s, "(1 min) Pós-síntese: o mesmo firmware roda no netlist e as 3 somas batem com o RTL. O LEC "
         "prova que o netlist é o mesmo circuito do RTL. Essa tabela fecha a parte 1.")
final.append(s)

# =====================================================================
# 30. DOIS NÍVEIS
s = new_slide(); title(s, "PARTE 2 — LAYOUT EM DOIS NÍVEIS")
for i, (t, d) in enumerate([
        ("Nível 1 — núcleo (asic_top)",
         "Netlist do Genus + 4 macros; die de 2,0 × 1,5 mm. Fluxo Classic do LibreLane: floorplan, PDN, "
         "posicionamento, CTS, roteamento, DRC e LVS."),
        ("Nível 2 — chip",
         "Núcleo como macro + anel de pads sky130_ef_io; die de 2,70 × 2,20 mm. 11 pads (4 de sinal: clk, "
         "rstn, rx, tx; 6 de alimentação; 1 fatia) + 4 cantos.")]):
    y = 2.1 + i * 3.75
    card(s, 0.8, y, 8.6, 3.45)
    text(s, 1.05, y + 0.15, 8.1, 0.7, t, size=25, bold=True, color=AMBER)
    text(s, 1.05, y + 0.9, 8.1, 2.45, d, size=20)
ix, iy, iw, ih = picture(s, IMG + "12_chip_preenchido.png", 9.9, 2.1, 9.3, 7.0)
caption(s, ix, iy + ih + 0.05, iw, "Chip final com o anel de pads e o preenchimento. Fonte: Autor")
notes(s, "(45 s) Parte 2, extra. O layout foi feito em dois níveis: primeiro o núcleo com as macros, "
         "depois o chip com o anel de pads do SkyWater.")
final.append(s)

# =====================================================================
# 31. NÚCLEO ETAPA A ETAPA
s = new_slide(); title(s, "PARTE 2 — NÚCLEO, ETAPA A ETAPA")
imgs = [("02_floorplan_planta.png", "1 · Floorplan"), ("03_pdn_malha.png", "2 · Rede de alimentação"),
        ("04_posicionamento_celulas.png", "3 · Posicionamento"), ("05_cts_buffers.png", "4 · Árvore de relógio"),
        ("06_roteamento_chip.png", "5 · Roteamento"), ("08_gds_klayout.png", "6 · GDS (KLayout)")]
cw = 18.4 / 3
for k, (f, lab) in enumerate(imgs):
    r, c = divmod(k, 3)
    x = 0.8 + c * cw; y = 2.05 + r * 3.72
    ix, iy, iw, ih = picture(s, IMG + f, x + 0.15, y, cw - 0.3, 3.15)
    text(s, x, iy + ih + 0.05, cw, 0.45, lab, size=19, bold=True, align=C, space=0)
notes(s, "(45 s) As etapas do núcleo no LibreLane: macros no floorplan, malha de alimentação, "
         "células, árvore de relógio, roteamento e o GDS final.")
final.append(s)

# =====================================================================
# 32. SIGN-OFF
s = new_slide(); title(s, "PARTE 2 — VERIFICAÇÃO FINAL")
rows = [["Verificação", "Núcleo (asic_top)", "Chip com o anel de pads"],
        ["DRC (Magic)", "0 defeitos reais (130 isentos: pinos sem uso das macros)", "0 no nosso desenho (faixa dos pads isenta)"],
        ["LVS (Netgen)", "Circuits match uniquely", "Circuits match uniquely"],
        ["XOR Magic × KLayout", "0", "0"],
        ["Antena", "0", "0"],
        ["LEC: layout × Genus", "19.828 pontos equivalentes", "—"],
        ["Simulação com o firmware", "3 somas = RTL", "3 somas = RTL (com os pads)"],
        ["STA: setup no pior caso", "+0,32 ns (TT)", "+2,37 ns (SS)"],
        ["STA: hold", "15 caminhos ≤ 28 ps no FF (aceitos)", "+3,63 ns"]]
table(s, 0.8, 2.1, 18.4, rows, [4.2, 7.3, 6.9], rowh=0.7, size=18, bold_first_col=True)
card(s, 0.8, 8.65, 18.4, 0.85, fill=AMBER, alpha=22, line=False)
text(s, 0.8, 8.65, 18.4, 0.85,
     [[("Cadeia fechada: ", {"bold": True, "color": AMBER}),
       ("RTL ≡ Genus ≡ layout (LEC) ≡ GDS (LVS), e o desenho roda o firmware.", {})]],
     size=22, align=C, anchor=MSO_ANCHOR.MIDDLE)
notes(s, "(1 min) O sign-off. DRC e LVS limpos no que é nosso; os erros que sobram são das células da "
         "foundry. O LEC e a simulação provam que o layout é o mesmo circuito e que funciona. "
         "Timing fecha nos dois níveis; os 15 holds de 28 ps no corner rápido ficaram documentados.")
final.append(s)

# =====================================================================
# 33. LIÇÕES
s = new_slide(); title(s, "PARTE 2 — TRÊS LIÇÕES")
cards3 = [("Congestionamento", "4.682 → 0",
           "Excesso no roteamento global. Densidade alvo de 65 % e a DMEM movida para o canto abriram o canal entre as macros."),
          ("Macros vazias no GDS", "15,7 mi → 0",
           "Diferenças no XOR Magic × KLayout: o LEF da OpenRAM vinha sem FOREIGN e o KLayout gravava as macros vazias."),
          ("Transição no pino tx", "3,54 → 0,11 ns",
           "Com o modelo de tempo do núcleo, o reparo viu a saída fraca e pôs 1 buffer antes do pad (limite: 1,5 ns).")]
for i, (t, n, d) in enumerate(cards3):
    x = 0.8 + i * 6.3
    card(s, x, 2.1, 5.8, 7.35)
    text(s, x + 0.25, 2.25, 5.3, 0.65, t, size=25, bold=True)
    if i == 0:
        picture(s, IMG + "congestao_antes.png", x + 0.25, 3.0, 2.55, 1.95)
        picture(s, IMG + "06_roteamento_global_congestao.png", x + 3.0, 3.0, 2.55, 1.95)
        text(s, x + 0.25, 4.95, 2.55, 0.4, "antes", size=15, align=C, color="D8D4F0", space=0)
        text(s, x + 3.0, 4.95, 2.55, 0.4, "depois", size=15, align=C, color="D8D4F0", space=0)
    elif i == 1:
        picture(s, IMG + "08_gds_klayout.png", x + 0.25, 3.0, 5.3, 1.95)
        text(s, x + 0.25, 4.95, 5.3, 0.4, "GDS do KLayout, já com as macros", size=15, align=C, color="D8D4F0", space=0)
    else:
        picture(s, IMG + "11_chip.png", x + 0.25, 3.0, 5.3, 1.95)
        text(s, x + 0.25, 4.95, 5.3, 0.4, "chip refeito com o buffer (05/11)", size=15, align=C, color="D8D4F0", space=0)
    ny = 5.35
    text(s, x + 0.2, ny, 5.4, 1.0, [[(n, {"bold": True, "font": HEAD})]], size=40, color=AMBER, align=C,
         anchor=MSO_ANCHOR.MIDDLE)
    text(s, x + 0.3, ny + 1.15, 5.2, 9.3 - ny - 1.15, d, size=20)
notes(s, "(1 min) Três problemas que viraram lição: congestão resolvida mudando o floorplan; macros "
         "vazias no GDS por um campo que faltava no LEF da OpenRAM; e a transição do pino tx, resolvida "
         "dando ao fluxo do chip o modelo de tempo do núcleo.")
final.append(s)

# =====================================================================
# 34. CONCLUSÕES
s = new_slide(); title(s, "CONCLUSÕES")
cols = [("Bloco", "IP ISFFT verificado com UVM (10/10 testes, 100 % funcional) e testável com DFT (99,65 % stuck-at)."),
        ("Sistema", "NEORV32 controla a ISFFT sozinho na Kria KR260: EVM igual ao modelo, 5,06 µs por matriz."),
        ("Silício", "SoC em SkyWater 130 nm: 1,91 mm² a 50 MHz no Cadence; GDSII com padring e DRC/LVS limpos (extra).")]
for i, (t, d) in enumerate(cols):
    x = 0.8 + i * 6.45
    card(s, x, 2.1, 5.7, 3.2)
    text(s, x + 0.25, 2.2, 5.2, 0.7, t, size=30, bold=True, color=AMBER, font=HEAD)
    text(s, x + 0.25, 2.95, 5.2, 2.3, d, size=22)
    if i < 2:
        arrow(s, x + 5.78, 3.7, x + 6.37, 3.7, color=AMBER, width=4)
card(s, 0.8, 5.65, 18.4, 1.45, fill=AMBER, alpha=22, line=False)
text(s, 1.0, 5.65, 18.0, 1.45,
     [[("Mesmo estímulo, mesma resposta: ", {"bold": True, "color": AMBER}),
       ("EVM 3,41 / 0,78 / 0,60 % na placa, no RTL do chip e no UVM; as mesmas 3 somas do RTL ao layout.", {})]],
     size=22, anchor=MSO_ANCHOR.MIDDLE)
text(s, 0.8, 7.4, 18.4, 0.6, "Próximos passos", size=24, bold=True, color=CYAN)
text(s, 0.8, 8.0, 18.4, 1.45, [
    "Trocar ISFFT + Heisenberg pela Transformada de Zak e crescer a matriz rumo a 1024 × 256 (LEO).",
    "Protótipo na ZCU102 + FMCOMMS3 (AD9361) e transmissão over-the-air entre duas placas."],
    size=21, bullet=True, space=6)
notes(s, "(1 min) Fechamento: bloco, sistema e silício, com o mesmo resultado em todos os níveis. "
         "Próximos passos do transceptor: Zak, matriz maior e transmissão real.")
final.append(s)

# =====================================================================
# Ordem final e remoção do resto
sldIdLst = prs.slides._sldIdLst
id_of = {}
for sldId in list(sldIdLst):
    id_of[prs.part.related_part(sldId.rId)] = sldId
keep = [id_of[s.part] for s in final]
for sldId in list(sldIdLst):
    sldIdLst.remove(sldId)
for sldId in keep:
    sldIdLst.append(sldId)
# solta as relações dos slides que saíram
kept_parts = {s.part for s in final}
for rel in list(prs.part.rels.values()):
    if rel.reltype.endswith("/slide") and rel.target_part not in kept_parts:
        prs.part.drop_rel(rel.rId)
prs.save(OUT)
print("slides:", len(final))
