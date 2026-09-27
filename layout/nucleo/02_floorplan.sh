#!/usr/bin/env bash
#=============================================================================
# 02_floorplan.sh -- ETAPA 2: floorplan
#
#   Continua a rodada atual, do fim da etapa 1:
#     OpenROAD.Floorplan        die 2000 x 1500 um, nucleo, linhas de celulas
#     Odb.SetPowerConnections   quem liga em vccd1/vssd1
#     Odb.ManualMacroPlacement  as 4 macros na posicao/orientacao do config
#     OpenROAD.CutRows          tira as linhas de celula de baixo das macros
#                               (+ halo de 15 um)
#     OpenROAD.TapEndcapInsertion  celulas de tap (poço) e de fim de linha
#
#   Imagens: planta inteira + zoom no halo de uma macro.
#
# Uso:  bash layout/nucleo/02_floorplan.sh
#       SO_GUI=1  bash layout/nucleo/02_floorplan.sh   (so reabre a janela)
#       SEM_GUI=1 bash layout/nucleo/02_floorplan.sh   (so salva as imagens)
#=============================================================================
source "$(dirname "$0")/comum.sh"
confere_ambiente

if [ "${SO_GUI:-0}" != 1 ]; then
  roda_trecho OpenROAD.STAPrePNR OpenROAD.Floorplan OpenROAD.TapEndcapInsertion
  echo ">>> metricas depois do floorplan:"
  guarda_metricas OpenROAD.TapEndcapInsertion 02_floorplan
fi
abre_gui OpenROAD.TapEndcapInsertion floorplan 02_floorplan

echo
echo "Conferir na imagem: as 4 macros dentro do nucleo, sem se tocar; a"
echo "IMEM e a DMEM com os pinos virados para o canal entre elas; in_mem"
echo "embaixo e out_mem em cima, na direita. Linhas de celula cortadas em"
echo "volta das macros."
echo "Proximo: bash layout/nucleo/03_pdn.sh"
