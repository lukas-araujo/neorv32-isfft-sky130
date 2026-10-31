#=============================================================================
# pdn_chip.tcl -- PDN do CHIP (etapa 11 parte 2; DIARIO_GDSII, 37a sessao)
#
# Lido pelo OpenROAD.GeneratePDN do LibreLane via PDN_CFG (no lugar do
# scripts/openroad/common/pdn_cfg.tcl padrao).
#
# O PROBLEMA: o nucleo (asic_top) e uma macro que ocupa met4 E met5 inteiros
# (o PDN dele, etapa 3). O jeito comum de alimentar macro -- faixa de met5
# do chip passando por cima dos pinos de met4 da macro, com via -- nao serve:
# nao ha camada livre por cima. A ligacao tem de ser na BORDA da macro.
#
# Pinos vccd1/vssd1 do LEF do nucleo (Magic.WriteLEF, etapa 8):
#   anel do nucleo a ~30 um da borda (1,6 um de largura) e faixas met4
#   verticais (passo 153,6) e met5 horizontais (passo 153,18) que terminam
#   no anel. As faixas met5 vao ate x = 1970,5 um; dali ate a borda (2000) o
#   LEF nao tem obstrucao em met5. Por baixo (met4) ha uma obstrucao corrida
#   (y 2,2-29,5), por cima e pela esquerda tambem: so a DIREITA esta livre.
#
# A SOLUCAO (L65):
#   1. grade do chip com o MESMO passo, largura e espacamento das faixas do
#      nucleo (sao os padroes do LibreLane para o sky130) e deslocamento
#      calculado para que cada faixa met5 do chip termine bem em frente a
#      uma faixa met5 do nucleo (macro em (350, 350), orientacao N);
#   2. anel do chip em met4/met5, ligado ao met3 dos pads VCCD/VSSD
#      (-connect_to_pads);
#   3. depois do pdngen: uma PONTE de met5 por faixa, da ponta da faixa do
#      chip ate 1 um para dentro do pino do nucleo. Mesma camada, mesma rede:
#      liga por sobreposicao, sem via.
#=============================================================================

source $::env(SCRIPTS_DIR)/openroad/common/set_global_connections.tcl
set_global_connections

set_voltage_domain -name CORE -power $::env(VDD_NET) -ground $::env(GND_NET)

#-----------------------------------------------------------------------------
# Grade das celulas-padrao do chip (so ha 4 conb_1 + as tap/endcap)
#-----------------------------------------------------------------------------
define_pdn_grid -name chip -starts_with POWER -voltage_domain CORE

# trilhos das linhas (met1), onde ficam as conb_1 e as tap cells
add_pdn_stripe -grid chip -layer met1 -width 0.48 -followpins

# Faixas alinhadas com as do nucleo. Area de nucleo do chip comeca em
# (300,38, 301,92) [grade das linhas]. Centro da 1a faixa vccd do nucleo:
#   met4: 350 + 55,54 + 0,8 = 406,34 -> offset 406,34 - 300,38 = 105,96
#   met5: 350 + 56,65 + 0,8 = 407,45 -> offset 407,45 - 301,92 = 105,53
add_pdn_stripe -grid chip -layer met4 -width 1.6 -spacing 1.7 \
    -pitch 153.6 -offset 105.96 -starts_with POWER -extend_to_core_ring
add_pdn_stripe -grid chip -layer met5 -width 1.6 -spacing 1.7 \
    -pitch 153.18 -offset 105.53 -starts_with POWER -extend_to_core_ring

# As faixas met4 acima so caem a partir de x = 406: as linhas na faixa
# estreita a esquerda da macro (x 300-340) e a direita (2360-2400) ficariam
# sem alimentacao. Um par de faixas met4 em cada uma (offset 20, passo 2059).
add_pdn_stripe -grid chip -layer met4 -width 1.6 -spacing 1.7 \
    -pitch 2059 -offset 20 -starts_with POWER -extend_to_core_ring

# Anel do chip: entre a area de nucleo (x/y ~300) e a borda interna dos
# pads (~200). Ligado ao met3 que os pads de VCCD/VSSD tem do lado de dentro.
add_pdn_ring -grid chip -layers {met4 met5} -widths {5 5} -spacings {1.7 1.7} \
    -core_offset {6 6} -connect_to_pads -connect_to_pad_layers met3

add_pdn_connect -grid chip -layers {met1 met4}
add_pdn_connect -grid chip -layers {met4 met5}

#-----------------------------------------------------------------------------
# A macro do nucleo: grade de instancia sem faixas, so para o pdngen trata-la
# como bloqueio (com afastamento de 5 um) e nao passar faixas por cima.
#-----------------------------------------------------------------------------
define_pdn_grid -macro -instances u_core -name nucleo -halo 5 -starts_with POWER
add_pdn_connect -grid nucleo -layers {met4 met5}

#-----------------------------------------------------------------------------
# pdngen aqui mesmo, para poder pôr as pontes DEPOIS dele
#-----------------------------------------------------------------------------
pdngen

proc pontes_nucleo {inst_name} {
    set block [ord::get_db_block]
    set dbu [[ord::get_db_tech] getDbUnitsPerMicron]
    set inst [$block findInst $inst_name]
    if { $inst == "NULL" } { error "pontes_nucleo: instancia $inst_name nao existe" }
    if { [$inst getOrient] != "R0" } {
        error "pontes_nucleo: $inst_name precisa estar em N (R0), esta em [$inst getOrient]"
    }
    set bb [$inst getBBox]
    set ox [$bb xMin]
    set oy [$bb yMin]
    set master [$inst getMaster]
    set W [$master getWidth]
    set H [$master getHeight]
    set margem [expr {int(40 * $dbu)}]   ;# fora do anel do nucleo (~30 um)
    set dentro [expr {int(1 * $dbu)}]    ;# quanto a ponte entra no pino
    set fora [expr {int(15 * $dbu)}]     ;# quanto passa da borda (> halo 5)
    set total 0
    foreach {pino rede} [list vccd1 $::env(VDD_NET) vssd1 $::env(GND_NET)] {
        set net [$block findNet $rede]
        set sw [odb::dbSWire_create $net "ROUTED"]
        set n 0
        foreach mpin [[$master findMTerm $pino] getMPins] {
            foreach box [$mpin getGeometry] {
                set layer [$box getTechLayer]
                if { [$layer getName] != "met5" } { continue }
                # faixa horizontal que chega perto da borda DIREITA,
                # sem ser o anel de cima/baixo do nucleo
                # (as faixas comecam no anel da esquerda, x = 29,12: nao filtrar xMin)
                if { [$box xMax] < $W - $margem } { continue }
                if { [$box yMin] < $margem || [$box yMax] > $H - $margem } { continue }
                odb::dbSBox_create $sw $layer \
                    [expr {$ox + [$box xMax] - $dentro}] [expr {$oy + [$box yMin]}] \
                    [expr {$ox + $W + $fora}]            [expr {$oy + [$box yMax]}] \
                    "STRIPE"
                incr n
            }
        }
        puts "\[INFO\] pontes_nucleo: $n pontes met5 de $rede ate $inst_name/$pino"
        incr total $n
    }
    if { $total == 0 } { error "pontes_nucleo: nenhuma ponte criada" }
}
pontes_nucleo u_core

# O pdn.tcl do LibreLane chama pdngen depois de ler este arquivo. Ele ja
# rodou acima (e as pontes dependem disso): a segunda chamada vira aviso.
rename pdngen pdngen_ja_rodou
proc pdngen {args} {
    puts "\[INFO\] pdngen ja rodou dentro do PDN_CFG (layout/chip/pdn_chip.tcl, L65)"
}
