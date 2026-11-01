# isfft_dft.tcl -- sintese COM DFT (scan) do IP da ISFFT (isfft_axi_v4), sky130
#
# DIARIO_DFT (frente T). Roda pelo bloco 1 do run_first_dft.tcl.
# Mesma estrutura do neorv32_isfft_soc.tcl (sintese do chip); o que muda:
#   - topo = isfft_axi_v4 (so o IP; as 2 macros 1rw1r ficam caixa-preta)
#   - celulas de scan LIBERADAS (o tech.tcl do chip as evita)
#   - sinais de teste, regras de DFT, cadeias, arquivos para o Modus
#
# Sessao 1 (T1-T8): scan completo, 16 cadeias, SEM test_mode e SEM shadow
# logic nas macros. E a base: o ATPG (bloco 3) mede quanto se perde em
# volta das macros, e so entao se decide o que inserir.

puts "  "
puts "=== isfft_dft :: sintese com scan do IP da ISFFT ==="
puts "  "

set PROJECT_DIR $env(PROJECT_DIR)
set DESIGNS     $env(DESIGNS)
set HDL_NAME    $env(HDL_NAME)
set NCADEIAS    $env(NCADEIAS)

#-----------------------------------------------------------------------------
# Variaveis do SDC (mesmos numeros do chip: 50 MHz)
#-----------------------------------------------------------------------------
set MAIN_CLOCK_NAME aclk
set period_clk      20.0
set clk_uncertainty 2.0
set clk_latency     1.0
set in_delay        6.0
set out_delay       6.0
set out_load        0.05
set slew_min_rise 0.05
set slew_min_fall 0.05
set slew_max_rise 0.50
set slew_max_fall 0.50

#-----------------------------------------------------------------------------
# Bibliotecas: celulas + as 2 macros da ISFFT (o IP nao tem IMEM/DMEM)
#-----------------------------------------------------------------------------
set MACRO_LIST {sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2}
set TYP_LIST {sky130_fd_sc_hd__tt_025C_1v80.lib
              sram_1rw1r_64x256_TT_1p8V_25C.lib
              sram_1rw1r_64x64_wpr2_TT_1p8V_25C.lib}
set TYP_LIB_OPERATING_CONDITION tt_025C_1v80

#-----------------------------------------------------------------------------
# Caminhos e tecnologia
#
# path.tcl e tech.tcl sao da sintese do chip (backend/synthesis/, outra
# frente): aqui so LIDOS, nunca editados. O path.tcl aponta RPT_DIR/DEV_DIR
# para a sintese do chip -- redefinidos logo abaixo para a pasta da DFT.
#-----------------------------------------------------------------------------
source ${PROJECT_DIR}/backend/synthesis/scripts/common/path.tcl
source ${PROJECT_DIR}/backend/synthesis/scripts/common/tech.tcl

set DFT_DIR   ${PROJECT_DIR}/backend/dft_isfft
set RPT_DIR   ${DFT_DIR}/reports
set DEV_DIR   ${DFT_DIR}/deliverables
set MODUS_DIR ${DFT_DIR}/modus_work

#-----------------------------------------------------------------------------
# T2 -- A UNICA diferenca de tecnologia em relacao ao chip: scan liberado
#
# O tech.tcl do chip poe 'avoid' em sdf*/sedf* porque la nao ha DFT
# (flip-flop de scan usado como comum deixaria SCD/SCE soltos). Aqui as
# celulas de scan sao o objetivo. O sky130 tem 24, todas com 'test_cell'
# no .lib (e por esse grupo que o Genus reconhece SCD/SCE/Q).
# Continuam evitadas: sdlclkp (nao ha clock gating), lpflow, probe,
# sparecell e as celulas proibidas no layout (drc_exclude, nenhuma de scan).
#-----------------------------------------------------------------------------
set_db [get_db lib_cells *__sdf*]  .avoid false
set_db [get_db lib_cells *__sedf*] .avoid false
puts "--> celulas de scan liberadas: [llength [get_db lib_cells *__sdf*]] sdf* + [llength [get_db lib_cells *__sedf*]] sedf*"

#-----------------------------------------------------------------------------
# RTL: o mesmo que o Genus sintetizou no chip e que o UVM verificou
# (frontend/isfft_axi_v4.v + frontend/isfft/*.v)
#-----------------------------------------------------------------------------
set RTL_FILES [concat ${FRONTEND_DIR}/isfft_axi_v4.v [lsort [glob ${ISFFT_RTL_DIR}/*.v]]]
puts "--> RTL: [llength $RTL_FILES] arquivos"
set_db init_hdl_search_path "${FRONTEND_DIR} ${ISFFT_RTL_DIR}"
read_hdl -language sv $RTL_FILES

elaborate ${HDL_NAME}
set_top_module ${HDL_NAME}

check_design -unresolved ${HDL_NAME} > ${RPT_DIR}/${DESIGNS}_unresolved.rpt
check_design -all        ${HDL_NAME} > ${RPT_DIR}/${DESIGNS}_check_design.rpt

#=============================================================================
# DFT -- configuracao (antes do SDC: as portas de teste tem de existir)
#=============================================================================

# T1 -- scan com mux na entrada (muxed scan): a unica que o sky130 tem
set_db dft_scan_style muxed_scan
set_db dft_prefix     DFT_

# Shift enable: porta nova, ativa em 1. Em deslocamento (scan_en = 1) cada
# flip-flop pega o SCD (o Q do vizinho); em captura (scan_en = 0), o D.
define_shift_enable -name scan_en -active high -create_port scan_en

# Relogio de teste = o proprio aclk (o IP tem um relogio so). -period em ps.
define_test_clock -name aclk -period 20000 aclk

# T3 -- SEM test_mode nesta rodada. O que costuma exigi-lo nao existe aqui:
#   - reset assincrono: NENHUM no IP (66 blocos always, todos so com
#     posedge do relogio; aresetn e sincrono, o core_rst e logica comum);
#   - clock gating / relogio gerado: nenhum;
#   - latch: nenhum.
# Reset sincrono e so mais uma entrada do D: o ATPG o controla pelas
# cadeias como qualquer dado. (FE 15a sessao previa precisar; o RTL diz
# que nao.)

#-----------------------------------------------------------------------------
# Regras de DFT ANTES da sintese: quais flip-flops podem virar scan.
# Esperado: 0 violacoes. Flip-flop reprovado aqui fica fora das cadeias.
#-----------------------------------------------------------------------------
check_dft_rules > ${RPT_DIR}/${DESIGNS}_dft_rules_pre.rpt
puts "--> conferir ${RPT_DIR}/${DESIGNS}_dft_rules_pre.rpt (esperado: 0 violacoes)"

#-----------------------------------------------------------------------------
# Restricoes (modo funcional: scan_en = 0 por case analysis)
#-----------------------------------------------------------------------------
read_sdc ${DFT_DIR}/constraints/${DESIGNS}.sdc
report timing -lint > ${RPT_DIR}/${DESIGNS}_timing_lint.rpt

set_db auto_ungroup none

#-----------------------------------------------------------------------------
# Sintese. Com dft_scan_style definido e as regras passando, o syn_map ja
# mapeia os flip-flops direto nas celulas de scan ("map to scan"):
# dfxtp -> sdfxtp; edfxtp -> sedfxtp (ou sdfxtp + mux, a criterio do Genus).
#-----------------------------------------------------------------------------
set_db syn_generic_effort medium
syn_generic ${HDL_NAME}
set_db syn_map_effort medium
syn_map ${HDL_NAME}

# Quantos flip-flops viraram scan (antes de costurar)
report_scan_registers > ${RPT_DIR}/${DESIGNS}_scan_registers_premap.rpt

#=============================================================================
# T5 -- Cadeias: 16, com portas scan_in_<i> / scan_out_<i>
#
# 12.559 flip-flops (contagem do Yosys, sim/run_dft_aberto.sh) / 16 ~ 785
# por cadeia. Por que 16: cada padrao custa ~L ciclos de deslocamento; com 1
# cadeia seriam 12.559 ciclos por padrao, com 16 sao ~785. No IP as portas
# nao custam nada (sao fios dentro do chip); no CHIP, que tem 4 pinos, 32
# portas de teste nao caberiam -- e o motivo da compressao (sessao futura).
# Um relogio, uma borda: sem lockup latch.
#=============================================================================
for {set i 0} {$i < $NCADEIAS} {incr i} {
    define_scan_chain -name cadeia_$i -sdi scan_in_$i -sdo scan_out_$i \
                      -shift_enable scan_en -create_ports
}
connect_scan_chains ${HDL_NAME}

syn_opt

#-----------------------------------------------------------------------------
# Celulas de amarracao (igual ao chip, L2 do DIARIO_GDSII): web0 = 0 das
# macros. O IP nao vai para o layout, mas o netlist fica no mesmo padrao.
#-----------------------------------------------------------------------------
if {[catch {add_tieoffs -high sky130_fd_sc_hd__conb_1 -low sky130_fd_sc_hd__conb_1 \
                       -max_fanout 1 -all -verbose ${HDL_NAME}} msg]} {
    puts "!!! add_tieoffs FALHOU: $msg"
}

#-----------------------------------------------------------------------------
# Relatorios
#-----------------------------------------------------------------------------
check_dft_rules        > ${RPT_DIR}/${DESIGNS}_dft_rules_pos.rpt
report_scan_setup      > ${RPT_DIR}/${DESIGNS}_scan_setup.rpt
report_scan_chains     > ${RPT_DIR}/${DESIGNS}_scan_chains.rpt
report_scan_registers  > ${RPT_DIR}/${DESIGNS}_scan_registers.rpt

report_design_rules  > ${RPT_DIR}/${DESIGNS}_drc.rpt
report_area          > ${RPT_DIR}/${DESIGNS}_area.rpt
report_area -depth 3 > ${RPT_DIR}/${DESIGNS}_area_hier.rpt
report_timing        > ${RPT_DIR}/${DESIGNS}_timing.rpt
report_gates         > ${RPT_DIR}/${DESIGNS}_gates.rpt
report_qor           > ${RPT_DIR}/${DESIGNS}_qor.rpt

#-----------------------------------------------------------------------------
# Entregaveis
#-----------------------------------------------------------------------------
write_hdl     ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}.v
write_sdc     ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}.sdc
write_scandef ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}.scandef

# LEC: RTL (sem scan) x netlist (com scan). O dofile do Genus sabe dos
# sinais de teste e prende scan_en = 0 no revisado -- conferir no .do.
write_do_lec -revised_design ${DEV_DIR}/${DESIGNS}.v \
             -logfile ${RPT_DIR}/${DESIGNS}_lec.log \
             > ${DEV_DIR}/${DESIGNS}_lec.do

#-----------------------------------------------------------------------------
# T7 -- Arquivos para o ATPG no Modus (bloco 3)
#
# Biblioteca = sky130_fd_sc_hd.v JA pre-processado com FUNCTIONAL (o Modus
# le a celula como modelo estrutural; o modelo comportamental depende de
# 'specify' que o arquivo nao tem) + as macros como caixa-preta.
# Gerado em sim/run_dft_aberto.sh; o run_first_dft.tcl descompacta.
#-----------------------------------------------------------------------------
set ATPG_LIB [list ${DFT_DIR}/modus/sky130_fd_sc_hd_atpg.v ${DFT_DIR}/modus/macros_caixa_preta.v]
if {[catch {write_dft_atpg -library $ATPG_LIB -directory ${MODUS_DIR} ${HDL_NAME}} msg]} {
    puts "  "
    puts "!!! write_dft_atpg FALHOU: $msg"
    puts "!!! Anote a mensagem no DIARIO_DFT. O netlist e o scandef ja estao em ${DEV_DIR}."
    puts "  "
}

#-----------------------------------------------------------------------------
# Copia ACHATADA do netlist, so para a simulacao do bloco 2b (regressao da
# Kria com scan_en = 0). Motivo: o testbench compila tambem o wrapper da
# etapa 1 (referencia), que usa o nucleo RTL -- top_isfft, fft_1d_top...;
# o netlist hierarquico tem modulos com os mesmos nomes e o Xcelium
# recusaria a dupla definicao. Achatado, sobra um modulo so: isfft_axi_v4.
# Fica por ULTIMO: tudo acima (relatorios, LEC, Modus) usa o hierarquico.
#-----------------------------------------------------------------------------
if {[catch {ungroup -all -flatten -force} msg]} {
    puts "!!! ungroup FALHOU: $msg -- sem netlist achatado; o bloco 2b nao roda"
} else {
    write_hdl ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}_flat.v
}

puts "  "
puts "=== fim. relatorios em ${RPT_DIR}, Modus em ${MODUS_DIR} ==="
puts "  "
