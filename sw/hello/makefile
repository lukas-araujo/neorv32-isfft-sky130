# =============================================================================
# hello -- firmware de teste do SoC ASIC
#
# Gera neorv32_raw_exe.hex (uma palavra de 32 bits por linha), que o
# testbench carrega na macro da IMEM por $readmemh.
#
#   NEORV32_HOME=~/Projects/neorv32 make clean_all hex
# =============================================================================
APP_SRC = main.c
NEORV32_HOME ?= ../../../neorv32

MARCH = rv32imc_zicsr_zifencei
MABI  = ilp32
EFFORT = -Os

# Tamanhos REAIS das macros: o linker acusa estouro em vez de gerar
# um binario que nao cabe.
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=8k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=4k

include $(NEORV32_HOME)/sw/common/common.mk
