// pinos_alimentacao_pads.v -- liga USE_POWER_PINS SO para os pads e o chip_top
//
// A biblioteca de celulas (sky130_fd_sc_hd.v) usa a MESMA macro para
// ganhar os pinos VPWR/VGND/VPB/VNB. Com -DUSE_POWER_PINS na linha de
// comando, todas as celulas (as do nucleo e as conb_1 do chip_top) ficam
// com esses pinos soltos e as saidas viram X (DIARIO_GDSII, 35a sessao).
// Um `define vale da posicao em diante, atravessando arquivos: este
// arquivo entra na lista DEPOIS das celulas, do nucleo e dos modelos das
// macros e ANTES dos modelos dos pads e do chip_top (os ultimos da lista),
// do mesmo jeito que o restore_nettype.v.
`define USE_POWER_PINS
// O nucleo e um netlist SEM pinos de alimentacao (o do layout, etapa 9):
// o chip_top so liga vccd1/vssd1 do u_core quando isto NAO esta definido
// (no LibreLane, etapa 11).
`define NUCLEO_SEM_ALIMENTACAO
