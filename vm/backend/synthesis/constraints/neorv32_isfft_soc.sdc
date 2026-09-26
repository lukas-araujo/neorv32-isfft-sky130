#-----------------------------------------------------------------------------
# neorv32_isfft_soc.sdc
#
# Mesmo sequential.sdc da turma, mesmas variaveis vindas do .tcl.
# O chip tem 4 portas: clk_i, rstn_i, uart0_txd_o, uart0_rxd_i.
#
# ⚠️ SOBRE A QUALIDADE DESTE TIMING
# O .lib das 4 macros vem do modelo ANALITICO da OpenRAM (ignora o slew
# de entrada). A sintese fecha e da numeros, mas o caminho que passa por
# macro nao e conclusao de timing. STA com parasitas so depois do layout
# (D23, "se der tempo").
#-----------------------------------------------------------------------------

set sdc_version 1.5
current_design ${HDL_NAME}

#################################################################################
## IDEAL NETS
#################################################################################
set_ideal_net [get_nets ${MAIN_CLOCK_NAME}]
set_ideal_net [get_nets ${MAIN_RST_NAME}]

#################################################################################
## CLOCK
#################################################################################
create_clock -name ${MAIN_CLOCK_NAME} -period $period_clk \
             [get_ports ${MAIN_CLOCK_NAME}]
set_clock_uncertainty ${clk_uncertainty} [get_clocks ${MAIN_CLOCK_NAME}]
set_clock_latency ${clk_latency} [get_clocks ${MAIN_CLOCK_NAME}]

#################################################################################
## RESET
##
## rstn_i e assincrono no NEORV32 (que o sincroniza por dentro) e entra
## como reset sincrono na ISFFT (aresetn). Nao se analisa timing a partir
## da porta: e false path, como no projeto anterior.
#################################################################################
set_false_path -from [get_ports ${MAIN_RST_NAME}]

#################################################################################
## INPUT PINS  (so uart0_rxd_i; o NEORV32 sincroniza a entrada serial)
#################################################################################
set entradas [remove_from_collection [all_inputs] \
              [get_ports [list ${MAIN_CLOCK_NAME} ${MAIN_RST_NAME}]]]

set_input_delay -clock [get_clocks ${MAIN_CLOCK_NAME}] ${in_delay} $entradas

#################################################################################
## OUTPUT PINS  (so uart0_txd_o)
#################################################################################
set_output_delay -clock [get_clocks ${MAIN_CLOCK_NAME}] ${out_delay} [all_outputs]

#################################################################################
# DEFAULT OUTPUT PIN LOAD
#################################################################################
set_load -pin_load ${out_load} [get_ports [all_outputs]]

#################################################################################
## DEFAULT DRIVER
#################################################################################
set_input_transition -rise -min $slew_min_rise $entradas
set_input_transition -fall -min $slew_min_fall $entradas
set_input_transition -rise -max $slew_max_rise $entradas
set_input_transition -fall -max $slew_max_fall $entradas
