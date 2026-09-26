#!/usr/bin/env python3
"""
lib_33bits.py -- iguala o .lib das macros de 1 porta ao .v e ao .lef (L1)

Projeto: NEORV32 + ISFFT em ASIC (sky130) -- ver DIARIO_GDSII.md

O PROBLEMA
    As macros 1rw da OpenRAM no sky130 tem uma coluna sobressalente. O .v
    (simulacao) e o .lef/.gds (layout) mostram isso:
        din0[32:0]  dout0[32:0]  spare_wen0
    O .lib (timing) que a OpenRAM escreve NAO:
        din0[31:0]  dout0[31:0]  (sem spare_wen0)
    No front-end isso foi contornado com -define SRAM_LIB_VIEW (32 bits no
    RTL). No layout nao da: o LEF tem 33 bits + spare_wen0, e pino de
    entrada da macro sem ligacao fica flutuando.

O QUE ESTE SCRIPT FAZ (no proprio arquivo, em macros/<m>/)
    1. type(data): bit_width 32 -> 33, bit_from 31 -> 32
    2. memory(): word_width 32 -> 33
    3. pin(din0[31:0]) e pin(dout0[31:0]) -> [32:0]
       (o bit 32 herda a capacitancia e os arcos de timing do barramento)
    4. pin(spare_wen0): copia do bloco pin(web0) -- mesma capacitancia e o
       mesmo setup/hold contra clk0. E a escrita da coluna sobressalente,
       controlada como o web0.

    Idempotente: se ja estiver com 33 bits, so confere e sai.
    O original fica no historico do git.

USO
    python3 macros/lib_33bits.py            # corrige as 2 macros 1rw
    python3 macros/lib_33bits.py --check    # so confere (sai 1 se faltar)
"""
import re
import sys
from pathlib import Path

MACROS = ["sram_8kbyte_1rw_32x2048_8", "sram_4kbyte_1rw_32x1024_8"]
AQUI = Path(__file__).resolve().parent


def bloco(texto, inicio):
    """Devolve (ini, fim) do bloco { ... } que comeca em 'inicio'."""
    i = texto.index("{", inicio)
    nivel = 0
    for j in range(i, len(texto)):
        if texto[j] == "{":
            nivel += 1
        elif texto[j] == "}":
            nivel -= 1
            if nivel == 0:
                return inicio, j + 1
    raise ValueError("bloco sem fechamento")


def ja_corrigido(t):
    return ("pin(din0[32:0])" in t and "pin(dout0[32:0])" in t
            and re.search(r"\bpin\(spare_wen0\)", t) is not None)


def corrige(t, nome):
    # 1. tipo 'data'
    m = re.search(r"type \(data\)\s*\{", t)
    ini, fim = bloco(t, m.start())
    tipo = t[ini:fim]
    assert "bit_width : 32;" in tipo and "bit_from : 31;" in tipo, "type(data) inesperado"
    tipo = tipo.replace("bit_width : 32;", "bit_width : 33;").replace("bit_from : 31;", "bit_from : 32;")
    t = t[:ini] + tipo + t[fim:]

    # 2. memory()
    t, n = re.subn(r"(memory\(\)\s*\{[^}]*word_width\s*:\s*)32;", r"\g<1>33;", t)
    assert n == 1, "memory() inesperado"

    # 3. pinos do barramento
    for p in ("din0", "dout0"):
        assert t.count(f"pin({p}[31:0])") == 1, f"pin({p}[31:0]) inesperado"
        t = t.replace(f"pin({p}[31:0])", f"pin({p}[32:0])")

    # 4. spare_wen0 = copia do web0, inserido logo depois dele
    m = re.search(r"\n(\s*)pin\(web0\)\s*\{", t)
    ini, fim = bloco(t, m.start() + 1)
    web0 = t[ini:fim]
    spare = web0.replace("pin(web0)", "pin(spare_wen0)", 1)
    t = t[:fim] + "\n\n" + m.group(1) + spare.lstrip() + t[fim:]
    return t


def main():
    so_confere = "--check" in sys.argv
    falhou = False
    for nome in MACROS:
        arq = AQUI / nome / f"{nome}_TT_1p8V_25C.lib"
        t = arq.read_text()
        if ja_corrigido(t):
            print(f"ok (ja tem 33 bits): {arq.relative_to(AQUI.parent)}")
            continue
        if so_confere:
            print(f"FALTA corrigir: {arq.relative_to(AQUI.parent)}")
            falhou = True
            continue
        novo = corrige(t, nome)
        assert ja_corrigido(novo)
        assert novo.count("{") == novo.count("}"), "chaves desbalanceadas"
        arq.write_text(novo)
        print(f"corrigido: {arq.relative_to(AQUI.parent)}")
    sys.exit(1 if falhou else 0)


if __name__ == "__main__":
    main()
