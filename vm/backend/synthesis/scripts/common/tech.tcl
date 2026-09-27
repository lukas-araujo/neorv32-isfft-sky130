
#-----------------------------------------------------------------------------
# Create Library Domain
#
# UM corner so (TT 1.8 V 25 C). As 4 macros da OpenRAM foram caracterizadas
# so nesse corner (nominal_corner_only = True): criar 'worst'/'best' com as
# celulas padrao nao adiantaria -- nao ha corner da memoria para casar.
#-----------------------------------------------------------------------------
create_library_domain {typ}
set_db lib_search_path "${LIB_DIR} ${LEF_DIR}"
set_db [get_db library_domains typ] .library ${TYP_LIST}
set_db [get_db library_domains typ] .default true

#-----------------------------------------------------------------------------
# Operating conditions
#-----------------------------------------------------------------------------
set_db [get_db library_domains *typ] .operating_conditions ${TYP_LIB_OPERATING_CONDITION}
get_db [get_db library_domains *typ] .operating_conditions

#-----------------------------------------------------------------------------
# Celulas que o Genus NAO deve usar
#
# 1. Scan (sdf*, sedf*, sdlclkp*): nao ha fluxo de DFT. Flip-flop de scan
#    usado como flip-flop comum deixa SCD/SCE para a ferramenta decidir;
#    sem DFT nao ha motivo para arriscar. (Projeto anterior: foi a primeira
#    suspeita do X na simulacao pos-sintese. A causa real era outra -- os
#    modelos das celulas sem FUNCTIONAL; ver run_first.tcl e DIARIO.)
# 2. lpflow_* : celulas de gerenciamento de energia (isolamento, level
#    shifter, KAPWR). Precisam de trilhos de alimentacao especiais no
#    layout; nao temos dominios de energia.
# 3. probe*, macro_sparecell: celulas de teste/reserva, nao sao logica.
#
# As mesmas celulas ficaram de fora na sintese de conferencia com o Yosys
# (nuvem) -- a simulacao de portas que passou foi com esta mesma escolha.
#-----------------------------------------------------------------------------
set_db [get_db lib_cells *__sdf*]              .avoid true
set_db [get_db lib_cells *__sedf*]             .avoid true
set_db [get_db lib_cells *__sdlclkp*]          .avoid true
set_db [get_db lib_cells *__lpflow_*]          .avoid true
set_db [get_db lib_cells *__probe*]            .avoid true
set_db [get_db lib_cells *__macro_sparecell*]  .avoid true

#-----------------------------------------------------------------------------
# 4. Celulas proibidas no LAYOUT (L20 -- DIARIO_GDSII, 10a sessao)
#
# O LibreLane recusa no posicionamento/roteamento as celulas da lista
# drc_exclude.cells do PDK (PNR_EXCLUDED_CELL_FILE): variantes _0 e outras
# com problema de DRC no desenho. Na 1a rodada do layout o netlist do Genus
# tinha 227 instancias delas (and2_0, or2_0, o21ai_0, a2111oi_0,
# a21boi_0). A sintese precisa saber das regras do layout: mesma lista aqui.
# (A outra lista do PDK, no_synth.cells, e so preferencia de sintese do
#  Yosys -- as celulas dela sao validas no layout; nao entra aqui.)
#-----------------------------------------------------------------------------
set f_excl [open ${TECH_DIR}/drc_exclude.cells]
set n_excl 0
foreach l [split [read $f_excl] "\n"] {
    set l [string trim $l]
    if { $l eq "" || [string index $l 0] eq "#" } { continue }
    set cs [get_db lib_cells */$l]
    if { [llength $cs] } { set_db $cs .avoid true ; incr n_excl [llength $cs] }
}
close $f_excl
puts "--> drc_exclude.cells: $n_excl celulas marcadas avoid"

#=============================================================================
# LEF -- DELIBERADAMENTE NAO CARREGADO (licao do projeto anterior)
#=============================================================================
# sky130_fd_sc_hd.lef e LEF de MACROS: sem o technology LEF antes, o Genus
# aborta ("layer 'li1' ... not found", PHYS-10). E sem QRC/cap table do
# sky130 aberto, o modo e wireload de qualquer forma -- LEF nao muda nada
# aqui. Os LEF (celulas + 4 macros) estao em tech/lef/ para o layout.
#
# SE UM DIA FOR PRECISO (ex.: Innovus):
#   set_db lef_library {sky130_fd_sc_hd__nom.tlef sky130_fd_sc_hd.lef
#                       sky130_ef_sc_hd.lef <macros>.lef}
#   (o tech LEF vem do PDK: sky130A/libs.ref/sky130_fd_sc_hd/techlef/)
#=============================================================================

#-----------------------------------------------------------------------------
# Macros SRAM: garantir que NAO estao marcadas avoid/dont_use
#
# Projeto anterior: macro de rodada FRONT-END tinha area 0 no .lib, e o
# Genus marca avoid/dont_use em lib_cell com area 0 -- a instancia ficava
# sem vinculo, sem erro. Agora as 4 vem da rodada BACK-END (area no .lib),
# entao nao deveria acontecer; fica como garantia, custa nada.
#
# Conferir depois da sintese (o run_first.tcl mostra):
#   reports/<design>_gates.rpt  -> as 4 macros, 1 instancia cada
#-----------------------------------------------------------------------------
foreach m ${MACRO_LIST} {
    set_db [get_db lib_cells *${m}*] .avoid    false
    set_db [get_db lib_cells *${m}*] .dont_use false
}

#-----------------------------------------------------------------------------
# Interconnect
#
# 'ple' precisa de LEF + cap table/QRC. Sem eles, wireload. A precisao ja
# e limitada por outro motivo: o .lib das macros usa modelo analitico
# (analytical_delay = True na OpenRAM).
#-----------------------------------------------------------------------------
set_db interconnect_mode wireload
get_db interconnect_mode

#-----------------------------------------------------------------------------
# Report important info
#-----------------------------------------------------------------------------
get_db [get_db library_sets *typ] .libraries
