#-----------------------------------------------------------------------------
# nucleo.sdc -- restricoes do nucleo (asic_top) no LibreLane
#
# E o base.sdc do proprio LibreLane (librelane/scripts/base.sdc) com UMA
# mudanca: rstn_i como false path, igual ao SDC do Genus
# (vm/backend/synthesis/constraints/neorv32_isfft_soc.sdc). Os valores vem
# do config.json:
#   CLOCK_PERIOD 20 ns (50 MHz), IO_DELAY_CONSTRAINT 30 % (6 ns, como no Genus)
#
# Diferenca consciente para o Genus: incerteza de clock. No Genus eram 2 ns
# (10 %, antes da arvore de clock existir). Aqui o clock e PROPAGADO depois
# do CTS -- o atraso real da arvore entra na conta -- e a incerteza fica no
# padrao do LibreLane (CLOCK_UNCERTAINTY_CONSTRAINT do PDK).
#-----------------------------------------------------------------------------
set clock_port [lindex $::env(CLOCK_PORT) 0]
create_clock [get_ports $clock_port] -name $clock_port -period $::env(CLOCK_PERIOD)
set clocks [get_clocks $clock_port]

set io_delay [expr $::env(CLOCK_PERIOD) * $::env(IO_DELAY_CONSTRAINT) / 100]
set clk_input [get_port $clock_port]
set rst_input [get_port rstn_i]
set entradas {}
foreach p [all_inputs] {
    if { $p != $clk_input && $p != $rst_input } { lappend entradas $p }
}
set_input_delay  $io_delay -clock $clocks $entradas
set_output_delay $io_delay -clock $clocks [all_outputs]

# rstn_i: assincrono no NEORV32 (sincronizado por dentro), sincrono na ISFFT.
# Nao se analisa timing a partir da porta -- como no Genus.
set_false_path -from $rst_input

set_max_fanout $::env(MAX_FANOUT_CONSTRAINT) [current_design]
if { [info exists ::env(MAX_TRANSITION_CONSTRAINT)] } {
    set_max_transition $::env(MAX_TRANSITION_CONSTRAINT) [current_design]
}
if { [info exists ::env(MAX_CAPACITANCE_CONSTRAINT)] } {
    set_max_capacitance $::env(MAX_CAPACITANCE_CONSTRAINT) [current_design]
}

if { ![info exists ::env(SYNTH_CLK_DRIVING_CELL)] } {
    set ::env(SYNTH_CLK_DRIVING_CELL) $::env(SYNTH_DRIVING_CELL)
}
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_DRIVING_CELL) "/"] 1] \
    [concat $entradas $rst_input]
set_driving_cell \
    -lib_cell [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 0] \
    -pin [lindex [split $::env(SYNTH_CLK_DRIVING_CELL) "/"] 1] \
    $clk_input

set_load [expr $::env(OUTPUT_CAP_LOAD) / 1000.0] [all_outputs]
set_clock_uncertainty $::env(CLOCK_UNCERTAINTY_CONSTRAINT) $clocks
set_clock_transition  $::env(CLOCK_TRANSITION_CONSTRAINT) $clocks
set_timing_derate -early [expr 1-[expr $::env(TIME_DERATING_CONSTRAINT) / 100.0]]
set_timing_derate -late  [expr 1+[expr $::env(TIME_DERATING_CONSTRAINT) / 100.0]]

if { [info exists ::env(OPENLANE_SDC_IDEAL_CLOCKS)] && $::env(OPENLANE_SDC_IDEAL_CLOCKS) } {
    unset_propagated_clock [all_clocks]
} else {
    set_propagated_clock [all_clocks]
}
