//=============================================================================
// neorv32_isfft_soc_lec.do -- Conformal LEC escrito a mao (ALTERNATIVA)
//
// O bloco 3 do run_first.tcl roda PRIMEIRO o dofile que o proprio Genus
// escreve (deliverables/neorv32_isfft_soc_lec_genus.do), que conhece as
// otimizacoes sequenciais da sintese. Este aqui e o do projeto anterior,
// adaptado -- util se o do Genus falhar, e didatico.
//
//   LEC       -> "e o mesmo circuito?"   (nao ve reset, X, timing)
//   simulacao -> "esse circuito funciona?"
//
// ⚠️ @PROJECT_DIR@ e trocado pelo caminho real pelo run_first.tcl (sed).
// O Conformal NAO entende $env(...) nem variavel de shell (licao do
// projeto anterior) -- por isso o arquivo final tem caminho absoluto.
//=============================================================================

set log file @PROJECT_DIR@/backend/synthesis/reports/lec_detail.log -replace
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

//-----------------------------------------------------------------------------
// GOLDEN: o RTL, lido como na sintese (sem defines desde a rodada para o
// layout: .lib das macros de 1 porta com 33 bits -- DIARIO_GDSII, L1)
//-----------------------------------------------------------------------------
read design -verilog2k -golden -lastmod -noelab \
    @PROJECT_DIR@/frontend/*.v \
    @PROJECT_DIR@/frontend/isfft/*.v

elaborate design -golden -root asic_top

//-----------------------------------------------------------------------------
// REVISED: o netlist
//-----------------------------------------------------------------------------
read design -verilog2k -revised -lastmod -noelab -netlist \
    @PROJECT_DIR@/backend/synthesis/deliverables/neorv32_isfft_soc.v

elaborate design -revised -root asic_top

//-----------------------------------------------------------------------------
// A sintese remove flip-flops constantes (bits de CSR que nunca mudam,
// etc.). Sem isto eles viram pontos nao mapeados e comparacoes falsas.
//-----------------------------------------------------------------------------
set flatten model -seq_constant
set analyze option -auto

//-----------------------------------------------------------------------------
// Comparacao
//-----------------------------------------------------------------------------
set system mode lec

report design data     > @PROJECT_DIR@/backend/synthesis/reports/lec_design.rpt
report black box       > @PROJECT_DIR@/backend/synthesis/reports/lec_blackbox.rpt
report unmapped points > @PROJECT_DIR@/backend/synthesis/reports/lec_unmapped.rpt

add compared points -all
compare

//-----------------------------------------------------------------------------
// O que conferir, em ordem:
//   1. lec_compare.rpt  -> 0 non-equivalent
//   2. lec_unmapped.rpt -> nao mapeados sao suspeitos
//   3. lec_blackbox.rpt -> so as 4 macros
//-----------------------------------------------------------------------------
report compare data   > @PROJECT_DIR@/backend/synthesis/reports/lec_compare.rpt
report verification   > @PROJECT_DIR@/backend/synthesis/reports/lec_verification.rpt
report statistics     > @PROJECT_DIR@/backend/synthesis/reports/lec_statistics.rpt

exit -force
