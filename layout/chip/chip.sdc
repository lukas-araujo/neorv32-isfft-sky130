#=============================================================================
# chip.sdc -- restricoes do CHIP (nivel 2, etapa 11)
#
# O relogio agora nasce no PINO do chip (clk_pad) e atravessa o pad de
# entrada (sky130_ef_io__gpiov2_pad_wrapped, PAD -> IN, Liberty do PDK)
# ate o nucleo. O nucleo e macro sem Liberty: o timing dele ja foi fechado
# no nivel 1 (etapa 7). Aqui so contam os caminhos de fora: pino -> pad ->
# nucleo e nucleo -> pad -> pino.
#=============================================================================
create_clock -name clk_i -period 20 [get_ports clk_pad]
set_clock_uncertainty 0.25 [get_clocks clk_i]
set_clock_transition 0.15 [get_clocks clk_i]

# UART: mesmos 30 % do periodo do nucleo (nucleo.sdc)
set_input_delay  6 -clock clk_i [get_ports rx_pad]
set_output_delay 6 -clock clk_i [get_ports tx_pad]

# Reset assincrono
set_false_path -from [get_ports rstn_pad]

# Pinos de alimentacao nao sao sinais
set_false_path -through [get_ports {vccd_pad vssd_pad vddio_pad vssio_pad vdda_pad vssa_pad}]
