# neorv32_isfft_soc.tcl
# Sintese do chip NEORV32 + ISFFT (4 macros OpenRAM) em sky130.
# Mesma estrutura do neorv32_sram_soc.tcl (fluxo padrao da turma).

puts "  "
puts "=== neorv32_isfft_soc :: sintese sky130 ==="
puts "  "

#-----------------------------------------------------------------------------
# Main Custom Variables Design Dependent
#
# DESIGNS  = nome do projeto (pasta, scripts, relatorios, netlist)
# HDL_NAME = modulo de topo do RTL (asic_top)
#-----------------------------------------------------------------------------
set PROJECT_DIR $env(PROJECT_DIR)
set DESIGNS     $env(DESIGNS)
set HDL_NAME    $env(HDL_NAME)

#-----------------------------------------------------------------------------
# Variaveis usadas no SDC
#
# O chip tem so 4 portas: clk_i, rstn_i, uart0_txd_o, uart0_rxd_i.
# (AXI e SLINK ficam dentro de asic_top.)
#-----------------------------------------------------------------------------
set MAIN_CLOCK_NAME clk_i
set MAIN_RST_NAME   rstn_i

# 50 MHz -- tem que casar com CLOCK_FREQUENCY em neorv32_asic (GHDL)
set period_clk      20.0
set clk_uncertainty 2.0   ;# 10% do periodo, antes do CTS
set clk_latency     1.0
set in_delay        6.0   ;# 30% do periodo
set out_delay       6.0
set out_load        0.05  ;# pF

set slew_min_rise 0.05
set slew_min_fall 0.05
set slew_max_rise 0.50
set slew_max_fall 0.50

#-----------------------------------------------------------------------------
# Bibliotecas
#
# Celulas padrao + as 4 macros da OpenRAM (rodada BACK-END: com area).
# As macros entram como CAIXA-PRETA: o Genus le so o .lib delas.
#-----------------------------------------------------------------------------
set MACRO_LIST {sram_8kbyte_1rw_32x2048_8
                sram_4kbyte_1rw_32x1024_8
                sram_1rw1r_64x256
                sram_1rw1r_64x64_wpr2}

set TYP_LIST {sky130_fd_sc_hd__tt_025C_1v80.lib
              sram_8kbyte_1rw_32x2048_8_TT_1p8V_25C.lib
              sram_4kbyte_1rw_32x1024_8_TT_1p8V_25C.lib
              sram_1rw1r_64x256_TT_1p8V_25C.lib
              sram_1rw1r_64x64_wpr2_TT_1p8V_25C.lib}

set TYP_LIB_OPERATING_CONDITION tt_025C_1v80

#-----------------------------------------------------------------------------
# Load Path / Tech
#-----------------------------------------------------------------------------
source ${PROJECT_DIR}/backend/synthesis/scripts/common/path.tcl
source ${SCRIPT_DIR}/common/tech.tcl

#-----------------------------------------------------------------------------
# Analyze RTL
#
# DIFERENCA para o projeto anterior: tudo e Verilog. O NEORV32 foi
# convertido para UM Verilog pelo GHDL (frontend/neorv32_asic.v, D14):
# sem VHDL, sem biblioteca 'neorv32', sem ordem de analise.
#
# ⚠️ -define SRAM_LIB_VIEW e OBRIGATORIO.
# Sem ele, sram4k_1rw/sram8k_1rw instanciam a view de SIMULACAO das
# macros de 1 porta (33 bits de dado + spare_wen0), que nao casa com o
# .lib (32 bits, sem spare_wen0). As macros 1rw1r nao dependem disto.
#
# -language sv: igual ao projeto anterior. Conferido que nenhum nome do
# RTL e palavra reservada de SystemVerilog.
#-----------------------------------------------------------------------------
set_db init_hdl_search_path "${FRONTEND_DIR} ${ISFFT_RTL_DIR}"

source ${SCRIPT_DIR}/rtl_files.tcl

read_hdl -language sv -define SRAM_LIB_VIEW $RTL_FILES

#-----------------------------------------------------------------------------
# Elaborate
#-----------------------------------------------------------------------------
elaborate ${HDL_NAME}
set_top_module ${HDL_NAME}

#-----------------------------------------------------------------------------
# check_design -unresolved  -- NAO PULE ESTA ETAPA
#
# Modulo nao resolvido vira caixa-preta SILENCIOSAMENTE. Aqui NADA deve
# aparecer: as 4 macros sao celulas do .lib (resolvidas), nao caixas-pretas
# de RTL. Qualquer coisa listada e bug.
#-----------------------------------------------------------------------------
check_design -unresolved ${HDL_NAME} > ${RPT_DIR}/${DESIGNS}_unresolved.rpt
check_design -all        ${HDL_NAME} > ${RPT_DIR}/${DESIGNS}_check_design.rpt
puts "--> conferir ${RPT_DIR}/${DESIGNS}_unresolved.rpt"
check_library

#-----------------------------------------------------------------------------
# Constraints
#-----------------------------------------------------------------------------
read_sdc ${BACKEND_DIR}/synthesis/constraints/${DESIGNS}.sdc

# check_timing: caminho sem restricao, clock nao declarado, entrada sem
# input_delay. SDC ruim faz o timing "fechar" pelo motivo errado.
report timing -lint > ${RPT_DIR}/${DESIGNS}_timing_lint.rpt

#-----------------------------------------------------------------------------
# Pos-elaborate
#
# Hierarquia preservada: a area por bloco (CPU, ISFFT, SLINK...) sai no
# relatorio hierarquico, e os nomes de instancia do netlist ficam iguais
# aos do RTL.
#-----------------------------------------------------------------------------
set_db auto_ungroup none

#-----------------------------------------------------------------------------
# Sintese
#-----------------------------------------------------------------------------
set_db syn_generic_effort medium
syn_generic ${HDL_NAME}

set_db syn_map_effort medium
syn_map ${HDL_NAME}

set_db syn_opt_effort medium
syn_opt

#-----------------------------------------------------------------------------
# Relatorios
#-----------------------------------------------------------------------------
report_design_rules  > ${RPT_DIR}/${DESIGNS}_drc.rpt
report_area          > ${RPT_DIR}/${DESIGNS}_area.rpt
report_timing        > ${RPT_DIR}/${DESIGNS}_timing.rpt
report_gates         > ${RPT_DIR}/${DESIGNS}_gates.rpt
report_qor           > ${RPT_DIR}/${DESIGNS}_qor.rpt
report_power         > ${RPT_DIR}/${DESIGNS}_power.rpt

# Area por bloco: asic_top > u_cpu (NEORV32) / u_isfft (ISFFT) > ...
report_area -depth 4 > ${RPT_DIR}/${DESIGNS}_area_hier.rpt

# Os 10 piores caminhos: mostra se o critico passa pelas macros
report_timing -max_paths 10 > ${RPT_DIR}/${DESIGNS}_timing_top10.rpt

#-----------------------------------------------------------------------------
# Entregaveis
#-----------------------------------------------------------------------------
write_sdf -edge check_edge -setuphold merge_always -nonegchecks \
          -recrem split -version 3.0 -design ${HDL_NAME} \
          > ${DEV_DIR}/${DESIGNS}.sdf
write_hdl ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}.v
write_sdc ${HDL_NAME} > ${DEV_DIR}/${DESIGNS}.sdc

# Dofile de LEC gerado pelo proprio Genus (RTL -> netlist final). Ele sabe
# das otimizacoes sequenciais que a sintese fez. E o primeiro a rodar no
# bloco 3 do run_first.tcl; o dofile escrito a mao fica como alternativa.
write_do_lec -revised_design ${DEV_DIR}/${DESIGNS}.v \
             -logfile ${RPT_DIR}/${DESIGNS}_lec_genus.log \
             > ${DEV_DIR}/${DESIGNS}_lec_genus.do

puts "  "
puts "=== fim. relatorios em ${RPT_DIR} ==="
puts "  "
