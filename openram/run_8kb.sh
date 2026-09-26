#!/usr/bin/env bash
#=============================================================================
# run_8kb.sh -- gera a macro de 8 kB em segundo plano (sobrevive ao terminal)
#
# Uso:
#   source ~/Projects/env_openram.sh
#   bash run_8kb.sh
#
# Acompanhar:
#   tail -f ~/Projects/asic/openram/log-8kb-backend.txt
#=============================================================================
DIR="$(cd "$(dirname "$0")" && pwd)"
OPENRAM="$HOME/Projects/OpenRAM"          # raiz do repo (sram_compiler.py)
LOG="$DIR/log-8kb-backend.txt"
mkdir -p "$DIR/out"                       # a OpenRAM usa os.mkdir: nao cria pais

command -v magic >/dev/null || { echo "ERRO: magic fora do PATH -- faltou 'source ~/Projects/env_openram.sh'"; exit 1; }

nohup bash -c "
  echo \"inicio: \$(date)\"
  t0=\$(date +%s)
  python3 -u '$OPENRAM/sram_compiler.py' -v --keeptemp '$DIR/sram_8kbyte_1rw_32x2048_8.py'
  echo \"fim: \$(date)  duracao: \$(( \$(date +%s) - t0 )) s\"
" > "$LOG" 2>&1 &

echo "PID $! -- rodando em segundo plano"
echo "log: $LOG"
echo
echo "Confira em 1 minuto (ponto de parada):"
echo "  grep -m1 'Using bitcell' $LOG      # tem que ser bitcell_1port"
echo "  grep 'Rows:' $LOG"
