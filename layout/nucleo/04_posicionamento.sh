#!/usr/bin/env bash
#=============================================================================
# 04_posicionamento.sh -- ETAPA 4: posicionamento das celulas padrao
#
#   Continua a rodada atual, do fim da etapa 3 (Odb.RemovePDNObstructions):
#     Odb.AddRoutingObstructions   (nenhuma definida por nos)
#     OpenROAD.GlobalPlacementSkipIO  posicionamento global SEM os pinos de
#                                  E/S, so para saber onde a logica fica
#     OpenROAD.IOPlacement         pinos de E/S na borda, perto de quem usa
#     Odb.CustomIOPlacement / Odb.ApplyDEFTemplate  (nada nosso)
#     OpenROAD.GlobalPlacement     posicionamento global de verdade (RePlAce):
#                                  as celulas "se espalham" como carga
#                                  eletrica ate a densidade alvo
#     Odb.WriteVerilogHeader, Checker.PowerGridViolations
#     OpenROAD.STAMidPNR           STA com fio estimado pela distancia
#     OpenROAD.RepairDesignPostGPL resizer: buffers e troca de tamanho para
#                                  slew, capacitancia e fanout maximos
#     Odb.ManualGlobalPlacement    (nada nosso)
#     OpenROAD.DetailedPlacement   encaixa cada celula num sitio da linha,
#                                  sem sobreposicao
#
#   Densidade alvo: PL_TARGET_DENSITY_PCT = 65 no config (L29). Sem ela o
#   LibreLane usa utilizacao + 10, e a utilizacao CONTA AS MACROS (71,2 %):
#   deu ~81 % e o roteamento global congestionou (DIARIO_GDSII, 18a sessao).
#   O log diz o valor usado (GPL-0023).
#
#   Imagens: celulas no chip inteiro + mapa de densidade + zoom no canal
#   IMEM/DMEM (onde chegam os 140 pinos das memorias da CPU).
#
#   Demora mais que as etapas anteriores (60 mil celulas): minutos.
#
# Uso:  bash layout/nucleo/04_posicionamento.sh   (SO_GUI=1 / SEM_GUI=1 como no 02)
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho Odb.RemovePDNObstructions Odb.AddRoutingObstructions OpenROAD.DetailedPlacement
  echo ">>> metricas depois do posicionamento:"
  guarda_metricas OpenROAD.DetailedPlacement 04_posicionamento

  # Resumo das mensagens que interessam, de cada passo
  resumo="$(pasta_resultados)/04_posicionamento.txt"
  : > "$resumo"
  for passo in OpenROAD.GlobalPlacementSkipIO OpenROAD.IOPlacement \
               OpenROAD.GlobalPlacement OpenROAD.RepairDesignPostGPL \
               OpenROAD.DetailedPlacement; do
    st="$(estado_de "$passo")"
    [ -n "$st" ] || continue
    d="$(dirname "$st")"
    {
      echo "== $passo ($(basename "$d"))"
      grep -hE "target density|GPL-100[1-5]|GPL-0056|GPL-0089|RSZ-00(3[4-9]|4[0-9]|5[0-9])|Inserted|Resized|[Dd]isplacement|PPL-00|DPL-|ERROR|WARNING (GPL|DPL|RSZ|PPL)" \
        "$d"/*.log 2>/dev/null | sort | uniq -c | head -30 || true
      echo
    } >> "$resumo"
  done
  echo ">>> resumo dos logs (tambem em ${resumo#$REPO/}):"
  sed 's/^/    /' "$resumo"
fi
abre_gui OpenROAD.DetailedPlacement posicionamento 04_posicionamento

echo
echo "Conferir: celulas em todo o espaco livre, mais densas perto das macros"
echo "e no meio; nenhuma celula em cima de macro ou do halo; o canal"
echo "IMEM/DMEM ocupado (os pinos das memorias puxam a logica para la)."
echo "No resumo: GPL-1005 (congestionamento estimado; ideal <= 1) e nenhum ERROR."
echo "Proximo: bash layout/nucleo/05_cts.sh"
