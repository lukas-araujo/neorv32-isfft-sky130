#=============================================================================
# diag_congestao.tcl -- refaz o roteamento global do LibreLane FORA do fluxo,
# deixando terminar com congestao, para ver ONDE ela esta
#
# Chamado pelo diag_congestao.sh. Le do _env.tcl do ultimo passo
# OpenROAD.GlobalRouting o .odb de entrada e as opcoes do roteamento, e:
#   - global_route -allow_congestion -congestion_report_file  (lista de
#     regioes congestionadas, formato do DRC Viewer)
#   - mapa de calor "Routing Congestion" salvo em PNG
# Nao grava nada na rodada (nao chama write_views).
#=============================================================================
# So as variaveis de CONFIGURACAO do passo (o _env.tcl nao tem as que o
# LibreLane injeta ao rodar: SCRIPTS_DIR, _SDC_IN, _LIB_CORNER_*...). Por
# isso os scripts do LibreLane nao sao usados: os comandos do
# roteamento global vao aqui direto, iguais aos de
# scripts/openroad/common/{set_routing_layers,set_layer_adjustments,grt}.tcl
source $::env(DIAG_ENV)
read_db $::env(CURRENT_ODB)

set_routing_layers -signal $::env(RT_MIN_LAYER)-$::env(RT_MAX_LAYER) \
                   -clock  $::env(RT_MIN_LAYER)-$::env(RT_MAX_LAYER)

# ajuste global e depois camada a camada (como o LibreLane faz)
set_global_routing_layer_adjustment * $::env(GRT_ADJUSTMENT)
set tech [[ord::get_db] getTech]
set nomes [list]
foreach l [$tech getLayers] {
    if { [$l getRoutingLevel] >= 1 } { lappend nomes [$l getName] }
}
set i 0
foreach a [split $::env(GRT_LAYER_ADJUSTMENTS) " "] {
    set_global_routing_layer_adjustment [lindex $nomes $i] $a
    puts "\[diag\] ajuste da camada [lindex $nomes $i]: $a"
    incr i
}
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
