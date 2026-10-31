#!/usr/bin/env python3
"""fecha_gds.py -- acha (e conserta) BOUNDARY aberto num GDS (L74).

Etapa 11 parte 2b (DIARIO_GDSII, 37a sessao). O sky130_fd_io.gds do PDK tem
um poligono cujo ultimo ponto nao repete o primeiro, na celula
sky130_fd_io__overlay_vddio_lvc. O GDSII exige o poligono fechado (o ultimo
par XY igual ao primeiro). O Magic avisa "Boundary is not closed" e o
LibreLane (MAGIC_CAPTURE_ERRORS) trata a frase como erro fatal.

  python3 fecha_gds.py confere <arquivo.gds>
      le os registros do GDS (sem biblioteca nenhuma) e lista os BOUNDARY
      abertos: celula, camada/tipo, primeiro e ultimo ponto. Sai 1 se achar.

  python3 fecha_gds.py fecha <entrada.gds> <saida.gds>
      lista, grava uma copia com os poligonos fechados e confere a copia.
      Conserto direto nos registros: so o XY do BOUNDARY aberto ganha um
      ponto (o primeiro, repetido no fim); o resto do arquivo sai byte a byte
      igual. Sem KLayout: nada de reordenar celulas ou mudar propriedades.

Formato de um registro GDSII: 2 bytes de tamanho (inclui o cabecalho),
1 byte de tipo, 1 byte de tipo de dado, depois os dados (big-endian).
"""
import struct
import sys

BGNSTR, STRNAME, ENDSTR = 0x05, 0x06, 0x07
BOUNDARY, LAYER, DATATYPE, XY, ENDEL = 0x08, 0x0D, 0x0E, 0x10, 0x11


def registros(dados):
    i, n = 0, len(dados)
    while i + 4 <= n:
        tam, tipo = struct.unpack_from(">HB", dados, i)
        if tam < 4:
            break  # enchimento no fim do arquivo
        yield i, tam, tipo
        i += tam


def abertos(dados):
    """[(posicao do XY, celula, camada, tipo, primeiro, ultimo)]"""
    r = []
    cel, no_bnd, cam, tip = "?", False, None, None
    for pos, tam, tipo in registros(dados):
        if tipo == STRNAME:
            cel = dados[pos + 4:pos + tam].rstrip(b"\0").decode("ascii", "replace")
        elif tipo == BOUNDARY:
            no_bnd, cam, tip = True, None, None
        elif tipo == LAYER and no_bnd:
            cam = struct.unpack_from(">h", dados, pos + 4)[0]
        elif tipo == DATATYPE and no_bnd:
            tip = struct.unpack_from(">h", dados, pos + 4)[0]
        elif tipo == XY and no_bnd:
            k = (tam - 4) // 4
            pts = struct.unpack_from(f">{k}i", dados, pos + 4)
            p0, p1 = pts[0:2], pts[-2:]
            if p0 != p1:
                r.append((pos, cel, cam, tip, p0, p1))
        elif tipo == ENDEL:
            no_bnd = False
    return r


def mostra(lista, nome):
    if not lista:
        print(f"{nome}: nenhum BOUNDARY aberto")
        return
    print(f"{nome}: {len(lista)} BOUNDARY aberto(s)")
    for pos, cel, cam, tip, p0, p1 in lista[:20]:
        print(f"   byte {pos}: celula {cel}, camada {cam}/{tip}, "
              f"primeiro ponto {p0}, ultimo {p1}")


def fecha(dados, lista):
    saida, ini = bytearray(), 0
    for pos, *_ , p0, _p1 in lista:
        tam = struct.unpack_from(">H", dados, pos)[0]
        if tam + 8 > 0xFFFF:
            sys.exit(f"byte {pos}: XY ja tem o tamanho maximo, nao cabe mais um ponto")
        saida += dados[ini:pos]
        saida += struct.pack(">HBB", tam + 8, XY, 3) + dados[pos + 4:pos + tam] + struct.pack(">2i", *p0)
        ini = pos + tam
    saida += dados[ini:]
    return bytes(saida)


def main():
    if len(sys.argv) == 3 and sys.argv[1] == "confere":
        lista = abertos(open(sys.argv[2], "rb").read())
        mostra(lista, sys.argv[2])
        sys.exit(1 if lista else 0)
    if len(sys.argv) == 4 and sys.argv[1] == "fecha":
        dados = open(sys.argv[2], "rb").read()
        lista = abertos(dados)
        mostra(lista, sys.argv[2])
        novo = fecha(dados, lista)
        open(sys.argv[3], "wb").write(novo)
        resto = abertos(novo)
        mostra(resto, sys.argv[3])
        sys.exit(1 if resto else 0)
    sys.exit(__doc__)


if __name__ == "__main__":
    main()
