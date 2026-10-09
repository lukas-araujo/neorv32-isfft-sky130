# conta_gds.py -- conta formas por camada nos dois GDS da etapa 8 (Magic x
# KLayout), separando o que esta DENTRO das 4 macros do resto do chip.
#
# Rodado pelo diag_xor.sh:  klayout -b -r conta_gds.py
#   GDS_A, GDS_B (caminhos), MACROS (nomes separados por espaco) e SAIDA
#   vem do ambiente.
#
# Contagem hierarquica (de baixo para cima): formas da celula + formas das
# subcelulas x numero de instancias (arrays contam todos os elementos).
# Nao achata nada: roda em segundos mesmo com dezenas de milhoes de formas.
import os
import pya

macros = os.environ["MACROS"].split()
saida = open(os.environ["SAIDA"], "w")


def conta(path):
    ly = pya.Layout()
    ly.read(path)
    top = ly.top_cells()
    camadas = {li: ly.get_info(li).to_s() for li in ly.layer_indices()}
    total = {}  # cell_index -> {camada: n}
    for ci in ly.each_cell_bottom_up():
        c = ly.cell(ci)
        n = {nome: c.shapes(li).size() for li, nome in camadas.items()}
        for inst in c.each_inst():
            k = inst.na * inst.nb if inst.is_regular_array() else 1
            for nome, v in total[inst.cell_index].items():
                n[nome] = n.get(nome, 0) + k * v
        total[ci] = n
    return ly, top, total


res = {}
for tag in ("GDS_A", "GDS_B"):
    path = os.environ[tag]
    ly, top, total = conta(path)
    saida.write(f"== {tag}: {path}\n")
    saida.write(f"   celulas de topo: {[t.name for t in top]}; celulas: {ly.cells()}\n")
    t = top[0]
    inst_macro = {m: 0 for m in macros}
    for inst in t.each_inst():
        nome = ly.cell(inst.cell_index).name
        if nome in inst_macro:
            inst_macro[nome] += 1
    dentro = {}
    for m in macros:
        c = ly.cell(m)
        if c is None:
            saida.write(f"   macro {m}: AUSENTE no GDS\n")
            continue
        n = total[c.cell_index()]
        s = sum(n.values())
        saida.write(f"   macro {m}: {inst_macro[m]} instancia(s), {s} formas, "
                    f"{sum(1 for v in n.values() if v)} camadas, "
                    f"{len(list(c.each_child_cell()))} subcelulas diretas\n")
        for nome, v in n.items():
            dentro[nome] = dentro.get(nome, 0) + v * inst_macro[m]
    res[tag] = (total[t.cell_index()], dentro)
    saida.write("\n")

a_tot, a_den = res["GDS_A"]
b_tot, b_den = res["GDS_B"]
saida.write("| Camada | A dentro das macros | B dentro das macros | A fora | B fora |\n")
saida.write("|---|---|---|---|---|\n")
for nome in sorted(set(a_tot) | set(b_tot)):
    ad, bd = a_den.get(nome, 0), b_den.get(nome, 0)
    af, bf = a_tot.get(nome, 0) - ad, b_tot.get(nome, 0) - bd
    if ad or bd or af or bf:
        marca = "" if (ad == bd and af == bf) else "  <-- difere"
        saida.write(f"| {nome} | {ad} | {bd} | {af} | {bf} |{marca}\n")
saida.close()
