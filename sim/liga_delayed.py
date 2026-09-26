#!/usr/bin/env python3
"""liga_delayed.py -- aciona os fios <ENTRADA>_delayed dos modelos sky130 sem 'specify'.

Uso: python3 liga_delayed.py sky130_fd_sc_hd.v sky130_fd_sc_hd_ligado.v

Nos modelos comportamentais (sem FUNCTIONAL) as celulas sequenciais leem
copias atrasadas das entradas (D_delayed, CLK_delayed, RESET_B_delayed...).
Quem as aciona e o bloco 'specify' ($setuphold/$recrem com argumentos de
atraso). Este arquivo nao tem 'specify', entao elas ficam em Z e o flip-flop
em X. Aqui cada <ENTRADA>_delayed vira 'assign <ENTRADA>_delayed = <ENTRADA>;'
-- o que o specify faria com atraso zero, sem checagem de tempo.
Fios *_delayed que ja sao acionados dentro da celula (ex.: SCE_gate_delayed,
saida de um nor) nao sao tocados."""
import re, sys
out, n, entradas = [], 0, set()
for linha in open(sys.argv[1]).read().split('\n'):
    if re.match(r'\s*module\s', linha):
        entradas = set()
    m = re.match(r'\s*input\s+(?:wire\s+)?(?:\[[^\]]*\]\s*)?(\w+)\s*;', linha)
    if m:
        entradas.add(m.group(1))
    out.append(linha)
    m = re.match(r'\s*wire\s+(\w+)_delayed\s*;', linha)
    if m and m.group(1) in entradas:
        out.append(f'    assign {m.group(1)}_delayed = {m.group(1)};  // sem specify: liga direto')
        n += 1
open(sys.argv[2], 'w').write('\n'.join(out))
print(f"{n} fios <entrada>_delayed ligados")
