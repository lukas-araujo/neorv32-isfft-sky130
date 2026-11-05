# Apresentação final (CI Digital) — NEORV32 + ISFFT

`apresentacao_final.pptx`: 34 slides no template do CI Digital, feitos a partir do
deck do PC4 (`Ci_Digital_-_Etapa_2_-_Ponto_de_Controle_4.pptx`). Meta: 20 min de fala
(até 30 min); cada slide tem nota de fala com o tempo sugerido.
`build.py` gera o deck (python-pptx); precisa do deck do PC4 e das imagens citadas no topo.

## Estrutura (pedida pelo Lukas, 05/11/2026)

| # | Seção | Slides |
|---|---|---|
| 1 | Contextualização (Doppler em LEO, OTFS, onde entra a ISFFT) | 2–4 |
| 2 | Objetivo | 5 |
| 3 | IP ISFFT sozinho (a conta, bloco operacional, interfaces AXI) + as 3 matrizes de teste | 6–9 |
| 4 | UVM (só o IP): ambiente, funcionalidade, cobertura, IMC | 10–13 |
| 5 | DFT (só o IP): fluxo, cobertura e custo, telas do Modus | 14–17 |
| 6 | FPGA: fluxo, KR260, arquitetura com NEORV32, block design, implementação, Jupyter | 18–23 |
| 7 | RTL→GDSII: fluxo; parte 1 Cadence (arquitetura ASIC com NEORV32, macro × FF, síntese, netlist, pós-síntese + LEC); parte 2 software livre (dois níveis, etapas do núcleo, sign-off, lições) | 24–33 |
| 8 | Conclusões | 34 |

Decisões de forma: arquitetura com RISC-V aparece duas vezes (Kria e ASIC); UVM e DFT
antes da FPGA porque são só do IP; sem selo de item avaliado; título curto (≤ ~30
caracteres, 50 pt).

## Fontes dos números

`doc/tabelas_uvm.md`, `doc/tabelas_sintese.md`, `DIARIO.md` (D32, D38), `DIARIO_DFT.md`
(T10, 5ª sessão), `DIARIO_GDSII.md` (sessões 27, 30, 34, 35, 39 e 05/11), notebook
`processamento_otfs` (PDF: EVM e ciclos na placa, 100 MHz) e as telas do Vivado do PC4
(timing, potência, utilização).

## Pendente (Lukas)

- Trocar as capturas de tela ruins (IMC, block design, Genus, Modus) e incluir as que faltarem.
- Capa: data "Nov. 2026" e "PONTO DE CONTROLE 4" — ajustar para o dia da apresentação.
- Mostrar o PDF do notebook no slide 23, se quiser.
