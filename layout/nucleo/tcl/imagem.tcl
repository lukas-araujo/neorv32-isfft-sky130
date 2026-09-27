#=============================================================================
# imagem.tcl -- abre um .odb no OpenROAD, ajusta a visao e salva imagens
#
# Chamado pelo abre_gui do comum.sh (nao rode direto). Variaveis de ambiente:
#   IMG_ODB      banco de dados do layout no fim da etapa
#   IMG_MODO     floorplan | pdn   (uma visao por etapa; novas entram aqui)
#   IMG_DIR      pasta de saida (resultados/<rodada>_layout_nucleo/imagens)
#   IMG_PREFIXO  prefixo dos arquivos (ex.: 02_floorplan)
#
# Depois de salvar, a janela fica ABERTA para explorar (a nao ser com
# SEM_GUI=1). Tudo o que o script faz da para refazer na mao pelo painel
# "Display Control" da esquerda.
#=============================================================================

read_db $::env(IMG_ODB)
set blk   [ord::get_db_block]
set dbu   [$blk getDefUnits]
set modo  $::env(IMG_MODO)
set pre   [file join $::env(IMG_DIR) $::env(IMG_PREFIXO)]
set LARG  2400   ;# largura das imagens em pixels (boa para slide)

proc um { v } { return [expr { double($v) / $::dbu }] }

# Tenta um comando de exibicao; se o nome da opcao mudar entre versoes do
# OpenROAD, avisa e segue (a imagem sai, so sem aquele ajuste).
proc mostra { nome valor } {
    if { [catch { gui::set_display_controls $nome visible $valor } e] } {
        puts "\[imagem\] aviso: '$nome' nao existe nesta versao ($e)"
    }
}

proc salva { arquivo {area {}} } {
    set args [list -width $::LARG]
    if { $area ne {} } { lappend args -area $area }
    if { [catch { save_image {*}$args $arquivo } e] } {
        puts "\[imagem\] ERRO ao salvar $arquivo: $e"
    } else {
        puts "\[imagem\] salvo: [file tail $arquivo]"
    }
}

# Caixa de uma instancia pelo nome do modelo (master), em um
proc caixa_macro { master } {
    foreach i [$::blk getInsts] {
        if { [[$i getMaster] getName] eq $master } {
            set b [$i getBBox]
            return [list [um [$b xMin]] [um [$b yMin]] [um [$b xMax]] [um [$b yMax]]]
        }
    }
    return {}
}

gui::fit

switch $modo {

    floorplan {
        # 1) planta inteira: die, nucleo, 4 macros, linhas de celulas
        mostra "Nets/*" false
        mostra "Rows" true
        mostra "Misc/Instances/Names" true
        gui::fit
        salva ${pre}_planta.png

        # 2) zoom num canto da IMEM: linhas cortadas em volta da macro (halo)
        #    e as celulas de tap/endcap ja inseridas
        set c [caixa_macro sram_8kbyte_1rw_32x2048_8]
        if { $c ne {} } {
            lassign $c x0 y0 x1 y1
            salva ${pre}_zoom_halo.png [list [expr {$x1-40}] [expr {$y0-40}] [expr {$x1+60}] [expr {$y0+30}]]
        }
    }

    pdn {
        # 1) so a malha: met4 (vertical) e met5 (horizontal), anel do nucleo
        mostra "Layers/*" false
        mostra "Layers/met4" true
        mostra "Layers/met5" true
        mostra "Layers/via4" true
        mostra "Nets/*" false
        mostra "Nets/Power" true
        mostra "Nets/Ground" true
        mostra "Instances/StdCells" false
        gui::fit
        salva ${pre}_malha.png

        # 2) zoom na borda da IMEM: tiras de met5 descendo (via4) no anel
        #    met4 da macro -- e assim que a macro recebe alimentacao
        mostra "Layers/*" true
        set c [caixa_macro sram_8kbyte_1rw_32x2048_8]
        if { $c ne {} } {
            lassign $c x0 y0 x1 y1
            salva ${pre}_zoom_anel_macro.png [list [expr {$x1-30}] [expr {$y0+60}] [expr {$x1+50}] [expr {$y0+140}]]
        }
        # 3) canto do die: anel do nucleo (PDN_CORE_RING)
        salva ${pre}_zoom_anel_nucleo.png [list 0 0 120 120]
    }

    default {
        gui::fit
        salva ${pre}.png
    }
}

gui::fit
if { [info exists ::env(QT_QPA_PLATFORM)] && $::env(QT_QPA_PLATFORM) eq "offscreen" } {
    exit
}
puts ""
puts "================================================================"
puts " Imagens salvas. A janela fica aberta para voce explorar."
puts " Painel da esquerda (Display Control): liga/desliga camadas, redes,"
puts " celulas. Feche a janela para voltar ao terminal."
puts "================================================================"
