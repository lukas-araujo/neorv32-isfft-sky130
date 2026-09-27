#!/usr/bin/env python3
"""
compara_ligacoes.py -- prova que dois netlists de portas tem a MESMA LIGACAO

Uso: python3 compara_ligacoes.py <antes_bits.v> <depois_bits.v>
     (os dois ja achatados e com 'splitnets -ports': 1 bit por fio)

Para cada pino de cada instancia (mesmo nome de instancia nos dois lados),
compara a rede a que ele esta ligado. No lado "antes" os 'assign' dizem
que dois nomes sao o MESMO fio (juntados por union-find). Passa se existe
uma correspondencia 1:1 entre as redes dos dois lados que explica todos
os pinos. Serve para transformacoes que so renomeiam/fundem fios (como o
achatamento do 01_leitura.sh); nao e equivalencia logica geral (isso e o
LEC).

Sai com codigo 0 se IGUAIS, 1 se diferentes.
"""
import re, sys
tok = re.compile(r"\\\S+|[A-Za-z_][\w$]*(?:\[\d+\])?|\d+'[bh][0-9a-fA-FxXzZ]+|[{},()=;.]")
def parse(fn):
    txt = open(fn).read()
    assigns, pins = [], {}
    for m in re.finditer(r"^\s*assign\s+(.*?)\s*=\s*(.*?)\s*;", txt, re.M):
        assigns.append((m.group(1).strip(), m.group(2).strip()))
    for m in re.finditer(r"^\s*(\S+)\s+(\\\S+|\w+)\s*\((.*?)\);", txt, re.M | re.S):
        cell, inst, body = m.groups()
        if cell in ("module", "input", "output", "wire", "assign"): continue
        for pm in re.finditer(r"\.(\w+)\(\s*(.*?)\s*\)(?=\s*,|\s*$)", body, re.S):
            pin, expr = pm.groups()
            expr = expr.strip()
            if expr.startswith("{"):
                bits = [b.strip() for b in expr.strip("{} ").split(",")]
            else:
                bits = [expr] if expr else []
            n = len(bits)
            for i, b in enumerate(bits):
                pins[(inst, pin, n - 1 - i)] = b
    return assigns, pins
def norm(s): return s.strip().rstrip(" ")
ga, gp = parse(sys.argv[1]); ta, tp = parse(sys.argv[2])
print("antes: %d assigns, %d pinos | depois: %d assigns, %d pinos" % (len(ga), len(gp), len(ta), len(tp)))
par = {}
def f(x):
    par.setdefault(x, x)
    while par[x] != x: par[x] = par[par[x]]; x = par[x]
    return x
def bits(e):
    e = e.strip()
    if e.startswith("{"):
        return [x.strip() for x in e.strip("{} ").split(",")]
    return [e]
nconc = 0
for a, b in ga:
    la, lb = bits(a), bits(b)
    assert len(la) == len(lb), (a[:80], b[:80])
    nconc += len(la) > 1
    for x, y in zip(la, lb):
        par[f(norm(x))] = f(norm(y))
print("assigns com concatenacao:", nconc)
chaves = set(gp) ^ set(tp)
print("pinos so num dos lados:", len(chaves), list(chaves)[:5])
m, inv, erros = {}, {}, 0
for k in gp:
    if k not in tp: continue
    g = f(norm(gp[k])); t = norm(tp[k])
    if g.startswith(("1'","0'")) or t.startswith(("1'","0'")):
        if g != t: erros += 1; print("const difere", k, g, t) if erros < 5 else None
        continue
    if m.setdefault(g, t) != t: erros += 1; print("rede gold->2 redes gate", k, g, m[g], t) if erros < 5 else None
    if inv.setdefault(t, g) != g: erros += 1; print("rede gate->2 redes gold", k, t, inv[t], g) if erros < 5 else None
print("redes comparadas:", len(m), "| erros:", erros)
ok = erros == 0 and not chaves
print("RESULTADO:", "IGUAIS (mesma ligacao em todos os pinos)" if ok else "DIFERENTES")
sys.exit(0 if ok else 1)
