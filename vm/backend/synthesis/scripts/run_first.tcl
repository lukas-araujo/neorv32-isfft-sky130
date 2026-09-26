# run_first.tcl -- na verdade um script SHELL, como no fluxo padrao.
# Uso:  source run_first.tcl     (a partir do bash)
#
# Blocos (descomente UM por vez, no fim do arquivo). Ordem sugerida:
#   0) Simulacao RTL no Xcelium       -- confere o RTL e o testbench na VM
#   1) Sintese -- Genus               -- JA DESCOMENTADO
#   2) Simulacao pos-sintese -- Xcelium
#   3) Equivalencia -- Conformal LEC
#
# ⚠️ Este arquivo e lido com 'source': nao ponha 'exit' nele (fecharia o
#    terminal).
#
# DIFERENCAS para o neorv32_sram_soc:
#   - tudo Verilog (NEORV32 convertido pelo GHDL): sem VHDL
#   - 4 macros SRAM em vez de 1
#   - modelos das celulas com FUNCTIONAL na simulacao de portas (bloco 2):
#     era por isso que a do projeto anterior ficava em X (ver DIARIO)
#   - sem bloco com SDF: o sky130_fd_sc_hd.v do pacote nao tem blocos
#     'specify', entao nao ha onde anotar atraso (ver DIARIO)

export DESIGNS="neorv32_isfft_soc"
export HDL_NAME="asic_top"
export USER=aluno12
export PROJECT_DIR=/prj/ci/workarea/${USER}/projetos/${DESIGNS}
export BACKEND_DIR=${PROJECT_DIR}/backend

export TECH_DIR=${PROJECT_DIR}/tech

export PATH=/tools/cadence/DDI221/bin:/tools/cadence/DDI221/tools/bin
export PATH=$PATH:/tools/cadence/XCELIUM2309/tools/bin/64bit
export PATH=$PATH:/tools/cadence/XCELIUM2309/tools/bin
export PATH=$PATH:/tools/cadence/SSV231/bin:/tools/cadence/SSV231/tools/bin
export PATH=$PATH:/tools/cadence/CONFRML232/bin:/tools/cadence/CONFRML232/tools/bin
export PATH=$PATH:/tools/bin
export PATH=$PATH:/home/${USER}/.local/bin:/home/${USER}/bin
export PATH=$PATH:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

#=============================================================================
# Variaveis do projeto usadas pelos blocos abaixo
#=============================================================================
export SYN_DIR=${PROJECT_DIR}/backend/synthesis
export SCRIPTS=${SYN_DIR}/scripts
export DEV_DIR=${SYN_DIR}/deliverables
export RPT_DIR=${SYN_DIR}/reports
export SIM_DIR=${SYN_DIR}/sim_postsyn
export SIMRTL_DIR=${SYN_DIR}/sim_rtl

# Firmware: 3 matrizes do notebook da Kria pelo chip inteiro
# (DMEM -> DMA -> SLINK -> ISFFT -> SLINK -> DMA -> DMEM). As somas
# esperadas (chk_rtl.txt) sao as da simulacao RTL, que deu EVM igual ao
# da Kria (D32).
export HEX_FILE=${PROJECT_DIR}/sw/isfft_evm/neorv32_raw_exe.hex
export CHK_FILE=${PROJECT_DIR}/sw/isfft_evm/chk_rtl.txt

mkdir -p ${SYN_DIR}/work ${RPT_DIR} ${DEV_DIR} ${SIM_DIR} ${SIMRTL_DIR}

#=============================================================================
# Modelos de simulacao das macros (usado nos blocos 0 e 2)
#
# - macros de 1 porta (IMEM 8 kB, DMEM 4 kB): o modelo da OpenRAM (33 bits)
#   e renomeado para <macro>_beh; o adaptador sram_lib_view_model.v tem o
#   nome da macro e a interface do .lib (32 bits). Ver o cabecalho dele.
# - macros 1rw1r (ISFFT): .v e .lib ja casam; so copiadas.
# - VERBOSE = 0 nas 4: sem isto o modelo imprime CADA acesso.
#
# ⚠️ ${m}_beh e nao $m_beh: com '_' colado o shell leria a variavel
#    "m_beh" (vazia). Licao registrada no DIARIO.
#=============================================================================
prepara_modelos () {
  for m in sram_8kbyte_1rw_32x2048_8 sram_4kbyte_1rw_32x1024_8; do
    sed -e "s/module ${m}(/module ${m}_beh(/" \
        -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' \
        ${TECH_DIR}/verilog/${m}.v > $1/${m}_beh.v
  done
  for m in sram_1rw1r_64x256 sram_1rw1r_64x64_wpr2; do
    sed -e 's/parameter VERBOSE = 1 ;/parameter VERBOSE = 0 ;/' \
        ${TECH_DIR}/verilog/${m}.v > $1/${m}.v
  done
  grep -l "VERBOSE = 0" $1/*.v
}

#=============================================================================
# 0) SIMULACAO RTL -- XCELIUM  (opcional, ~1-2 min)
#
# Mesmo testbench e mesmos modelos de memoria da simulacao pos-sintese;
# so muda o circuito (RTL no lugar do netlist). Esperado no fim:
#   [TB] matriz 0/1/2: soma = RTL ...   e   [TB] PASSOU
#=============================================================================

#cd ${SIMRTL_DIR}
#prepara_modelos ${SIMRTL_DIR}
#xrun -64bit -access +rwc -timescale 1ns/1ps \
#  -define SRAM_LIB_VIEW \
#  ${PROJECT_DIR}/frontend/*.v \
#  ${PROJECT_DIR}/frontend/isfft/*.v \
#  ${SCRIPTS}/sram_lib_view_model.v \
#  ${SIMRTL_DIR}/sram_8kbyte_1rw_32x2048_8_beh.v \
#  ${SIMRTL_DIR}/sram_4kbyte_1rw_32x1024_8_beh.v \
#  ${SIMRTL_DIR}/sram_1rw1r_64x256.v \
#  ${SIMRTL_DIR}/sram_1rw1r_64x64_wpr2.v \
#  ${SCRIPTS}/tb_gate.v \
#  +IMEM_HEX=${HEX_FILE} +CHK_FILE=${CHK_FILE} \
#  -top tb_gate 2>&1 | tee ${SIMRTL_DIR}/xrun_rtl.log

#=============================================================================
# 1) SINTESE -- GENUS
#
# Termina no prompt do Genus: confira o que quiser e digite 'exit'. Depois
# disso, as linhas de conferencia abaixo rodam sozinhas.
#=============================================================================

cd ${SYN_DIR}/work

## apenas o programa (modo interativo)
## depois, no prompt:  source ${SCRIPTS}/${DESIGNS}.tcl
#genus -abort_on_error -lic_startup Genus_Synthesis \
#      -lic_startup_options Genus_Physical_Opt -log genus -overwrite

## programa + script (sintese automatizada)
genus -abort_on_error -lic_startup Genus_Synthesis \
      -lic_startup_options Genus_Physical_Opt -log genus -overwrite \
      -files ${SCRIPTS}/${DESIGNS}.tcl

echo
echo "=== Conferencia da sintese ==="
echo "--- modulos nao resolvidos (esperado: nenhum) ---"
grep -iv "^ *$\|^#\|Generated\|Genus\|Version\|Date" ${RPT_DIR}/${DESIGNS}_unresolved.rpt | head -20
echo "--- macros no netlist (esperado: 4 linhas, 1 instancia cada) ---"
grep -E "sram_8kbyte|sram_4kbyte|sram_1rw1r" ${RPT_DIR}/${DESIGNS}_gates.rpt
echo "--- celulas evitadas no netlist (esperado: 0) ---"
grep -cE "sky130_fd_sc_hd__(sdf|sedf|sdlclkp|lpflow|probe)" ${DEV_DIR}/${DESIGNS}.v
echo "--- slack (timing) ---"
grep -m3 -i "slack" ${RPT_DIR}/${DESIGNS}_timing.rpt

#=============================================================================
# 2) SIMULACAO POS-SINTESE -- XCELIUM  (sem SDF: atraso unitario)
#
# ⚠️ -define FUNCTIONAL e OBRIGATORIO. Sem ele, os flip-flops do
#    sky130_fd_sc_hd.v usam D_delayed/CLK_delayed/RESET_B_delayed, que
#    deveriam vir dos blocos 'specify' -- e este arquivo NAO TEM nenhum
#    'specify'. Resultado: todo flip-flop fica em X para sempre, com
#    qualquer simulador. Era o X do projeto anterior.
# ⚠️ UNIT_DELAY=#1: flip-flops com 1 ns de atraso, sem corrida entre
#    clock e dado no netlist sem arvore de clock.
# ⚠️ O sky130_fd_sc_hd.v do pacote tem 1 linha corrigida (um `endif sem
#    //, linha 49162) que so aparece com FUNCTIONAL. Ver DIARIO.
# ⚠️ Nao usar -v no arquivo de celulas (licao do projeto anterior).
#
# Esperado no fim (conferido na nuvem com netlist do Yosys + Icarus):
#   [TB] matriz 0: soma = RTL (0xeb88508e)
#   [TB] matriz 1: soma = RTL (0xba7fc58e)
#   [TB] matriz 2: soma = RTL (0xb29c0211)
#   [TB] PASSOU
#=============================================================================

#cd ${SIM_DIR}
#prepara_modelos ${SIM_DIR}
#xrun -64bit -access +rwc -timescale 1ns/1ps \
#  -define FUNCTIONAL -define 'UNIT_DELAY=#1' \
#  ${TECH_DIR}/verilog/primitives.v \
#  ${TECH_DIR}/verilog/sky130_fd_sc_hd.v \
#  ${SCRIPTS}/restore_nettype.v \
#  ${DEV_DIR}/${DESIGNS}.v \
#  ${SCRIPTS}/sram_lib_view_model.v \
#  ${SIM_DIR}/sram_8kbyte_1rw_32x2048_8_beh.v \
#  ${SIM_DIR}/sram_4kbyte_1rw_32x1024_8_beh.v \
#  ${SIM_DIR}/sram_1rw1r_64x256.v \
#  ${SIM_DIR}/sram_1rw1r_64x64_wpr2.v \
#  ${SCRIPTS}/tb_gate.v \
#  +IMEM_HEX=${HEX_FILE} +CHK_FILE=${CHK_FILE} \
#  -top tb_gate 2>&1 | tee ${SIM_DIR}/xrun_postsyn.log

#=============================================================================
# 3) EQUIVALENCIA LOGICA -- CONFORMAL LEC
#
# 3a) dofile escrito pelo Genus (deliverables/<design>_lec_genus.do).
#     Se ele terminar no prompt do Conformal, digite 'exit'.
# 3b) alternativa: o dofile escrito a mao (caminhos absolutos gerados aqui).
#
# O que conferir: 0 non-equivalent; nao mapeados; caixas-pretas = 4 macros.
#=============================================================================

## 3a
#cd ${SYN_DIR}/work
#lec -xl -nogui \
#    -dofile ${DEV_DIR}/${DESIGNS}_lec_genus.do \
#    2>&1 | tee ${RPT_DIR}/${DESIGNS}_lec_genus_run.log

## 3b
#cd ${SYN_DIR}/work
#sed "s|@PROJECT_DIR@|${PROJECT_DIR}|g" ${SCRIPTS}/${DESIGNS}_lec.do > ${SYN_DIR}/work/${DESIGNS}_lec.do
#lec -xl -nogui \
#    -dofile ${SYN_DIR}/work/${DESIGNS}_lec.do \
#    -logfile ${RPT_DIR}/${DESIGNS}_lec.log \
#    2>&1 | tee ${RPT_DIR}/${DESIGNS}_lec_run.log
