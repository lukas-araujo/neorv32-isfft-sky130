#!/usr/bin/env python3
"""
lef_foreign.py -- poe "FOREIGN <macro> ;" nos LEF das macros (L45)

Projeto: NEORV32 + ISFFT em ASIC (sky130) -- ver DIARIO_GDSII.md, 29a sessao

O PROBLEMA
    A OpenRAM escreve o LEF sem a linha FOREIGN. Ela diz "o desenho de
    verdade desta macro e a celula <nome> de um GDS externo". As celulas
    padrao do sky130 tem (FOREIGN sky130_fd_sc_hd__... ;).

    Sem FOREIGN, o leitor LEF/DEF do KLayout DESENHA a macro com a
    geometria do LEF (pinos e obstrucoes). O KLayout.StreamOut do LibreLane
    limpa essa celula e le o GDS da macro com KLAYOUT_CONFLICT_RESOLUTION =
    RenameCell: como a celula ja existe (vazia, mas nao "fantasma"), o
    conteudo do GDS entra como "<nome>$1" e a instancia do chip continua
    apontando para a celula VAZIA. Resultado na 28a sessao: GDS do KLayout
    com as 4 macros vazias e 15,7 milhoes de diferencas no XOR.

    Com FOREIGN, a celula nasce "fantasma" (so o nome) e a leitura do GDS
    a preenche -- igual as celulas padrao.

O QUE ESTE SCRIPT FAZ (no proprio arquivo, em macros/<m>/)
    Acrescenta "   FOREIGN <nome> ;" logo depois de "CLASS BLOCK ;" de cada
    MACRO que nao tem FOREIGN. Nenhuma coordenada muda. Idempotente.

USO
    python3 macros/lef_foreign.py            # corrige as macros
    python3 macros/lef_foreign.py --check    # so confere (sai 1 se faltar)
"""
import re
import sys
from pathlib import Path

AQUI = Path(__file__).resolve().parent
so_confere = "--check" in sys.argv
faltou = False

for lef in sorted(AQUI.glob("*/*.lef")):
    texto = lef.read_text()
    linhas = texto.splitlines(keepends=True)
    # 1a passada: quais MACROs ja tem FOREIGN (em qualquer linha do bloco)
    com_foreign, macro = set(), None
    for l in linhas:
        m = re.match(r"\s*MACRO\s+(\S+)", l)
        if m:
            macro = m.group(1)
        elif macro and re.match(r"\s*FOREIGN\b", l):
            com_foreign.add(macro)
        elif macro and re.match(r"\s*END\s+" + re.escape(macro) + r"\s*$", l):
            macro = None
    # 2a passada: insere depois de CLASS BLOCK nas que nao tem
    saida, macro, mudou = [], None, False
    for l in linhas:
        m = re.match(r"\s*MACRO\s+(\S+)", l)
        if m:
            macro = m.group(1)
        saida.append(l)
        if macro and macro not in com_foreign and re.match(r"\s*CLASS\s+BLOCK\s*;", l):
            indent = re.match(r"(\s*)", l).group(1)
            saida.append(f"{indent}FOREIGN {macro} ;\n")
            com_foreign.add(macro)
            mudou = True
    if so_confere:
        ok = not mudou
        print(f"{'ok' if ok else 'SEM FOREIGN'}: {lef.relative_to(AQUI)}")
        faltou = faltou or not ok
    elif mudou:
        lef.write_text("".join(saida))
        print(f"corrigido: {lef.relative_to(AQUI)}")
    else:
        print(f"ja tinha: {lef.relative_to(AQUI)}")

sys.exit(1 if (so_confere and faltou) else 0)
