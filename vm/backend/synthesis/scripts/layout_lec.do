//=============================================================================
// layout_lec.do -- Conformal LEC da ETAPA 9 do layout (DIARIO_GDSII)
//
// "O que o LibreLane desenhou e o mesmo circuito que a sintese entregou?"
// REVISED e sempre o netlist do layout (asic_top_layout.v: o netlist final
// do LibreLane sem as celulas so fisicas). O GOLDEN muda com o bloco:
//   4a  netlist do Genus que ENTROU no layout, achatado (mesmos nomes de
//       flip-flop: o mapeamento sai por nome)
//   4c  o RTL (a cadeia inteira de uma vez: RTL -> Genus -> layout)
//
// O que o layout mexeu e o LEC tem de engolir: ~13 mil buffers de reparo,
// a arvore de relogio (~3 mil buffers), 242 + 383 buffers de hold, celulas
// trocadas por outras mais fortes, celulas de amarracao duplicadas. Nada
// disso muda a funcao; flip-flops e macros sao os mesmos.
//
// Trocados pelo run_first.tcl (sed): @PROJECT_DIR@ @TAG@ @GOLDEN_OPT@
// @GOLDEN_FILES@ @REVISED@. O Conformal nao entende variavel de shell.
//=============================================================================

set log file @PROJECT_DIR@/backend/synthesis/reports/@TAG@_detail.log -replace
set dofile abort on

// Macros: caixa-preta nos dois lados. Como no dofile que o Genus escreve
// (e que passou na sintese): (1) modulo sem definicao vira caixa-preta em
// vez de erro; (2) notranslate com -library; (3) os .lib das macros entram
// na biblioteca. So o "add notranslate module" sem o .lib parava com
// "Module 'sram_...' is referenced but not defined" (DIARIO_GDSII, 33a sessao).
set undefined cell black_box -noascend -both
add notranslate modules -library -both sram_8kbyte_1rw_32x2048_8 sram_4kbyte_1rw_32x1024_8 sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2

read library -liberty -statetable -both \
    @PROJECT_DIR@/tech/lib/sky130_fd_sc_hd__tt_025C_1v80.lib \
    @PROJECT_DIR@/tech/lib/sram_8kbyte_1rw_32x2048_8_TT_1p8V_25C.lib \
    @PROJECT_DIR@/tech/lib/sram_4kbyte_1rw_32x1024_8_TT_1p8V_25C.lib \
    @PROJECT_DIR@/tech/lib/sram_1rw1r_64x256_TT_1p8V_25C.lib \
    @PROJECT_DIR@/tech/lib/sram_1rw1r_64x64_wpr2_TT_1p8V_25C.lib

// GOLDEN
read design -verilog2k -golden -lastmod @GOLDEN_OPT@ @GOLDEN_FILES@
elaborate design -golden -root asic_top

// REVISED: o netlist do layout
read design -verilog2k -revised -lastmod -netlist @REVISED@
elaborate design -revised -root asic_top

// Flip-flops constantes (bits de CSR que nunca mudam) -- so importa no 4c
set flatten model -seq_constant
set analyze option -auto

set system mode lec

report design data     > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_design.rpt
report black box       > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_blackbox.rpt
report unmapped points > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_unmapped.rpt

add compared points -all
compare

// O que conferir:
//   @TAG@_compare.rpt   -> 0 non-equivalent, 0 aborted
//   @TAG@_unmapped.rpt  -> nao mapeados sao suspeitos
//   @TAG@_blackbox.rpt  -> so as 4 macros
report compare data   > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_compare.rpt
report verification   > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_verification.rpt
report statistics     > @PROJECT_DIR@/backend/synthesis/reports/@TAG@_statistics.rpt

exit -force
