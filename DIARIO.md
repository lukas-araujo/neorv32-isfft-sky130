# DIÁRIO — NEORV32 + ISFFT em ASIC (SkyWater 130 nm)

Diário de bordo do fluxo ASIC do SoC **NEORV32 + acelerador ISFFT**, do RTL
até o layout, com **todas as memórias geradas pela OpenRAM**.

Este projeto junta dois trabalhos anteriores:

| Origem | O que herda |
|---|---|
| `neorv32-openram-sky130` (DIARIO/TUTORIAL do projeto OpenRAM) | Ambiente, fluxo Genus/Xcelium/Conformal na VM, macro SRAM de 4 kB, armadilhas do sky130 |
| `kria_ISFFT_NEORV32` (etapa 2 do transceptor OTFS) | NEORV32 + ponte AXI + `isfft_axi_v3` validados em hardware |

Decisões herdadas do diário do projeto OpenRAM são citadas como
**OR-Dn** (ex.: OR-D1). Decisões deste projeto são **Dn**.

---

## Como usar este diário

Cada problema encontrado segue o modelo:

```
### 🐛 <título curto>
**Sintoma:** o que apareceu (mensagem, log, comportamento).
**Causa:** por que quebrou, quando eu descobrir.
**Resolvi com:** o que funcionou.
**Tempo gasto:** aproximado.
**Vira slide?** sim/não — e por quê.
```

Decisões entram na tabela da entrada do dia **e** no índice de decisões
no fim do arquivo, com o status: ✅ adotada · 🟡 proposta (aguarda
confirmação) · ❌ descartada.

---

## Caminhos do projeto

| O quê | Onde |
|---|---|
| Repositório (notebook) | `/home/lukas/Projects/neorv32-openram-sky130` |
| NEORV32 | `/home/lukas/Projects/neorv32` |
| OpenRAM | `/home/lukas/Projects/OpenRAM` |
| PDK | `/home/lukas/Projects/pdks` |
| venv | `/home/lukas/Projects/envs/microelectronics` |
| Ambiente isolado da OpenRAM | `/home/lukas/Projects/env_openram.sh` |
| Firmware da Kria | `~/Projects/neorv32/sw/example/fw_isfft_proc` |
| Projeto na VM (goku, aluno12) | `/prj/ci/workarea/aluno12/projetos/neorv32_sram_soc` |

---

## Proposta do projeto — Ponto de Controle 1

> Resumo do que vamos fazer, do RTL ao GDSII. Uma linha de motivo por
> item. Detalhes e histórico nas entradas datadas abaixo.

### Objetivo

Levar o SoC **NEORV32 + acelerador ISFFT** (validado na Kria KR260) do
RTL ao **layout (GDSII)** em **SkyWater 130 nm**, com **macros da OpenRAM
onde elas compensam** — fronteira macro × flip-flop **medida** no próprio
projeto.

### Ponto de partida

| O que já existe | Estado |
|---|---|
| NEORV32 + `xbus2axi4_bridge` + `isfft_axi_v3` | Validados em hardware na Kria (EVM 0,60–3,41%) |
| Testbench da ISFFT com modelo de referência | Pegou 3 de 3 mutações |
| Macro SRAM 4 kB (32×1024) pela OpenRAM | Gerada até GDS/LEF (284.139 µm²) |
| Fluxo Genus na VM com sky130 | Testado em projeto anterior |

### Arquitetura alvo

```
            ┌──────────────────── NEORV32 ────────────────────┐
            │  CPU rv32imc ── IMEM (macro) ── DMEM (macro)     │
            │   │                                              │
            │   ├── DMA ──► SLINK TX ──┐     SLINK RX ◄──┐     │
            │   └── XBUS ──┐           │                 │     │
            └──────────────┼───────────┼─────────────────┼─────┘
                           ▼           ▼ conv. 32→64     │ conv. 64→32
                    xbus2axi4_bridge   │                 │
                           │ AXI4-Lite ▼  AXI-Stream     │
                           └──────► isfft_axi_v3 ────────┘
```

- **Controle:** CPU → XBUS → ponte AXI → registradores da ISFFT.
- **Dados:** DMA copia a matriz da DMEM para o SLINK; o stream passa pela ISFFT e volta pelo SLINK para a DMEM.

### O que muda da Kria para o ASIC

| Mudança | Por quê |
|---|---|
| Tirar Zynq, SmartConnect, BRAM Controller e AXI DMA | São IPs da Xilinx; não existem em ASIC |
| IMEM e DMEM internas viram macros OpenRAM (módulos substituíveis do NEORV32) | Array VHDL vira flip-flop: ~5× mais área por bit |
| Converter o NEORV32 de VHDL para um Verilog único (GHDL) | O Yosys/LibreLane não lê VHDL; uma só fonte para todas as ferramentas |
| DMA + SLINK do NEORV32 no lugar do AXI DMA | Movem os dados sem a CPU, com blocos nativos do processador |
| Conversores de stream 32↔64 bits com `tlast` | SLINK tem 32 bits; a ISFFT, 64 |
| FIFOs do SLINK com 64 posições | O SLINK não segura o barramento; a FIFO precisa caber uma matriz inteira |
| Ponte AXI4 → AXI4-Lite só por ligação de portas | Sem burst, a ponte já gera transações de 1 palavra |
| Leitura da FIFO de saída da ISFFT passa a ser síncrona | Macro SRAM entrega o dado 1 ciclo depois; o RTL atual lê de forma assíncrona |
| Firmware reescrito para DMA + SLINK | O atual usa o AXI DMA e a caixa de correio da Kria |
| Clock de 100 → 50 MHz | Período que fechou na síntese do projeto anterior |
| Banco de registradores em flip-flops (`CPU_RF_ARCH_SEL = 2`) | 2 leituras + 1 escrita por ciclo; na Kria era estilo de RAM de FPGA |

### Memórias → macros OpenRAM

| Memória | Tamanho | Implementação | Macro ÷ flip-flop (medido) |
|---|---|---|---|
| IMEM (programa) | 2048 × 32 | **Macro** 1rw 8 kB | 0,16× |
| DMEM (dados) | 1024 × 32 | **Macro** 1rw 4 kB | 0,20× |
| FIFO de saída da ISFFT | 256 × 64 | **Macro** 1rw1r 64×256 | 0,41× |
| Buffer de entrada da ISFFT | 64 × 64 | **Macro** 1rw1r 64×64 | 0,85× |
| Ping-pong da ISFFT | 2 × 8 × 8 × 32 | Flip-flop | 1,42× (2 macros 64×32) |
| Memórias do Spiral (`memMod`) | 16 × (4 ou 8) × 32 | Flip-flop | 6,0× (16 macros 32×16) |
| FIFOs do SLINK, DMA, UART | ≤ 64 × 37 | Flip-flop | ~1,27× (modelo) |
| Banco de registradores | 32 × 32, 2R1W | Flip-flop | — (porta) |

**Regra medida:** macro 1rw1r de 64 bits custa ≈ 103.900 µm² fixos +
11,8 µm²/bit; flip-flop custa 43,9 µm²/bit. **A macro só compensa acima
de ~3.200 bits.** Resultado: memórias da ISFFT com **0,64×** a área de
tudo-em-flip-flop, com 4 macros no chip (em vez de 20+).

O número de macros é ditado pelos **acessos por ciclo**, não pelos bits: o
Spiral teria 16 memórias ativas ao mesmo tempo; o ping-pong, 1 escrita +
2 leituras por ciclo. Macros de 64 bits precisam de 2 palavras por linha
(com 1, o anel de alimentação da OpenRAM não fecha).

### Fluxo e ferramentas

| # | Etapa | Ferramenta | Onde | Situação |
|---|---|---|---|---|
| | **Front-end — RTL e simulação** | | | |
| 1 | Gerar as macros SRAM | **OpenRAM** | Notebook | ✅ |
| 2 | Converter o NEORV32 para Verilog | **GHDL** | Notebook | ✅ |
| 3 | RTL novo: memórias, conversores, ISFFT, topo | Verilog | Notebook | ✅ |
| 4 | Firmware com DMA + SLINK | **riscv-none-elf-gcc** | Notebook | ✅ |
| 5 | Simulação do chip (EVM igual à Kria) | **Icarus Verilog** | Notebook | ✅ |
| | **Síntese e verificação** | | | |
| 6 | Síntese lógica | **Genus** | VM | ▶ próximo |
| 7 | Equivalência RTL × netlist | **Conformal LEC** | VM | |
| 8 | Simulação pós-síntese | **Xcelium** | VM | |
| | **Back-end — layout** | | | |
| 9 | Floorplan, place, CTS e roteamento | **LibreLane** (OpenROAD) | Notebook | |
| 10 | DRC, LVS e GDSII | **Magic**, **Netgen**, **KLayout** | Notebook | |

*Se der tempo:* STA com parasitas extraídos (**Tempus**, SPEF do OpenROAD)
e potência (**Joules**), na VM.

Versão para slide: `doc/tabela_fluxo.png` (`doc/gera_tabela_fluxo.py`;
para atualizar a situação, mude a última coluna e rode de novo).

Por que duas máquinas: o Cadence da VM não tem regras físicas nem
extração para o sky130 (sem PVS/Pegasus/Quantus); o layout fecha no
fluxo aberto.

### Verificação

| O quê | Como |
|---|---|
| Módulos de memória com macro | Testbench contra o módulo VHDL original |
| ISFFT com macros | **Testbench novo**: versão original e versão com macros lado a lado, palavra por palavra, com pausas aleatórias e pacote truncado |
| Conversores e SLINK | Testbench de stream com contrapressão |
| SoC completo | Firmware processa matrizes; saída comparada com o modelo em Python (EVM) |
| Netlist | Conformal LEC + simulação pós-síntese com o mesmo firmware |
| Layout | DRC e LVS limpos na lógica; violações herdadas da macro documentadas |

### Entregáveis e métricas

- GDSII do SoC, com imagem do layout.
- Área total e por bloco; área de cada memória em **macro × flip-flop**.
- Frequência / slack após síntese e após layout.
- Relatórios de DRC, LVS e equivalência.
- EVM da simulação do SoC igual ao da Kria.

### Riscos

| Risco | Plano |
|---|---|
| ~~Memórias rasas saírem maiores como macro~~ | **Confirmado e resolvido:** só vira macro acima de ~3.200 bits |
| Macro gerada tem ~394 mil violações de DRC | Documentar; comparar com a macro pré-gerada do PDK |
| 4 macros largas (720–810 µm) no mesmo die | Empilhar na vertical; posicionamento manual no floorplan |
| Rodada back-end da OpenRAM leva horas por macro | Gerar em lote, fora do horário de trabalho |
| `.lib`, `.lef` e `.v` da macro divergem (32 × 33 bits) | Interface de 33 bits no layout; adaptador na simulação |

### Fora de escopo

Tapeout, DFT/scan, múltiplos corners, carga do programa em silício
(bootloader/JTAG) e a troca para a Transformada de Zak.

---

## 2026-09-18 — Levantamento de contexto e arquitetura do barramento

**Objetivo:** reunir o que os dois projetos anteriores já provaram,
decidir a arquitetura do barramento de controle e levantar o que muda
da FPGA para o silício, antes de escrever qualquer RTL.

### O ponto de partida: projeto OpenRAM

**Ambiente (OR-D1, fluxo híbrido).**
- Notebook (Linux-Batata): OpenRAM v1.2.49 (commit `b2b069ce`), PDK via
  `ciel`, GHDL, Magic, Netgen e LibreLane.
- VM goku: Genus e Innovus (DDI 22.1), Xcelium 23.09, Conformal 23.2,
  Tempus (SSV 23.1). **Sem** PVS, Pegasus ou Quantus → não há assinatura
  física no Cadence com sky130.

**Estrutura de scripts na VM** (a da turma, adaptada):
`run_first.tcl` com blocos comentados, `common/path.tcl` e
`common/tech.tcl`, árvore `frontend/` + `backend/synthesis/{scripts,
constraints,reports,deliverables,work}`. Adaptações para o sky130:
domínio único TT, wireload em vez de QRC, linguagem mista com a
biblioteca `neorv32`, ordem dos VHDL tirada do log do GHDL.
**Regra:** comandos de Genus e Xcelium vão dentro do `run_first.tcl`,
não em scripts `.sh` separados.

**A macro SRAM** `sram_4kbyte_1rw_32x1024_8` (32 bits × 1024, 1rw):

| | |
|---|---|
| Front-end | 41 min |
| Back-end | 3 h 53 min |
| Área | 284.139 µm² → **8,67 µm²/bit** |
| DRC / LVS | **394.613 / 3 erros** |
| Potência dinâmica confiável | 13,13 mW (front-end; a back-end estourou) |

**Síntese do SoC anterior:** 127.736 µm², slack +2253 ps a 50 MHz,
banco de registradores = 46% da CPU (42.367 µm² → **41,4 µm²/bit**).

> ⚠️ **Números desatualizados.** Os relatórios do pacote da VM são de uma
> rodada posterior: 133.140 µm², regfile 44.958 µm², +2048 ps. Ver a
> 2ª sessão de 2026-09-18.

**Armadilhas que continuam valendo:**
- Views `.lib` e `.v` da macro divergem (32 × 33 bits, `spare_wen0`) →
  `SRAM_SYNTH_VIEW`.
- Spare rows/cols obrigatórias no sky130.
- `nix develop` faz a OpenRAM cair em `pbitcell` sem aviso.
- `python3 -u` obrigatório na OpenRAM.
- Genus podou os bits 31:12 do decodificador de endereço.

**Pendências herdadas:**
- Simulação pós-síntese: `xbus_cyc`/`xbus_stb` em X (pista: mux de scan
  do `sdfrtp`).
- Conformal LEC travado em `neorv32.neorv32_cfs`.
- 3 erros de LVS da macro.
- Layout wrapper + macro no LibreLane: guia entregue, execução não
  registrada.

### O ponto de partida: ISFFT na Kria

`isfft_axi_v3`, todo em Verilog:
- Registradores AXI4-Lite: CTRL, STATUS, MAT_IN, MAT_OUT, ERR_CNT,
  ID = `0x15FF0300`, PKT_MAT.
- Buffer de entrada de 64 palavras (64 bits) com commit/rollback.
- FIFO de saída de 256 palavras com reserva por crédito.
- `top_isfft` inalterado: DFT8 do Spiral em ponto fixo de 16 bits,
  latência 41 ciclos, gap 4, banco ping-pong 2×8×8×32 bits, duas FSMs.

Verificação: testbench autoverificável contra o wrapper da etapa 1,
com pausas aleatórias, parada longa de `tready` e pacote truncado. As
3 mutações deliberadas foram detectadas. **Esse testbench vira a
regressão de qualquer mudança no RTL da ISFFT.**

Hardware: NEORV32 controlou ISFFT e DMA sozinho; o Zynq só serviu de
depurador via caixa de correio na BRAM. EVM idêntico à etapa 1:
**3,41% (impulso), 0,78% (senoide), 0,60% (rampa).**

Notas de passagem daquele chat:
1. O ping-pong faz 4 acessos por ciclo (2 leituras + 2 escritas) — não
   cabe numa macro OpenRAM comum.
2. O Spiral entra como RTL sintetizável normal.
3. O testbench v3 é a regressão.

### O que a Kria tinha que o sky130 não tem

| Bloco na Kria | Tipo | No ASIC |
|---|---|---|
| NEORV32 + ponte XBUS→AXI4 | VHDL puro | Reaproveita igual |
| `isfft_axi_v3` | Verilog próprio | Reaproveita igual |
| SmartConnect | IP Xilinx | Decodificador AXI4-Lite próprio |
| AXI BRAM Controller + BRAM | IP Xilinx | Wrapper AXI4-Lite + macro OpenRAM |
| AXI DMA | IP Xilinx | Substituir (decisão pendente) |
| DMEM interna 32 kB | array VHDL | Viraria flip-flops → macro OpenRAM |
| Zynq (carga do programa e depuração) | PS | Não existe (ver limitação abaixo) |

### Discussão: Wishbone ou AXI?

Minha proposta inicial foi usar o XBUS (Wishbone) com uma ponte
Wishbone→AXI4-Lite na frente da ISFFT. **Lukas questionou:** por que
trocar, se o NEORV32 com AXI já foi validado na Kria?

A pergunta estava certa. A proposta vinha por herança do projeto
OpenRAM, cujo `sram_wb_wrapper` é Wishbone, e não por necessidade
técnica.

Fatos levantados:
- O barramento **nativo** do NEORV32 é o XBUS. O `m_axi` da Kria vem do
  `neorv32_vivado_ip.vhd`, que liga o XBUS a uma ponte
  (`rtl/system_integration/xbus2axi4_bridge.vhd`).
- A ponte e o wrapper são **VHDL puro**. Os atributos de interface da
  Xilinx são ignorados pelo Genus. Sintetizam no ASIC.
- A quantidade de RTL novo é praticamente a mesma nos dois caminhos.
  A diferença é **o que fica comprovado em hardware**: com AXI, o
  controle da ISFFT roda exatamente como na placa, e o bloco novo é só
  o wrapper da SRAM, que é o lado mais simples (latência fixa de 1
  ciclo).

Custo aceito: toda busca de instrução passa pela ponte. Na Kria já era
assim e funcionou; é questão de desempenho, não de correção. Medir esse
custo vira resultado.

### Conferência: a ponte faz burst?

```
$ grep -n "awlen\|arlen\|awburst" .../xbus2axi4_bridge.vhd
159:  m_axi_arlen <= ... when BURST_EN and (burst = '1') else (others => '0');
168:  m_axi_awlen <= ... when BURST_EN and (burst = '1') else (others => '0');
170:  m_axi_awburst <= "01"; -- incrementing bursts only

$ grep -n "BURST_EN\|CACHE_EN\|ICACHE\|DCACHE" .../neorv32_vivado_ip.vhd
 94:    ICACHE_EN   : boolean := false;
 96:    DCACHE_EN   : boolean := false;
306:  constant burst_en_c : boolean := CACHE_BURSTS_EN and (ICACHE_EN or DCACHE_EN);
707:      BURST_EN  => burst_en_c,
```

Leitura:
- Burst só existe se `BURST_EN` estiver ligado **e** a transação vier
  marcada como burst (`xbus_cti_i = "010"`, linha 232), o que só os
  caches fazem.
- No wrapper, `BURST_EN` depende de `CACHE_BURSTS_EN` **e** de algum
  cache existir.
- Sem burst, a ponte só usa `S_SINGLE_READ` / `S_SINGLE_WRITE`,
  `awlen`/`arlen` = 0 e o `ack` vem direto da resposta AXI (linha 300).
  **É o comportamento de um AXI4-Lite.**

### A configuração real da Kria

Extraída no Tcl Console do Vivado com
`report_property [get_bd_cells -hierarchical -filter {VLNV =~ *neorv32*}] CONFIG.*`.
Genéricos relevantes:

| Genérico | Valor na Kria |
|---|---|
| `ICACHE_EN` / `DCACHE_EN` / `CACHE_BURSTS_EN` | `false` / `false` / `false` |
| `IMEM_EN` | `false` |
| `BOOT_MODE_SELECT` / `BOOT_ADDR_CUSTOM` | `1` / `0x00000000` |
| `DMEM_EN` / `DMEM_BASE` / `DMEM_SIZE` | `true` / `0x80000000` / 32768 |
| `CPU_RF_ARCH_SEL` | `1` |
| `CLOCK_FREQUENCY` | 100000000 |
| `RISCV_ISA_C` / `_M` / `_Zicntr` | `true` / `true` / `true` |
| `IO_UART0_EN` / RX FIFO / TX FIFO | `true` / 64 / 64 |
| `IO_DMA_EN` / `IO_SLINK_EN` | `false` / `false` |
| `OCD_EN` | `false` |
| `XBUS_EN` / `XBUS_TIMEOUT` | `true` / 2048 |

**Confirmado: a Kria rodou sem burst.** A ponte validada na placa é
exatamente a que vai para o ASIC.

**Confirmado: o programa já vinha pelo barramento externo.** A CPU acorda
em `0x0000_0000` sem bootloader.

### O que muda na configuração do ASIC

| Genérico | Kria | ASIC | Motivo |
|---|---|---|---|
| `DMEM_EN` | `true` (32 kB) | `false` | 32 kB em flip-flops ≈ 1,36 milhão de µm² (> 10× o SoC). Vira SRAM OpenRAM externa em `0x8000_0000` |
| `IO_UART0_RX/TX_FIFO` | 64 / 64 | 1 / 1 | ~1.024 bits de FIFO em flip-flops ≈ 42.000 µm², o tamanho do banco de registradores. No ASIC a UART só serve ao log da simulação |
| `CLOCK_FREQUENCY` | 100 MHz | 50 MHz | Período que fechou na síntese do SoC. Informa o software (UART, SYSINFO); precisa bater com o SDC |
| `CPU_RF_ARCH_SEL` | 1 | ~~a decidir~~ **2** | ✅ Já era 2 (`reg`) no `soc_config_pkg.vhd`. Ver Correção 2 |
| `IO_DMA_EN` / `IO_SLINK_EN` | `false` | **a decidir** | Depende do substituto do AXI DMA |

O comentário em `rtl/neorv32_sram_soc.vhd` (linha 54) registra que o
default `0` é `sram_sync` e que o projeto ASIC não usa o default de
propósito.

### 🐛 O firmware não cabe em 4 kB

**Sintoma:**
```
$ riscv-none-elf-size main.elf
   text    data     bss     dec     hex filename
   4428       0     256    4684    124c main.elf
```
O `.text` tem **4.428 bytes**, 332 a mais que a macro de 4.096.

**Causa:** o plano original previa uma SRAM de programa de 4 kB. O
firmware da Kria inclui o `neorv32_rte_setup()` (tratador de traps),
a UART e o código do AXI DMA da Xilinx.

**Agravante:** o firmware vai mudar de novo. Sai o código do AXI DMA e
entra o do caminho de dados novo. O tamanho final ainda é incerto.

**Resolvi com (proposta):** dois bancos da macro de 4 kB que já existe,
em `0x0000_0000` e `0x0000_1000`, escolhidos pelo bit 12 do endereço.
Ficam 8 kB contíguos **sem gerar macro nova** (uma de 8 kB custaria
outra rodada back-end de várias horas). E dividir a memória em bancos
é prática comum em chips reais, então serve à aula.

**O makefile muda** (linhas 22 e 23; hoje estão em 32k/32k, herança da
BRAM e da DMEM da Kria):
```make
USER_FLAGS += -Wl,--defsym,__neorv32_rom_size=8k
USER_FLAGS += -Wl,--defsym,__neorv32_ram_size=4k
```
Assim o **linker acusa o estouro**, em vez de gerar um binário que não
cabe na memória.

Dados e pilha cabem com folga: `.bss` de 256 bytes, sobrando ~3,8 kB
para a pilha.

> ⚠️ **Corrigido na 2ª sessão.** A partição do projeto ASIC não vem do
> makefile da Kria: está em `soc_config_pkg.vhd`, hoje em 2048/2048.
> O estouro é de 2.380 B contra a região ROM, não de 332 B. Ver
> Correção 3.

**Vira slide?** Sim. "Mediu antes de gerar" é a lição: 332 bytes teriam
virado um bug silencioso de simulação.

### Mapa de memória proposto

| Endereço | Bloco | Implementação |
|---|---|---|
| `0x0000_0000` | Programa, banco 0 | Macro OpenRAM 4 kB |
| `0x0000_1000` | Programa, banco 1 | Macro OpenRAM 4 kB |
| `0x4001_0000` | ISFFT (registradores) | `isfft_axi_v3`, sem mudanças |
| `0x8000_0000` | Dados e pilha | Macro OpenRAM 4 kB |

O endereço da ISFFT e o da DMEM são os mesmos da Kria. O **linker
script do firmware continua valendo**; muda só o tamanho das regiões.

Barramento de controle: NEORV32 → ponte XBUS→AXI4 → **decodificador
AXI4-Lite 1→4** (três bancos de SRAM + ISFFT), com resposta zerada fora
do handshake (mesmo defeito do "portão de saída" já achado no projeto
OpenRAM).

### Inventário de memórias (proposta, aguarda decisão)

"Todas as memórias pela OpenRAM" precisa de escopo. Levantamento, com
a estimativa em flip-flops a 41,4 µm²/bit (medido no regfile):

| Memória | Tamanho | Bits | Portas | Estimativa em FF | Proposta |
|---|---|---|---|---|---|
| Programa (2 bancos) | 2 × 32×1024 | 65.536 | 1rw | — | OpenRAM (macro existente) |
| Dados | 32×1024 | 32.768 | 1rw | — | OpenRAM (macro existente) |
| FIFO de saída da ISFFT | 256×64 | 16.384 | 1 escrita + 1 leitura | ~678.000 µm² | OpenRAM 1rw1r |
| Buffer de entrada da ISFFT | 64×64 | 4.096 | 1 escrita + 1 leitura | ~170.000 µm² | OpenRAM 1rw1r |
| Ping-pong | 2×64×32 | 4.096 | 2 leituras + 2 escritas | ~170.000 µm² | 8 macros de 16×32, separadas por (paridade da linha × paridade da coluna) |
| Regfile, FIFOs internas do NEORV32 | pequenas | — | regfile é 2R1W | — | Flip-flops, profundidade mínima |

Sobre o ping-pong: a escrita grava as colunas `2c` e `2c+1` da mesma
linha; a leitura lê as linhas `2p` e `2p+1` da mesma coluna. Separando
por (linha mod 2, coluna mod 2), os acessos simultâneos sempre caem em
macros diferentes. **Suspeita a confirmar:** macros de 16×32 devem sair
*maiores* que os flip-flops (a periferia domina) e podem estar abaixo
do mínimo que a OpenRAM aceita no sky130. Medir isso é resultado.

Ainda falta conferir se os `.v` do Spiral inferem memórias internas
(permutações).

### Caminho de dados (pendente)

O AXI DMA da Xilinx precisa de substituto. A opção levantada: **DMA +
SLINK do próprio NEORV32**. O DMA copia da SRAM para o SLINK TX, os
dados passam pela ISFFT e o DMA traz o resultado do SLINK RX para a
SRAM. Pontos em aberto:
- SLINK é de 32 bits; a ISFFT usa palavras de 64 → conversor 32↔64 com
  `tlast`.
- O v3 já tolera pausas no `tvalid`, o que torna essa troca viável.
- O firmware precisa ser reescrito para o DMA do NEORV32.
- As FIFOs do SLINK e a FIFO de descritores do DMA são arrays em VHDL →
  manter a profundidade mínima.

### Limitação registrada: quem carrega o programa?

Na Kria, o Zynq escrevia o binário na BRAM. **No ASIC, nada carrega o
programa na SRAM.** Na simulação, o programa entra por `$readmemh` no
modelo da macro, como no projeto OpenRAM. Num chip real seria preciso
um bootloader por UART (`BOOT_MODE_SELECT = 0`) ou o OCD por JTAG.
Como o projeto não vai para tapeout, fica documentado e não implementado.

### Decisões do dia

| # | Decisão | Status | Motivo |
|---|---|---|---|
| D1 | ~~Barramento de controle em **AXI**, reaproveitando `neorv32_vivado_ip.vhd` + `xbus2axi4_bridge.vhd` como bloco CPU~~ | ❌ **revista** | O projeto ASIC não usa AXI nem tem esses arquivos. Ver Correção 1 e o D1 reescrito |
| D2 | Caches desligados e **sem burst** → decodificador e wrapper da SRAM em **AXI4-Lite** | ✅ | Igual à Kria (confirmado nos genéricos); SRAM de 1 ciclo não se beneficia de cache |
| D3 | `DMEM_EN = false`; dados numa macro OpenRAM externa em `0x8000_0000` | 🟡 | DMEM interna viraria flip-flops; mantém o endereço da Kria |
| D4 | Programa em **dois bancos** da macro de 4 kB (8 kB) | 🟡 | Firmware tem 4.428 B de `.text`; evita nova rodada back-end |
| D5 | Makefile: `rom_size = 8k`, `ram_size = 4k` | 🟡 | Linker acusa estouro |
| D6 | FIFOs da UART0 em 1 / 1 | 🟡 | ~42.000 µm² de FIFO só para log de simulação |
| D7 | `CLOCK_FREQUENCY = 50 MHz` | 🟡 | Período que fechou na síntese anterior |
| D8 | Carga do programa só por `$readmemh` na simulação | 🟡 | Sem tapeout; bootloader/OCD ficam documentados |

---

## 2026-09-18 (2ª sessão) — Chegou o pacote da VM: três correções

**Objetivo:** ler o projeto real da VM (`neorv32_sram_soc.zip`, 3,6 MB)
em vez de trabalhar de memória, e conferir o que a entrada anterior
deste diário afirmou.

**Resultado: a entrada anterior errou em três pontos.** Todos por eu ter
descrito o projeto ASIC a partir da conversa, não do código.

### 🐛 CORREÇÃO 1 — o projeto ASIC não tem AXI nenhum

**O que eu escrevi:** que D1 seria "reaproveitar
`neorv32_vivado_ip.vhd` + `xbus2axi4_bridge.vhd` como bloco CPU".

**O que o código mostra:** `frontend/neorv32_sram_soc.vhd` instancia
`neorv32.neorv32_top` **direto**, com as portas `xbus_*`, ligadas ao
`sram_wb_wrapper`. O `xbus_cti_o` está em `open` — "sem rajada: nosso
escravo nao usa".

E a árvore `frontend/neorv32/` (55 arquivos, listados em
`rtl_files.tcl`) **não inclui `system_integration/`**. Nem o
`neorv32_vivado_ip.vhd`, nem o `xbus2axi4_bridge.vhd` existem na VM.

**Consequência:** o AXI não é "o que já foi validado" *neste* projeto.
O que foi validado aqui é o Wishbone. O AXI foi validado no outro
projeto, na Kria. São dois conjuntos de código provados, em lados
diferentes do barramento.

**Isso muda o balanço de D1.** Reescrito abaixo.

### 🐛 CORREÇÃO 2 — `CPU_RF_ARCH_SEL` já estava decidido

Eu listei como pendência "replicar a Kria (1) ou manter o estilo
medido". `soc_config_pkg.vhd` responde:

```vhdl
constant CPU_RF_ARCH_C : natural := 2;
```

Com o motivo documentado no próprio arquivo: `0 = sram_sync` é pensado
para FPGA, onde o sintetizador infere block RAM; em ASIC não existe
block RAM, então flip-flops explícitos são previsíveis. O valor `1` da
Kria é irrelevante aqui — era o estilo de RAM de FPGA.

**Pendência fechada.** O que sobra é o *experimento* dos quatro valores
(OR-D20), que é outra coisa.

### 🐛 CORREÇÃO 3 — a partição do linker é 2k/2k, não 32k/32k

Eu citei o makefile do firmware da **Kria** (`rom_size=32k`,
`ram_size=32k`, herança da BRAM e da DMEM de lá). O projeto ASIC usa:

```vhdl
constant ROM_SIZE_C : natural := 2048;
constant RAM_SIZE_C : natural := 2048;
```

Duas regiões de 2 kB **dentro da única SRAM de 4 kB**, com o stack
pointer nascendo em `0x00001000`. O comentário admite: "A divisao
2k/2k e chute inicial".

**O problema do firmware é pior do que eu escrevi.** Não é `.text` de
4.428 B contra 4.096 de macro: é contra **2.048 B de região ROM**. São
2.380 bytes de estouro, não 332.

Para calibrar: o firmware que está na VM hoje
(`sw/neorv32_raw_exe.hex`, o demo do somador) tem **748 palavras =
2.992 B** — já não caberia em 2 kB de ROM. A partição precisa mudar de
qualquer forma, com ISFFT ou sem.

### Números reais da síntese — a entrada anterior estava desatualizada

Os relatórios do pacote são de **09/09/2026 20:52**, mais novos que os
que eu citei:

| | Diário antigo | Pacote (real) |
|---|---|---|
| Área do SoC | 127.736 µm² | **133.140,19 µm²** |
| Regfile (`ARCHSEL2`) | 42.367 µm² | **44.958,12 µm²** |
| µm²/bit do flip-flop | 41,4 | **43,9** |
| Slack | +2253 ps | **+2048 ps** |

**A razão flip-flop ÷ célula de SRAM passa de 4,8× para 5,06×**
(43,9 ÷ 8,67). Os 284.139 µm² da macro continuam sendo **2,1× toda a
lógica do SoC**.

Área por bloco (`*_area_hier.rpt`), que é o que interessa para decidir
o que cortar:

| Bloco | Área (µm²) | % do SoC |
|---|---|---|
| CPU | 96.201,01 | 72,3% |
| ↳ banco de registradores | 44.958,12 | 33,8% (46,7% da CPU) |
| ↳ contadores (Zicntr) | 7.873,80 | 5,9% |
| **UART0** (RX FIFO 1, TX FIFO 32) | **13.656,85** | **10,3%** |
| CFS (somador) | 6.064,57 | 4,6% |
| Bus switch | 683,16 | 0,5% |
| `sram_wb_wrapper` | **344,08** | 0,26% |
| XBUS | 266,51 | 0,2% |
| `sram_macro_shim` | 0,00 | — (só a caixa-preta) |

Duas leituras:

**A UART custa 10% do SoC.** E a RX FIFO já está em 1 — o gasto é a TX
FIFO de 32 palavras. Isso ajusta D6: não é "1/1", é **só a TX**.

**O wrapper da SRAM custa 344 µm².** É 0,26% do SoC. Qualquer discussão
sobre "reaproveitar ou reescrever o wrapper" é sobre *verificação
provada*, não sobre área.

### ✅ O X do `sdfrtp` foi resolvido — e eu listei como pendência aberta

`common/tech.tcl` traz:

```tcl
set_db [get_db lib_cells *__sdf*] .avoid true
```

com o diagnóstico completo no comentário: sem fluxo de DFT, os pinos
SCD/SCE ficam abertos, SCE em X faz o mux de scan interno não decidir,
e `Q` sai em X mesmo com `D` e reset perfeitos. Achado no SimVision com
"Go to Cause", que levou até o
`sky130_fd_sc_hd__udp_mux_2to1` dentro de um `sdfrtp`.

Conferido no netlist do pacote:

```
grep -c "sky130_fd_sc_hd__sdf" .../neorv32_sram_soc.v  ->  0
```

Zero células de scan. Os flops são `dfrtp_1` (2.043), `dfxtp_1` (719),
`dfrbp_1` (106) e `dfstp` (14). **A causa do X foi eliminada nesta
rodada.** Falta saber se a simulação pós-síntese passou depois disso —
o `xrun.log` do pacote é de uma invocação que morreu em `*E,FILEMIS`
(caminhos errados), não o diagnóstico.

### ⚠️ Comentário obsoleto em `soc_config_pkg.vhd`

O pacote tem um bloco de aviso que **contradiz o código**:

```
-- ⚠️ ESPELHAMENTO
-- Nosso wrapper usa apenas os bits baixos do endereco e NAO decodifica
-- faixa. Qualquer acesso que chegue ao XBUS [...] e atendido pela SRAM,
-- espelhado a cada 4 kB.
```

Mas o `sram_wb_wrapper.v` **decodifica faixa** desde a correção da
poda: tem `fora_da_faixa = |wb_adr_i[31:ADDR_BITS+2]`, responde
`wb_err_o` fora da faixa e o próprio arquivo explica que usar o
endereço completo "é o que impede a poda da lógica que o produz".

O comentário é de antes da correção. **Apagar:** um aviso que descreve
um defeito já corrigido é pior que nenhum aviso — quem ler vai
procurar um espelhamento que não existe.

### D1 reescrito: três caminhos, e o terceiro é melhor

Com a Correção 1, o balanço muda. Os blocos provados são:

| Bloco | Provado onde | Interface |
|---|---|---|
| `neorv32_top` + XBUS + `sram_wb_wrapper` | Síntese Genus, este projeto | Wishbone |
| `xbus2axi4_bridge` | Kria, em hardware | XBUS → AXI4 |
| `isfft_axi_v3` | Kria, em hardware + testbench | AXI4-Lite + stream |

| Caminho | RTL novo | Descarta |
|---|---|---|
| **A — tudo Wishbone** | Decodificador WB 1→4 + ponte WB→AXI4-Lite | — |
| **B — tudo AXI** | Decodificador AXI4-Lite 1→4 + wrapper AXI4-Lite da SRAM | `sram_wb_wrapper` (verificação, não área) |
| **C — híbrido** | **Decodificador XBUS 1→4** + amarração AXI4→AXI4-Lite | — |

**O caminho C:** o decodificador divide o XBUS; os três bancos de
memória vão para instâncias de `sram_wb_wrapper` (provadas aqui) e o
ramo da ISFFT vai para o `xbus2axi4_bridge` (provado na Kria) e daí
para o `isfft_axi_v3` (provado na Kria). **Nenhum dos dois lados é
reescrito.** O único bloco realmente novo é o decodificador.

A amarração AXI4→AXI4-Lite é fina, não é ponte: com `BURST_EN = false`
a ponte já emite `awlen = 0` e um beat por transação. Sobram
`awsize`/`awburst`/`awcache`/`awprot`/`awid`, que o escravo Lite
ignora, e `bid`/`rid`, que precisam ser amarrados. Na Kria era o
SmartConnect que fazia isso.

**Recomendação: caminho C.** Aguarda confirmação.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| D1 | ~~AXI com `neorv32_vivado_ip.vhd`~~ → **híbrido (caminho C)**: decodificador XBUS, memórias em `sram_wb_wrapper`, ISFFT atrás do `xbus2axi4_bridge` | 🟡 | Único caminho que não reescreve nenhum bloco já provado |
| D2 | Sem cache, sem burst (mantida) | ✅ | Confirmada nos dois lados: `xbus_cti_o => open` aqui, caches `false` na Kria |
| D4 | Programa em 2 bancos de 4 kB (mantida, motivo mais forte) | 🟡 | Estouro é de 2.380 B contra a região ROM, não 332 B |
| D5 | ~~`rom_size=8k`, `ram_size=4k` no makefile~~ → **`ROM_SIZE_C` / `RAM_SIZE_C` no `soc_config_pkg.vhd`** | 🟡 | A partição é do pacote VHDL (hoje 2048/2048), não do makefile da Kria |
| D6 | ~~UART0 em 1/1~~ → **só a TX FIFO, de 32 para 1** | 🟡 | RX já está em 1; a TX é o que custa (UART0 = 13.657 µm² = 10,3% do SoC) |
| D9 | `CPU_RF_ARCH_C = 2` (flip-flops), como já está | ✅ | Já decidido e documentado no pacote; o `1` da Kria era estilo de RAM de FPGA |
| D10 | Apagar o aviso de ESPELHAMENTO do `soc_config_pkg.vhd` | ✅ | Descreve defeito já corrigido; induz a erro |
| D11 | Números canônicos de área e timing = relatórios do pacote (09/09 20:52) | ✅ | Mais novos que os do diário anterior |

### Confirmações úteis para o layout

O caminho hierárquico da macro, que o `GUIA_LAYOUT.md` tinha chutado
como `u_sram/u_sram`, **está certo** para o escopo wrapper + macro:

```
neorv32_sram_soc
└── u_sram          sram_wb_wrapper_ADDR_BITS10
    └── u_sram      sram_macro_shim_WORD_ADDR_BITS10
        └── u_sram  sram_4kbyte_1rw_32x1024_8   (netlist, linha 31097)
```

Com `DESIGN_NAME = sram_wb_wrapper` no LibreLane, o caminho é
`u_sram/u_sram`. Do topo do SoC seriam três níveis.

**A macro na VM é a de front-end:** só `.v` (view de simulação, 33
bits) e `.lib` sem área. Não há `.lef` nem `.gds` lá. É por isso que
`tech.tcl` precisa de

```tcl
set_db [get_db lib_cells *sram_4kbyte*] .avoid false
set_db [get_db lib_cells *sram_4kbyte*] .dont_use false
```

— o Genus marca `avoid` automaticamente em qualquer `lib_cell` com área
zero, e sem isso a instância não vincula: a síntese termina sem erro, a
área sai plausível, e os caminhos de/para os pinos da memória **não são
analisados**.

Para o Genus somar a área da memória sozinho, é preciso subir o `.lib`
da rodada back-end do notebook.

---

## 2026-09-18 (3ª sessão) — Base nova: RTL da Kria + módulos substituíveis do NEORV32

**Decisão do Lukas:** não manter nenhum RTL do teste anterior
(`sram_wb_wrapper`, `sram_macro_shim`, `soc_config_pkg`,
`neorv32_sram_soc.vhd`, CFS do somador). Motivo, nas palavras dele:
"os RTLs são fontes de aprendizado". A base passa a ser **o que rodou na
Kria**: a árvore do NEORV32 dela e o `isfft_axi_v3`.

Isso **torna obsoletos os caminhos A, B e C** da 2ª sessão — todos
partiam de reaproveitar o `sram_wb_wrapper`.

Recebido `arquivos.zip` (227 arquivos): árvore completa do NEORV32
(`core/`, `system_integration/`, `verilog/`, `test_setups/`), o
`isfft_axi_v3_0/` empacotado, `isfft_axi_wrapper.v` e `tb_isfft_axi_v3.v`,
`main.c` + `makefile` do `fw_isfft_proc_v2`, a rodada back-end completa
da macro (`out_4kb_backend/`, com `.gds`, `.lef`, `.lib`, `.v`) e os
`DIARIO.md` / `TUTORIAL.md` do projeto OpenRAM.

### 🔑 O achado: o NEORV32 tem um fluxo oficial para ASIC

`rtl_neorv32/verilog/` traz um `Makefile` que converte o SoC inteiro em
**um único Verilog** com `ghdl synth`, e permite **excluir módulos VHDL
e substituí-los por Verilog próprio**:

```
make VHDL_EXCLUDE=neorv32_dmem.vhd VERILOG_SRC=modules/neorv32_dmem.v clean convert sim
```

Os módulos substituíveis ("Replaceable Modules") têm entidade uniforme —
só genéricos inteiros e portas de largura fixa — justamente para isso:
`neorv32_imem`, `neorv32_dmem`, `neorv32_cache_ram`, `neorv32_bootrom`,
`neorv32_cfs`, `neorv32_cpu_alu_cfu`.

**Consequência:** a IMEM e a DMEM **internas** podem ser as macros
OpenRAM. Nada de XBUS decodificado, nada de wrapper de barramento, nada
de decodificação de faixa — quem decodifica é o próprio gateway do
NEORV32. E a interface é quase a da macro:

| `neorv32_dmem` | Macro OpenRAM |
|---|---|
| `req_addr_i[AWIDTH-1:2]` | `addr0` (+ 1 bit sobressalente em 0) |
| `req_data_i` | `din0` |
| `req_ben_i & {4{req_stb_i}}` | `wmask0` / `csb0` |
| `req_rw_i` | `~web0` |
| `rsp_data_o` (1 ciclo depois) | `dout0` (1 ciclo depois) |

A latência é a mesma: 1 ciclo. E o módulo de referência **já zera
`rsp_data_o` fora do `ack`** — o mesmo "portão de saída" que achamos na
mão no projeto anterior. Confirma o padrão.

**Bônus, e é grande:** o mesmo fluxo resolve o **bloqueio do LibreLane**
(Yosys não lê VHDL). A conversão deixa de ser um passo no fim e vira a
base do projeto: sai um Verilog único que serve ao Genus, ao Yosys, ao
Icarus e ao Verilator.

### 🐛 Bug no módulo de exemplo `modules/neorv32_dmem.v`

**Sintoma (por leitura, antes de simular):** o `neorv32_dmem.v` de
exemplo **nunca reconhece escrita**.

```verilog
ack <= {ack[0], req_stb_i & ~req_rw_i};   // só leitura
assign rsp_ack_o = ack[0];
```

**Comparação:**

| Arquivo | Ack de escrita |
|---|---|
| `core/neorv32_dmem.vhd` (referência) | `wrack <= req_stb_i and req_rw_i;` → `rsp_ack_o <= wrack or rdack(...)` ✅ |
| `verilog/modules/neorv32_imem.v` | `wrack` presente, `rdack[OUTREG] \| wrack` ✅ |
| `verilog/modules/neorv32_dmem.v` | **ausente** ❌ |

**Consequência:** o primeiro `sw` na DMEM ficaria esperando um `ack`
que nunca vem. O CI do NEORV32 provavelmente não pega porque o programa
de teste não escreve na DMEM ou porque o testbench usa outra
configuração.

**Resolvi com:** escrever nossos módulos tendo o **VHDL como
referência**, não o exemplo em Verilog. Vale reportar upstream.

**Vira slide?** Sim. "Exemplo oficial não é especificação" — e foi
achado por comparação de três arquivos, não por simulação.

### 🐛 A LEF concorda com o `.v`, não com o `.lib`

O diário antigo dizia que "`.lib` e `.v` divergem". Faltava a terceira
view. Conferido na rodada back-end:

| View | `din0`/`dout0` | `spare_wen0` | Área |
|---|---|---|---|
| `.v` (simulação) | 33 bits | existe | — |
| **`.lef` (físico)** | **33 bits** | **existe** | 808,845 × 351,29 µm |
| `.lib` (timing) | 32 bits | **não existe** | 284.139,16 µm² ✅ |

**O `.lib` é o que está fora.** Consequência para o layout: com
`SRAM_SYNTH_VIEW` (32 bits), o netlist deixaria o 33º bit e o
`spare_wen0` da LEF **sem conexão** — e `spare_wen0` flutuando é
problema real no LVS. Para o LibreLane, a instância tem que usar a
interface de 33 bits com `spare_wen0 = 0`, e o `.lib` vira só aviso de
timing no bit 32.

**O `GUIA_LAYOUT.md` estava errado nisso:** mandava
`VERILOG_DEFINES = ["SRAM_SYNTH_VIEW", "SRAM_4KB"]`.

### 🐛 A macro não é quadrada

```
SIZE 808.845 BY 351.29 ;
```

Proporção **2,3 : 1**. O `GUIA_LAYOUT.md` supôs ~530 × 536 µm e um die
de 700 × 700 µm — **onde a macro não cabe** (808 µm de largura). Com
duas macros (IMEM + DMEM) empilhadas: ~809 × 703 µm só de memória.

Em compensação, o `.lib` back-end **tem área** (`284139.16`). O
`set_db ... .avoid false` do `tech.tcl` deixa de ser necessário e o
Genus passa a somar a memória sozinho.

### Inventário completo de memórias (lido do RTL, não estimado)

Estimativa em flip-flops a **43,9 µm²/bit** (regfile medido na síntese
de 09/09):

| Memória | Onde | Tamanho | Bits | Acesso | Em FF (µm²) |
|---|---|---|---|---|---|
| IMEM | NEORV32 | 1024 × 32 | 32.768 | 1rw | ~1.438.000 |
| DMEM | NEORV32 | 1024 × 32 | 32.768 | 1rw | ~1.438.000 |
| **`out_mem`** | `isfft_axi_v3.v:132` | 256 × 64 | **16.384** | 1W + 1R **assíncrono** | **~719.000** |
| `in_mem` | `isfft_axi_v3.v:90` | 64 × 64 | 4.096 | 1W + 1R síncrono | ~180.000 |
| `ping_pong_ram` | `top_isfft.v:41` | 2×8×8 × 32 | 4.096 | 2W + 2R por ciclo | ~180.000 |
| `memMod` × 16 | Spiral (`memArray4/8_*`) | 8 ou 4 × 32 | 3.584 | 1W + 1R, escreve todo ciclo | ~157.000 |
| `shiftRegFIFO` | Spiral | — | — | registrador de deslocamento | (é FF por natureza) |
| Regfile | NEORV32 | 32 × 32 | 1.024 | 2R1W | 44.958 (medido) |

**Leituras:**

- **O `out_mem` da ISFFT sozinho vale 2,5 macros de 4 kB em flip-flops.**
  É o segundo maior alvo depois de IMEM/DMEM, e maior que qualquer bloco
  lógico do SoC.
- **Ele tem leitura assíncrona:** `assign m00_axis_tdata = out_mem[out_rd_ptr]`.
  Macro OpenRAM é síncrona. Trocar exige reestruturar a leitura da FIFO
  (pré-busca de 1 palavra). É o mesmo dilema do `sram_async` × `sram_sync`
  do `CPU_RF_ARCH_SEL`, agora em RTL nosso.
- **FIFO = 1 escrita + 1 leitura simultâneas** → precisa de macro
  **1rw1r**, não 1rw. 256 × 64 = duas macros `1rw1r 32×256` lado a lado.
- **Spiral e ping-pong são rasos demais para macro** (4–16 palavras).
  A periferia de uma macro OpenRAM domina nessa profundidade.
- O `memMod` tem `writeSel = 1'b1` fixo: **escreve em todo ciclo**.
  Numa SRAM real, isso é consumo de potência contínuo.

### Mapa do NEORV32 na Kria vs. ASIC

A Kria usava `IMEM_EN = false` (programa na BRAM via `m_axi`) e
`DMEM_EN = true` (32 kB). Com os módulos substituíveis:

| | Kria | ASIC |
|---|---|---|
| Programa | BRAM externa via AXI, `0x0000_0000` | **IMEM interna = macro**, `0x0000_0000` |
| Dados | DMEM interna 32 kB, `0x8000_0000` | **DMEM interna = macro 4 kB**, `0x8000_0000` |
| `BOOT_MODE_SELECT` | 1 (endereço custom `0x0`) | 2 (IMEM) |
| XBUS | ponte → SmartConnect → BRAM, DMA, ISFFT | ponte → **só a ISFFT** (sem decodificador) |

Com o XBUS livre, a ISFFT é o **único escravo**. Sem decodificador.

### A ponte AXI é mais simples de adaptar do que eu disse

Conferido no `xbus2axi4_bridge.vhd`: **não há canais de ID** (`awid`,
`bid`, `rid`). A adaptação AXI4 → AXI4-Lite é só ligação de portas:

- `awlen`, `awsize`, `awburst`, `awcache`, `awprot`, `wlast` e os
  equivalentes de leitura: `open` (o escravo Lite não os tem).
- `m_axi_rlast => '1'`.

Zero lógica.

### ⚠️ O firmware não é reaproveitável como está

O `main.c` (`fw_isfft_proc_v2`, 238 linhas) fala com o **AXI DMA da
Xilinx** (`MM2S_DMACR`, `S2MM_DA`...) e com a **caixa de correio na BRAM**
(`0x0000_8000`) que o Jupyter lia. Nenhum dos dois existe no ASIC. O
núcleo (configurar ISFFT, medir `mcycle`) se aproveita; o transporte de
dados precisa ser reescrito para o DMA + SLINK do NEORV32 ou para
cópia pela CPU.

Nota: o `riscv-none-elf-size` da 1ª sessão (4.428 B) foi do
`fw_isfft_proc`; o do pacote é o `fw_isfft_proc_v2`. Medir de novo.

### ⚠️ O diário antigo está atrás do `tech.tcl`

O `DIARIO.md` do projeto OpenRAM termina a simulação pós-síntese em
"NÃO RESOLVIDO", com 4 hipóteses por testar. O `tech.tcl` da VM já
contém o achado seguinte (`avoid` nos `sdf*`, via "Go to Cause" no
SimVision). **Essa descoberta nunca foi registrada no diário antigo.**
Com a base nova, a questão vira: o mesmo `avoid` entra no script novo
desde o início.

### Decisões desta sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| D12 | **Nenhum RTL do teste anterior.** Base = árvore NEORV32 da Kria + `isfft_axi_v3` | ✅ | Decisão do Lukas; o RTL é material de aprendizado |
| D13 | IMEM e DMEM **internas**, substituídas por Verilog próprio envolvendo a macro OpenRAM (fluxo "Replaceable Modules") | 🟡 | Rota oficial do NEORV32; elimina decodificador e wrapper de barramento |
| D14 | Converter o SoC para Verilog único com o `Makefile` de `rtl/verilog/` **no início** | 🟡 | Uma netlist-fonte para Genus, Yosys, Icarus e Verilator; destrava o LibreLane |
| D15 | Módulos substituídos escritos a partir do **VHDL**, não do exemplo Verilog | ✅ | Exemplo `neorv32_dmem.v` não reconhece escrita |
| D16 | XBUS → `xbus2axi4_bridge` → `isfft_axi_v3`, sem decodificador, amarração só por port map | 🟡 | ISFFT é o único escravo externo |
| D17 | No layout, instanciar a macro com a interface de **33 bits** + `spare_wen0 = 0` | 🟡 | A LEF tem 33 bits e `spare_wen0`; o `.lib` é a view divergente |
| D18 | Usar o `.lib` **back-end** no Genus (área real) | ✅ | Dispensa o `avoid false` |
| D1 | ~~Híbrido (caminho C)~~ | ❌ | Substituída por D13 + D16 |

---

## 2026-09-18 (4ª sessão) — Tamanho mínimo da OpenRAM para o Spiral

**Confirmado pelo Lukas:** banco de registradores fica em flip-flops;
STA com SPEF e potência entram como "se der tempo", depois do layout.

### O limite está no código, antes de rodar

Clonei a OpenRAM no mesmo commit da instalação do notebook (`b2b069c`,
v1.2.49). Em `compiler/sram_config.py`, `amend_words_per_row`:

```python
if (not OPTS.is_unit_test and tentative_num_rows < 16):
    debug.check(tentative_num_rows * words_per_row >= 16,
                "Minimum number of rows is 16, but given {0}".format(tentative_num_rows))
```

**Mínimo: 16 palavras.** As configs oficiais `sky130_sram_1rw_tiny.py` e
`sky130_sram_1rw1r_tiny.py` também usam 16 — é o piso da ferramenta.

Consequência para o Spiral (`memMod` de 8 e 4 palavras): usam a macro de
16 com os bits altos do endereço em 0. **Metade ou 3/4 de cada macro
fica sem uso.** O ping-pong dividido em 8 blocos de 16 palavras cabe
exato.

Outros dois pontos do código:
- A regra de paridade (spare row/col obrigatórias) só é checada com
  **1 porta**. As configs 1rw1r não levam spare — igual à `tiny` oficial.
- 1rw1r usa **`bitcell_2port`**, célula diferente (e maior) que a do 1rw.

### O teste (notebook, back-end direto — o front-end dá área 0)

Pacote `spiral_min/`:

| Teste | Config | Esperado | Serve para |
|---|---|---|---|
| A | 1rw1r 32×8 | **falha** em segundos | Registrar a mensagem real do limite |
| B | 1rw1r 32×16 | gera | Macro do Spiral |
| C | 1rw 32×16 + spare | gera | Macro do ping-pong |

Referência em flip-flop (43,9 µm²/bit): 32×16 = **22.477 µm²**,
32×8 = 11.238 µm², 32×4 = 5.619 µm². **Hipótese:** a macro de 16
palavras sai maior que isso — a periferia (decodificador, amplificadores,
anel de alimentação) não encolhe com o número de palavras.

### A verificar no testbench, não aqui

O `memMod` do Spiral escreve em **todo ciclo** (`writeSel = 1'b1`) e lê
no mesmo ciclo. Se escrita e leitura caírem no mesmo endereço, a macro
1rw1r não garante o dado antigo. Os bits `inFlip`/`outFlip` sugerem que
nunca colidem — confirmar com asserção no testbench.

---

## 2026-09-19 — ✅ Resultado do teste de tamanho mínimo

`spiral_min/run_min.sh`, back-end, notebook. Duas tentativas perdidas
por erro meu no script (caminho do `sram_compiler.py` e `out/`
inexistente — a OpenRAM usa `os.mkdir`, não cria pastas intermediárias).

### Números

| Teste | Tempo | Bitcell | Área (µm²) | LEF (µm) | DRC | LVS |
|---|---|---|---|---|---|---|
| A — 1rw1r 32×8 | 3 s | `bitcell_2port` | — | — | — | — |
| B — 1rw1r 32×16 | 399 s | `bitcell_2port` | **58.926** | 358,32 × 164,45 | **0** | 2 |
| C — 1rw 32×16 | 365 s | `bitcell_1port` | **43.663** | 286,24 × 152,54 | 7.259 | 3 |

Teste A falhou como previsto:
`ERROR: file sram_config.py: line 179: Minimum number of rows is 16, but given 8.0`

### 🔑 A aposta se confirmou: macro rasa perde para flip-flop

| Memória | µm²/bit | × flip-flop |
|---|---|---|
| Macro 1rw 32×1024 (4 kB) | **8,67** | 0,20× |
| Flip-flop (regfile medido) | **43,9** | 1× |
| Macro 1rw 32×16 | **85,3** | 1,94× |
| Macro 1rw1r 32×16 | **115,1** | 2,62× |

A periferia (decodificador, amplificadores, controle, anel de
alimentação) tem tamanho quase fixo. Com 16 palavras ela domina; com
1024 ela se dilui. **O ponto de equilíbrio está entre 16 e 1024
palavras** — falta medir onde.

Impacto no projeto, se "tudo vira macro":

| Bloco | Macros | Área em macro | Área em FF | Razão |
|---|---|---|---|---|
| Spiral (`memMod`) | 16 × 1rw1r 32×16 | 942.816 µm² | 157.338 µm² | **6,0×** |
| Ping-pong | 8 × 1rw 32×16 | 349.304 µm² | 179.814 µm² | **1,9×** |

O Spiral piora ainda mais porque usa só 8 ou 4 das 16 palavras.
Só as macros do Spiral somariam **~3,3× a macro de 4 kB** e **7× a
lógica inteira do SoC anterior**.

**Vira slide?** Sim — é a figura central do projeto: µm²/bit contra
profundidade, com o flip-flop como linha horizontal.

### 🐛 O DRC da macro 1rw escala com o número de bitcells

| | Bitcells (aprox.) | DRC | DRC por bitcell |
|---|---|---|---|
| 1rw 4 kB | 129 × 257 ≈ 33.150 | 394.613 | 11,9 |
| 1rw 32×16 | 17 × 33 ≈ 561 | 7.259 | 12,9 |
| 1rw1r 32×16 | — (`bitcell_2port`) | **0** | 0 |

Número de erros praticamente proporcional ao número de células
`bitcell_1port`, e **zero** na versão 2-port, que usa outra célula.
**Hipótese:** as violações estão na bitcell de 1 porta do sky130
(célula da foundry, desenhada com regras próprias de SRAM que o DRC
padrão do Magic não reconhece), não na periferia gerada pela OpenRAM.
**A confirmar** abrindo o relatório de DRC e vendo onde as violações
caem.

Se confirmado, muda a leitura dos "394 mil erros" do projeto anterior:
não é macro quebrada, é regra de SRAM avaliada com o deck de lógica.

### LVS: 2 e 3 erros, padrão estável

1rw: 3 erros (igual à 4 kB). 1rw1r: 2 erros. O log da 4 kB já mostrava
`sky130_fd_bd_sram__sram_sp_colend ... disconnected node: bl, vdd, gnd`.
**Pendente:** ler os `.lvs.report` (ficam em `/tmp`, somem no reboot).

---

## 2026-09-19 (2ª sessão) — Relatórios de DRC/LVS e quantas macros de verdade

### DRC: a periferia está limpa

Os `.drc.out` só trazem o total, sem localizar. Mas a **lista de células
carregadas** já separa as duas macros:

| | Periferia (dff, sense amp, write driver, decodificador, controle) | Bitcell | DRC |
|---|---|---|---|
| 1rw1r 32×16 | células `openram_*` | `openram_dp_cell` (desenhada pela OpenRAM) | **0** |
| 1rw 32×16 | **as mesmas** células `openram_*` | `sram_sp_cell_opt1`, `colend`, `wlstrap`, `corner`… (**da foundry**) | 7.259 |

A periferia é a mesma família nas duas e dá zero na 1rw1r. **O que só a
1rw tem são as células de SRAM da foundry.** Somado à proporção de
~12 erros por bitcell (entrada anterior), a hipótese fica bem apoiada.
Nota: o `run_drc.sh` carrega essas células de `maglef_lib` e acusa
*timestamp mismatch* nelas.

Para confirmar por contagem direta: abrir a macro no Magic e rodar
`drc listall count` por célula. Baixa prioridade.

### LVS: mesma contagem de transistores, classificação diferente

| | Layout (circuito 1) | Esquemático (circuito 2) |
|---|---|---|
| 1rw 32×16 | 515 `nfet_01v8` | 429 `nfet_01v8` + **86 `special_nfet_01v8`** |
| 1rw1r 32×16 | 703 `nfet_01v8` | 544 `nfet_01v8` + **159 `special_nfet_01v8`** |
| Total de dispositivos | 6.043 / 1.553 | 6.043 / 1.553 ✅ iguais |

**Não falta nem sobra transistor.** O esquemático da OpenRAM chama parte
deles de `special_nfet` (dispositivo de SRAM do sky130, que exige camada
marcadora); a extração do layout não enxerga a marcação e chama de
`nfet` comum. Aparece até no `control_logic_rw` (52 `special_nfet`).
Somam-se redes `vdd_uqN` "sem par" (vdd fragmentado dentro das
subcélulas). Na 1rw1r, o `clk0 ↔ clk1` trocado no topo é efeito
colateral: com os netlists diferentes, o Netgen não desempata a simetria
("Port matching may fail to disambiguate symmetries").

**Leitura:** o LVS falha por **classificação de dispositivo**, não por
conexão errada. Documentar; não é bloqueio para o fluxo.

### ❓ Pergunta do Lukas: por que 16 macros no Spiral e 8 no ping-pong?

A resposta é **porta, não tamanho.** Uma macro 1rw1r faz no máximo
1 escrita + 1 leitura por ciclo.

**Spiral: 16 é o mínimo.** Não é uma memória partida em 16 — são 16
memórias que trabalham **ao mesmo tempo, em todo ciclo**:
- 8 blocos de permutação (`perm*`), cada um num estágio diferente do
  pipeline, todos ativos juntos.
- Cada bloco recebe **2 elementos por ciclo** e os distribui em 2 bancos
  (`inBank = addr[2] ^ addr[0]`, em `perm6807.v`) justamente para que
  cada banco receba só 1 escrita e 1 leitura por ciclo.

Juntar dois `memMod` exigiria 2 escritas + 2 leituras na mesma macro. A
OpenRAM no sky130 só tem célula de 1 e de 2 portas; mais que isso cai no
`pbitcell` genérico, com densidade pior. **É a arquitetura de FFT em
streaming: a memória é distribuída pelos estágios.**

**Ping-pong: dá para cair de 8 para 2 — mas não para 1.** Eu tinha
escolhido 8 macros 1rw de 32 bits. Usando palavra de **64 bits**:

- Macro `M[paridade da linha]`, endereço `{banco, linha>>1, coluna>>1}`
  (32 palavras), dado = `{coluna par, coluna ímpar}`.
- **Escrita** (colunas `2c` e `2c+1` da mesma linha) = 1 palavra de
  64 bits em **uma** macro.
- **Leitura** (linhas `2p` e `2p+1` da mesma coluna) = 1 palavra em
  **cada** macro.
- A macro que recebe a escrita também recebe uma leitura → **1rw1r**.

1 macro só exigiria 1 escrita + 2 leituras por ciclo: não existe.

**A mesma ideia vale para os buffers:** `in_mem` (64×64) e `out_mem`
(256×64) viram **1 macro de 64 bits cada**, e não 2 de 32. A OpenRAM
aceita palavra de 64 (há config oficial `sky130_sram_4kbyte_1rw_64x512_8`).

**Vira slide?** Sim: "o número de macros é ditado pelo número de acessos
por ciclo, não pelo número de bits."

### Próxima medição (`spiral_min_v2`)

| Teste | Config | Para |
|---|---|---|
| D | 1rw1r 64×32 | Ping-pong (2 macros) |
| E | 1rw1r 64×64 | `in_mem` |
| F | 1rw1r 64×256 | `out_mem` |

Referências em flip-flop: ping-pong 179.814 µm² (2 macros D teriam que
somar menos que isso), `in_mem` 179.814 µm², `out_mem` 719.258 µm².
O script agora copia os relatórios do `/tmp` sozinho.

---

## 2026-09-19 (3ª sessão) — Testes D, E, F: a FIFO de saída compensa; D e E quebram no roteador

### Números

| Teste | Tempo | Linhas × colunas | Resultado |
|---|---|---|---|
| D — 1rw1r 64×32 (ping-pong) | 286 s | 32 × 64 | ❌ roteamento de alimentação |
| E — 1rw1r 64×64 (`in_mem`) | 498 s | 64 × 64 | ❌ roteamento de alimentação |
| F — 1rw1r 64×256 (`out_mem`) | **8.627 s (2 h 24 min)** | 128 × 128 | ✅ **296.939 µm²**, 747,12 × 397,445 µm, DRC 2, LVS 3 |

### ✅ A FIFO de saída: primeira memória da ISFFT em que a macro ganha

| | Área (µm²) | µm²/bit |
|---|---|---|
| `out_mem` em flip-flop (estimado) | 719.258 | 43,9 |
| `out_mem` em macro 1rw1r 64×256 | **296.939** | **18,1** |

**Macro = 0,41× o flip-flop** (2,4× menor). É a memória mais cara da
ISFFT e a macro compensa com folga.

Tempo: 2 h 24 min para 16 kbits em 1rw1r, contra 3 h 53 min para
32 kbits em 1rw. Planejar as rodadas grandes para a madrugada.

### 🔑 Modelo de custo: periferia fixa + custo por bit

Com dois pontos 1rw1r (B: 512 bits, F: 16.384 bits):

```
área ≈ P + k · bits      k ≈ 15,0 µm²/bit      P ≈ 51.200 µm²
```

**~51 mil µm² de custo fixo** (decodificador, amplificadores, controle,
anel) antes do primeiro bit. O flip-flop não tem custo fixo e custa
43,9 µm²/bit. **Ponto de equilíbrio ≈ 1.800 bits.**

| Memória | Bits | Modelo prevê | Flip-flop | Veredito previsto |
|---|---|---|---|---|
| `memMod` do Spiral (16×) | 512 cada (256 ou 128 usados) | medido: 58.926 | 5.619–11.238 | ❌ perde 5–10× |
| Ping-pong (2 macros) | 2.048 cada | ~82.000 cada → ~164.000 | 179.814 | ≈ empate |
| `in_mem` | 4.096 | ~112.700 | 179.814 | ✅ ganha (~0,63×) |
| FIFO do SLINK (2×) | 2.368 cada | ~86.800 cada | ~104.000 cada | ✅ ganha pouco |
| `out_mem` | 16.384 | medido: 296.939 | 719.258 | ✅ ganha (0,41×) |

Ressalva: são **dois pontos** e larguras diferentes (32 e 64 bits); a
periferia também cresce com o número de colunas. Os testes G e H servem
para **validar a previsão**.

**Vira slide?** Sim — "o custo fixo da macro": uma reta com intercepto
contra uma reta pela origem, e o cruzamento em ~1.800 bits.

### 🐛 D e E: `Couldn't route from (vdd layer=m3 ...)`

```
D: ... (vdd m3 ll=v[214.535,-38.355]) to (vdd m3 ll=v[214.995,-27.085])
E: ... (vdd m3 ll=v[28.115,-38.355])  to (vdd m3 ll=v[28.115,-27.085])
```

O roteador de alimentação (`compiler/router/supply_router.py`) não
achou caminho entre dois pinos de vdd em m3 **na mesma faixa**, de
y ≈ −38 a y ≈ −27, logo abaixo do arranjo. Mesmo lugar nos dois.

**O que D e E têm em comum e F e B não:** 64 bits com **1 palavra por
linha** (64 colunas). O F tinha 2 palavras por linha (128 colunas); o B,
32 bits. **Hipótese:** essa geometria específica bloqueia o anel.

**Tentativa (testes G e H):** mesmas memórias com `words_per_row = 2`
forçado (a OpenRAM respeita o valor quando dado na config). Reserva,
se falhar: testes I e J com alimentação em pinos laterais
(`supply_pin_type = "left"`) em vez de anel.

### DRC 2 na F

A 1rw1r 32×16 deu 0; a 64×256 deu **2**. Poucos o bastante para serem
reais e localizáveis. Pendente: abrir no Magic e ver onde estão.

---

## 2026-09-19 (4ª sessão) — G e H: o roteador resolvido e o modelo corrigido

### Números

| Teste | Tempo | Linhas × colunas | Área (µm²) | LEF (µm) | Proporção | DRC | LVS |
|---|---|---|---|---|---|---|---|
| G — 1rw1r 64×32, 2 palavras/linha | 2.835 s | 16 × 128 | **127.404** | 722,88 × 176,245 | 4,1 : 1 | 2 | 3 |
| H — 1rw1r 64×64, 2 palavras/linha | 3.432 s | 32 × 128 | **152.932** | 735,8 × 207,845 | 3,5 : 1 | 2 | 3 |

### ✅ Hipótese do roteador confirmada

Mesmas memórias de D e E, só com `words_per_row = 2`: as duas fecharam.
**O anel de alimentação da OpenRAM falha com macro 1rw1r de 64 bits e
1 palavra por linha** (64 colunas). Com 128 colunas, passa. Os testes
I e J (pinos laterais) não foram necessários.

**Regra prática para o projeto:** macro de 64 bits → forçar
`words_per_row = 2`.

### 🐛 Meu modelo de custo estava errado

Eu previ ~82.000 µm² para G e ~112.700 para H. Deu **127.404** e
**152.932** (+55% e +36%). **Causa:** misturei um ponto de 32 bits (B)
com um de 64 bits (F); a periferia de uma macro de 128 colunas é bem
maior que a de 32.

Refeito só com os três pontos 1rw1r de 64 bits e 2 palavras por linha
(G, H, F):

```
área ≈ 103.900 µm² + 11,8 µm²/bit        (erro ≤ 0,5% nos três pontos)
```

| | Bits | Medido | Modelo | Erro |
|---|---|---|---|---|
| G | 2.048 | 127.404 | 128.043 | +0,5% |
| H | 4.096 | 152.932 | 152.186 | −0,5% |
| F | 16.384 | 296.939 | 297.046 | 0,0% |

**Ponto de equilíbrio contra o flip-flop (43,9 µm²/bit): ~3.200 bits.**
Abaixo disso, a periferia de ~104 mil µm² não se paga.

**Vira slide?** Sim — e o erro também: "dois pontos de famílias
diferentes não fazem uma reta".

### Veredito por memória, medido

| Memória | Bits | Macro | Flip-flop | Macro ÷ FF | |
|---|---|---|---|---|---|
| IMEM / DMEM 4 kB | 32.768 | 284.139 (1rw) | 1.438.515 | **0,20×** | ✅ macro |
| `out_mem` | 16.384 | 296.939 | 719.258 | **0,41×** | ✅ macro |
| `in_mem` | 4.096 | 152.932 | 179.814 | **0,85×** | ✅ macro, por pouco |
| Ping-pong (2 macros) | 2 × 2.048 | 254.808 | 179.814 | **1,42×** | ❌ flip-flop |
| FIFO do SLINK (cada) | 2.368 | ~131.800 (modelo) | 103.955 | ~1,27× | ❌ flip-flop |
| Spiral (16 macros) | 16 × 512 | 942.816 | 157.338 | **6,0×** | ❌ flip-flop |

Memórias da ISFFT somadas:

| Estratégia | Área | Macros |
|---|---|---|
| Tudo em flip-flop | 1.236.224 µm² | 0 |
| **Tudo em macro** | **1.647.495 µm²** (1,33× o FF) | 20 |
| **Macro onde compensa** (`out_mem`, `in_mem`) | **787.023 µm²** (0,64× o FF) | 2 |

"Tudo em macro" fica **33% maior** que não usar macro nenhuma. "Macro
onde compensa" fica **36% menor** — e com 18 macros a menos para
posicionar no layout.

### ⚠️ Macros de 64 bits são largas e baixas

Todas têm ~720–750 µm de largura (128 colunas de célula 2-port), com
proporção de até 4:1. A macro 1rw de 4 kB também é larga (808 µm). No
floorplan isso favorece **empilhar as macros na vertical**, numa faixa
de ~810 µm de largura.

### DRC 2 e LVS 3: padrão fixo com 2 palavras por linha

| Macro | Palavras/linha | Mux de coluna | DRC | LVS |
|---|---|---|---|---|
| B 32×16 | 1 | não | 0 | 2 |
| F, G, H (64 bits) | 2 | **sim** | **2** | **3** |

Os mesmos 2 erros de DRC aparecem nas três macros com multiplexador de
coluna, qualquer que seja o tamanho, e nunca na que não tem. **Hipótese:**
os 2 erros estão no `column_mux_array` (ou na ligação dele). A confirmar
no Magic.

---

## 2026-09-19 (5ª sessão) — ✅ D26 decidido; primeiro RTL: IMEM e DMEM com macro

**Decisão do Lukas:** macro só onde compensa (D26). Proposta atualizada
no topo do diário.

### Projeto novo: `asic/`

```
asic/
├── macros/sram_4kbyte_1rw_32x1024_8/   .v .lef .lib .gds .html (rodada back-end)
├── rtl/mem/sram4k_1rw.v                interface normalizada da macro
├── rtl/neorv32_imem.v                  substituto da IMEM (Replaceable Module)
├── rtl/neorv32_dmem.v                  substituto da DMEM
├── tb/tb_mem_equiv.v                   DUT x VHDL oficial
└── sim/run_tb_mem.sh                   referência, simulação e mutações
```

**`sram4k_1rw.v`** — esconde a macro atrás de uma interface limpa
(`cs`, `we`, `ben`, `addr[9:0]`, dados de 32 bits). Por padrão usa a
interface de **33 bits + `spare_wen0`**, igual à `.v` e à `.lef` (D17).
Para o Genus, que só lê o `.lib`, `-define SRAM_LIB_VIEW`.

**`neorv32_dmem.v` / `neorv32_imem.v`** — mesma entidade do VHDL
(`AWIDTH`, `OUTREG`, `INITROM`), handshake copiado do VHDL
(`wrack` incluído), saída zerada fora do `ack`. Com `INITROM = 1` a
IMEM se comporta como ROM: escrita não altera nem recebe `ack`.

**Checagem que falha na elaboração, não só na simulação:** `AWIDTH ≠ 12`
ou `OUTREG ≠ 0` instanciam um módulo inexistente com o motivo no nome
(`ERRO_neorv32_dmem_macro_so_suporta_AWIDTH_12`). Resolve a pendência
antiga do `$fatal`, que o Genus ignora.

### Verificação: a referência é o próprio VHDL do NEORV32

O script roda `ghdl synth` em `neorv32_dmem.vhd` e `neorv32_imem.vhd`
com os mesmos generics e renomeia o resultado para `ref_mem`. **Nenhum
modelo escrito à mão:** o DUT é comparado com o código oficial.

| Configuração | Leituras | Escritas | Bytes comparados | Resultado |
|---|---|---|---|---|
| DMEM | 9.916 (8.676 parciais) | 10.084 (9.447 parciais) | 24.480 | ✅ |
| IMEM como RAM | 9.916 | 10.084 | 24.480 | ✅ |
| IMEM como ROM (imagem padrão, 199 palavras) | 9.915 | 10.085 (sem `ack`) | 24.539 | ✅ |

Mais 1.024 escritas de preenchimento e 2.000 acessos em rajada (strobe
em todo ciclo) por configuração. Endereços com bits altos aleatórios em
25% dos acessos (a memória deve ignorá-los).

### Mutações: as 4 detectadas

| Mutação | Detectada por |
|---|---|
| Sem `wrack` (o bug do exemplo oficial) | `ack dut=0 ref=1` |
| Ignora `ben` na escrita | leitura seguinte difere |
| Sem portão de saída | `dado fora de leitura: dut=xxxxxxxx` |
| ROM aceita escrita | leitura seguinte difere |

### 🐛 Bug do exemplo oficial confirmado por simulação

O `rtl/verilog/modules/neorv32_dmem.v` do NEORV32, rodado no **mesmo**
testbench:

```
[130000] ERRO handshake: ack dut=0 ref=1
```

Falha na **primeira escrita** (130 ns). O que era leitura de código
(3ª sessão) agora é fato medido. Vale abrir uma issue no repositório do
NEORV32 com esse log.

### ⚠️ Diferença conhecida em relação à ROM do VHDL

A ROM do VHDL usa só os bits de endereço necessários para a imagem
(`index_size_f(image_size_c)`): acima dela, **espelha** a imagem. A
macro tem 1024 palavras de verdade: acima da imagem, devolve o que
estiver lá. O testbench só lê dentro da imagem. Firmware correto nunca
lê fora dela — registrado, não corrigido.

### 🐛 Primeira rodada no notebook: dois tropeços

1. **`ghdl: command not found`.** O terminal ainda tinha o
   `env_openram.sh` carregado das rodadas da OpenRAM, e ele **tira o OSS
   CAD Suite do PATH** de propósito (armadilha já registrada no projeto
   anterior). Resolvido abrindo um terminal novo. O script agora confere
   `ghdl`, `iverilog`, `vvp` e o suporte a `synth` antes de começar, e diz
   o que fazer.
2. **`Unable to bind wire/reg/memory 'seed'`.** Erro meu no testbench: a
   tarefa `pulso` usava `seed`, declarada depois dela. O Icarus 12 do
   Ubuntu aceitou; o do OSS CAD Suite exige declaração antes do uso — e
   está certo. **Lição:** testar com a mesma ferramenta de quem vai rodar.

O script classificou corretamente os dois casos de erro de compilação
das mutações como "mutação inválida" em vez de "detectada".

### ✅ Confirmado no notebook (OSS CAD Suite)

`ghdl` e `iverilog` de `/tools/oss-cad-suite/bin`. **Resultado idêntico
ao da nuvem, número por número** (9.916 leituras, 24.480 bytes
comparados, mesmas 4 mutações com as mesmas mensagens): o estímulo é
determinístico pela `SEED`, e duas instalações diferentes de GHDL e
Icarus chegaram ao mesmo veredito.

### Ferramentas

`ghdl` 4.1 (com `synth`) e `iverilog` 12. Rodando no notebook com o
OSS CAD Suite: `NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_mem.sh`
(~7 s).

---

## 2026-09-19 (6ª sessão) — Macro de 8 kB para a IMEM

**Decisão do Lukas:** gerar uma macro de **8 kB** para a IMEM e seguir
o trabalho enquanto ela roda. Motivo: o firmware da Kria tinha 4.428 B
de `.text` e vai ser reescrito; 4 kB é apertado demais para arriscar.

Config: `asic/openram/sram_8kbyte_1rw_32x2048_8.py` — mesma receita da
de 4 kB (1rw, escrita por byte, spare row/col obrigatórias), só
`num_words = 2048`. Roda em segundo plano com `run_8kb.sh` (`nohup`).
Estimativa: 8–10 h (a de 4 kB levou 3 h 53 min).

**Ponto de parada conferido (notebook):**

```
Using bitcell: bitcell_1port
Rows: 256 Cols: 256
```

Célula certa. Mesma largura da de 4 kB (256 colunas = 8 palavras por
linha) com o **dobro de linhas** (128 → 256): a macro deve sair com a
mesma largura (~809 µm) e mais alta. Com 256 colunas o anel de
alimentação fechou na de 4 kB, então o risco do teste D/E não se aplica.

**Madrugada de 20/09, 02:15 — ainda gerando.** Etapa: extração do
layout para o LVS (`run_ext.sh`, Magic), com **5 h só nessa etapa**
(18.423 s). Processo saudável: `magicdnull` a ~91% de CPU (1 núcleo),
2,5 GB de RAM, swap zerado, 16 GB livres. Não é travamento — é a
extração crescendo mais que linearmente com o tamanho.

⚠️ A OpenRAM só grava `.gds`/`.lef`/`.lib` **depois** do DRC/LVS:
interromper agora perde tudo. **Plano B** se não fechar: rodar de novo
com `check_lvsdrc = False` — o DRC/LVS da macro já tem causa conhecida
(células da foundry e classificação de dispositivos), e o que importa é
o DRC/LVS do chip inteiro, no LibreLane.

**Como acompanhar:** `pgrep -af sram_compiler` (vazio = terminou) e
`grep -E "^fim:|ERROR" log-8kb-backend.txt`. No Nix o Magic roda como
`magicdnull`: `ps -C magic` não o encontra, usar `pgrep -af magic`.

Enquanto isso, o SoC continua com a IMEM de 4 kB — a troca é só o
`AWIDTH` (12 → 13) e o nome da macro. A DMEM fica em 4 kB (`.bss` de
256 B + pilha).

---

## 2026-09-19 (7ª sessão) — ✅ Primeiro "olá": NEORV32 rodando das macros

Enquanto a macro de 8 kB gera no notebook, o SoC foi montado com a
IMEM de 4 kB.

### O que entrou

| Arquivo | Papel |
|---|---|
| `rtl/soc/neorv32_asic.vhd` | Wrapper de conversão: `neorv32_top` com a configuração do ASIC + `xbus2axi4_bridge` |
| `sim/convert.sh` | VHDL → **um Verilog** (`build/neorv32_asic.v`) com `ghdl synth`, IMEM/DMEM excluídas |
| `sw/hello/` | Firmware de teste (UART, DMEM em palavra/meia/byte, `mcycle`) |
| `tb/tb_soc.v` | Carrega o firmware na macro da IMEM, decodifica a UART, encerra em `#FIM#` |
| `sim/run_tb_soc.sh` | Converte, compila o firmware e simula |

**Configuração no wrapper** (diferenças para a Kria, cada uma com a
decisão ao lado no próprio arquivo): 50 MHz, `BOOT_MODE_SELECT = 2`
(IMEM ROM), IMEM e DMEM de 4 kB, `CPU_RF_ARCH_SEL = 2`, UART0 com FIFOs
de 1, DMA ligado, SLINK com FIFOs de 64. Portas para fora: UART0,
**AXI4-Lite** (para a ISFFT) e **SLINK**.

A ponte AXI está **dentro** do wrapper, porque é VHDL: a conversão sai
com a interface AXI4-Lite pronta, e `rlast = '1'` fica amarrado ali
(D16).

### Conversão

```
saida: build/neorv32_asic.v (31.114 linhas, 32 modulos)
neorv32_imem #(.AWIDTH(12), .INITROM(1'b1), .OUTREG(1'b0)) ...   <- caixa-preta
neorv32_dmem #(.AWIDTH(12), .OUTREG(1'b0)) ...                   <- caixa-preta
```

As duas memórias saem como caixas-pretas com os parâmetros certos, e
nenhum módulo `neorv32_imem`/`neorv32_dmem` vindo do VHDL (o script
confere). `INITROM` chega como `1'b1`; nosso `(INITROM != 0)` trata.

### Resultado

```
[TB] IMEM[0..2] = 0f14020f3 080001217 0ffc20213
[UART] Ola do NEORV32 com IMEM/DMEM em macro OpenRAM!
[UART] clk = 0x02faf080 Hz               <- 50.000.000
[UART] DMEM erros = 0x00000000
[UART] 100 nops = 0x000003ea ciclos      <- 1.002
[UART] RESULTADO: OK
[TB] fim em 14.369 ms (718473 ciclos)
[TB] PASSOU
```

**Busca de instrução na macro da IMEM, leitura/escrita de palavra,
meia-palavra e byte na macro da DMEM e UART funcionando — no Verilog
convertido, que é o que vai para Genus e LibreLane.**

`100 nops = 1.002 ciclos`: ~10 ciclos por volta do laço (`nop` + `addi`
+ `bne`). Sem cache, cada instrução passa pelo barramento até a macro.
Número de referência para comparar depois.

### 🐛 Três tropeços no caminho

1. **O "olá" com `printf` não cabe em 4 kB.** O linker acusou
   `region 'rom' overflowed by 32 bytes` — graças ao `rom_size=4k` no
   makefile. Trocado por uma impressão hexadecimal mínima: `.text` caiu
   para **3.240 B**. Confirma na prática a decisão D27 (8 kB).
2. **O modelo da OpenRAM imprime todo acesso** (`VERBOSE = 1`). Com a CPU
   buscando instrução a cada ciclo, a simulação ficava presa escrevendo
   log. Resolvido com `defparam ... VERBOSE = 0` no testbench.
3. **Saída bufferizada:** `vvp | grep` só mostrava o texto no fim.
   `grep --line-buffered` + `$fflush` no testbench.

### ✅ Confirmado no notebook

Mesmo resultado, **ciclo por ciclo**: `fim em 14.369 ms (718473 ciclos)`,
mesmas linhas de UART. Simulação levou **101 s** no notebook (147 s na
nuvem).

Uma diferença inofensiva: o Verilog convertido saiu com **30.185 linhas**
no notebook e **31.114** na nuvem — versões diferentes do GHDL (OSS CAD
Suite × Ubuntu) formatam a saída de jeitos diferentes. Mesmos 32
módulos, mesmas caixas-pretas, e o comportamento idêntico até o último
ciclo prova que o circuito é o mesmo.

### Custo de simulação

718.473 ciclos em 147 s ≈ **4.900 ciclos/s** no Icarus. Aceitável para
firmwares curtos; para a ISFFT com várias matrizes, vale considerar o
Verilator (o `Makefile` oficial do NEORV32 já suporta).

### Versão do NEORV32

A árvore `rtl/core` da Kria é idêntica, arquivo por arquivo, ao commit
**`8bdbe48`** do NEORV32 (6/set/2026, versão 1.13.5.6). Usado para o
`sw/` do firmware na nuvem. Toolchain: xPack `riscv-none-elf-gcc`
15.2.0, a mesma do notebook.

---

## 2026-09-19 (8ª sessão) — Conversores SLINK ↔ ISFFT (32 ↔ 64 bits)

### Macro de 8 kB: ponto de parada ok

`bitcell_1port` e `Rows: 256 Cols: 256` (ver 6ª sessão). Rodando.

### O desenho: o `last` do SLINK vira o `tlast` da ISFFT

Plano anterior: o conversor contaria 32 palavras e geraria o `tlast`
sozinho (exigia `PKT_MAT = 1`). **Trocado por algo mais simples e mais
fiel:** o conversor só repassa o `last`.

- O SLINK marca `last` pelo **endereço** da escrita: `DATA` (+0x8) ou
  `DATA_LAST` (+0xC).
- O DMA do NEORV32 aceita **vários descritores na fila** (4). O firmware
  enfileira dois: **63 palavras → `DATA`** e **1 palavra → `DATA_LAST`**.
  Zero trabalho da CPU, e o `tlast` sai exatamente na última palavra.
- Consequências boas: `PKT_MAT` volta a funcionar com qualquer valor, e
  dá para **testar o rollback da ISFFT** (pacote truncado) pelo firmware,
  como na Kria.

| Bloco | Faz | Ordem das metades |
|---|---|---|
| `rtl/isfft/stream_32to64.v` | SLINK TX → `s00_axis` | 1ª palavra → `[31:0]`, 2ª → `[63:32]` |
| `rtl/isfft/stream_64to32.v` | `m00_axis` → SLINK RX | `[31:0]` sai primeiro, `tlast` na 2ª metade |

A ordem é a mesma em que o AXI DMA da Kria lia/escrevia a DDR
(little-endian): **a matriz fica na DMEM com o mesmo formato que tinha na
DDR** — o modelo Python e os vetores de teste da Kria continuam valendo.

`last` numa palavra ímpar (erro do firmware): a metade sai sozinha com
`[63:32] = 0` e `tlast`. A ISFFT acusa erro de `tlast` — comportamento
desejado.

Vazão: 1 palavra de 32 bits por ciclo nos dois sentidos, sem bolha.

### Verificação: `sim/run_tb_stream.sh`

| Bancada | Estímulo | Resultado |
|---|---|---|
| A: 32 → 64 | 20.000 palavras, `valid` 70%, `ready` 60%, 136 pacotes ímpares | ✅ 10.068 palavras de 64 |
| B: 64 → 32 | 20.000 palavras, `tlast` aleatório | ✅ 40.000 palavras de 32 |
| C: 32 → 64 → 32 | volta completa, pacotes pares | ✅ saída idêntica à entrada |

Mutações — as 4 detectadas: metades trocadas, `ready` de saída
ignorado, `last` na 1ª metade, e `s_ready` que perde dado no fim da
palavra.

### 🐛 O testbench estava errado antes do RTL

Primeira rodada: A e C "falhando" com palavras **duplicadas**. O RTL
estava certo; o gerador decidia trocar de palavra olhando o `ready` na
**descida** do clock — mas nessa mesma descida ele sorteava o novo
`ready` de saída, do qual o `s_ready` depende. Resultado: trocava uma
palavra que não tinha sido aceita. Corrigido: a fonte só avança se o
handshake **aconteceu na subida** (flags `*_ok`).

**Notebook (OSS CAD Suite): resultado idêntico** — mesmas contagens
(10.068 / 40.000 / 20.000, 136 pacotes ímpares) e as mesmas 4 mensagens
de mutação.

**Lição que vale slide:** as 4 mutações "passaram" como detectadas
também com o testbench quebrado — ele acusava erro em tudo. **Mutação
só prova algo quando a versão correta passa.** Por isso o script roda a
versão correta primeiro e só considera as mutações se ela passar.

---

## 2026-09-19 (9ª sessão) — ✅ Chip inteiro: DMEM → DMA → SLINK → ISFFT → SLINK → DMA → DMEM

### O que entrou

| Arquivo | Papel |
|---|---|
| `rtl/soc/asic_top.v` | Topo do chip: `neorv32_asic` + conversores + `isfft_axi_v3`, com janela de endereço da ISFFT |
| `rtl/isfft/core/*.v` | RTL da ISFFT da Kria, **sem alteração** (58 arquivos) |
| `sw/isfft_dma/` | Firmware: 2 matrizes pelo caminho DMA + SLINK, imprime `CHK <m> <soma>` |
| `tb/tb_top.v` | Chip inteiro + **segunda `isfft_axi_v3` como referência** |
| `sim/run_tb_top.sh` | Converte, compila e simula (`DEBUG=1` liga o monitor) |

### Resultado

```
[UART] CHK 0 0xb7a05c22 ciclos 0x00000a3e
[TB] matriz 0: soma na DMEM = referencia (0xb7a05c22)
[UART] CHK 1 0xa4176d8c ciclos 0x00000a3e
[TB] matriz 1: soma na DMEM = referencia (0xa4176d8c)
[UART] MAT_IN 0x00000002 MAT_OUT 0x00000002 ERR 0x00000000
[TB] palavras de 64 bits: entrada 64, saida chip 64, ref 64, comparadas 64
[TB] PASSOU
```

**O que isso prova:** a saída da ISFFT do chip é idêntica, palavra por
palavra, à de uma ISFFT de referência que recebeu as mesmas entradas; e
o que **chegou na DMEM** (soma calculada pelo firmware) é idêntico à
saída da referência. Contadores da ISFFT: 2 matrizes entrando, 2 saindo,
0 erros de `tlast` — o `last` do SLINK virou `tlast` no lugar certo.

**O que isso NÃO prova:** a matemática da ISFFT. A referência é o mesmo
RTL — só o encanamento novo está sendo verificado. A matemática foi
validada na Kria por EVM; falta repetir aqui com os vetores e o modelo
Python da Kria.

**Tempo por matriz: 2.622 ciclos (0xa3e)** — DMA de ida (64 palavras),
ISFFT, espera da FIFO RX, DMA de volta (64 palavras). ≈ 52 µs a 50 MHz.
Número de referência para otimizar depois.

### Janela de endereço da ISFFT (D31)

A ISFFT é o único escravo externo, mas o topo **só repassa o handshake
se o endereço cai em `0x4001_0xxx`**. Fora dela a transação não termina,
o XBUS estoura o timeout (2.048 ciclos) e a CPU recebe **erro de
barramento** — em vez de acessar a ISFFT espelhada por engano. Seguro
porque a ponte segura o endereço num registrador durante toda a
transação e limpa a FIFO de dados quando o XBUS desiste. Bônus: os bits
altos do endereço passam a ser usados, e a síntese não os poda (a
lição da poda no projeto anterior).

### 🐛 A fila do DMA só cabia UM descritor (D30)

**Sintoma:** com o monitor (`DEBUG=1`), entraram 31 palavras de 64 bits
(62 de 32) e tudo parou. Faltavam as 2 últimas — o segundo descritor,
o do `DATA_LAST`, nunca rodou.

**Causa:** no RTL do DMA, `DSC_FIFO : ... (1 descriptor = 3 entries)`.
Com `IO_DMA_DSC_FIFO = 4` (o padrão) cabe **um** descritor. A segunda
chamada a `neorv32_dma_program` achou a fila cheia e devolveu erro — e
o firmware **ignorava o retorno**. Dois erros meus.

**Resolvi com:** `IO_DMA_DSC_FIFO = 8` (2 descritores; +4 entradas de
32 bits em flip-flop) e o firmware agora checa o retorno de cada
`neorv32_dma_program`.

**Vira slide?** Sim: "o valor padrão de um genérico pode não fazer o
que o nome sugere" + "nunca ignorar código de retorno".

### 🐛 Dois tropeços do testbench (não do chip)

1. **Referência atrasada.** A referência recebe cada palavra 1 ciclo
   depois do chip (passa pela fila do testbench); o chip saía na frente e
   o testbench acusava "chip produziu antes da referência". Corrigido:
   as duas saídas são guardadas e comparadas por índice.
2. **Simulação lenta.** Com a ISFFT, o Icarus cai para ~1.650 ciclos/s.
   A UART a 115.200 baud gastava ~3 ms simulados só no título. Firmware
   de teste agora usa **1 Mbaud** (só simulação). Rodada inteira: 85 s.

### 🐛 Achados sobre o material de partida

- **O `isfft_axi_wrapper.v` do pacote não é o wrapper da etapa 1.** É
  uma cópia antiga do próprio `isfft_axi_v3` (difere só na linha do
  atributo `ASSOCIATED_BUSIF` em maiúsculas — a versão de antes da
  correção da Kria). O `tb_isfft_axi_v3.v` precisa do wrapper da etapa 1
  de verdade para rodar. **Pedir ao Lukas.**
- **NEORV32: cabeçalho e RTL do SLINK discordam nos bits de interrupção.**
  RTL (`neorv32_slink.vhd`): 16, 18, 19, 21. Cabeçalho
  (`neorv32_slink.h`): 16, 17, 18, 19. Não nos afeta (usamos polling, bits
  8–12, que concordam), mas é defeito real do commit `8bdbe48`. Candidato
  a issue, junto com o `wrack` da DMEM de exemplo.

---

## 2026-09-23 (10ª sessão) — Macro de 8 kB pronta, regressão da Kria e ✅ EVM no chip

### Macro de 8 kB (IMEM): terminou

| Item | 4 kB (DMEM) | **8 kB (IMEM)** |
|---|---|---|
| Organização | 32 × 1024 | 32 × 2048 (256 linhas × 256 colunas) |
| Tamanho (LEF) | 808,845 × 351,29 µm | **810,845 × 553,53 µm** |
| Área | 284.139 µm² | **448.827 µm²** |
| µm² por bit | 8,67 | **6,85** |
| Macro ÷ flip-flop (43,9 µm²/bit) | 0,20× | **0,16×** |
| Tempo de geração (notebook) | 41 min + 3 h 53 min | **40.348 s ≈ 11 h 12 min** |
| GDS | — | 61 MB |
| DRC (Magic) | 394.613 | 782.645 (1,98×) |
| LVS | 3 | **1** (`LVS mismatch`) |

- **Dobrar a capacidade custou só 58% a mais de área:** a parte fixa
  (decodificadores, amplificadores, anel) se dilui. A largura quase não
  muda (+2 µm); cresce só a altura.
- **DRC dobrou junto com o número de bitcells**, o que confirma a origem:
  são as bitcells de 1 porta da foundry (~12 por célula), não o que a
  OpenRAM monta em volta.
- **LVS 1** (a de 4 kB teve 3): o relatório ainda não foi aberto. A
  suspeita é a mesma classificação `special_nfet_01v8` × `nfet_01v8`, com
  a mesma contagem de dispositivos. Confirmar no `.lvs.report` quando der.
- **Para o layout:** IMEM + DMEM empilhadas somam ≈ 905 µm de altura com
  ≈ 811 µm de largura, antes de `in_mem`/`out_mem`. O die passa de 1 mm.

**Falta:** as vistas `.v`, `.lib`, `.lef` da macro na nuvem (o `.gds` não
precisa) para trocar a IMEM para 8 kB.

### Wrapper da etapa 1 e regressão da Kria

O `isfft_axi_wrapper.v` **da etapa 1** chegou (o do pacote anterior era
cópia do v3). Guardado em `rtl/isfft/ref/` porque **não entra no chip**: só
serve de referência para o `tb_isfft_axi_v3.v`.

| Arquivo | Papel |
|---|---|
| `rtl/isfft/ref/isfft_axi_wrapper.v` | Wrapper da etapa 1: `top_isfft` direto, `tready = 1`, `tlast` a cada 32 palavras |
| `sim/run_tb_isfft_ref.sh` | Roda o `tb_isfft_axi_v3.v` da Kria; `CORE=<pasta>` troca o RTL da ISFFT testada |

```
$ bash sim/run_tb_isfft_ref.sh
Fase 1: gerando referencia com o wrapper da etapa 1...
  referencia: 1280 palavras
Fase 2: wrapper novo com pausas aleatorias...
  injetando pacote truncado (20 palavras com tlast)
PASSOU: 40 matrizes identicas a referencia, tlast e registradores OK
```

4 s de simulação. Mutações no `isfft_axi_v3` (metades da saída trocadas;
ponteiro de leitura do `in_mem` deslocado): **2 de 2 detectadas**.

**Para que serve:** é o gabarito para quando `out_mem` e `in_mem` virarem
macro. A ISFFT com macros roda nesta mesma bancada com
`CORE=<pasta nova>` e precisa sair idêntica ao wrapper da etapa 1.

### ✅ Validação numérica no chip: EVM igual ao da Kria

As 3 matrizes do `processamento_otfs.ipynb` passaram pelo **chip
inteiro**: ROM → DMEM → DMA → SLINK → conversor → ISFFT → conversor →
SLINK → DMA → DMEM. O testbench copia da DMEM o que chegou, e o mesmo
modelo numpy do notebook calcula o EVM.

| Arquivo | Papel |
|---|---|
| `sw/isfft_evm/evm.py` | `gera`: matrizes do notebook → `vetores.h`. `avalia`: EVM contra o modelo e contra a Kria |
| `sw/isfft_evm/main.c` | Firmware `isfft_dma` com as matrizes fixas; imprime `DUMP <m> <endereço>` |
| `tb/tb_top.v` | `+DUMP=<pasta>`: ao ver `DUMP`, grava 64 palavras da DMEM em `saida_<m>.hex` |
| `sim/run_tb_evm.sh` | `gera` → chip inteiro → `avalia` |

```
$ NEORV32_HOME=~/Projects/neorv32 bash sim/run_tb_evm.sh
...
[TB] palavras de 64 bits: entrada 96, saida chip 96, ref 96, comparadas 96
[TB] PASSOU
=== EVM (modelo numpy x saida na DMEM) ===
matriz 1 (Impulso ): EVM 3.4122%   Kria 3.41%   erro medio 0.40   = Kria
matriz 2 (Senoide ): EVM 0.7822%   Kria 0.78%   erro medio 0.10   = Kria
matriz 3 (Rampa   ): EVM 0.5965%   Kria 0.60%   erro medio 0.09   = Kria
EVM: PASSOU
```

Formato igual ao da Kria: palavra de 32 bits = `(imag << 16) | real`
(int16), saída lida com `reshape(8,8).T`, modelo `ifft` nas linhas, `fft`
nas colunas, `/8`. Firmware: 2.692 B de `.text` (cabe na ROM de 4 kB).
Tempo: 2.622 ciclos por matriz, como antes; 124 s de simulação.

**O que isso prova:** o chip calcula a ISFFT com a **mesma precisão
medida no hardware da Kria**, até a segunda casa decimal. Fecha a
pendência deixada na 9ª sessão ("o que isso NÃO prova: a matemática").

**Critério (D32):** o RTL da ISFFT é o mesmo da Kria, então a saída
precisa ser **igual**, não só "EVM baixo". Tolerância de 0,005 ponto
percentual, só para absorver o arredondamento do número da Kria.

Teste negativo do avaliador: saída com real e imaginário trocados dá
EVM ≈ 141% e `FALHOU`.

**Vira slide?** Sim: "EVM do chip = EVM da Kria (3,41 / 0,78 / 0,60 %)".
Uma linha que liga as duas etapas do projeto.

### D28 confirmada: IMEM como ROM (modo 2)

`BOOT_MODE_SELECT = 2`: a CPU começa na IMEM e não pode escrever nela.

| Modo | Como o programa entra | Por que não |
|---|---|---|
| **2 (escolhido)** | `$readmemh` do testbench direto na macro | — |
| 0 (bootloader) | ROM de 3.816 B em portas + upload pela UART | Área extra e simulação lenta; fica para "se der tempo" |
| 1 (endereço externo) | Flash SPI externa | Fora do escopo |

**Limitação assumida:** a IMEM é SRAM (volátil). Um chip fabricado com
este RTL ligaria com a IMEM vazia — **o chip só roda em simulação** (já
era a D8). "ROM" aqui quer dizer só que a CPU não escreve na IMEM.

**Pós-síntese:** o testbench carrega o programa do mesmo jeito. A macro
continua caixa-preta na netlist (o Genus não sintetiza a SRAM), então o
modelo `.v` da OpenRAM entra na simulação e o `mem` dele recebe o
`$readmemh`. Cuidado previsto: o Genus pode achatar a hierarquia e
renomear a instância (ex.: `\neorv32_top_inst/.../u_macro`). O caminho da
macro no testbench vira um `` `define `` passado pelo script, conferido
na netlist antes de simular.

**Vira slide?** Sim, uma linha: "programa carregado pelo testbench (RTL e
pós-síntese); bootloader fica como melhoria".

### 🐛 `rtl/isfft/core` não existia no notebook

**Sintoma:** `run_tb_isfft_ref.sh` → `rtl/isfft/core/*.v: No such file or directory`.
**Causa:** os 58 arquivos da ISFFT foram no `asic_top.tgz` (9ª sessão, com
prefixo `asic/`), que não chegou a ser extraído; o pacote de hoje trazia
só os arquivos novos.
**Resolvi com:** `asic_completo.tgz` — todo o fonte do projeto (sem
`build/`, sem macros, sem `openram/out`), extraído em `~/Projects`.
Daqui para a frente as entregas vão **sempre completas**, com o mesmo
prefixo `asic/`.
**Vira slide?** Não.

**Notebook (OSS CAD Suite), 2026-09-23:** `run_tb_isfft_ref.sh` PASSOU e
`run_tb_evm.sh` PASSOU com os mesmos números (CHK, 0xa3e ciclos, EVM
3,4122 / 0,7822 / 0,5965 %). 82 s de simulação contra 124 s na nuvem.

---

## 2026-09-23 (11ª sessão) — ✅ IMEM de 8 kB no chip

As vistas da macro de 8 kB chegaram (`.v`, `.lib`, `.lef`, `.html`, em
`macros/sram_8kbyte_1rw_32x2048_8/`). A interface é igual à de 4 kB. Só
o endereço cresce: 12 bits, sendo o de cima a linha sobressalente, que
fica em 0. Continuam os 33 bits no `.v`/`.lef` e 32 no `.lib`.

### O que mudou

| Arquivo | Mudança |
|---|---|
| `rtl/mem/sram8k_1rw.v` | **Novo**: cópia da `sram4k_1rw` com endereço de 11 bits e a macro de 8 kB |
| `rtl/neorv32_imem.v` | `AWIDTH = 13` (só aceita 13), `sram8k_1rw`, endereço `req_addr_i[12:2]` |
| `rtl/soc/neorv32_asic.vhd` | `IMEM_SIZE => 8*1024` |
| `sw/*/makefile` | `__neorv32_rom_size=8k` (RAM segue 4k) |
| `sim/run_tb_soc.sh`, `run_tb_top.sh` | Compilam `sram8k_1rw.v` + modelo da macro de 8 kB |
| `tb/tb_mem_equiv.v`, `sim/run_tb_mem.sh` | Largura parametrizada (`MEM_AWIDTH`): DMEM 12, IMEM 13; mutação nova |
| `sw/hello/main.c`, `tb/tb_soc.v` | Volta o `printf` + tabela de 1 kB acima de 0x1000; o tb mostra o maior endereço lido da IMEM |

A DMEM **não mudou**: continua com a `sram4k_1rw` e `AWIDTH = 12`.

### Verificação

| Bancada | Resultado |
|---|---|
| `run_tb_mem.sh` (IMEM contra o VHDL oficial com `AWIDTH = 13`) | ✅ 3 configurações; imem_ram escreve e lê as **2048** palavras |
| Mutações de `run_tb_mem.sh` | ✅ **5/5**, incluindo a nova `imem_4k_addr` (IMEM perde o bit 12 do endereço) |
| `run_tb_soc.sh` (hello, 5.288 B) | ✅ tabela 0x0F00–0x12FC conferida, 0 erros; maior leitura 0x141D |
| Mesma mutação `imem_4k_addr` no SoC inteiro | ✅ detectada: **192 erros**, exatamente as 192 palavras da tabela acima de 0x1000 |
| `run_tb_evm.sh` (chip inteiro) | ✅ EVM 3,4122 / 0,7822 / 0,5965 %, igual à Kria |
| `run_tb_isfft_ref.sh`, `run_tb_stream.sh` | ✅ (não dependem da IMEM; rodados de novo por garantia) |
| Verilog convertido | `neorv32_imem #(.AWIDTH(13), .INITROM(1))`, `neorv32_dmem #(.AWIDTH(12))` |

### 🐛 O firmware de teste não usava a metade de cima

**Sintoma:** com o `printf` de volta, o hello ficou com 4.132 B, acima de
4 kB. Mas o monitor mostrou que o maior endereço lido era **0x0F96**.
**Causa:** o que passava de 0x1000 eram só strings de exceção que nunca
são impressas. Um programa maior que 4 kB **não prova** que a metade de
cima é lida.
**Resolvi com:** uma tabela de 1 kB com padrão conhecido em `.rodata`,
conferida palavra a palavra pelo firmware. Ela cai em 0x0F00–0x12FC. O
teste só vale porque a mutação no SoC (bit 12 perdido) dá exatamente os
192 erros esperados.
**Obs.:** o `.text` do hello termina em 0xB08. O que é lido acima de
0x1000 é dado (a tabela e o `_ctype_` da libc), não instrução. Vale do
mesmo jeito: busca e leitura de dado entram pela **mesma porta** da IMEM,
com o mesmo caminho de endereço.
**Vira slide?** Sim, junto com a lição das mutações: "teste que não
exercita o caminho novo passa sem provar nada".

### Temporização das duas macros (`.lib`)

| | 4 kB | 8 kB |
|---|---|---|
| setup (din, addr, csb, web) | 0,103 ns | 0,103 ns |
| hold | −0,056 ns | −0,056 ns |
| clk → dout | 0,405–0,551 ns | 0,408–0,553 ns |

Quase idênticas **porque o `.lib` vem do modelo analítico**
(`analytical_delay = True`). O próprio datasheet avisa: *"results may
not be precise"*. Na síntese a 50 MHz (20 ns) não pesa. Para a
assinatura final, a caracterização por SPICE fica na lista de "se der
tempo".

### 🐛 Macro de 8 kB fora de `macros/` no notebook

**Sintoma:** `FALTA: .../macros/sram_8kbyte_1rw_32x2048_8/sram_8kbyte_1rw_32x2048_8.v`
no `run_tb_mem.sh`; `No such file or directory` no `run_tb_soc.sh`/`run_tb_evm.sh`.
**Causa:** a OpenRAM grava em `openram/out/`; os scripts leem de
`macros/`. O pacote do projeto não leva `macros/` (de propósito, para não
sobrescrever o notebook).
**Resolvi com:** copiar `.v`, `.lef`, `.gds`, `.html` e `_TT_1p8V_25C.lib` de
`openram/out/sram_8kbyte_1rw_32x2048_8/` para `macros/sram_8kbyte_1rw_32x2048_8/`.
**Regra:** macro pronta vai para `macros/<nome>/` com as 5 vistas, igual à de 4 kB.
**Vira slide?** Não.

**Notebook, depois da cópia:** `run_tb_mem.sh` TUDO OK (5/5 mutações),
`run_tb_soc.sh` PASSOU (tabela 0x0F00–0x12FC, 0 erros; maior leitura
0x141D), `run_tb_evm.sh` PASSOU com EVM igual à Kria. **Idêntico à nuvem.**
Tempos: 97 s (hello) e 84 s (EVM).

### Macros da ISFFT: vêm da rodada de medição

`out_mem` e `in_mem` usam as macros **F** (`sram_1rw1r_64x256`) e **H**
(`sram_1rw1r_64x64_wpr2`), já geradas com back-end em
`neorv32-openram-sky130/openram/spiral_min/out/`. Vão para `macros/` com
as 5 vistas (mesma regra). **Os nomes da OpenRAM ficam:** renomear exige
mudar a célula em `.v`, `.lef`, `.lib` e `.gds`, com risco e sem ganho.

---

## 2026-09-23 (12ª sessão) — ✅ `in_mem` e `out_mem` em macro: `isfft_axi_v4`

### Macros usadas

| Memória | Macro | Tamanho (LEF) | Área |
|---|---|---|---|
| `in_mem` 64 × 64 | H `sram_1rw1r_64x64_wpr2` | 735,8 × 207,845 µm | 152.932 µm² |
| `out_mem` 256 × 64 | F `sram_1rw1r_64x256` | 747,12 × 397,445 µm | 296.939 µm² |

Interface das duas: porta 0 (RW) com `csb0/web0/addr0/din0/dout0`, porta 1
(R) com `csb1/addr1/dout1`, 64 bits, **sem coluna sobressalente** (1rw1r
não precisa). Sem o problema de 33 bits das macros de 1 porta.

⚠️ **Os `.lib` das duas não vieram no pacote** (`.v`, `.lef`, `.html` sim).
Simulação não precisa; o Genus precisa.

### D33: v4 é um módulo novo; a v3 fica intocada

`rtl/isfft/isfft_axi_v4.v` é **cópia da v3** com só as duas memórias
trocadas: o `diff` mostra 119 linhas novas, todas nas duas seções de
memória. A v3 continua em `rtl/isfft/core/` sem alteração e serve de
**referência** (regressão e `tb_top`).

### `in_mem`: leitura 1 ciclo mais tarde, `next_in` junto

| | v3 | v4 |
|---|---|---|
| Escrita | `in_mem[wr] <= tdata` | macro, porta 0 (`csb0 = ~in_hs`) |
| Leitura | `core_x <= in_mem[rd]` (dado em `core_x` no ciclo seguinte) | endereço na porta 1; dado sai da macro no ciclo seguinte e entra em `core_x` no outro (+1) |
| `next_in` do núcleo | combinacional | **registrado** (+1 ciclo) |

O núcleo vê **a mesma sequência (next_in, dado)** da v3, só que 1 ciclo
depois. O dado da macro passa por registrador antes do núcleo: melhor
para a temporização e sem `X` no núcleo (o modelo da OpenRAM põe `X` na
saída depois de cada borda).

### `out_mem`: pré-busca com buffer de 2 palavras

A v3 lia **de forma assíncrona** (`tdata = out_mem[rd_ptr]`). A macro só
tem leitura síncrona. Solução:

```
núcleo → macro (porta 0) ─(porta 1, 1 ciclo)→ ob_q0 / ob_q1 → m00_axis
```

- 3 ponteiros: `out_wr_ptr` (escrita), `ram_rd_ptr` (**busca**),
  `out_rd_ptr` (**entrega**, igual à v3). `out_used`, cheio, reserva e
  STATUS continuam contando o total: **a capacidade não muda** (256).
- Busca quando há palavra na macro **e** lugar no buffer, contando a que
  já está a caminho; a saída no mesmo ciclo libera lugar. Vazão: 1
  palavra por ciclo.
- `tdata` sai de **registrador** (`ob_q0`): bom para a temporização.
- Custo: ~140 flip-flops (2 × 64 do buffer + ponteiro + controle), ≈ 1% da
  área que as macros economizam.

**Conflito leitura × escrita no mesmo endereço** (proibido na macro):
impossível pelos ponteiros. Na `in_mem`, a leitura só pega palavra
confirmada e a escrita só ocorre com `in_used < 64`. Na `out_mem`, a busca
exige `ram_cnt ≠ 0`, e `ram_cnt = 256` só com a FIFO cheia, que bloqueia a
escrita. Conferido no modelo: **0 avisos** de acesso simultâneo nas
simulações (que enchem as duas FIFOs).

### Verificação

| Bancada | Resultado |
|---|---|
| `run_tb_isfft_ref.sh` v3 (Kria) | ✅ 40 matrizes, parada longa, pacote truncado |
| `run_tb_isfft_ref.sh` **v4** (mesmo tb, só o módulo trocado) | ✅ idêntico ao wrapper da etapa 1, registradores OK |
| Mutações da v4 | ✅ **5/5**: `next_in` fora de fase, busca sem limite de ocupação, buffer fora de ordem, busca pelo ponteiro de entrega, `core_x` sem esperar a macro |
| `run_tb_top.sh` (chip com v4 × referência **v3** lado a lado — **D21**) | ✅ 64/64 palavras; somas iguais às da 9ª sessão |
| `run_tb_evm.sh` (chip com v4) | ✅ EVM 3,4122 / 0,7822 / 0,5965 %, igual à Kria |

Ciclos por matriz no firmware: **2.622**, igual à v3. A latência extra
(1 ciclo na entrada, 1–2 na saída) some no polling do firmware.

`run_tb_isfft_ref.sh` ganhou limite de tempo por simulação (30 s; a v4
leva 4 s): a mutação "busca sem limite" **trava** o fluxo, e travar
também conta como detectada.

**Vira slide?** Sim: o desenho da pré-busca (3 ponteiros + buffer de 2)
e "leitura assíncrona → síncrona sem mudar a interface".

### Memórias do chip: todas as macros no lugar

| Memória | Macro | Área |
|---|---|---|
| IMEM 8 kB | `sram_8kbyte_1rw_32x2048_8` | 448.827 µm² |
| DMEM 4 kB | `sram_4kbyte_1rw_32x1024_8` | 284.139 µm² |
| `out_mem` | `sram_1rw1r_64x256` | 296.939 µm² |
| `in_mem` | `sram_1rw1r_64x64_wpr2` | 152.932 µm² |
| **Total** | 4 macros | **1.182.837 µm²** |

Só de macros: ~1,18 mm². Com os LEF, o empilhamento mais simples (duas
colunas de ~811 µm) passa de 1,6 mm de largura. O planejamento do layout
fica para quando a síntese der a área da lógica.

### Diagrama de blocos do chip

`doc/diagrama_chip.png` (e `.svg`), no mesmo padrão do diagrama da Kria:
verde = macro SRAM (OpenRAM), roxo = lógica em células sky130, tracejado
= só no testbench. Gerado por `doc/gera_diagrama.py` (SVG) e
`doc/render_png.py` (PNG pelo Chromium). Para mudar, edite o `.py` e rode
de novo: o desenho fica versionado junto com o RTL.

**Vira slide?** Sim: é o slide da arquitetura, lado a lado com o da Kria.

Versão enxuta para o slide: `python3 gera_diagrama.py simples` →
`doc/diagrama_chip_simples.{svg,png}`. A ISFFT aparece sem detalhe interno
(sem "v4", `in_mem` e `out_mem`), o monitor da UART sem descrição e os
rótulos sem parênteses. `render_png.py` recebe o nome do SVG.

### 🐛 `.lib` das macros F e H não copiado: `$m_TT...` é outra variável

**Sintoma:** em `macros/sram_1rw1r_64x256/` ficaram `.v`, `.lef`, `.gds`,
`.html`, mas **sem o `.lib`** (que existe em `spiral_min/out/`).
**Causa:** erro meu no comando: `$SRC/$m/$m{.v,…,_TT_1p8V_25C.lib}`. O
bash expande as chaves primeiro e sobra `$m_TT_1p8V_25C.lib`. Como `_` e
letras continuam valendo em nome de variável, isso vira a variável
`$m_TT_1p8V_25C` (vazia): o `cp` tentou copiar `…/.lib`.
**Resolvi com:** `${m}_TT_1p8V_25C.lib`.
**Regra:** variável colada em texto que começa com `_` ou letra → sempre
`${nome}`.
**Vira slide?** Não.

---

## 2026-09-23 (13ª sessão) — Pasta da VM e revisão: a simulação de portas achou 3 problemas

**Pedido do Lukas:** montar a pasta da VM no mesmo formato da
`neorv32_sram_soc`, completa (só falta rodar o `run_first.tcl`), e revisar
tudo para não dar erro na síntese nem na simulação pós-síntese.

### A pasta (`sim/monta_vm.sh`)

A pasta é **montada por script** a partir do projeto; os scripts da VM
moram em `vm/` (fonte de verdade). Mudou algo no RTL → roda de novo.

```
neorv32_isfft_soc/
├── LEIAME.md  DIARIO.md
├── frontend/            RTL do chip, só Verilog (neorv32_asic.v gerado pelo GHDL + nosso RTL)
│   └── isfft/           núcleo da ISFFT (57 arquivos; sem a v3)
├── sw/isfft_evm/        firmware das 3 matrizes + chk_rtl.txt (somas do RTL)
├── sw/hello/            firmware da IMEM inteira
├── tech/{lib,lef,verilog}/   sky130 + 4 macros (.lib back-end, .lef, .v)
└── backend/synthesis/
    ├── scripts/         run_first.tcl, neorv32_isfft_soc.tcl, common/{path,tech}.tcl,
    │                    rtl_files.tcl (gerado), _lec.do, tb_gate.v,
    │                    sram_lib_view_model.v, restore_nettype.v
    ├── constraints/     neorv32_isfft_soc.sdc
    └── work/ reports/ deliverables/ sim_rtl/ sim_postsyn/
```

| Mudança em relação ao projeto anterior | Por quê |
|---|---|
| `DESIGNS=neorv32_isfft_soc`, `HDL_NAME=asic_top` | Pasta/relatórios com nome do projeto; topo do RTL continua `asic_top` |
| Tudo Verilog: `read_hdl -language sv -define SRAM_LIB_VIEW` | NEORV32 já convertido (D14); conferido que nenhum nome é palavra reservada de SV |
| 4 `.lib` de macro; `avoid false` nas 4 (garantia) | Rodada back-end tem área; o `avoid` automático do projeto anterior não deve ocorrer |
| `avoid` em `sdf*`, `sedf*`, `sdlclkp*`, `lpflow_*`, `probe*`, `macro_sparecell` | Sem DFT; células de energia/teste não são lógica |
| `report_area -depth 4`, top-10 de timing, `write_sdc`, `write_do_lec` | Área por bloco; LEC com o dofile que o Genus escreve |
| Bloco 0 novo: simulação **RTL** no Xcelium com o mesmo tb | Confere RTL + testbench na VM antes da síntese |
| `tb_gate.v` sem referência hierárquica | Carga da IMEM feita pelo adaptador (`+IMEM_HEX`); somas comparadas com `chk_rtl.txt`. Não depende dos nomes do netlist |
| LEC: dofile do Genus (3a) + o escrito à mão (3b, `@PROJECT_DIR@` trocado por `sed`) | Conformal não entende variável (lição anterior) |
| **Sem** bloco de simulação com SDF | Ver achado 1 |

### Revisão: o que dava para conferir na nuvem, conferido

Genus/Xcelium/Conformal não existem aqui. O que existe: **Yosys** (via
pip) e **Icarus**. Com eles, o mesmo RTL da pasta foi sintetizado nas
mesmas células sky130 (mesmas células evitadas) e o netlist foi simulado
com o mesmo testbench e os mesmos adaptadores. Script:
`sim/run_gls_yosys.sh` (roda também no notebook).

| Conferência | Resultado |
|---|---|
| RTL da pasta compila como Verilog-2005 puro | ✅ |
| `.lib` × `.v` das macros | 1 porta: 32 × 33 bits (resolvido por `SRAM_LIB_VIEW` + adaptador); 1rw1r: iguais |
| Palavras reservadas de SystemVerilog no RTL | nenhuma |
| `tb_gate` sobre o RTL com as views do `.lib` | ✅ somas = RTL, `PASSOU` |
| Síntese Yosys | ✅ 4 macros (1 instância cada), 0 células evitadas, hierarquia preservada |
| Área de lógica estimada (Yosys, sem macros) | ~0,96 mm² (NEORV32 ~0,33; ISFFT ~0,63). Com macros: ~2,1 mm². O Genus vai dar o número de verdade |
| **Simulação de portas** (netlist Yosys + Icarus, `FUNCTIONAL`) | ❌ → 3 achados abaixo → ✅ **as 3 somas = RTL, contadores 3/3/0, `PASSOU`** (188.195 ciclos; 43 min no Icarus) |

### 🐛 Achado 1: o `sky130_fd_sc_hd.v` do pacote não tem `specify` — era o X do projeto anterior

**Sintoma:** netlist inteiro em X; o gerador de reset do NEORV32
(`neorv32_sys_reset`) nunca sai de X, mesmo com `rstn_i` e `clk_i` certos.
**Causa:** na variante sem `FUNCTIONAL`, os flip-flops do sky130 usam
`D_delayed`, `CLK_delayed`, `RESET_B_delayed`, que deveriam ser gerados
pelos checks de tempo do bloco `specify`. **Este arquivo não tem nenhum
`specify`** (`grep` = 0): os fios `*_delayed` nunca são acionados e todo
flip-flop fica em X, em qualquer simulador.
**Isso explica o projeto anterior:** "SCE flutuando no `sdfrtp`" era
sintoma, não causa — o `udp_mux` do `sdfrtp` também lia `SCD_delayed`/
`SCE_delayed`. As 5 hipóteses descartadas de 09/09 estavam certas em
descartar; a sexta era esta.
**Resolvi com:** `-define FUNCTIONAL -define 'UNIT_DELAY=#1'` na
simulação de portas + correção da linha 49162 (`` `endif `` sem `//`, o
bug do PDK que o projeto anterior achou e que só aparece com
`FUNCTIONAL`). Sem `specify`, **não há simulação com SDF** com este
arquivo — o bloco foi retirado.
**Vira slide?** Sim: "o X do projeto anterior não era do circuito, era
do modelo".

### 📘 Explicação completa: o erro do `specify` nos modelos das células

#### O que é o erro

O `tech/verilog/sky130_fd_sc_hd.v` traz os modelos de simulação de todas as células da biblioteca `sky130_fd_sc_hd`. Cada célula aparece em **quatro variantes**, escolhidas por duas macros de pré-processador:

| | sem `FUNCTIONAL` | com `FUNCTIONAL` |
|---|---|---|
| sem `USE_POWER_PINS` | comportamental | funcional |
| com `USE_POWER_PINS` | comportamental com pinos de alimentação | funcional com pinos de alimentação |

Se nada for definido, a simulação usa a variante **comportamental**. Nela, o flip-flop `dfrtp` é assim:

```verilog
module sky130_fd_sc_hd__dfrtp (Q, CLK, D, RESET_B);
    ...
    wire D_delayed;
    wire RESET_B_delayed;
    wire CLK_delayed;
    ...
    not  not0 (RESET, RESET_B_delayed);
    sky130_fd_sc_hd__udp_dff$PR_pp$PG$N dff0 (buf_Q, D_delayed, CLK_delayed, RESET, notifier, VPWR, VGND);
    ...
endmodule
```

O flip-flop interno (a UDP `udp_dff`) não lê `D`, `CLK` e `RESET_B`. Ele lê `D_delayed`, `CLK_delayed` e `RESET_B_delayed`, e **nenhuma linha do módulo aciona esses fios**. Quem deveria acioná-los é o bloco `specify`, com as verificações de tempo da célula:

```verilog
specify
    $setuphold (posedge CLK, D, 0:0:0, 0:0:0, notifier, cond1, cond1, CLK_delayed, D_delayed);
    ...
endspecify
```

Os dois últimos argumentos de `$setuphold` são os sinais atrasados. O simulador os cria como cópias de `CLK` e `D`, deslocadas o necessário para verificar setup/hold com limites negativos. Ou seja, **o modelo comportamental só funciona se o bloco `specify` existir.** E este arquivo não tem nenhum:

```bash
grep -c "specify" tech/verilog/sky130_fd_sc_hd.v
# 0
```

#### O que ele causou

Fio sem driver vale `z`, e a UDP trata `z` na entrada como desconhecido. Resultado: **todo flip-flop do netlist fica em X desde o instante 0, para sempre**. Isso vale inclusive para os que têm reset, porque o próprio `RESET_B_delayed` também não tem driver. Não depende do circuito, do sintetizador nem do simulador: acontece no Xcelium e no Icarus, com netlist do Genus ou do Yosys.

- **Nesta sessão (nuvem):** `clk_i` e `rstn_i` chegavam certos ao chip, mas o gerador de reset do NEORV32 (`neorv32_sys_reset`) ficou em X do começo ao fim. Resultado: 1,38 milhão de sinais em X, e a UART nunca transmitiu.
- **No projeto anterior:** foi a causa da simulação pós-síntese que nunca passou (`xbus_cyc`/`xbus_stb` em X, a CPU nunca pedia instrução). A suspeita final, "SCE flutuando no `sdfrtp`", era sintoma: o mux de scan do `sdfrtp` também lê `SCD_delayed`/`SCE_delayed`. Evitar as células `sdf*` não teria resolvido, porque o `dfrtp` comum tem o mesmo problema.

**Por que é traiçoeiro:** não gera nenhum erro nem aviso de compilação, porque os fios estão declarados, só não são acionados. O netlist elabora, o programa carrega e o clock corre. O X parece defeito do circuito e leva a investigação para o lugar errado.

**Como reconhecer:** um flip-flop com reset ativo continua em X durante o reset. Com um modelo correto isso não acontece. Basta sondar o `Q` de qualquer `dfrtp` com `RESET_B = 0`.

#### Como resolver

A variante **funcional** da mesma célula liga `D`, `CLK` e `RESET_B` direto à UDP, sem sinais atrasados:

```verilog
not                                     not0 (RESET, RESET_B);
sky130_fd_sc_hd__udp_dff$PR `UNIT_DELAY dff0 (buf_Q, D, CLK, RESET);
```

A correção tem três partes:

1. **Definir `FUNCTIONAL`**, que escolhe essa variante: `xrun -define FUNCTIONAL` ou `iverilog -DFUNCTIONAL`.
2. **Definir `UNIT_DELAY`**, que é o atraso da UDP na variante funcional. Sem ele definido, a compilação falha. Use `-define 'UNIT_DELAY=#1'` (ou `-DUNIT_DELAY=#1`). Com atraso zero, a saída de um flip-flop mudaria no mesmo instante da borda de clock, e num netlist sem árvore de clock outro flip-flop poderia capturar o valor novo em vez do antigo (corrida). Com `#1`, toda saída muda 1 ns depois da borda: a corrida some e a função não muda.
3. **Corrigir a linha 49162** do `sky130_fd_sc_hd.v`. A variante funcional expõe um erro de sintaxe no próprio arquivo do PDK (já achado no projeto anterior):
   ```verilog
   `endif SKY130_FD_SC_HD__LPFLOW_BLEEDER_FUNCTIONAL_V        // errado: falta //
   `endif  // SKY130_FD_SC_HD__LPFLOW_BLEEDER_FUNCTIONAL_V    // certo
   ```
   Conferência: `grep -n '^`endif [A-Z]' tech/verilog/sky130_fd_sc_hd.v` tem que sair vazio. A pasta da VM já vem corrigida, e o `sim/monta_vm.sh` aplica a correção sempre.

Comando completo: é o bloco 2 do `run_first.tcl`. As duas lições anteriores continuam valendo: o arquivo de células **não** pode ser lido com `-v`, e o `restore_nettype.v` vem logo depois dele.

#### O que se perde

A variante funcional não tem temporização: é simulação **lógica** com atraso unitário. Ela responde "o netlist faz o mesmo que o RTL?" e "sai do reset sem X?", mas não responde "cumpre setup/hold?". Pelo mesmo motivo, **não dá para simular com SDF usando este arquivo**: a anotação SDF precisa dos caminhos e verificações declarados no `specify`. A verificação de tempo fica com a STA (timing do Genus agora; STA com parasitas depois do layout, se der tempo).

Se um dia for preciso simular com SDF, será necessário um modelo de células **com** `specify`. Antes de usar qualquer arquivo de células, conferir: `grep -c specify <arquivo>.v` tem que ser maior que 0. Não vale a pena escrever `assign D_delayed = D;` à mão: seriam centenas de módulos editados num arquivo do PDK, para ter o que a variante funcional já dá.

#### Resumo

| | |
|---|---|
| **Erro** | O modelo comportamental usa `*_delayed`, que só o `specify` aciona; o arquivo não tem `specify` |
| **Efeito** | Todo flip-flop em X para sempre, sem erro de compilação |
| **Diagnóstico** | `grep -c specify` = 0; `dfrtp` com reset ativo continua em X |
| **Correção** | `-define FUNCTIONAL`, `-define 'UNIT_DELAY=#1'` e a linha 49162 corrigida |
| **Consequência** | Simulação só funcional, com atraso unitário; sem SDF; a temporização fica com a STA |

#### Pegamos a versão errada do PDK?

**Não.** O arquivo é o `sky130_fd_sc_hd.v` padrão que o **open_pdks** gera em `sky130A/libs.ref/sky130_fd_sc_hd/verilog/`: 1.524 módulos concatenados a partir dos modelos do repositório `skywater-pdk`, com o cabeçalho "This file is autogenerated". Ele é distribuído assim, sem as partes de temporização, e o próprio uso de referência do sky130 para simulação de portas (os testes do Caravel/Efabless) compila com `-DFUNCTIONAL -DUNIT_DELAY=#1` justamente por isso. Não é defeito da nossa instalação nem versão errada: é o jeito como o PDK aberto entrega o modelo. O que faltou no projeto anterior foi saber que `FUNCTIONAL` não é opcional com este arquivo.

Para conferir no notebook (nosso pacote veio de lá):
```bash
grep -c specify ~/Projects/pdks/sky130A/libs.ref/sky130_fd_sc_hd/verilog/sky130_fd_sc_hd.v   # esperado: 0
```


### 🐛 Achado 2: `next_out` do Spiral com lixo de power-up → `core_armado`

**Sintoma:** com `FUNCTIONAL`, a CPU sai do reset e imprime o título;
no ciclo 27.870 a UART vira X. Rastro: `out_val` da ISFFT em X desde
3 ciclos após o reset → SLINK → CPU (quando o firmware liga o SLINK).
**Causa:** o `next_out` do Spiral passa por `shiftRegFIFO` **sem reset**;
`out_valid_sr` carregava `1111` sempre que `next_out = 1`. No RTL, `if (X)`
conta como falso; no FPGA os registradores ligam em 0. **No silício, bits
aleatórios gerariam pulsos falsos e empurrariam lixo na FIFO de saída.**
**Resolvi com:** `core_armado` na v4 — `next_out` só vale depois da
primeira matriz entregue ao núcleo (zera com `dp_rst`).

### 🐛 Achado 3: o `next` dos `codeBlock` do Spiral congela no reset (D34)

**Sintoma:** com o achado 2 resolvido, vai até o ciclo 37.588: a 1ª
matriz entra limpa na ISFFT (64 palavras), sai no tempo certo (32
palavras) — **todas em X**. Rastro estágio a estágio: IFFT inteira ok;
FFT: estágio 1 ok, estágio 2 (`rc6892` → `perm6890`) nunca sai de X.
**Causa:** no `perm`, os seletores de banco `inFlip0`/`outFlip0` são
resetados e depois **só alternam** (`~X = X`): um único `next` em X
logo após o reset os perde para sempre. E o `next` que chega vem do
registrador `next` dos `codeBlock`, que tem o ramo de reset **vazio**:
fica **congelado** no valor de power-up durante todo o reset e sai logo
depois. Por isso esticar o reset não resolveu (tentei primeiro: 127
ciclos).
**Resolvi com:** `next <= 0;` no ramo de reset dos 10 `codeBlock`
(1 linha cada; `rtl/isfft/core/LEIAME_ASIC.md`). **Prova de que nada mais
mudou:** regressão da Kria com núcleo original × corrigido → as 1.280
palavras de saída **idênticas**; EVM igual.
**Mantidos como proteção extra:** reset do núcleo estendido por 127
ciclos (`core_rst`, varre os `shiftRegFIFO` com zeros) e `core_armado`.

**Vira slide?** Sim, os três: "o RTL não vê X — `if (X)` é falso; o
FPGA liga em zero; o silício não". A simulação de portas é a única etapa
que pega isso, e ela só funcionou depois do achado 1.

### Estado final (nuvem)

| Bancada | Resultado |
|---|---|
| `run_tb_isfft_ref.sh` (v3, v4, 5/5 mutações, núcleo original × corrigido) | ✅ 1.280 palavras idênticas |
| `run_tb_evm.sh` (chip RTL, notebook-style) | ✅ EVM 3,4122 / 0,7822 / 0,5965 % = Kria |
| `run_gls_yosys.sh` modo RTL (pasta da VM) | ✅ `PASSOU` |
| `run_gls_yosys.sh` portas (pasta da VM) | ✅ `PASSOU` |

Obs.: em portas o testbench conta 188.195 ciclos até o `#FIM#`; no RTL,
188.194. É o atraso unitário de 1 ns deslocando a amostragem da UART —
os ciclos por matriz medidos pelo firmware são os mesmos (0xa3e).

**Na VM, na ordem:** bloco 0 (RTL no Xcelium, ~1–2 min), bloco 1
(Genus), bloco 2 (pós-síntese), bloco 3 (LEC). Cada um tem o "esperado"
escrito no `run_first.tcl`.

---

## 2026-09-26 (14ª sessão) — ✅ Síntese no Genus rodou até o fim

Bloco 1 do `run_first.tcl` na VM: o script chegou ao fim **sem erro**
(`-abort_on_error` não disparou). Todos os comandos novos foram aceitos:
`check_design -all`, `report_area -depth 4`, `report_timing -max_paths 10`,
`write_sdc`, `write_do_lec`.

- `report_power` usou o Joules em modo vectorless (sem atividade de
  simulação): número só de referência.
- `write_do_lec` escreveu um dofile **composto**, com duas comparações:
  RTL → `fv_map` (netlist intermediário que o Genus gravou no `syn_map`) e
  `fv_map` → netlist final. É o fluxo recomendado da Cadence; é o bloco 3a.
- Aviso "This version of the tool is 837 days old": só a idade da
  instalação, sem efeito.

### Conferência (saída do `run_first.tcl`)

| Item | Resultado |
|---|---|
| Módulos não resolvidos / módulos vazios | **0 / 0** |
| Macros no netlist | **4**, 1 instância cada, com a área do `.lib` back-end |
| Células evitadas no netlist | **0** |
| Slack de setup a 50 MHz | **+2.410 ps**, 0 caminhos violando |
| DRC (transição, capacitância, fanout) | sem violações |
| Tempo de síntese | ~10 min (597 s) |

### Área (`report_area -depth 4`)

| Bloco | Área (µm²) | Obs. |
|---|---|---|
| **Chip inteiro** | **1.912.963** | 60.028 células, 19.827 sequenciais |
| 4 macros | 1.182.838 | 62% do chip |
| Lógica (células padrão) | 730.125 | |
| NEORV32 (lógica, sem IMEM/DMEM) | ~275.800 | |
| └ FIFOs do SLINK (2 × 64 × 37) | 146.751 | **53% da lógica do NEORV32** (D19: precisa caber 1 matriz) |
| └ CPU | 97.059 | banco de registradores 45.919 |
| └ DMA | 17.244 | |
| ISFFT (lógica, sem `in_mem`/`out_mem`) | ~448.100 | |
| └ FFT 1D / IFFT 1D (Spiral) | 138.335 / 141.105 | |
| └ ping-pong + registradores do `top_isfft` | ~149.000 | em flip-flop (D26) |
| Conversores 32↔64 | 6.205 | |

O Yosys tinha estimado ~0,96 mm² de lógica; o Genus fechou em 0,73 mm².

### Timing

Caminho crítico **dentro da CPU**: do controle até o divisor/multiplicador
(`neorv32_cpu_alu_muldiv`), uma cadeia de subtração de 32 bits. Não passa
por macro nem pela ISFFT. Folga de 2,4 ns em 20 ns.

`timing_lint`: só avisos esperados, todos sobre `rstn_i` (false path +
ideal net; sem atraso externo nem transição). Nenhum clock sem forma de
onda, nenhuma rede com múltiplos drivers, nenhum laço combinacional.

`check_design`: 502 pinos sequenciais sem carga e 137 pinos constantes
(bits que o circuito nunca usa: saídas `Q_N`, CSRs fixos), 4 instâncias
preservadas (as macros). Nada fora do esperado.

### ⚠️ Potência: número das macros não vale

O relatório diz **2.767 W** de potência interna em "memory". É o `.lib` das
macros: a OpenRAM (modelo analítico) escreve `internal_power` com valores
fora de escala (ex.: `rise_power` = 1,0e+11 no `clk1` da 1rw1r). Só
registradores + lógica valem como referência: ~50 mW, vectorless (sem
atividade real). Potência de verdade fica para o Joules com atividade de
simulação, se der tempo (D23).

### ✅ Simulação pós-síntese (bloco 2): o netlist do Genus funciona

Primeira simulação de portas que funciona desde o projeto anterior. No
Xcelium, **31 s** no total (contra 43 min do Icarus na nuvem).

```
[IMEM] mem[0..2] = 0f14020f3 080001217 0ffc20213
[UART] CHK 0 0xeb88508e ciclos 0x00000a3e
[UART] CHK 1 0xba7fc58e ciclos 0x00000a3e
[UART] CHK 2 0xb29c0211 ciclos 0x00000a3e
[UART] MAT_IN 0x00000003 MAT_OUT 0x00000003 ERR 0x00000000
[UART] RESULTADO: OK
[TB] fim em 3.764 ms (188195 ciclos)
```

As 3 somas são **idênticas às do RTL**, os ciclos por matriz também
(0xa3e), contadores 3/3/0 e "RESULTADO: OK". O netlist do Genus sai do
reset sem X e calcula a ISFFT bit a bit igual ao RTL (que dá EVM igual
ao da Kria).

### 🐛 O testbench deu FALHOU mesmo com o chip certo

**Sintoma:** `[TB] ERRO: 0 CHK recebidos, 3 esperados` e 11 avisos
`*W,SYSFMW: $sscanf -- Input does not match format string at character ' '`.
**Causa:** a linha da UART fica num `reg [8*200-1:0]` com zeros à
esquerda (bytes ainda não usados). O **Xcelium** lê esses zeros como
espaço, e o formato `"CHK %d 0x%h"` exige que o texto comece em `C`. O
**Icarus** ignora os zeros, por isso passou na nuvem.
**Resolvi com:** espaço no início do formato: `" CHK %d 0x%h"`. Espaço
no formato casa com qualquer quantidade de espaço, inclusive nenhum.
Conferido no Icarus (RTL e texto sem `CHK`).
**Vira slide?** Não. Mas vale a nota: "o mesmo testbench pode se
comportar diferente em dois simuladores".

Avisos restantes do log: 1.000 `NODNTW` dentro dos arquivos do PDK
(`default_nettype none`, já conhecidos e inofensivos) e 1 `MXWARN`.

**Rodada de novo com o `tb_gate.v` corrigido: ✅ `[TB] PASSOU`** — as 3
matrizes "soma = RTL", 188.195 ciclos, 31 s.

Sobram 8 avisos `SYSFMW`: são as linhas da UART que **não** são `CHK`
(título, `DUMP`, `MAT_IN`, `RESULTADO`, `#FIM#`). O Xcelium avisa quando o
`$sscanf` não casa; o Icarus fica quieto. Esperados, inofensivos. O
`MXWARN` só diz que os 1.000 `NODNTW` do PDK bateram no limite de avisos.

### ✅ LEC (bloco 3a): RTL ≡ netlist

Dofile composto que o Genus escreveu (`write_do_lec`), duas etapas:

| Etapa | Método | Resultado |
|---|---|---|
| `fv_map` → netlist final | plana | **19.828 pontos equivalentes** (1 saída, 19.823 flip-flops, 4 caixas-pretas = as macros); 0 não mapeados, 0 não-equivalentes, 0 abortados → **PASS** |
| RTL → `fv_map` | hierárquica, módulo a módulo | **169/169 módulos equivalentes** (NEQ 0, ABORT 0) |

Tempo: ~25 min (1.480 s) na etapa hierárquica. O RTL foi lido com
`-define SRAM_LIB_VIEW`, as 4 macros como caixa-preta nos dois lados.
Avisos do log (sinais sem carga, portas não usadas, "Unreachable DFF
removed") são as mesmas podas de lógica sem efeito que o `check_design`
mostrou; não afetam a prova. O dofile escrito à mão (3b) não precisou
ser usado.

**Fechamento da síntese (D38):**

| Verificação | Pergunta | Resposta |
|---|---|---|
| Genus | sintetiza e fecha timing? | sim, slack +2,4 ns a 50 MHz, 1,91 mm² |
| LEC (Conformal) | o netlist é o mesmo circuito do RTL? | sim, 169/169 módulos, 19.828 pontos |
| Pós-síntese (Xcelium) | o netlist funciona (reset, X)? | sim, somas = RTL, `PASSOU` |
| RTL (EVM) | a matemática está certa? | sim, EVM = Kria |

**Vira slide?** Sim: é o slide de fechamento do front-end.

**Próximo:** layout (LibreLane), no notebook.

---

## 2026-09-26 (15ª sessão) — Fim do front-end neste chat; o que leva para os próximos

**Decisão do Lukas:** o caminho até o GDSII continua em **outro chat**
(mesma estratégia da migração Kria → ASIC). Este chat fica para dúvidas
sobre o que foi feito e para coletar resultados para relatório e slides.
Duas tarefas esquecidas entram na lista: **UVM no IP da ISFFT** e
**síntese com DFT só no IP da ISFFT**.

### Estado ao encerrar

| Etapa | Estado | Onde está a prova |
|---|---|---|
| Macros OpenRAM (4) | ✅ | `macros/`, tabelas das sessões 2–4, 10, 12 |
| RTL (NEORV32 convertido + ISFFT v4 + conversores) | ✅ | sessões 5–12 |
| Simulação RTL + EVM = Kria | ✅ | D32 |
| Síntese Genus (50 MHz, 1,91 mm², +2,4 ns) | ✅ | 14ª sessão |
| Pós-síntese Xcelium (somas = RTL) | ✅ | D37 |
| LEC (169/169 módulos, 19.828 pontos) | ✅ | D38 |
| Layout (LibreLane) → GDSII | ⏳ | próximo chat |
| UVM no IP da ISFFT | ⏳ | a fazer |
| Síntese com DFT no IP da ISFFT | ⏳ | a fazer |

### Levar para o chat do GDSII

| Arquivo | De onde | Por quê |
|---|---|---|
| `DIARIO.md` | projeto | contexto e decisões (D1–D38) |
| `asic_completo.tgz` | projeto | RTL (`frontend` = mesmo RTL da síntese), scripts, `monta_vm.sh`, `run_gls_yosys.sh` |
| `neorv32_isfft_soc.v`, `.sdc`, `.sdf` | VM: `backend/synthesis/deliverables/` | netlist e restrições do Genus (referência) |
| `_area_hier.rpt`, `_timing.rpt`, `_qor.rpt` | VM: `reports/` | números de comparação para o layout |
| `.lef`, `.gds`, `.lib`, `.v` das 4 macros | notebook: `macros/` | o layout precisa do **GDS e do LEF** |
| `diagrama_chip.png` | projeto: `doc/` | planta do chip |

Pontos em aberto que o layout tem que resolver (não esquecer):
1. **D17 — 33 × 32 bits das macros de 1 porta.** O `.lef` (e o `.gds`)
   tem `din0/dout0[32:0]` + `spare_wen0`; o `.lib` tem 32 bits. O
   LibreLane usa o LEF no P&R e o `.lib` no STA: as views brigam. Decidir
   entre sintetizar sem `SRAM_LIB_VIEW` (33 bits, casa com LEF/GDS) e
   ajustar/gerar um `.lib` de 33 bits.
2. **Tamanho do die:** as 4 macros somam 1,18 mm²; a maior tem 810,8 ×
   553,5 µm. Lógica ~0,73 mm² (Genus).
3. **DRC das macros:** ~390 mil / 783 mil erros na bitcell de 1 porta
   (foundry, ~12 por célula) e 2 nas 1rw1r; LVS 1–3 por classificação de
   dispositivo. Decidir como tratar (waiver/ignorar dentro da macro).
4. `.lib` das macros com potência interna fora de escala (14ª sessão).

### Levar para o trabalho de UVM (IP da ISFFT)

| Arquivo | De onde | Papel no UVM |
|---|---|---|
| `rtl/isfft/isfft_axi_v4.v` + `rtl/isfft/core/*.v` | projeto | **DUT** (o IP que vai no chip) |
| `rtl/isfft/core/LEIAME_ASIC.md` | projeto | o que mudou no núcleo (D34) |
| `macros/sram_1rw1r_64x256.v`, `macros/sram_1rw1r_64x64_wpr2.v` | projeto | modelos das macros (com `VERBOSE = 0`) |
| `rtl/isfft/ref/isfft_axi_wrapper.v` | projeto | referência RTL da etapa 1 (pode ser o modelo de referência do scoreboard) |
| `tb/ref/tb_isfft_axi_v3.v` | projeto | cenários já validados: pausas, parada longa, pacote truncado, registradores |
| `sw/isfft_evm/evm.py` + `processamento_otfs.ipynb` | projeto / Kria | modelo numpy (`ifft` linhas, `fft` colunas, /8) e EVM |
| mapa de registradores | cabeçalho do `isfft_axi_v4.v` | CTRL, STATUS, MAT_IN, MAT_OUT, ERR_CNT, ID, PKT_MAT |

Interfaces para os agentes: **AXI4-Lite** (escravo, 6 bits de endereço) e
**AXI4-Stream** 64 bits (entrada com `tlast`, saída com `tready`). Onde:
Xcelium da VM (`xrun -uvm`).

### Levar para a síntese com DFT (só o IP da ISFFT)

| Arquivo | De onde | Obs. |
|---|---|---|
| mesmo RTL do UVM (`isfft_axi_v4.v` + núcleo) | projeto | topo = `isfft_axi_v4` |
| `.lib` das 2 macros 1rw1r + `sky130_fd_sc_hd__tt_025C_1v80.lib` | pasta da VM `tech/lib/` | |
| `neorv32_isfft_soc.tcl`, `common/tech.tcl`, `path.tcl`, SDC | pasta da VM | base do script novo |

Atenção para a DFT:
1. **Liberar as células de scan.** Nosso `tech.tcl` põe `avoid` em
   `sdf*`/`sedf*`. Para DFT elas são necessárias: o script de DFT não pode
   herdar essa linha. (O X do projeto anterior não era delas — era o
   modelo sem `FUNCTIONAL`; com `FUNCTIONAL` o `sdfrtp` simula normal.)
2. **SDC novo:** as portas do IP são `aclk`, `aresetn`, AXI4-Lite e
   AXI-Stream (não `clk_i`/`rstn_i`).
3. **Macros são caixa-preta para o scan:** os flip-flops em volta das
   duas macros perdem controlabilidade/observabilidade; esperar cobertura
   menor ali.
4. Portas de teste (`scan_en`, `scan_in`, `scan_out`, `test_mode`) criadas
   pelo Genus. ATPG depende de ter o Modus na VM (conferir).
5. Reset: `aresetn` é síncrono na ISFFT e o reset interno (`core_rst`,
   `dp_rst`) é gerado por lógica: tende a precisar de controle em modo de
   teste.

---

## Índice de decisões

Decisões que perderam o objeto com a base nova (D12) ficam riscadas,
com o motivo — o raciocínio continua valendo como registro.

| # | Resumo | Status | Data |
|---|---|---|---|
| D1 | ~~Híbrido: decodificador XBUS + `sram_wb_wrapper`~~ | ❌ substituída por D13 + D16 | 2026-09-18 |
| D2 | Sem cache, sem burst | ✅ | 2026-09-18 |
| D3 | ~~DMEM externa em OpenRAM~~ | ❌ vira DMEM **interna** = macro (D13) | 2026-09-18 |
| D4 | ~~Programa em 2 bancos de 4 kB~~ | ❌ reavaliar com o tamanho do `fw_isfft_proc_v2` | 2026-09-18 |
| D5 | ~~Partição do linker no `soc_config_pkg.vhd`~~ | ❌ o pacote não existe mais; linker volta ao makefile | 2026-09-18 |
| D6 | UART0: TX FIFO mínima | 🟡 (na Kria era 64/64) | 2026-09-18 |
| D7 | Clock de 50 MHz | ✅ | 2026-09-18 |
| D8 | Programa carregado só em simulação | ✅ | 2026-09-18 |
| D9 | `CPU_RF_ARCH_SEL = 2` (flip-flops) | ✅ (Kria usava 1 — muda no ASIC) | 2026-09-18 |
| D10 | ~~Apagar aviso de ESPELHAMENTO~~ | ❌ arquivo descartado | 2026-09-18 |
| D11 | Números canônicos = relatórios de 09/09 (referência histórica) | ✅ | 2026-09-18 |
| D12 | Base = RTL da Kria; nenhum RTL do teste anterior | ✅ | 2026-09-18 |
| D13 | IMEM/DMEM internas = macros, via Replaceable Modules | ✅ | 2026-09-18 |
| D14 | Conversão para Verilog único no início do projeto | ✅ | 2026-09-18 |
| D15 | Módulos substituídos escritos a partir do VHDL | ✅ | 2026-09-18 |
| D16 | XBUS → ponte → ISFFT, sem decodificador | ✅ | 2026-09-18 |
| D17 | Macro no layout com interface de 33 bits + `spare_wen0 = 0` | 🟡 | 2026-09-18 |
| D18 | `.lib` back-end no Genus | ✅ | 2026-09-18 |
| D19 | Transporte de dados: DMA + SLINK do NEORV32, FIFOs de 64, conversores 32↔64 | ✅ | 2026-09-18 |
| D20 | ~~Tudo vira macro~~ | ❌ substituída por D26 após medição | 2026-09-18 |
| D21 | Testbench novo: ISFFT original × ISFFT com macros, lado a lado | ✅ feito: `tb_top` (v4 × v3) + regressão da Kria nas duas | 2026-09-23 |
| D22 | ~~Macros do Spiral e do ping-pong em 32×16~~ | ❌ medido 6,0× e 1,9× maior que FF; ficam em flip-flop (D26) | 2026-09-19 |
| D23 | STA com SPEF e potência só depois do GDSII, se houver tempo | ✅ | 2026-09-18 |
| D24 | Palavra de 64 bits: ping-pong em 2 macros 1rw1r; `in_mem` e `out_mem` em 1 macro cada | ✅ medido (G, H, F) | 2026-09-19 |
| D25 | Macros de 64 bits com `words_per_row = 2` | ✅ com 1 palavra/linha o anel de alimentação não fecha | 2026-09-19 |
| D26 | Macro só onde compensa: IMEM, DMEM, `out_mem`, `in_mem`; resto em flip-flop | ✅ decidido pelo Lukas | 2026-09-19 |
| D27 | IMEM de 8 kB (macro nova 32×2048); DMEM segue em 4 kB | ✅ no RTL e verificada (448.827 µm², 0,16× FF) | 2026-09-23 |
| D28 | IMEM como ROM (`BOOT_MODE_SELECT = 2`); programa entra pelo testbench (`$readmemh` na macro) no RTL **e na pós-síntese** | ✅ confirmada pelo Lukas | 2026-09-23 |
| D29 | `tlast` vem do `last` do SLINK (2 descritores de DMA: N−1 palavras em `DATA`, 1 em `DATA_LAST`); conversores só repassam | ✅ | 2026-09-19 |
| D30 | `IO_DMA_DSC_FIFO = 8` (o padrão 4 comporta só 1 descritor) | ✅ | 2026-09-19 |
| D31 | ISFFT só responde na janela `0x4001_0xxx`; fora dela, erro de barramento por timeout | ✅ | 2026-09-19 |
| D32 | Validação numérica: EVM do chip **igual** ao da Kria (±0,005 p.p.), com as matrizes e o modelo do notebook | ✅ passou | 2026-09-23 |
| D33 | ISFFT do chip = `isfft_axi_v4` (módulo novo: `in_mem`/`out_mem` em macro, pré-busca na saída); `isfft_axi_v3` intocada como referência | ✅ | 2026-09-23 |
| D34 | Núcleo Spiral: `next <= 0` no reset dos 10 `codeBlock` (única mudança no núcleo da Kria); v4 com `core_armado` e reset do núcleo estendido (127 ciclos) | ✅ saídas idênticas ao núcleo original; portas `PASSOU` | 2026-09-23 |
| D35 | Simulação pós-síntese com `FUNCTIONAL` + `UNIT_DELAY=#1`; sem SDF (o `sky130_fd_sc_hd.v` não tem `specify`) | ✅ | 2026-09-23 |
| D37 | Pós-síntese do netlist do Genus: somas = RTL, 31 s no Xcelium | ✅ | 2026-09-26 |
| D38 | LEC RTL ≡ netlist (dofile do Genus): 169/169 módulos, 19.828 pontos, PASS | ✅ | 2026-09-26 |
| D39 | GDSII segue em outro chat; este fica para dúvidas e resultados. Novas tarefas: UVM e DFT só no IP da ISFFT | ✅ | 2026-09-26 |
| D36 | Pasta da VM montada por `sim/monta_vm.sh`; scripts da VM moram em `vm/`; conferência aberta por `sim/run_gls_yosys.sh` antes de ir à VM | ✅ | 2026-09-23 |

---

## Pendências abertas

**Decisões (bloqueiam o RTL)**
- [x] ~~Confirmar D13, D14, D16~~ — confirmadas
- [x] ~~Escopo das memórias da ISFFT~~ — tudo vira macro (D20)
- [x] ~~Transporte de dados~~ — DMA + SLINK (D19)
- [x] ~~Profundidade mínima da OpenRAM~~ — 16 palavras (código-fonte)
- [x] ~~Rodar `spiral_min/`~~ — ver entrada de 2026-09-19
- [x] ~~Copiar relatórios de DRC/LVS~~ — analisados: DRC nas células da foundry, LVS por classificação de dispositivo
- [x] ~~Rodar `spiral_min_v2`~~ — F ok; D e E falharam no roteador de alimentação
- [x] ~~Rodar `spiral_min_v3`~~ — G e H fecharam
- [x] ~~Decidir D26~~ — macro só onde compensa
- [ ] Localizar os 2 erros de DRC das macros com mux de coluna (F, G, H)
- [x] ~~Decidir se Spiral e ping-pong continuam como macro~~ — ficam em flip-flop (D26)
- [x] ~~Tamanho da IMEM/DMEM~~ — firmware real 2.692 B; IMEM 8 kB, DMEM 4 kB (D27)
- [ ] Macros geradas (DRC sujo) × pré-geradas do `sky130_sram_macros`

**Arquivos**
- [x] Pacote da VM (`neorv32_sram_soc.zip`)
- [x] `arquivos.zip`: NEORV32 da Kria, ISFFT, testbench, firmware,
      rodada back-end, DIARIO/TUTORIAL do projeto OpenRAM
- [x] `isfft_axi_wrapper.v` (etapa 1) e `processamento_otfs.ipynb`
- [x] ~~Vistas `.v`, `.lib`, `.lef` da macro de 8 kB~~
- [x] ~~Resultado do `run_tb_top.sh` no notebook~~ — via `run_tb_evm.sh`, idêntico
- [x] ~~Confirmar D28~~ — modo 2 confirmado

**RTL**
- [x] ~~`neorv32_imem.v` e `neorv32_dmem.v` com a macro~~ — verificados contra o VHDL oficial, 4/4 mutações
- [x] ~~Rodar `sim/run_tb_mem.sh` no notebook~~ — TUDO OK, idêntico à nuvem
- [x] ~~Wrapper VHDL de conversão~~ — `rtl/soc/neorv32_asic.vhd`, "olá" rodando das macros (nuvem e notebook)
- [x] ~~Conversores 32↔64~~ — `rtl/isfft/stream_*.v`, verificados, 4/4 mutações
- [x] ~~Topo Verilog~~ — `rtl/soc/asic_top.v`
- [x] ~~Firmware DMA + SLINK~~ — `sw/isfft_dma`, 2 matrizes, somas iguais à referência
- [x] ~~**Validação numérica** no chip~~ — EVM 3,41 / 0,78 / 0,60 %, igual à Kria (D32)
- [x] ~~Trocar a IMEM para 8 kB~~ — tb_mem 5/5, tb_soc com a metade de cima, EVM igual à Kria
- [x] ~~Wrapper da **etapa 1**~~ — recebido; `run_tb_isfft_ref.sh` PASSOU, 2/2 mutações
- [ ] Reportar ao NEORV32: bits de IRQ do SLINK (RTL × cabeçalho)
- [x] ~~`out_mem` e `in_mem` → macros 1rw1r~~ — `isfft_axi_v4`, regressão + 5/5 mutações + EVM (D33)
- [x] ~~Vistas das macros F e H~~ — `.v`, `.lef`, `.html` recebidos
- [ ] **`.lib` das macros F e H** (não vieram no pacote; necessários no Genus)
- [ ] Reportar upstream o bug de `wrack` em `verilog/modules/neorv32_dmem.v` (log de simulação pronto)

**Fluxo**
- [x] ~~Refazer `rtl_files.tcl` e o script do Genus para o Verilog único~~ — pasta da VM (13ª sessão)
- [x] ~~`tech.tcl` novo com `avoid` nos `sdf*`~~ — e `sedf*`, `lpflow*`, `probe*`; `avoid false` das macros mantido como garantia
- [x] ~~Rodar na VM: blocos 1, 2, 3~~ — Genus, pós-síntese e LEC passaram (14ª sessão)
- [ ] Material para slide: `resultado_postsyn.txt` + forma de onda no SimVision
- [ ] **Layout no LibreLane** (outro chat — ver 15ª sessão)
- [ ] **UVM no IP da ISFFT** (`isfft_axi_v4`)
- [ ] **Síntese com DFT no IP da ISFFT** (liberar células de scan)
- [ ] Corrigir o `GUIA_LAYOUT.md`: IMEM 810,845 × 553,53 µm + DMEM
      808,845 × 351,29 µm (≈ 905 µm empilhadas); interface de 33 bits (D17)

**Herdadas do projeto OpenRAM**
- [x] ~~Registrar no diário antigo o achado do `sdfrtp`~~ — superado: a causa real do X era o modelo sem `FUNCTIONAL` (13ª sessão)
- [ ] 3 erros de LVS da macro
- [x] ~~Conformal travado em `neorv32_cfs`~~ — CFS do somador sai com D12
