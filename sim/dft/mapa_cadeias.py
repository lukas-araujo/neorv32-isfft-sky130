#!/usr/bin/env python3
"""
mapa_cadeias.py -- segue as cadeias de scan num netlist e gera o mapa
(cadeia, posicao) de cada flip-flop. DIARIO_DFT, 3a sessao (T13).

Serve ao testbench do modo de teste (vm/backend/dft_isfft/tb/
tb_isfft_modo_teste.v): para carregar um valor num registrador pelas cadeias
(ou ler um registrador depois da captura), o tb precisa saber em que
cadeia e em que posicao esta cada bit. Quem sabe e o netlist: o SCD de cada
flip-flop de scan vem do Q do anterior (talvez passando por buffers); o 1o
vem da porta scan_in.

Funciona com o netlist do Genus (portas scan_in_<i>/scan_out_<i>) e com o
de conferencia do sim/dft/dft_costura.py (barramentos scan_in[i]/scan_out[i]).

Posicao 0 = o flip-flop ligado ao scan_in (o 1o a receber um bit);
posicao L-1 = o que aparece no scan_out.

Uso:
  python3 mapa_cadeias.py <netlist.v> <topo> <saida.vh> [saida.txt]

Saida .vh (incluida pelo tb):
  localparam NCAD; function L(c); e, para cada registrador pedido em
  REGISTRADORES, macros `<reg>_C(i)` / `<reg>_P(i)` (cadeia e posicao do bit
  i) e o caminho da instancia do bit escolhido para a falha injetada.
Saida .txt: comprimentos e a lista completa (cadeia, posicao, instancia, Q).
"""
import re
import sys

if len(sys.argv) < 4:
    sys.exit(__doc__)
ent, topo, sai_vh = sys.argv[1:4]
sai_txt = sys.argv[4] if len(sys.argv) > 4 else None

# Registradores do isfft_axi_v4 que o tb carrega ou le (nome no RTL, largura)
REGISTRADORES = [
    ("mat_in_cnt", 32), ("mat_out_cnt", 32), ("err_cnt", 32),
    ("pkt_mat", 16), ("in_wcnt", 5), ("in_wr_ptr", 7), ("in_wr_commit", 7),
    ("in_rd_ptr", 7), ("ctrl_enable", 1), ("ctrl_soft_rst", 1),
]
# Falha stuck-at-0 injetada pelo tb: no pino D deste bit
FALHA = ("mat_in_cnt", 8)

txt = open(ent).read()
m = re.search(r"\bmodule\s+" + re.escape(topo) + r"\b", txt)
if not m:
    sys.exit("topo nao encontrado")
corpo = txt[m.end():txt.index("endmodule", m.end())]

INST = re.compile(r"(sky130_fd_sc_hd__(\w+?)_\d+)\s+(\\\S+\s|\S+)\s*\((.*?)\);", re.S)

def pinos(conn):
    """{pino: rede} -- redes podem ser identificadores escapados com indice"""
    d = {}
    for p in re.finditer(r"\.(\w+)\s*\(", conn):
        i, nivel, j = p.end(), 1, p.end()
        while nivel:
            nivel += {"(": 1, ")": -1}.get(conn[j], 0)
            j += 1
        d[p.group(1)] = norm(conn[i:j - 1])
    return d

def norm(n):
    """'\\a.b [5] ' -> 'a.b[5]';  'x' -> 'x'"""
    n = n.strip()
    if n.startswith("\\"):
        n = n[1:]
    return re.sub(r"\s+", "", n)

ffs = {}          # instancia -> {D, Q, SCD, SCE, cel}
driver = {}       # rede -> (tipo, rede de entrada) para buffers
for f in INST.finditer(corpo):
    cel, base, nome, conn = f.group(1), f.group(2), norm(f.group(3)), f.group(4)
    p = pinos(conn)
    if base in ("sdfxtp", "sedfxtp", "sdfxbp", "sdfrtp", "sdfstp"):
        ffs[nome] = dict(p, cel=cel)
    elif base in ("buf", "clkbuf", "dlygate4sd1", "dlygate4sd3", "dlymetal6s2s",
                  "dlygate4sd2", "dlymetal6s4s", "dlymetal6s6s"):
        driver[p["X"]] = ("buf", p["A"])
    elif base in ("inv", "clkinv"):
        driver[p["Y"]] = ("inv", p["A"])

# assign <a> = <b>; (o Genus pode ligar redes com assign)
for a in re.finditer(r"assign\s+(.+?)\s*=\s*(.+?);", corpo):
    driver[norm(a.group(1))] = ("buf", norm(a.group(2)))

q_de = {v["Q"]: k for k, v in ffs.items()}

def origem(rede):
    """sobe pelos buffers/inversores ate um Q ou uma porta; devolve (rede, inversoes)"""
    inv = 0
    vistos = set()
    while rede not in q_de and rede in driver and rede not in vistos:
        vistos.add(rede)
        t, r = driver[rede]
        inv ^= (t == "inv")
        rede = r
    return rede, inv

# sucessor: para cada fonte (Q ou porta), o flip-flop cujo SCD vem dela
suc = {}
for nome, p in ffs.items():
    fonte, inv = origem(p["SCD"])
    if inv:
        sys.exit("inversor no caminho de scan antes de %s: nao suportado" % nome)
    if fonte in suc:
        sys.exit("duas celulas no mesmo SCD (%s): %s, %s" % (fonte, suc[fonte], nome))
    suc[fonte] = nome

# portas de entrada de scan, nas duas convencoes
entradas = sorted({f for f in suc if re.fullmatch(r"scan_in(_\d+|\[\d+\])", f)},
                  key=lambda s: int(re.findall(r"\d+", s)[0]))
if not entradas:
    sys.exit("nenhum scan_in encontrado")

cadeias = []
for e in entradas:
    seq, atual = [], e
    while atual in suc:
        ff = suc[atual]
        seq.append(ff)
        atual = ffs[ff]["Q"]
    cadeias.append(seq)

usados = sum(len(c) for c in cadeias)
if usados != len(ffs):
    print("AVISO: %d flip-flops de scan, %d nas cadeias" % (len(ffs), usados))

pos = {}          # rede Q normalizada -> (c, p, instancia)
for c, seq in enumerate(cadeias):
    for p, ff in enumerate(seq):
        pos[ffs[ff]["Q"]] = (c, p, ff)

def acha(reg, i, larg):
    """posicao do bit i do registrador 'reg' pelo nome do Q"""
    cands = [reg + "[%d]" % i] if larg > 1 else [reg, reg + "[0]"]
    for q in cands:
        if q in pos:
            return pos[q]
    # Genus: Q pode ter outro nome; tenta pelo nome da instancia (<reg>_reg[i])
    alvo = [reg + "_reg[%d]" % i] if larg > 1 else [reg + "_reg"]
    for (c, p, ff) in pos.values():
        if ff in alvo:
            return (c, p, ff)
    return None

linhas = ["// GERADO por sim/dft/mapa_cadeias.py a partir de %s -- NAO EDITE" % ent.split("/")[-1],
          "localparam integer NCAD = %d;" % len(cadeias),
          "function integer L(input integer c);", "  case (c)"]
linhas += ["    %d: L = %d;" % (c, len(s)) for c, s in enumerate(cadeias)]
linhas += ["    default: L = 0;", "  endcase", "endfunction"]
faltam = []
for reg, larg in REGISTRADORES:
    cs, ps = [], []
    for i in range(larg):
        r = acha(reg, i, larg)
        if r is None:
            faltam.append("%s[%d]" % (reg, i)); cs.append(-1); ps.append(-1)
        else:
            cs.append(r[0]); ps.append(r[1])
    for nomef, vals in (("C", cs), ("P", ps)):
        linhas.append("function integer %s_%s(input integer i);" % (reg, nomef))
        linhas.append("  case (i)")
        linhas += ["    %d: %s_%s = %d;" % (i, reg, nomef, v) for i, v in enumerate(vals)]
        linhas.append("    default: %s_%s = -1;" % (reg, nomef))
        linhas.append("  endcase")
        linhas.append("endfunction")
r = acha(FALHA[0], FALHA[1], 32)
if r is None:
    sys.exit("bit da falha nao encontrado: %s[%d]" % FALHA)
inst = r[2]
ref = ("\\" + inst + " ") if re.search(r"[^\w]", inst) else inst
linhas.append("// falha stuck-at-0 no pino D de %s[%d] (instancia %s)" % (FALHA[0], FALHA[1], inst))
linhas.append("`define PINO_FALHA dut.%s.D" % ref)
open(sai_vh, "w").write("\n".join(linhas) + "\n")

print("cadeias: %d; comprimentos: %s" % (len(cadeias), " ".join(str(len(s)) for s in cadeias)))
print("flip-flops de scan: %d; nas cadeias: %d" % (len(ffs), usados))
for reg, larg in REGISTRADORES:
    a = acha(reg, 0, larg)
    print("  %-14s bit 0 em cadeia %s posicao %s (%s)" % (reg, a[0], a[1], a[2]) if a else "  %-14s NAO ACHADO" % reg)
print("falha: stuck-at-0 em %s.D (%s[%d], cadeia %d posicao %d)" % (inst, FALHA[0], FALHA[1], r[0], r[1]))
if faltam:
    print("NAO ACHADOS: %s" % " ".join(faltam))
if sai_txt:
    with open(sai_txt, "w") as f:
        for c, seq in enumerate(cadeias):
            f.write("# cadeia %d: %d flip-flops\n" % (c, len(seq)))
            for p, ff in enumerate(seq):
                f.write("%d %d %s %s\n" % (c, p, ff, ffs[ff]["Q"]))
sys.exit(1 if faltam else 0)
