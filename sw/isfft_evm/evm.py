#!/usr/bin/env python3
"""
evm.py -- validacao numerica da ISFFT no chip (mesmo criterio da Kria)

  python3 evm.py gera   <vetores.h>        gera as 3 matrizes do notebook da Kria
  python3 evm.py avalia <pasta com saida_<m>.hex>

Matrizes, formato e modelo copiados de processamento_otfs.ipynb (Kria):
  - entrada: int16, real/imag intercalados -> na DMEM, palavra i de 32 bits =
    (imag << 16) | real  (little-endian, igual ao buffer da DDR na Kria)
  - saida lida do mesmo jeito e transposta: reshape(8,8).T
  - modelo: ifft nas linhas, fft nas colunas, / 8
  - EVM = sqrt(mean|erro|^2 / mean|ref|^2) * 100
"""
import sys
import numpy as np

NOMES = ["Impulso", "Senoide", "Rampa"]
EVM_KRIA = [3.41, 0.78, 0.60]      # medido na KR260 (DIARIO)


def matrizes():
    m1 = np.zeros((8, 8), dtype=complex)
    m1[3, 3] = 1000 + 0j
    x = np.linspace(0, 2 * np.pi, 8)
    X, _ = np.meshgrid(x, x)
    m2 = (np.sin(X) * 500).astype(complex)
    m3 = (np.arange(64).reshape(8, 8) * 10).astype(complex)
    return [m1, m2, m3]


def para_palavras(m):
    flat = m.flatten()
    re = flat.real.astype(np.int16).view(np.uint16).astype(np.uint32)
    im = flat.imag.astype(np.int16).view(np.uint16).astype(np.uint32)
    return (im << 16) | re


def de_palavras(w):
    w = np.asarray(w, dtype=np.uint32)
    re = (w & 0xFFFF).astype(np.uint16).view(np.int16)
    im = (w >> 16).astype(np.uint16).view(np.int16)
    return (re + 1j * im).reshape(8, 8).T


def modelo(m):
    return np.fft.fft(np.fft.ifft(m, axis=1), axis=0) / 8.0


def gera(saida):
    ms = matrizes()
    with open(saida, "w") as f:
        f.write("// gerado por evm.py -- matrizes do processamento_otfs.ipynb (Kria)\n")
        f.write(f"#define N_MAT {len(ms)}\n")
        f.write(f"static const uint32_t matriz[{len(ms)}][64] = {{\n")
        for m in ms:
            w = para_palavras(m)
            f.write("  {" + ",".join(f"0x{v:08x}" for v in w) + "},\n")
        f.write("};\n")
    print(f"{saida}: {len(ms)} matrizes")


def avalia(pasta):
    ok = True
    for i, m in enumerate(matrizes()):
        try:
            w = [int(l, 16) for l in open(f"{pasta}/saida_{i}.hex") if l.strip()]
        except FileNotFoundError:
            print(f"matriz {i+1}: sem saida_{i}.hex"); ok = False; continue
        if len(w) != 64:
            print(f"matriz {i+1}: {len(w)} palavras (esperado 64)"); ok = False; continue
        hw, ref = de_palavras(w), modelo(m)
        err = np.abs(ref - hw)
        evm = np.sqrt(np.mean(err ** 2) / np.mean(np.abs(ref) ** 2)) * 100
        igual = abs(evm - EVM_KRIA[i]) < 0.005
        ok &= igual
        print(f"matriz {i+1} ({NOMES[i]:8s}): EVM {evm:.4f}%   Kria {EVM_KRIA[i]:.2f}%   "
              f"erro medio {np.mean(err):.2f}   {'= Kria' if igual else 'DIFERENTE da Kria'}")
    print("EVM: PASSOU" if ok else "EVM: FALHOU")
    return ok


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[1] not in ("gera", "avalia"):
        sys.exit(__doc__)
    if sys.argv[1] == "gera":
        gera(sys.argv[2])
    else:
        sys.exit(0 if avalia(sys.argv[2]) else 1)
