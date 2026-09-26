
#-----------------------------------------------------------------------------
# Common path variables (directory structure dependent)
#
# Adaptado do fluxo padrao da turma para o projeto NEORV32 + ISFFT (sky130).
# Mesma estrutura do projeto anterior (neorv32_sram_soc).
#-----------------------------------------------------------------------------
set BACKEND_DIR ${PROJECT_DIR}/backend
set SYNT_DIR ${BACKEND_DIR}/synthesis
set SCRIPT_DIR ${SYNT_DIR}/scripts
set RPT_DIR ${SYNT_DIR}/reports
set DEV_DIR ${SYNT_DIR}/deliverables
set LAYOUT_DIR ${BACKEND_DIR}/layout

#-----------------------------------------------------------------------------
# Setting rtl search directories
#
# frontend/        -> RTL do chip, TODO em Verilog:
#                     neorv32_asic.v (NEORV32 convertido pelo GHDL), topo,
#                     IMEM/DMEM com macro, conversores, ISFFT v4
# frontend/isfft/  -> nucleo da ISFFT (Spiral + FSMs), igual ao da Kria
#-----------------------------------------------------------------------------
set FRONTEND_DIR ${PROJECT_DIR}/frontend
set ISFFT_RTL_DIR ${FRONTEND_DIR}/isfft

#-----------------------------------------------------------------------------
# Setting technology directories
#
# O sky130 NAO esta instalado na VM: vem dentro do pacote, em tech/
# (Apache 2.0). As 4 macros da OpenRAM tambem.
#-----------------------------------------------------------------------------
set TECH_DIR ${PROJECT_DIR}/tech
set LIB_DIR ${TECH_DIR}/lib
set LEF_DIR ${TECH_DIR}/lef
