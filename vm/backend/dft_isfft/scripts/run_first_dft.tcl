# run_first_dft.tcl -- na verdade um script SHELL, como os outros run_first.
# Uso:  source run_first_dft.tcl     (a partir do bash)
#
# Frente de DFT: sintese COM scan do IP da ISFFT (isfft_axi_v4) e ATPG.
# Diario: DIARIO_DFT.md (decisoes Tn). NAO mexe na sintese do chip
# (backend/synthesis/, run_first.tcl): so LE de la o path.tcl e o tech.tcl.
#
# Blocos (descomente UM por vez, no fim do arquivo):
#   1) Sintese com scan -- Genus        -- JA DESCOMENTADO
#   2a) Equivalencia RTL x netlist com scan -- Conformal
#   2b) Regressao da Kria no netlist com scan (scan_en = 0) -- Xcelium
#   3) ATPG (falhas stuck-at) -- Modus
#   4) Simulacao dos padroes do ATPG -- Xcelium (script escrito pelo Genus)
#   5) MODO DE TESTE "na mao" -- Xcelium (sem Modus: carga, captura, descarga,
#      falha injetada; ideia do Prof. Gilmar). Precisa do tb/mapa_cadeias.vh,
#      gerado no notebook/nuvem a partir do netlist do Genus (traz_dft.sh +
#      sim/run_dft_modo_teste.sh)
#
# ⚠️ Lido com 'source': nao ponha 'exit' aqui (fecharia o terminal).

export DESIGNS="isfft_dft"
export HDL_NAME="isfft_axi_v4"
export NCADEIAS=16
export USER=aluno12
export PROJECT_DIR=/prj/ci/workarea/${USER}/projetos/neorv32_isfft_soc
export BACKEND_DIR=${PROJECT_DIR}/backend
export TECH_DIR=${PROJECT_DIR}/tech

# PATH completo da VM (CLAUDE.md), com UMA diferenca: o Modus e o 25.1
# (MODUS251), nao o 26.1. A licenca do servidor (Modus_common_ui) e v25.1; o
# 26.1 da TDA-011 (DIARIO_DFT, 2a sessao). O admin instalou o 25.1 em 03/11
# (T15).
export PATH=/tools/cadence/QUANTUS261/bin:/tools/cadence/QUANTUS261/tools/bin:/tools/cadence/PEGASUS261/bin:/tools/cadence/PEGASUS261/tools/bin:/tools/cadence/SSV261/bin:/tools/cadence/SSV261/tools/bin:/tools/cadence/XCELIUM2603/tools/bin/64bit:/tools/cadence/XCELIUM2603/tools/bin:/tools/cadence/MODUS251/bin:/tools/cadence/MODUS251/tools/bin:/tools/cadence/CONFRML261/bin:/tools/cadence/CONFRML261/tools/bin:/tools/cadence/DDI221/bin:/tools/cadence/DDI221/tools/bin:/tools/cadence/PVS251/bin:/tools/cadence/PVS251/tools/bin:/tools/cadence/VMANAGER2603/bin:/tools/bin:/tools/cadence/SPECTRE251/bin:/tools/cadence/SPECTRE251/tools/bin:/tools/cadence/IC618/bin:/tools/cadence/IC618/tools/bin:/tools/cadence/IC618/tools/dfII/bin:/pdk/TSMC/CLN12FFC+/TSMCHOME/sram/Compiler/MC2/MC2_2013.12.00.g/bin/Linux-64:/home/aluno12/.local/bin:/home/aluno12/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

export DFT_DIR=${BACKEND_DIR}/dft_isfft
export SCRIPTS=${DFT_DIR}/scripts
export RPT_DIR=${DFT_DIR}/reports
export DEV_DIR=${DFT_DIR}/deliverables
export MODUS_DIR=${DFT_DIR}/modus_work
export SIM_DIR=${DFT_DIR}/sim_kria

mkdir -p ${DFT_DIR}/work ${RPT_DIR} ${DEV_DIR} ${MODUS_DIR} ${SIM_DIR}

# Biblioteca do Modus: vem compactada (gerada por sim/run_dft_aberto.sh)
gunzip -kf ${DFT_DIR}/modus/sky130_fd_sc_hd_atpg.v.gz

#=============================================================================
# 1) SINTESE COM SCAN -- GENUS  (~5 min)
#
# Termina no prompt do Genus: confira o que quiser e digite 'exit'. Depois,
# a conferencia abaixo roda sozinha.
#=============================================================================

cd ${DFT_DIR}/work
genus -abort_on_error -lic_startup Genus_Synthesis \
      -lic_startup_options Genus_Physical_Opt -log genus -overwrite \
      -files ${SCRIPTS}/${DESIGNS}.tcl

echo
echo "=== Conferencia da sintese com scan ==="
echo "--- modulos nao resolvidos (esperado: nenhum) ---"
grep -iv "^ *$\|^#\|Generated\|Genus\|Version\|Date" ${RPT_DIR}/${DESIGNS}_unresolved.rpt | head -10
echo "--- regras de DFT antes da sintese (esperado: 0 violacoes) ---"
grep -iE "violation|Total" ${RPT_DIR}/${DESIGNS}_dft_rules_pre.rpt | head -10
echo "--- cadeias (esperado: 16, ~785 flip-flops cada) ---"
grep -iE "chain|length|bits" ${RPT_DIR}/${DESIGNS}_scan_chains.rpt | head -40
echo "--- flip-flops que NAO viraram scan (esperado: 0) ---"
grep -iE "not|fail|non.scan|total" ${RPT_DIR}/${DESIGNS}_scan_registers.rpt | head -10
echo "--- celulas de scan no netlist ---"
grep -oE "sky130_fd_sc_hd__s(e)?df\w+" ${DEV_DIR}/${DESIGNS}.v | sort | uniq -c
# (o Genus pode trocar edfxtp por sdfxtp + mux em vez de sedfxtp: 2a sessao)
echo "--- flip-flops comuns no netlist (esperado: 0) ---"
grep -cE "sky130_fd_sc_hd__(e)?df(x|r|s|b)\w+ " ${DEV_DIR}/${DESIGNS}.v
echo "--- portas de teste (esperado: 32 = 16 scan_in + 16 scan_out) ---"
grep -m1 -A40 "^module isfft_axi_v4" ${DEV_DIR}/${DESIGNS}.v | grep -oE "scan_(in|out)_[0-9]+" | sort -u | wc -l
echo "--- area e slack ---"
grep -iE "^ *(Total|Cell) Area|Leaf Instance|Sequential" ${RPT_DIR}/${DESIGNS}_qor.rpt | head -6
grep -m3 -i "slack" ${RPT_DIR}/${DESIGNS}_timing.rpt
echo "--- arquivos para o Modus ---"
ls -la ${MODUS_DIR}

#=============================================================================
# 2a) EQUIVALENCIA -- CONFORMAL LEC  (RTL sem scan x netlist com scan)
#
# O dofile e o do Genus (write_do_lec). Com scan_en = 0 o netlist tem de
# ser o RTL: o mux de scan vira fio. Conferir: 0 non-equivalent; as 2
# macros como caixa-preta; scan_en preso em 0 no revisado (procure
# 'add pin constraints' no .do).
#=============================================================================

#cd ${DFT_DIR}/work
#grep -n -i "constraint\|scan_en" ${DEV_DIR}/${DESIGNS}_lec.do
#lec -xl -nogui -dofile ${DEV_DIR}/${DESIGNS}_lec.do \
#    2>&1 | tee ${RPT_DIR}/${DESIGNS}_lec_run.log
#grep -B2 -A12 "Compared points" ${RPT_DIR}/${DESIGNS}_lec_run.log | tail -16

#=============================================================================
# 2b) REGRESSAO DA KRIA NO NETLIST COM SCAN -- XCELIUM  (scan_en = 0)
#
# O mesmo tb da Kria (40 matrizes, parada longa, pacote truncado, contra o
# wrapper da etapa 1), so que no netlist achatado do Genus com as portas de
# teste em 0. Mesmos defines da simulacao de portas do chip (FUNCTIONAL,
# UNIT_DELAY=#1; ver run_first.tcl da sintese).
# Esperado: "PASSOU: 40 matrizes identicas a referencia ..."
#=============================================================================

#cd ${SIM_DIR}
#xrun -64bit -access +rwc -timescale 1ns/1ps \
#  -define FUNCTIONAL -define 'UNIT_DELAY=#1' \
#  ${TECH_DIR}/verilog/primitives.v \
#  ${TECH_DIR}/verilog/sky130_fd_sc_hd.v \
#  ${BACKEND_DIR}/synthesis/scripts/restore_nettype.v \
#  ${DEV_DIR}/${DESIGNS}_flat.v \
#  ${TECH_DIR}/verilog/sram_1rw1r_64x64_wpr2.v \
#  ${TECH_DIR}/verilog/sram_1rw1r_64x256.v \
#  ${PROJECT_DIR}/frontend/isfft/*.v \
#  ${PROJECT_DIR}/verification/uvm_isfft/ref/isfft_axi_wrapper.v \
#  ${DFT_DIR}/tb/tb_isfft_dft.v \
#  -top tb_isfft_dft 2>&1 | tee ${SIM_DIR}/xrun_kria_scan.log
#grep -E "^(Fase|PASSOU|FALHOU|ERRO)" ${SIM_DIR}/xrun_kria_scan.log

#=============================================================================
# 3) ATPG -- MODUS  (falhas stuck-at; padroes de scan)
#
# O Genus escreveu em modus_work/ o script do Modus (write_dft_atpg):
# build_model (netlist + biblioteca), build_testmode (as 16 cadeias),
# verify_test_structures (as cadeias deslocam?), build_faultmodel,
# create_scanchain_tests, create_logic_tests, write_vectors.
# Os relatorios de cobertura saem no log; o testresults/ fica no
# modus_work (o sim/traz_vm.sh traz o log).
#
# ⚠️ O nome do script que o Genus escreve: confira com 'ls ${MODUS_DIR}'
#    (esperado runmodus.atpg.tcl). Se for outro, troque abaixo.
#=============================================================================

#cd ${MODUS_DIR}
#ls -la
#modus -file runmodus.atpg.tcl 2>&1 | tee ${RPT_DIR}/${DESIGNS}_modus.log
#echo "--- cobertura (procure 'Test Coverage' / 'Fault Coverage') ---"
#grep -iE "coverage|faults|patterns|tests" ${RPT_DIR}/${DESIGNS}_modus.log | tail -30

#=============================================================================
# 4) SIMULACAO DOS PADROES DO ATPG -- XCELIUM  (depois do bloco 3)
#
# O write_dft_atpg do Genus escreveu tambem o run_fullscan_sim (2a sessao do
# DIARIO_DFT): simula no netlist os vetores que o Modus gravou
# (write_vectors), com deslocamento e captura de verdade. E a prova de que
# os padroes que iriam para o testador batem com o circuito.
# Esperado: nenhuma "miscompare" no fim do log.
#=============================================================================

#cd ${MODUS_DIR}
#./run_fullscan_sim 2>&1 | tee ${RPT_DIR}/${DESIGNS}_sim_padroes.log
#grep -iE "miscompare|mismatch|error|passed|failed" ${RPT_DIR}/${DESIGNS}_sim_padroes.log | tail -20

#=============================================================================
# 5) MODO DE TESTE NA MAO -- XCELIUM  (DIARIO_DFT, 3a sessao, T13)
#
# O que um padrao de ATPG faz, escrito num testbench, no netlist com scan:
#   A. integridade das cadeias (carrega 12.5xx bits aleatorios, descarrega)
#   B. observar: o IP trabalha no modo normal; o estado sai pelas cadeias
#   C. controlar: estado escrito pelas cadeias, lido no AXI-Lite
#   D. padrao de captura: carga, 1 pulso com scan_en = 0, descarga
#      (mat_in_cnt 0xFF -> 0x100)
#   E. falha stuck-at-0 em mat_in_cnt[8].D: o teste de cadeia nao a ve;
#      o padrao de captura a ve
# tb/mapa_cadeias.vh diz em que cadeia/posicao esta cada bit -- gerado do
# netlist achatado do Genus (sim/run_dft_modo_teste.sh no notebook).
# Mesmo netlist e mesmos defines do bloco 2b.
# Esperado: "[MT] RESULTADO: TUDO OK"
#=============================================================================

#cd ${SIM_DIR}
#xrun -64bit -access +rwc -timescale 1ns/1ps \
#  -define FUNCTIONAL -define 'UNIT_DELAY=#1' \
#  -incdir ${DFT_DIR}/tb \
#  ${TECH_DIR}/verilog/primitives.v \
#  ${TECH_DIR}/verilog/sky130_fd_sc_hd.v \
#  ${BACKEND_DIR}/synthesis/scripts/restore_nettype.v \
#  ${DEV_DIR}/${DESIGNS}_flat.v \
#  ${TECH_DIR}/verilog/sram_1rw1r_64x64_wpr2.v \
#  ${TECH_DIR}/verilog/sram_1rw1r_64x256.v \
#  ${DFT_DIR}/tb/tb_isfft_modo_teste.v \
#  -top tb_isfft_modo_teste 2>&1 | tee ${SIM_DIR}/xrun_modo_teste.log
#grep "^\[MT\]" ${SIM_DIR}/xrun_modo_teste.log
