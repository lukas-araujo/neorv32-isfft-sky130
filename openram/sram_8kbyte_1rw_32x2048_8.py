"""
SRAM 8 kB para a IMEM do NEORV32 (sky130) -- rodada BACK-END.

Projeto: NEORV32 + ISFFT em ASIC (sky130)

Por que 8 kB: o firmware da Kria tinha 4.428 bytes de .text e vai ser
reescrito (DMA + SLINK). A macro de 4 kB e apertada demais para arriscar.

Mesma receita da macro de 4 kB (projeto OpenRAM), so muda num_words.

------------------------------------------------------------------------
TEMPO ESPERADO
------------------------------------------------------------------------
4 kB back-end levou 3 h 53 min. Com o dobro de bitcells, espere algo
como 8 a 10 horas. Rode com nohup (ver run_8kb.sh).

------------------------------------------------------------------------
NAO MEXER: spare row/col OBRIGATORIAS em macro de 1 porta no sky130
(regra de paridade; sem elas a memoria nao compila).
------------------------------------------------------------------------
"""
import os

word_size  = 32
num_words  = 2048          # 8 kB
write_size = 8             # escrita por byte: sb/sh do RISC-V

num_rw_ports = 1
num_r_ports  = 0
num_w_ports  = 0

num_spare_rows = 1
num_spare_cols = 1

tech_name = "sky130"
nominal_corner_only = True
route_supplies = "ring"
uniquify = True

check_lvsdrc = True        # back-end: layout + DRC/LVS
analytical_delay = True    # timing por modelo (como a de 4 kB)

output_name = "sram_8kbyte_1rw_32x2048_8"
output_path = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "out", output_name)
