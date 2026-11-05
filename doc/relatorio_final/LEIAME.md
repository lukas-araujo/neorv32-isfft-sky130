# Relatório final (CI Digital) — NEORV32 + ISFFT

`relatorio_final.tex` (IEEEtran, conferência, duas colunas, português), no mesmo
padrão do relatório do Estudo Dirigido 1. Compila com `pdflatex` (duas vezes).
Figuras em `Imagens/` (da apresentação final, do ED1 e de `resultados/`).

Seções: Introdução (Doppler em LEO, domínio atraso-Doppler, ISFFT, objetivos);
Arquitetura e Metodologia (fluxos, IP, Kria, ASIC, SkyWater + OpenRAM, 3 matrizes);
UVM; DFT; FPGA; ASIC no Cadence; GDSII com ferramentas abertas (extra); Conclusão.

Números: `doc/tabelas_sintese.md`, `doc/tabelas_uvm.md`, diários, apresentação final,
notebook `processamento_otfs` e relatório do ED1 (tempos do ARM: média 0,81 ms).
Correções em relação à apresentação: sky130 tem met1–met5 (não met8); Doppler de
±300 kHz corresponde a portadora de ~12 GHz (banda Ku).
