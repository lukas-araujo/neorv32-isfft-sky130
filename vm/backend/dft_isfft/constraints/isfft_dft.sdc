#-----------------------------------------------------------------------------
# isfft_dft.sdc -- IP da ISFFT (isfft_axi_v4) com scan, 50 MHz
#
# DIARIO_DFT, T4. Variaveis vem do isfft_dft.tcl (mesmo jeito do SDC do chip).
# O IP nao tem as portas do chip (clk_i/rstn_i/UART): tem aclk, aresetn,
# AXI4-Lite e os dois AXI4-Stream -- e, depois do define_shift_enable e do
# define_scan_chain (que criam as portas ANTES deste arquivo ser lido),
# scan_en, scan_in_<i> e scan_out_<i>.
#
# MODO FUNCIONAL: scan_en = 0 por case analysis. A sintese otimiza o
# caminho de dados de verdade; os caminhos de deslocamento (Q -> SCD do
# vizinho) sao fio curto, sem logica: nao precisam da atencao da sintese.
# (Num chip de verdade o modo de deslocamento ganharia um SDC proprio,
# mais lento -- o hold desses caminhos e assunto do layout.)
#-----------------------------------------------------------------------------

set sdc_version 1.5
current_design ${HDL_NAME}

set_ideal_net [get_nets ${MAIN_CLOCK_NAME}]

create_clock -name ${MAIN_CLOCK_NAME} -period $period_clk [get_ports ${MAIN_CLOCK_NAME}]
set_clock_uncertainty ${clk_uncertainty} [get_clocks ${MAIN_CLOCK_NAME}]
set_clock_latency     ${clk_latency}     [get_clocks ${MAIN_CLOCK_NAME}]

# aresetn e SINCRONO no IP: e um sinal de dado como outro qualquer (entra no
# D dos flip-flops). Fica com o mesmo atraso de entrada das outras portas --
# diferente do chip, onde rstn_i e assincrono no NEORV32 e vira false path.

# Modo funcional (ver cabecalho)
set_case_analysis 0 [get_ports scan_en]

# Entradas e saidas: o IP fica dentro do chip, entre registradores do
# NEORV32 e dos conversores. 30% do periodo de cada lado, como no chip.
set entradas [remove_from_collection [all_inputs] [get_ports ${MAIN_CLOCK_NAME}]]
set_input_delay  -clock [get_clocks ${MAIN_CLOCK_NAME}] ${in_delay}  $entradas
set_output_delay -clock [get_clocks ${MAIN_CLOCK_NAME}] ${out_delay} [all_outputs]

set_load -pin_load ${out_load} [get_ports [all_outputs]]

set_input_transition -rise -min $slew_min_rise $entradas
set_input_transition -fall -min $slew_min_fall $entradas
set_input_transition -rise -max $slew_max_rise $entradas
set_input_transition -fall -max $slew_max_fall $entradas
