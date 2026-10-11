#!/usr/bin/env python3
"""tira_fisicas.py -- netlist do layout sem as celulas so fisicas (etapa 9)

Uso: python3 tira_fisicas.py <entrada.nl.v> <saida.v> <golden.v>

O netlist final do LibreLane (asic_top.nl.v, do FillInsertion) tem TODA
instancia do layout, inclusive as que nao tem funcao logica:
  preenchimento  sky130_fd_sc_hd__fill_N, sky130_ef_sc_hd__fill_N
  desacoplamento sky130_fd_sc_hd__decap_N, sky130_ef_sc_hd__decap_12
  tap do poco    sky130_fd_sc_hd__tapvpwrvgnd_1
  diodo de antena sky130_fd_sc_hd__diode_2 (so um pino de entrada)
O Conformal e o Xcelium nao precisam delas (e as ef_ nem tem modelo .v no
pacote da VM). Mesma escolha do LibreLane para o netlist "logico"
(write_verilog -remove_cells [get_physical_cells]).

Le instrucao por instrucao (ate o ';'), entao funciona com instancias em
varias linhas. Imprime uma tabela com:
  - quantas instancias de cada tipo fisico sairam;
  - flip-flops e macros no golden (netlist do Genus achatado) x layout:
    TEM de bater -- o layout so poe/troca logica combinacional e buffers;
  - tipos de celula que existem no layout e nao no golden (buffers de
    relogio, de hold, ...).
"""
import collections
import re
import sys

FISICA = re.compile(r"^sky130_(fd|ef)_sc_hd__(fill|decap|tapvpwrvgnd|diode)_\w+$")
# flip-flops (df*, sdf*, edf*) e latches (dlx*, dlr*, dlclkp*). NAO pega as
# celulas de atraso dlygate*/dlymetal* -- sao os buffers de hold (31a sessao:
# o primeiro padrao, "dl*", contou 1.034 delas como flip-flop)
FF = re.compile(r"^sky130_fd_sc_hd__(df\w*|sdf\w*|edf\w*|dl[xr]\w*|dlclkp\w*)$")
MACRO = re.compile(r"^sram_\w+$")
PALAVRAS = {"module", "endmodule", "input", "output", "inout", "wire", "reg",
            "assign", "supply0", "supply1", "tri", "parameter", "localparam"}


def instrucoes(texto):
    """Divide em instrucoes terminadas por ';' (identificadores escapados
    do Verilog terminam em espaco, nao contem ';' na pratica)."""
    atual = []
    for linha in texto.splitlines(keepends=True):
        atual.append(linha)
        if linha.rstrip().endswith(";") or linha.strip() == "endmodule":
            yield "".join(atual)
            atual = []
    if atual:
        yield "".join(atual)


def tipo(instr):
    t = instr.split(None, 1)
    if not t:
        return None
    w = t[0]
    if w in PALAVRAS or w.startswith(("//", "`", "(*")):
        return None
    return w


def conta(caminho):
    c = collections.Counter()
    with open(caminho, errors="replace") as f:
        for ins in instrucoes(f.read()):
            t = tipo(ins)
            if t:
                c[t] += 1
    return c


entrada, saida, golden = sys.argv[1:4]
removidas = collections.Counter()
mantidas = collections.Counter()
with open(entrada, errors="replace") as f, open(saida, "w") as o:
    o.write("// asic_top -- netlist do LAYOUT (LibreLane, rodada final), sem as celulas\n"
            "// so fisicas (fill/decap/tap/diodo). Gerado por layout/nucleo/tira_fisicas.py\n")
    for ins in instrucoes(f.read()):
        t = tipo(ins)
        if t and FISICA.match(t):
            removidas[t] += 1
            continue
        if t:
            mantidas[t] += 1
        o.write(ins)

g = conta(golden)
print("| Celulas fisicas retiradas | Instancias |")
print("|---|---|")
for t, n in sorted(removidas.items(), key=lambda kv: -kv[1]):
    print(f"| `{t}` | {n} |")
print(f"| **Total** | **{sum(removidas.values())}** |")
print()


def soma(c, rx):
    return sum(n for t, n in c.items() if rx.match(t))


ff_g, ff_l = soma(g, FF), soma(mantidas, FF)
ma_g, ma_l = soma(g, MACRO), soma(mantidas, MACRO)
print("| | Golden (Genus achatado) | Layout (sem fisicas) | Confere |")
print("|---|---|---|---|")
print(f"| Instancias | {sum(g.values())} | {sum(mantidas.values())} | — |")
print(f"| Flip-flops | {ff_g} | {ff_l} | {'ok' if ff_g == ff_l else 'DIFERENTE'} |")
print(f"| Macros | {ma_g} | {ma_l} | {'ok' if ma_g == ma_l == 4 else 'DIFERENTE'} |")
print()
novos = {t: n for t, n in mantidas.items() if t not in g}
print("| Tipos de celula que so existem no layout | Instancias |")
print("|---|---|")
for t, n in sorted(novos.items(), key=lambda kv: -kv[1])[:25]:
    print(f"| `{t}` | {n} |")
sys.exit(0 if (ff_g == ff_l and ma_g == ma_l == 4) else 1)
