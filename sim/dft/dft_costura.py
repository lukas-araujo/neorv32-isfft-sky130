#!/usr/bin/env python3
"""
dft_costura.py -- insercao de scan "de mentira" num netlist do Yosys.

Conferencia ABERTA da frente de DFT (DIARIO_DFT, 1a sessao), antes da VM.
NAO e o netlist que vai para o ATPG: quem insere o scan de verdade e o Genus
(vm/backend/dft_isfft/). Serve para provar, com Icarus, tres coisas que o
Genus vai assumir:
  1. os modelos das celulas de scan do sky130 (sdfxtp, sedfxtp) deslocam;
  2. com scan_en = 0 o circuito e o mesmo (regressao da Kria passa);
  3. o teste de cadeia (flush) pega uma cadeia quebrada (mutacao).

O que faz:
  - sky130_fd_sc_hd__dfxtp_N  -> sky130_fd_sc_hd__sdfxtp_N   (+ SCD, SCE)
  - sky130_fd_sc_hd__edfxtp_1 -> sky130_fd_sc_hd__sedfxtp_1  (+ SCD, SCE)
  - flip-flops em ordem de nome, divididos em N cadeias quase iguais;
    SCD do 1o = scan_in[i], SCD dos outros = Q do anterior, scan_out[i] = Q
    do ultimo;
  - portas novas no topo: scan_en, scan_in[N-1:0], scan_out[N-1:0].
  - qualquer outro flip-flop (com reset assincrono etc.) -> erro: o IP nao
    tem nenhum (conferido no RTL), e o script nao sabe trata-lo.

Uso:
  python3 dft_costura.py <netlist_yosys.v> <topo> <saida.v> [cadeias] [--mutacao]
  --mutacao: SCE de um flip-flop no meio da cadeia 0 fica em 0 (cadeia
             quebrada). O flush tem de reprovar so a cadeia 0.
Imprime o comprimento de cada cadeia (o tb de flush le essa linha).
"""
import re
import sys

args = [a for a in sys.argv[1:] if not a.startswith("--")]
MUT = "--mutacao" in sys.argv
if len(args) < 3:
    sys.exit(__doc__)
ent, topo, sai = args[0], args[1], args[2]
N = int(args[3]) if len(args) > 3 else 16

txt = open(ent).read()

# Localiza o modulo de topo
m = re.search(r"\bmodule\s+" + re.escape(topo) + r"\s*\((.*?)\);", txt, re.S)
if not m:
    sys.exit("topo nao encontrado: " + topo)
ini_mod = m.start()
fim_mod = txt.index("endmodule", m.end())
corpo = txt[m.end():fim_mod]

# Instancias de flip-flop: "<celula> <nome> ( ... );"
FF = re.compile(r"(sky130_fd_sc_hd__(\w+?)_(\d+))\s+(\S+)\s*\((.*?)\);", re.S)
trocas = {"dfxtp": "sdfxtp", "edfxtp": "sedfxtp"}
seq_re = re.compile(r"^(e?df|sdf|sedf|dl|df)")

insts = []
for f in FF.finditer(corpo):
    base = f.group(2)
    if base in trocas:
        insts.append(f)
    elif seq_re.match(base):
        sys.exit("flip-flop nao suportado: %s (%s)" % (f.group(1), f.group(4)))

if not insts:
    sys.exit("nenhum flip-flop encontrado")

def pino_q(conn):
    # .Q( ... ) com parenteses balanceados: o nome pode ser identificador
    # escapado com indice ("\a.b.c [5]")
    i = conn.index(".Q(") + 3
    nivel, j = 1, i
    while nivel:
        nivel += {"(": 1, ")": -1}.get(conn[j], 0)
        j += 1
    # o espaco no fim e obrigatorio: identificador escapado ("\a.b ") so
    # termina em espaco -- sem ele, "\a.b)" engole o parentese
    return conn[i:j - 1].strip() + " "

# Ordem de nome (o Genus agrupa por hierarquia; aqui basta ser deterministico)
insts.sort(key=lambda f: f.group(4))
tot = len(insts)
tam = [tot // N + (1 if i < tot % N else 0) for i in range(N)]

novo = {}            # posicao no corpo -> texto novo
k = 0
saidas = []
mut_feita = None
for c in range(N):
    anterior = "scan_in[%d]" % c
    for j in range(tam[c]):
        f = insts[k]; k += 1
        base, drv = f.group(2), f.group(3)
        conn = f.group(5)
        sce = "scan_en"
        if MUT and c == 0 and j == tam[0] // 2:
            sce = "1'b0"; mut_feita = f.group(4)
        cel = "sky130_fd_sc_hd__%s_%s" % (trocas[base], drv)
        novo[(f.start(), f.end())] = "%s %s (%s, .SCD(%s), .SCE(%s));" % (
            cel, f.group(4), conn.rstrip(), anterior, sce)
        anterior = pino_q(conn)
    saidas.append(anterior)

partes, pos = [], 0
for (a, b) in sorted(novo):
    partes.append(corpo[pos:a]); partes.append(novo[(a, b)]); pos = b
partes.append(corpo[pos:])
corpo2 = "".join(partes)

# Portas novas
portas = m.group(1).rstrip() + ", scan_en, scan_in, scan_out"
decl = ("\n  input scan_en;\n  input [%d:0] scan_in;\n  output [%d:0] scan_out;\n" % (N - 1, N - 1))
decl += "".join("  assign scan_out[%d] = %s;\n" % (i, s) for i, s in enumerate(saidas))

saida = (txt[:ini_mod] + "module %s(%s);" % (topo, portas) + decl + corpo2 + txt[fim_mod:])
open(sai, "w").write(saida)

print("flip-flops na cadeia: %d (sdfxtp: %d, sedfxtp: %d)" % (
    tot, sum(1 for f in insts if f.group(2) == "dfxtp"),
    sum(1 for f in insts if f.group(2) == "edfxtp")))
print("CADEIAS %d %s" % (N, " ".join(map(str, tam))))
if MUT:
    print("MUTACAO: SCE = 0 em %s (cadeia 0, posicao %d)" % (mut_feita, tam[0] // 2))
