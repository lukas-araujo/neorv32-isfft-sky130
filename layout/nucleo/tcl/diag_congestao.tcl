#=============================================================================
# diag_congestao.tcl -- refaz o roteamento global do LibreLane FORA do fluxo,
# deixando terminar com congestao, para ver ONDE ela esta
#
# Chamado pelo diag_congestao.sh. Usa o _env.tcl do ultimo passo
# OpenROAD.GlobalRouting (mesmas camadas, ajustes e .odb de entrada) e:
#   - global_route -allow_congestion -congestion_report_file  (lista de
#     regioes congestionadas, formato do DRC Viewer)
#   - mapa de calor "Routing Congestion" salvo em PNG
# Nao grava nada na rodada (nao chama write_views).
#=============================================================================
source $::env(DIAG_ENV)
source $::env(SCRIPTS_DIR)/openroad/common/io.tcl
read_current_odb
source $::env(SCRIPTS_DIR)/openroad/common/set_routing_layers.tcl
source $::env(SCRIPTS_DIR)/openroad/common/set_layer_adjustments.tcl
set_macro_extension $::env(GRT_MACRO_EXTENSION)

global_route -congestion_iterations $::env(GRT_OVERFLOW_ITERS) -verbose \
    -allow_congestion -congestion_report_file $::env(DIAG_RPT)

set blk [ord::get_db_block]
set dbu [$blk getDefUnits]
set b   [$blk getDieArea]
set area [list [expr {[$b xMin]/$dbu - 20.0}] [expr {[$b yMin]/$dbu - 20.0}] \
               [expr {[$b xMax]/$dbu + 20.0}] [expr {[$b yMax]/$dbu + 20.0}]]
foreach {n v} {"Nets/*" false "Rows" false "Instances/StdCells" false \
               "Heat Maps/Routing Congestion" true} {
    if { [catch { gui::set_display_controls $n visible $v } e] } { puts "\[diag\] aviso: $n ($e)" }
}
if { [catch { save_image -width 2400 -area $area $::env(DIAG_PNG) } e] } {
    puts "\[diag\] ERRO ao salvar imagem: $e"
} else {
    puts "\[diag\] salvo: $::env(DIAG_PNG)"
}
if { [info exists ::env(QT_QPA_PLATFORM)] && $::env(QT_QPA_PLATFORM) eq "offscreen" } { exit }
