# run_first_uvm.tcl -- verificacao UVM do IP da ISFFT (isfft_axi_v4) no Xcelium
#
# Uso:  cd .../neorv32_isfft_soc/verification/uvm_isfft/scripts
#       source run_first_uvm.tcl        (a partir do bash, como o run_first.tcl)
#
# Mesmo jeito do run_first.tcl da sintese: variaveis no topo e blocos
# comentados; descomente UM bloco por vez. Separado de proposito: o
# run_first.tcl (sintese, pos-sintese, LEC) fica como esta.
#
# ⚠️ Lido com 'source': nao ponha 'exit' aqui (fecharia o terminal).
#
# O DUT e lido de ${PROJECT_DIR}/frontend -- o MESMO RTL que foi
# sintetizado. A lista de arquivos (work/isfft_dut.f) e gerada na hora por
# gera_dut_f.sh, antes de qualquer bloco.
#
# Fonte de verdade: vm/verification/uvm_isfft/ do repositorio (DIARIO_UVM).
# Nao edite aqui: mude no repositorio e monte a pasta de novo.

export DESIGNS="neorv32_isfft_soc"
export IP_NAME="isfft_axi_v4"
export USER=aluno12
export PROJECT_DIR=/prj/ci/workarea/${USER}/projetos/${DESIGNS}
export UVM_DIR=${PROJECT_DIR}/verification/uvm_isfft

# PATH completo da VM (o mesmo do CLAUDE.md). Com so o Xcelium o IMC (bloco
# 3) nao era achado.
export PATH=/tools/cadence/QUANTUS261/bin:/tools/cadence/QUANTUS261/tools/bin:/tools/cadence/PEGASUS261/bin:/tools/cadence/PEGASUS261/tools/bin:/tools/cadence/SSV261/bin:/tools/cadence/SSV261/tools/bin:/tools/cadence/XCELIUM2603/tools/bin/64bit:/tools/cadence/XCELIUM2603/tools/bin:/tools/cadence/MODUS261/bin:/tools/cadence/MODUS261/tools/bin:/tools/cadence/CONFRML261/bin:/tools/cadence/CONFRML261/tools/bin:/tools/cadence/DDI221/bin:/tools/cadence/DDI221/tools/bin:/tools/cadence/PVS251/bin:/tools/cadence/PVS251/tools/bin:/tools/cadence/VMANAGER2603/bin:/tools/bin:/tools/cadence/SPECTRE251/bin:/tools/cadence/SPECTRE251/tools/bin:/tools/cadence/IC618/bin:/tools/cadence/IC618/tools/bin:/tools/cadence/IC618/tools/dfII/bin:/pdk/TSMC/CLN12FFC+/TSMCHOME/sram/Compiler/MC2/MC2_2013.12.00.g/bin/Linux-64:/home/${USER}/.local/bin:/home/${USER}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin

#=============================================================================
# Variaveis da verificacao
#=============================================================================
export UVM_WORK=${UVM_DIR}/work          # xcelium.d, cov_work, formas de onda
export UVM_RPT=${UVM_DIR}/reports        # um log por teste + cobertura
mkdir -p ${UVM_WORK} ${UVM_RPT}

# Lista do DUT (frontend/ + macros + referencia), sempre refeita
bash ${UVM_DIR}/scripts/gera_dut_f.sh ${PROJECT_DIR} ${UVM_DIR} ${UVM_WORK}/isfft_dut.f

# Testes da regressao (bloco 2). Cada um termina com "TESTE PASSOU/FALHOU".
export TESTES="isfft_fumaca_test isfft_registradores_test isfft_kria_test \
isfft_aleatorio_test isfft_truncado_test isfft_contrapressao_test \
isfft_soft_reset_test isfft_kria_regressao_test"

# Opcoes comuns do xrun
#  -uvm             : UVM que vem com o Xcelium (o tb e compativel com 1.2 e
#                     IEEE 1800.2; a versao usada aparece no log: "UVM: ...")
#  -f isfft_uvm.f   : tb + (work/isfft_dut.f) DUT, nucleo, macros e referencia
#  -coverage all    : cobertura de codigo (bloco, expressao, FSM, toggle) +
#                     funcional (covergroups) + assercoes
#  -covdut          : cobertura de codigo so dentro do IP (nao do tb)
#  -covfile         : tira do -covdut o que nao e RTL do chip: modelos da
#                     OpenRAM e as 3 u_sva do bind (cobertura.ccf, U20)
export XRUN_OPTS="-64bit -sv -uvm -timescale 1ns/1ps \
  -xmlibdirname ${UVM_WORK}/xcelium.d \
  -f ${UVM_DIR}/scripts/isfft_uvm.f \
  -top isfft_tb_top \
  -coverage all -covdut ${IP_NAME} \
  -covfile ${UVM_DIR}/scripts/cobertura.ccf \
  -covworkdir ${UVM_WORK}/cov_work -covoverwrite \
  +UVM_NO_RELNOTES"

# Resultado de um teste a partir do log
resultado () {
  if grep -q "TESTE PASSOU" $1; then echo "PASSOU"; else echo "FALHOU"; fi
}

#=============================================================================
# BLOCO 0 -- COMPILAR E ELABORAR (sem simular)
#
# Esperado: sem *E no log; "xmelab: *W" do PDK/OpenRAM podem aparecer.
# Avisos do cobertura.ccf: nenhum (um modulo nao achado vira *W com o nome).
#=============================================================================

#cd ${UVM_WORK}
#xrun ${XRUN_OPTS} -elaborate -l ${UVM_RPT}/compila.log
#echo "--- erros de compilacao/elaboracao (esperado: nenhum) ---"
#grep -E "\*E,|\*F," ${UVM_RPT}/compila.log | head -20
#echo "--- linhas sobre o cobertura.ccf (esperado: nenhum aviso) ---"
#grep -i -E "ccf|covfile|deselect" ${UVM_RPT}/compila.log | head -20

#=============================================================================
# BLOCO 1 -- TESTE DE FUMACA (1 matriz)
#
# Esperado no fim do log:
#   [SB_RESUMO] 1 matrizes / 32 palavras comparadas bit a bit; 0 erros ...
#   [TESTE] TESTE PASSOU: isfft_fumaca_test
#=============================================================================

cd ${UVM_WORK}
xrun ${XRUN_OPTS} +UVM_TESTNAME=isfft_fumaca_test -svseed 1 \
     -covtest isfft_fumaca_test_s1 \
     -l ${UVM_RPT}/isfft_fumaca_test.log
echo
echo "=== isfft_fumaca_test: $(resultado ${UVM_RPT}/isfft_fumaca_test.log) ==="
grep -E "UVM: |SB_RESUMO|COBERTURA|UVM_ERROR @|UVM_FATAL @|\*E," ${UVM_RPT}/isfft_fumaca_test.log | head -20

#=============================================================================
# BLOCO 2 -- REGRESSAO (todos os testes)
#
# SEMENTES: quantas sementes por teste (1 = so a semente 1). Cada rodada
# grava a propria cobertura (-covtest <teste>_s<semente>) para o bloco 3.
# Esperado: todos PASSOU.
#=============================================================================

#export SEMENTES=1
#cd ${UVM_WORK}
## Rodadas antigas fora: com outro modelo de cobertura (ex.: antes do
## cobertura.ccf) o merge do bloco 3 misturaria dois modelos.
#rm -rf ${UVM_WORK}/cov_work/scope
#rm -f ${UVM_RPT}/regressao.txt
#for t in ${TESTES}; do
#  for s in $(seq 1 ${SEMENTES}); do
#    xrun ${XRUN_OPTS} +UVM_TESTNAME=${t} -svseed ${s} \
#         -covtest ${t}_s${s} -l ${UVM_RPT}/${t}_s${s}.log > /dev/null 2>&1
#    printf "%-28s semente %-3s %s\n" ${t} ${s} $(resultado ${UVM_RPT}/${t}_s${s}.log) \
#      | tee -a ${UVM_RPT}/regressao.txt
#  done
#done
#echo
#echo "=== Regressao: $(grep -c PASSOU ${UVM_RPT}/regressao.txt) PASSOU, $(grep -c FALHOU ${UVM_RPT}/regressao.txt) FALHOU ==="
#grep -h -E "KRIA\]|SB_RESUMO\].*faixa" ${UVM_RPT}/isfft_kria_test_s1.log ${UVM_RPT}/isfft_aleatorio_test_s1.log

#=============================================================================
# BLOCO 3 -- COBERTURA (IMC): junta todas as rodadas do bloco 2
#
# O merge vai para work/cov_merged (fora de cov_work/scope, para uma nova
# rodada nao juntar o merge antigo). Gera:
#   reports/cobertura_resumo.txt      resumo por instancia/metrica
#   reports/cobertura_funcional.txt   covergroups bin a bin + assercoes
# Para navegar no que faltou cobrir (GUI):  imc -load ${UVM_WORK}/cov_merged
#=============================================================================

#command -v imc > /dev/null || echo "imc fora do PATH -- procure: ls /tools/cadence/*/tools/bin/imc /tools/cadence/*/bin/imc"
#cd ${UVM_WORK}
#cat > ${UVM_WORK}/imc_cobertura.cmd <<EOF
#merge ${UVM_WORK}/cov_work/scope/* -out ${UVM_WORK}/cov_merged -overwrite
#load ${UVM_WORK}/cov_merged
#report -out ${UVM_RPT}/cobertura_resumo.txt -summary
#report -out ${UVM_RPT}/cobertura_funcional.txt -detail -metrics functional -all -aspect both -assertionStatus
#exit
#EOF
#imc -exec ${UVM_WORK}/imc_cobertura.cmd -logfile ${UVM_RPT}/imc.log
#head -40 ${UVM_RPT}/cobertura_resumo.txt
#echo "--- codigo dos modelos da OpenRAM e das u_sva (esperado: n/a ou ausentes, U20) ---"
#grep -E "u_in_mem|u_out_mem|u_sva" ${UVM_RPT}/cobertura_resumo.txt

#=============================================================================
# BLOCO 4 -- DEPURAR UM TESTE NO SIMVISION
#
# Troque TESTE_DBG. Abre o SimVision com acesso a sinais e a classes UVM
# (-linedebug permite breakpoint no codigo do tb). Sem cobertura (mais leve).
#=============================================================================

#export TESTE_DBG=isfft_fumaca_test
#cd ${UVM_WORK}
#xrun -64bit -sv -uvm -timescale 1ns/1ps \
#  -xmlibdirname ${UVM_WORK}/xcelium_dbg.d \
#  -f ${UVM_DIR}/scripts/isfft_uvm.f -top isfft_tb_top \
#  -access +rwc -linedebug -uvmlinedebug \
#  +UVM_TESTNAME=${TESTE_DBG} -svseed 1 +UVM_VERBOSITY=UVM_MEDIUM \
#  -gui -l ${UVM_RPT}/${TESTE_DBG}_gui.log
