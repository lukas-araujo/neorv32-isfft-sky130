#!/usr/bin/env bash
# Descompacta os .gds.gz das macros (o repositorio guarda so os .gz:
# o GDS da macro de 8 kB tem 61 MB, acima do aviso de 50 MB do GitHub).
# Os .gds descompactados ficam fora do git (.gitignore). Idempotente.
cd "$(dirname "$0")"
for f in */*.gds.gz; do
  [ -f "${f%.gz}" ] && [ "${f%.gz}" -nt "$f" ] && continue
  gunzip -kf "$f" && echo "ok: ${f%.gz}"
done
