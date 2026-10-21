# DIÁRIO UVM — verificação do IP da ISFFT (`isfft_axi_v4`)

Diário de bordo da verificação UVM do **IP da ISFFT que vai no chip**
(`isfft_axi_v4`: `in_mem` e `out_mem` nas macros OpenRAM, núcleo Spiral
com a correção FE-D34), no **Xcelium** da VM.

Continua o `DIARIO.md` (front-end do chip, sessões 1–15). Decisões de lá
são citadas como **FE-Dn** (ex.: FE-D33), como no `DIARIO_GDSII.md`
(decisões **Ln**). Decisões deste diário são **Un**.

| Diário | Trabalho | Prefixo | Situação |
|---|---|---|---|
| `DIARIO.md` | Front-end | D (citado como FE-D) | ✅ fechado |
| `DIARIO_GDSII.md` | Back-end até o GDSII | L | ▶ outro chat |
| `DIARIO_UVM.md` | UVM no IP da ISFFT | **U** | ▶ este |
| `DIARIO_DFT.md` | DFT no IP da ISFFT | T | ⏳ |

| Origem | O que herda |
|---|---|
| `DIARIO.md` (ASIC) | DUT (`isfft_axi_v4`, FE-D33/D34), macros F e H, pasta da VM e o jeito do `run_first.tcl`, 50 MHz (FE-D7) |
| Regressão da Kria (`tb_isfft_axi_v3.v`) | Cenários já validados: pausas, parada longa, pacote truncado, registradores; referência = wrapper da etapa 1 |
| `evm.py` / `processamento_otfs.ipynb` | Modelo numérico e as 3 matrizes da placa (EVM 3,41 / 0,78 / 0,60 %) |

---

## Como usar este diário

Mesmo modelo do `DIARIO.md`:

```
### 🐛 <título curto>
**Sintoma:** o que apareceu (mensagem, log, comportamento).
**Causa:** por que quebrou, quando eu descobrir.
**Resolvi com:** o que funcionou.
**Tempo gasto:** aproximado.
**Vira slide?** sim/não — e por quê.
```

Decisões entram na tabela da sessão **e** no índice no fim, com o status:
✅ adotada · 🟡 proposta (aguarda confirmação) · ❌ descartada.

---

## Caminhos

(Atualizados na 2ª sessão, com o repositório git. A 1ª sessão descreve a
organização antiga, `~/Projects/asic/uvm/` + `monta_vm_uvm.sh`.)

| O quê | Onde |
|---|---|
| Repositório | `github.com/lukas-araujo/neorv32-isfft-sky130` (privado); notebook: `~/Projects/neorv32-isfft-sky130` |
| Ambiente UVM (fonte de verdade, pasta dona) | `vm/verification/uvm_isfft/` |
| Monta a pasta da VM | `bash sim/monta_vm.sh` (copia tudo o que está em `vm/`) |
| Conferência aberta (Verilator) | `sim/run_uvm_verilator.sh`, `sim/run_uvm_mutacoes.sh` |
| Resultados da VM → repositório | `bash sim/traz_uvm.sh <pasta copiada da VM>` → `resultados/<data>_uvm/` |
| Projeto na VM (goku, aluno12) | `/prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc` |
| UVM na VM | `.../neorv32_isfft_soc/verification/uvm_isfft/` |
| Script da VM | `.../verification/uvm_isfft/scripts/run_first_uvm.tcl` |

---

## Plano de verificação

> Resumo do que o ambiente verifica e como. Detalhes nas sessões datadas.

### Objetivo

Verificar o `isfft_axi_v4` com **UVM** no Xcelium — o mesmo RTL que o
Genus sintetizou (`frontend/` da VM) — com estímulo aleatório
restrito, checagem automática (scoreboard + RAL + asserções) e cobertura
funcional e de código. A regressão direta da Kria (1 cenário fixo) vira
**8 testes** que rodam com qualquer semente.

### O DUT e as interfaces

| Interface | Tipo | Agente UVM |
|---|---|---|
| `s_axi_*` (6 bits de endereço) | AXI4-Lite escravo | `axil_agent` (mestre) + RAL |
| `s00_axis_*` (64 bits, `tlast`) | AXI4-Stream entrada | `axis_agent` mestre (pausas sorteadas) |
| `m00_axis_*` (64 bits, `tlast`) | AXI4-Stream saída | `axis_agent` escravo (`tready` sorteado + paradas) |

Mapa de registradores (cabeçalho do `isfft_axi_v4.v`): CTRL, STATUS,
MAT_IN, MAT_OUT, ERR_CNT, ID = `0x15FF0300`, PKT_MAT.

### Arquitetura do ambiente

```
 vseq ─► vsqr ─┬─► RAL ─► axil_agt ═══ AXI4-Lite ═══╗
               │            └ mon ─► predictor (RAL)  ║
               │                  ─► ref_model        ║
               │                  ─► scoreboard   ┌───╨────────────┐
               ├─► in_agt ═══ AXI-Stream entrada ═╡  isfft_axi_v4  │
               │     └ mon ─► ref_model           │ (macros F, H)  │
               │                │                 └───╥────────────┘
               │                │ 32 palavras seguidas║
               │                ▼                     ║
               │     wrapper da etapa 1 (tb)          ║
               │                │ esperado            ║
               │                ▼                     ║
               │           scoreboard ◄── mon ◄── out_agt (tready)
               └─► cobertura ◄── os três monitores + sonda (bind)
```

### O que é verificado, e como

| Característica | Como | Onde |
|---|---|---|
| Saída bit a bit | Scoreboard contra o **wrapper da etapa 1** (mesma referência da regressão da Kria) | todos os testes |
| Matemática da ISFFT | Modelo em **ponto flutuante** (`ifft` linhas, `fft` colunas, /8): erro máx. e médio em LSB | todos (exceto regressão Kria: dado cheio, só bit a bit, como o original) |
| EVM igual à placa | 3 matrizes do notebook, mesma conta do `evm.py` | `isfft_kria_test` |
| Commit/rollback da entrada | Modelo reproduz a regra (commit a cada 32; `tlast` antes → descarta e conta erro) | `truncado`, `kria_regressao`, `soft_reset` |
| `tlast` da saída e `PKT_MAT` | Scoreboard modela o contador de pacote com o `PKT_MAT` do RAL | todos |
| Registradores | RAL: reset (`uvm_reg_hw_reset_seq`), R/W, escrita em RO ignorada; contadores previstos pelo modelo (`predict`) e conferidos por `mirror(UVM_CHECK)` | `registradores` + fim de todos |
| Contrapressão | `tready` 50–75% e paradas longas (FIFO de saída cheia → entrada cheia) | `contrapressao`, `kria_regressao` |
| Soft reset com dado dentro | Épocas: perder o **fim** de uma época é permitido, o **meio** não | `soft_reset` |
| Protocolo AXI | Asserções nas interfaces (valid estável até o handshake, sem X, resposta OKAY) | sempre ligadas |
| Invariantes internas | Asserções por `bind` (sem tocar no RTL): sem overflow, reserva ≤ 256, pré-busca ≤ 2, `core_armado`, macro nunca lê e escreve o mesmo endereço | sempre ligadas |

### Testes

| Teste | Cenário |
|---|---|
| `isfft_fumaca_test` | 1 matriz, sem pausa |
| `isfft_registradores_test` | reset, R/W do `PKT_MAT` e `CTRL`, escrita em RO |
| `isfft_kria_test` | 3 matrizes da Kria: EVM = placa |
| `isfft_aleatorio_test` | 40 matrizes, 5 tipos × 4 faixas de amplitude, pausas, `tready` 75%, `PKT_MAT` 1–4 |
| `isfft_truncado_test` | idem + pacotes truncados (25%) + limpeza de erro |
| `isfft_contrapressao_test` | 60 matrizes, `tready` 50% e paradas de até 4.000 ciclos |
| `isfft_soft_reset_test` | soft reset com dados no DUT; depois pacote limpo |
| `isfft_kria_regressao_test` | o `tb_isfft_axi_v3` da Kria reescrito em UVM |

### Fora de escopo (por enquanto)

Chip inteiro em UVM (o NEORV32 já tem o tb com firmware), simulação de
portas com UVM, verificação formal.

---

## 2026-09-26 — 1ª sessão: organização, ambiente e conferência no Verilator

**Objetivo:** montar a estrutura da verificação UVM sem mexer no que já
existe, escrever o ambiente completo e conferi-lo com ferramenta aberta
antes de ir para a VM (mesma prática do `run_gls_yosys.sh`).

### Organização (pedido do Lukas)

- Mesma organização do projeto `asic/`: **fonte de verdade no projeto**,
  pasta da VM **montada por script**.
- `run_first_uvm.tcl` **separado** do `run_first.tcl`, numa pasta própria.
- Diário novo (este).

```
asic/                                  (projeto, notebook)
├── DIARIO.md                          front-end (sessões 1–15), intocado
├── DIARIO_UVM.md                      este diário
├── uvm/                               ambiente UVM (fonte de verdade)
│   ├── LEIAME.md
│   ├── tb/        isfft_tb_top.sv, axil_if.sv, axis_if.sv, isfft_sva.sv
│   ├── agents/    axil/axil_pkg.sv, axis/axis_pkg.sv
│   ├── env/       isfft_env_pkg.sv (+ isfft_regs, isfft_matriz, isfft_cobertura .svh)
│   ├── seq/       isfft_seq_pkg.sv
│   ├── tests/     isfft_test_pkg.sv
│   └── scripts/   run_first_uvm.tcl, isfft_uvm.f
└── sim/
    ├── monta_vm_uvm.sh                põe uvm/ dentro da pasta da VM
    ├── run_uvm_verilator.sh           mesmo ambiente no Verilator
    └── run_uvm_mutacoes.sh            defeitos plantados: o ambiente pega?

neorv32_isfft_soc/                     (VM)
├── frontend/ tech/ backend/           como estão (o UVM só LÊ frontend/ e tech/)
└── uvm/
    ├── (as mesmas pastas) + ref/isfft_axi_wrapper.v
    ├── scripts/run_first_uvm.tcl  isfft_uvm.f  isfft_dut.f (gerado)
    └── work/  reports/
```

**O DUT não é copiado.** O `isfft_dut.f` (gerado pelo `monta_vm_uvm.sh`)
aponta para `frontend/isfft_axi_v4.v` e `frontend/isfft/*.v` da VM: o UVM
verifica exatamente o RTL que o Genus sintetizou. O script ainda confere
se esses arquivos são iguais aos do projeto (deu 58 arquivos, 0
diferentes).

`run_first_uvm.tcl`, no mesmo formato do `run_first.tcl` (bash com
`source`, variáveis no topo, blocos comentados):

| Bloco | O quê |
|---|---|
| 0 | Compilar e elaborar (`xrun -uvm -elaborate`) |
| 1 | Teste de fumaça (vem descomentado) |
| 2 | Regressão: 8 testes × `SEMENTES`, cada um com `-covtest` próprio |
| 3 | Cobertura no IMC (junta as rodadas) |
| 4 | Depurar um teste no SimVision (`-linedebug -uvmlinedebug -gui`) |

### Conferência na nuvem: Verilator com UVM

O Cadence não existe na nuvem. O **Verilator 5.052** (05/09/2026) é a
primeira versão que roda **UVM 2020-3.2** (IEEE 1800.2). Compilado do
fonte (5.053-devel), com o `z3` para o `randomize()`.

- O ambiente roda com os **mesmos `.f`** da VM, sobre a pasta da VM
  montada (`run_uvm_verilator.sh <pasta da VM>`).
- O código evita o que mudou entre UVM 1.2 e IEEE 1800.2 (sem
  `uvm_test_done`, `set_config_*`, `starting_phase`), para rodar nos dois.
  O Xcelium 23.09 escolhe a versão pelo `-uvm`; o log imprime qual foi
  (`[TESTE] UVM: ...`).
- Compilação: ~3–7 min (o UVM inteiro vira C++). Simulação: segundos.

### 🔑 Primeira rodada: funcionou; o limite numérico que eu chutei, não

**Sintoma:** fumaça com 32 palavras iguais à referência, mas
`UVM_ERROR [SB_NUM] erro max 2.66 LSB (limite 2.00)`.
**Causa:** eu tinha posto 2 LSB e EVM ≤ 1% sem medir.
**Resolvi com:** medição (abaixo).
**Vira slide?** Não sozinho — entra no slide da medição.

### 🔑 Medição: o erro do ponto fixo não depende da amplitude

`isfft_aleatorio_test` com `+N_MAT=600 +SEM_CHECA_NUM` (checagem numérica
desligada, só registrando). 600 matrizes, 19.200 palavras — **todas iguais
à referência bit a bit**.

| Faixa (maior \|re\|,\|im\|) | Matrizes | Erro máx. (LSB) | Erro médio máx. (LSB) | EVM máx. | EVM médio |
|---|---|---|---|---|---|
| ≤ 64 | 117 | 3,10 | 1,01 | **57,0%** | 16,5% |
| 65 – 1.024 | 180 | 3,04 | 1,01 | 3,64% | 0,95% |
| 1.025 – 8.192 | 244 | 3,14 | 1,03 | 0,52% | 0,12% |
| 8.193 – 32.767 | 59 | **3,19** | 0,99 | 0,14% | 0,04% |

Leituras:
- **O erro absoluto é fixo** (~3 LSB no pior elemento, ~1 LSB na média),
  de amplitude 64 até escala cheia. É arredondamento do ponto fixo do
  Spiral, não depende do sinal.
- **Não há saturação** em escala cheia (±32.767): o erro não cresce. O
  núcleo escala dentro dos estágios.
- **EVM não serve de critério geral:** com sinal pequeno o mesmo erro de
  ~1 LSB vira 57%. O EVM de 3,41% do impulso da Kria é o mesmo fenômeno
  (saída de ~15 LSB).

**Critério adotado (U4):** por matriz, **erro máx. ≤ 4 LSB e erro médio
≤ 1,5 LSB** (medido: 3,19 e 1,03). Um erro de matemática (índice trocado,
real/imag, sinal) dá erro da ordem do próprio sinal, muito acima disso.
O EVM continua calculado e aparece no resumo por faixa; é **cobrado** só
no teste da Kria, contra o número da placa.

**Vira slide?** Sim: "o critério foi medido, não chutado" + a tabela.

### 🐛 EVM da senoide da Kria: 0,69% em vez de 0,78%

**Sintoma:** `isfft_kria_test`: impulso 3,4122% e rampa 0,5965% (= placa,
até a 4ª casa), senoide **0,6868%** contra 0,78% da Kria. A comparação bit
a bit tinha passado.
**Causa:** o meu modelo em SV bate com o `modelo()` do `evm.py` até
1e-13 (conferido em Python). A diferença está **na referência**: o
`evm.py` calcula `modelo(m)` sobre a matriz **antes** de truncar para
int16. A senoide `500·sin(2πc/7)` tem fração (390,9 → 390); o impulso e
a rampa são inteiros. Então o 0,78% da Kria **inclui o erro de quantizar
a entrada** (0,41 LSB na saída), e o scoreboard, que só vê as palavras já
truncadas, mede só o erro do circuito: 0,69%.
**Resolvi com:** o teste da Kria calcula o EVM como o notebook, com a
matriz ideal (`isfft_matriz::ideal()` + `isfft_modelo::avalia_real()`). O
log mostra os dois números.
**Vira slide?** Sim, uma linha: "EVM depende da referência: 0,78% (contra
a senoide ideal) = 0,69% do circuito + quantização da entrada".

### ✅ Regressão no Verilator: 8 de 8

`UVM_SRC=... bash sim/run_uvm_verilator.sh <pasta da VM>` (semente 1).
Compilação ~7 min (UVM inteiro em C++), simulação ~40 s no total.

| Teste | Matrizes / palavras bit a bit | Épocas | Tempo simulado | Resultado |
|---|---|---|---|---|
| `fumaca` | 1 / 32 | 1 | 7 µs | ✅ |
| `registradores` | — | 1 | 3 µs | ✅ |
| `kria` | 3 / 96 | 1 | 10 µs | ✅ EVM 3,4122 / 0,7822 / 0,5965 % = placa |
| `aleatorio` | 40 / 1.280 | 1 | 123 µs | ✅ |
| `truncado` | 40 / 1.280 | 1 | 123 µs | ✅ 3 truncados → `ERR_CNT=3` → limpo → 0 |
| `contrapressao` | 60 / 1.920 | 1 | 458 µs | ✅ FIFO de saída cheia (cobertura de ocupação 95%) |
| `soft_reset` | 8 / 256 | 2 | 29 µs | ✅ 1 matriz perdida no reset (permitido); cauda do pacote virou truncado, DUT e modelo contaram igual |
| `kria_regressao` | 40 / 1.280 | 1 | 184 µs | ✅ `ERR_CNT=1` → 0 |

Nenhum `UVM_WARNING`, nenhuma asserção disparada. Os números do teste da
Kria são os mesmos da simulação do chip inteiro (FE-D32) — agora
medidos no IP sozinho, com o modelo em SystemVerilog.

Cobertura funcional **por teste** (a soma de todos sai no bloco 3, IMC):

| Teste | Entrada | Saída | Registradores | Ocupação |
|---|---|---|---|---|
| `aleatorio` | 52% | 88% | 42% | 68% |
| `truncado` | 67% | 88% | 50% | 68% |
| `contrapressao` | 60% | 100% | 42% | 95% |
| `soft_reset` | 75% | 88% | 50% | 78% |
| `registradores` | 0% | 0% | 73% | 18% |

Nenhum teste sozinho cobre tudo, e é esse o motivo de haver vários. O que
cada um não cobre fica para o merge no IMC.

**Vira slide?** Sim: a tabela de testes com "bit a bit + numérico + RAL +
asserções" em todos.

### ✅ Mutações: 12 de 12 detectadas

`sim/run_uvm_mutacoes.sh`: cada mutação é um defeito plantado no DUT;
roda só depois de a versão correta passar (lição da 8ª sessão do
`DIARIO.md`: mutação só prova algo quando a versão certa passa). O script
lê nos logs **quem** acusou.

| Mutação | Onde | Quem pegou |
|---|---|---|
| W1 `next_in` fora de fase | wrapper | bit a bit + numérica |
| W2 pré-busca sem limite | wrapper | **asserção** (pré-busca > 2) + bit a bit + numérica |
| W3 buffer de saída fora de ordem | wrapper | **asserção** (AXI-Stream: `tdata` mudou esperando `tready`) + bit a bit + numérica |
| W4 busca pelo ponteiro de entrega | wrapper | bit a bit + numérica |
| W5 `core_x` sem esperar a macro | wrapper | bit a bit + numérica |
| W6 `tlast` uma matriz depois | wrapper | **só o modelo de `tlast`** (22 erros) |
| W7 rollback quebrado | wrapper | bit a bit + numérica + **watchdog** (travava — ver abaixo) |
| W8 `clr_err` ignorado | wrapper | **RAL** (`ERR_CNT`) + bit do `STATUS` |
| W9 soft reset não zera `MAT_IN` | wrapper | **RAL** (`MAT_IN`) |
| W10 ID errado | wrapper | **RAL** (`ID`) |
| N1 ping-pong lê a mesma linha 2× | **núcleo** | **só a numérica** — bit a bit: 1.280 palavras, **0 erros** |
| N2 real/imag trocados no ping-pong | **núcleo** | **só a numérica** + teste da Kria |

As W1–W5 são as mesmas 5 da regressão da Kria (`run_tb_isfft_ref.sh`).
As outras 7 exercitam o que o UVM trouxe de novo: modelo de `tlast`,
RAL, asserções e a checagem numérica.

**N1 e N2 são a razão da checagem numérica existir.** O núcleo Spiral é
o mesmo módulo no DUT e na referência (etapa 1): um defeito nele sai
igual dos dois lados, e a comparação bit a bit passa. Só o modelo em
ponto flutuante vê.

**Vira slide?** Sim, os dois: a tabela ("cada checagem pega uma classe
de defeito") e N1 ("bit a bit contra a própria referência não vê defeito
na referência").

### 🐛 Defeito que erra a todo ciclo trava a regressão

**Sintoma:** W2 detectada, mas a simulação continuou: 475 erros de
asserção (um por ciclo) e o teste só terminaria no limite de 200 mil
ciclos da sequência. A mensagem dizia "pré-busca com 0 palavras".
**Causa:** faltava o limite de erros do UVM. E a soma `ob_n + ob_pend`
na mensagem era calculada com 2 bits: com o defeito, `ob_n = 3` e
`ob_pend = 1` davam 4, que em 2 bits é 0.
**Resolvi com:** `set_max_quit_count(20)` no teste base (muda com
`+UVM_MAX_QUIT_COUNT=<n>,YES`) e a soma com 3 bits na mensagem.
**Conferido:** W2 rodada de novo para em exatamente 20 erros de asserção.
**Vira slide?** Não.

### 🐛 W7 travou a simulação para sempre

**Sintoma:** W7 detectada (erro numérico de milhares de LSB), mas o
teste não terminava.
**Causa:** sem rollback, as palavras do pacote truncado ficam no buffer
de entrada e as matrizes nunca completam: o buffer enche, o `tready` fica
em 0 para sempre e a sequência de entrada espera eternamente. Os limites
em ciclos estavam só no fim (`espera_esvaziar`) e no modelo de
referência.
**Resolvi com:** watchdog em ciclos no teste base (`+WATCHDOG=<ciclos>`,
padrão 500 mil; o teste mais longo usa ~23 mil): `uvm_fatal("WATCHDOG")`.
**Conferido:** W7 rodada de novo termina com `[WATCHDOG] teste passou de
500000 ciclos` (10 ms simulados), e a regressão com o código final
continua 8/8.
**Vira slide?** Sim, junto com U10: "um ambiente de verificação também
tem que saber falhar — defeito que trava não pode travar a regressão".

### Estado ao encerrar a sessão

| Etapa | Estado |
|---|---|
| Estrutura (`uvm/`, `monta_vm_uvm.sh`, `run_first_uvm.tcl`, diário) | ✅ |
| Ambiente (2 agentes, RAL, modelo, scoreboard, cobertura, 15 asserções, 8 testes) | ✅ |
| Regressão no Verilator | ✅ 8/8 |
| Mutações | ✅ 12/12 |
| Xcelium na VM | ⏳ próximo: blocos 0 e 1 |

### O que pode ser diferente no Xcelium (conferir na 1ª rodada)

O Verilator não é o Xcelium (lição da 14ª sessão do `DIARIO.md`: o
`$sscanf` se comportou diferente). Pontos a olhar:

1. **Versão do UVM** que o `-uvm` escolhe (a linha `[TESTE] UVM: ...` do
   log). O código foi escrito para rodar em UVM 1.2 e em IEEE 1800.2.
2. **Variáveis `${...}` dentro dos `.f`**: o xrun expande variáveis de
   ambiente nos arquivos `-f`; se reclamar de arquivo não encontrado com
   `${UVM_DIR}` no nome, é isso.
3. **`-coverage all` com classes UVM** e o `-covdut isfft_axi_v4`.
4. **Sintaxe do IMC** no bloco 3 (não há IMC aqui para testar).
5. Ordem de eventos na mesma borda (monitores leem logo depois da
   subida; drivers escrevem com `<=`). Funcionou no Verilator; o Xcelium
   segue a mesma norma.

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U1 | UVM só no IP (`isfft_axi_v4` + núcleo + macros F e H); DUT lido do `frontend/` da VM | ✅ | FE-D39; verifica o RTL que foi sintetizado |
| U2 | Organização: `uvm/` no projeto é a fonte de verdade; `sim/monta_vm_uvm.sh` cria `neorv32_isfft_soc/uvm/`; `run_first_uvm.tcl` separado em `uvm/scripts/`; diário novo | ✅ | Pedido do Lukas: não poluir o `run_first.tcl` |
| U3 | Referência bit a bit = wrapper da etapa 1, dirigido pelo modelo de referência (32 palavras seguidas por matriz confirmada) | 🟡 | Mesma referência da regressão da Kria; independe do wrapper novo |
| U4 | Checagem numérica independente (ponto flutuante): erro máx. ≤ 4 LSB, médio ≤ 1,5 LSB; EVM cobrado só no teste da Kria | 🟡 | Medido em 600 matrizes (3,19 / 1,03); o núcleo é o mesmo no DUT e na referência, então só esta checagem vê erro de matemática |
| U5 | RAL com predição explícita; MAT_IN, MAT_OUT e ERR_CNT previstos pelo modelo/scoreboard (`predict`) e conferidos com `mirror(UVM_CHECK)` | ✅ | Contadores RO não mudam por escrita; é o modelo que sabe o valor certo |
| U6 | Soft reset por épocas: perder o fim de uma época é permitido, o meio não | ✅ | O soft reset zera o caminho de dados de propósito |
| U7 | Asserções com ação `` `uvm_error `` (protocolo nas interfaces, invariantes por `bind`) | ✅ | Com `$error` a falha não conta no resumo do UVM e o teste diria PASSOU |
| U8 | Conferência no Verilator ≥ 5.052 (UVM 2020-3.2) antes da VM; código compatível com UVM 1.2 e IEEE 1800.2 | ✅ | Mesma prática do `run_gls_yosys.sh` |
| U9 | Clock de 50 MHz no tb | ✅ | FE-D7; o modelo da macro usa `negedge` + `#3` |
| U10 | Sem `set_timeout` do UVM; limites em ciclos: watchdog no teste base (500 mil), nas sequências e no modelo | ✅ | A unidade do timeout depende do timescale do `uvm_pkg` em cada simulador |
| U11 | `set_max_quit_count(20)` no teste base | ✅ | Defeito que erra a todo ciclo não trava a regressão |
| U12 | Mutações do UVM: as 5 da Kria + 7 novas (tlast, RAL, soft reset, núcleo) | ✅ | 12/12 detectadas; N1/N2 provam a checagem numérica |

---

## 2026-09-30 — 2ª sessão: integração ao repositório git e à pasta da VM

**Pedido do Lukas:** continuar o trabalho do chat anterior (1ª sessão),
analisar, corrigir o que precisar, integrar no repositório e na pasta
atual da VM. Recebidos: este diário, `asic_completo.tgz` (projeto do
notebook de 26/09, antes do git), `uvm_neorv32_isfft_soc.tgz` (a `uvm/`
montada para a VM) e `neorv32_isfft_soc.tar.xz` (a pasta da VM de hoje).

### O que o chat anterior tinha feito (conferido nos arquivos)

| Item | Situação |
|---|---|
| Ambiente (`uvm/`: 2 agentes, RAL, modelo, scoreboard, cobertura, 15 asserções, 8 testes) | 14 arquivos, ~2.600 linhas. Lido inteiro: nenhum defeito de lógica achado |
| `sim/monta_vm_uvm.sh`, `run_uvm_verilator.sh`, `run_uvm_mutacoes.sh` | Feitos para a organização antiga (`~/Projects/asic`, `neorv32_isfft_soc/uvm/`) |
| Resto do `asic_completo.tgz` | Fotografia de 26/09: o repositório já está à frente (L1, L9, L20...). **Só a parte do UVM foi aproveitada** |
| Pasta da VM de hoje | Sem `uvm/` (nunca rodou na VM). `frontend/isfft_axi_v4.v` e os 57 `frontend/isfft/*.v` **iguais** aos do repositório; modelos das 2 macros iguais |

### O que mudou na integração

| Antes (1ª sessão) | Agora | Por quê |
|---|---|---|
| Fonte em `~/Projects/asic/uvm/` | `vm/verification/uvm_isfft/` (pasta dona do UVM no `CLAUDE.md`) | Repositório git como fonte única (L8) |
| `sim/monta_vm_uvm.sh` monta `neorv32_isfft_soc/uvm/` | `sim/monta_vm.sh` (o geral) leva para `neorv32_isfft_soc/verification/uvm_isfft/`. `monta_vm_uvm.sh` **não veio** | O `monta_vm.sh` já copia tudo o que está em `vm/`; frente nova não mexe nele |
| `isfft_dut.f` escrito pelo `monta_vm_uvm.sh` com a lista do momento | `scripts/gera_dut_f.sh` escreve `work/isfft_dut.f` **na hora**, a partir de `frontend/`, antes de qualquer bloco; o Verilator usa o mesmo script | A lista nunca fica velha se o RTL mudar; VM e Verilator leem a mesma regra. Conferido: mesma lista de 61 arquivos que a do chat anterior |
| `ref/isfft_axi_wrapper.v` copiado na montagem | Cópia fixa em `vm/verification/uvm_isfft/ref/` (igual, byte a byte, a `rtl/isfft/ref/`); o `run_uvm_verilator.sh` avisa se divergir | O `frontend/` da VM só tem o RTL do chip; o wrapper da etapa 1 é congelado (front-end fechado) |
| Verilator rodava sobre a pasta da VM montada | `run_uvm_verilator.sh` monta sozinho um espelho mínimo (`build/uvm_verilator/vm`) com a regra do `monta_vm.sh`; `PASTA_VM=<pasta>` usa uma pasta montada | Não depende do GHDL/NEORV32 (o UVM só usa a ISFFT) |
| Mutações copiavam da pasta da VM | Copiam de `rtl/isfft/` do repositório | idem |
| Sem caminho de volta | `sim/traz_uvm.sh <pasta copiada da VM> [etapa]` → `resultados/<data>_uvm/` (logs, `regressao.txt`, cobertura, `isfft_dut.f`) | Mesmo fluxo do `traz_vm.sh` (L13), que só olha `backend/synthesis/` |
| Decisões citadas como ASIC-Dn | FE-Dn | Mesma convenção do `DIARIO_GDSII.md` |

Fora da pasta do UVM, só mudaram: uma linha na tabela do `vm/LEIAME.md`
(aponta para `verification/uvm_isfft/`), a linha do UVM no `README.md` e
no `CLAUDE.md`, e os três `sim/*uvm*.sh` (novos).

Conferências sem Cadence: `run_first_uvm.tcl` rodado com um `xrun` falso
sobre a cópia da pasta da VM (gera a lista, monta a linha do `xrun` com os
caminhos certos, lê o resultado do log) e `traz_uvm.sh` sobre essa saída.

### 🐛 Cobertura 0% em todos os testes no Verilator 5.052

**Sintoma:** regressão 8/8 PASSOU, mas `[COBERTURA] entrada 0.0% saida
0.0% registradores 0.0% ocupacao 0.0%` em todos os testes. Na 1ª sessão
saíam números (52–95%).
**Causa:** a 1ª sessão usou um Verilator **5.053-devel**; aqui compilei a
versão **5.052** (tag). Num teste mínimo (covergroup em classe e em módulo,
2 de 3 bins amostrados) o 5.052 devolve `get_coverage() = 0` e
`get_inst_coverage() = 66,7%`: a cobertura do **tipo** não é calculada, a
da **instância** é. Primeiro suspeitei do `--coverage-user` (a
documentação diz que ele instrumenta os covergroups): com ele, o mesmo 0.
Não era isso; o flag saiu de novo.
**Resolvi com:** `option.per_instance = 1` nos 4 grupos e o resumo lê
`get_inst_coverage()`. Há uma instância de cada grupo, então o número é o
mesmo; e no Xcelium, com `per_instance = 1`, a instância também aparece
separada no IMC.
**Tempo gasto:** ~20 min.
**Vira slide?** Não. Lição: "0% em tudo" é sinal de ferramenta, não de
teste — conferir com um caso mínimo.

### ✅ Regressão no Verilator 5.052 (estrutura nova, semente 1)

`UVM_SRC=<verilator>/test_regress/t/uvm bash sim/run_uvm_verilator.sh`.
Compilação 165 s; logs em `build/uvm_verilator/vm/verification/uvm_isfft/reports/`.

| Teste | Palavras bit a bit | Pior erro (LSB) | Entrada | Saída | Registradores | Ocupação | Resultado |
|---|---|---|---|---|---|---|---|
| `fumaca` | 32 | 2,66 | 35,7% | 50,0% | 52,6% | 53,3% | ✅ |
| `registradores` | — | — | 0% | 0% | 78,9% | 20,0% | ✅ |
| `kria` | 96 | 1,48 | 50,0% | 50,0% | 52,6% | 66,7% | ✅ EVM 3,4122 / 0,7822 / 0,5965 % = placa |
| `aleatorio` | 1.280 | 3,05 | 57,1% | 83,3% | 52,6% | 66,7% | ✅ |
| `truncado` | 1.280 | 3,05 | 71,4% | 83,3% | 57,9% | 66,7% | ✅ |
| `contrapressao` | 1.920 | 3,10 | 64,3% | 100% | 52,6% | 93,3% | ✅ |
| `soft_reset` | 256 (2 épocas) | 2,82 | 78,6% | 83,3% | 57,9% | 80,0% | ✅ |
| `kria_regressao` | 1.280 | 2,99 (só informativo) | 71,4% | 100% | 57,9% | 93,3% | ✅ |

0 `UVM_ERROR`, 0 `UVM_WARNING` nos 8 logs. Palavras, épocas, tempos
simulados e EVM iguais aos da 1ª sessão. Os percentuais de cobertura
**não** se comparam com a tabela da 1ª sessão (outra versão e outra
função); valem os de agora. O número que conta é o do merge no IMC
(bloco 3), na VM.

### ✅ Mutações no Verilator 5.052: 12 de 12 detectadas

`UVM_SRC=... bash sim/run_uvm_mutacoes.sh` (versão correta PASSOU antes;
arquivo mutado tirado de `rtl/isfft/`). Entre parênteses, quantos erros
de cada tipo.

| Mutação | Quem pegou |
|---|---|
| W1 `next_in` fora de fase | `SB_DADO`(10), `SB_NUM`(1) |
| W2 pré-busca sem limite | `SVA`(20) — para no limite de 20 erros (U11) |
| W3 buffer de saída fora de ordem | `SB_DADO`(10), `SVA`(9), `SB_NUM`(1) |
| W4 busca pelo ponteiro de entrega | `SB_NUM`(10), `SB_DADO`(10) |
| W5 `core_x` sem esperar a macro | `SB_DADO`(10), `SB_NUM`(1) |
| W6 `tlast` uma matriz depois | `SB_TLAST`(21) — só o modelo de `tlast` |
| W7 rollback quebrado | `SB_DADO`(10), `SB_NUM`(8), `WATCHDOG`(1) |
| W8 `clr_err` ignorado | `STATUS`(2), RAL(2) |
| W9 soft reset não zera `MAT_IN` | RAL(1) |
| W10 ID errado | RAL(1) |
| N1 ping-pong lê a mesma linha 2× (núcleo) | `SB_NUM`(10) — só a numérica |
| N2 real/imag trocados (núcleo) | `SB_NUM`(3), `KRIA`(3) — só a numérica e a Kria |

Mesmo quadro da 1ª sessão: a estrutura nova não perdeu nenhuma checagem.

### Na VM, na ordem

Pacote `build/vm_uvm/uvm_isfft_vm.tgz` (só `verification/uvm_isfft/`,
`DIARIO_UVM.md` e o `LEIAME.md` com a linha nova): extrair **dentro de**
`/prj/ci/workarea/aluno12/projetos/` — ele cai em `neorv32_isfft_soc/`
sem tocar em `frontend/`, `tech/` nem `backend/`. (Montar a pasta inteira
com `sim/monta_vm.sh` dá o mesmo resultado nessa parte.)

1. `cd .../neorv32_isfft_soc/verification/uvm_isfft/scripts`
2. Bloco 0 (compilar; descomentar o 0 e comentar o 1) — esperado: nenhum
   `*E`. Olhar a linha `isfft_dut.f: 58 arquivos do frontend...`.
3. Bloco 1 (fumaça) — `TESTE PASSOU`, `[TESTE] UVM: ...` diz a versão.
4. Bloco 2 (regressão, `SEMENTES=1` primeiro) — 8 PASSOU.
5. Bloco 3 (IMC) — sintaxe ainda não testada em lugar nenhum.
6. Trazer: copiar a pasta para o notebook e
   `bash sim/traz_uvm.sh <pasta> uvm_regressao`.

Pontos do Xcelium ainda não provados (lista da 1ª sessão): versão do UVM
do `-uvm`, `${UVM_DIR}`/`${UVM_WORK}` dentro do `.f`, `-coverage all` com
classes, sintaxe do IMC.

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U2 | ~~`uvm/` + `monta_vm_uvm.sh`~~ → fonte em `vm/verification/uvm_isfft/`, montada pelo `sim/monta_vm.sh`; na VM, `neorv32_isfft_soc/verification/uvm_isfft/` | ✅ | Organização do repositório (`CLAUDE.md`, L8) |
| U13 | Lista do DUT gerada na hora (`gera_dut_f.sh`), igual na VM e no Verilator | 🟡 | Não envelhece quando o RTL muda; uma regra só |
| U14 | Wrapper da etapa 1 como cópia fixa em `ref/`, conferida contra `rtl/isfft/ref/` | 🟡 | O `frontend/` da VM não tem a referência; o arquivo é congelado |
| U15 | Scripts do notebook do UVM em `sim/` (`run_uvm_verilator.sh`, `run_uvm_mutacoes.sh`, `traz_uvm.sh`); Verilator com espelho mínimo da VM | 🟡 | Mesmo lugar das outras bancadas (`run_gls_yosys.sh`, `traz_vm.sh`); não precisa do GHDL |
| U16 | Cobertura lida por instância (`per_instance = 1`, `get_inst_coverage`); Verilator de referência = **5.052** (tag) | ✅ | O 5.052 dá 0 no `get_coverage()`; com uma instância por grupo o número é o mesmo |

---

## 2026-09-30 — 3ª sessão: PATH da VM

### 🐛 IMC não achado no bloco 3

**Sintoma:** na VM, o bloco 3 (cobertura) não achou o `imc`.
**Causa:** o `run_first_uvm.tcl` herdou da 1ª sessão um `export PATH` só
com o Xcelium; o IMC não está nas pastas do Xcelium.
**Resolvi com:** o Lukas pôs o `export PATH` completo da VM e o IMC
funcionou. O mesmo `export`, inteiro, agora está no `run_first_uvm.tcl` e
no `CLAUDE.md` (regra: todo script da VM usa o PATH completo).
**Tempo gasto:** pouco (resolvido pelo Lukas na VM).
**Vira slide?** Não.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U17 | `run_first_uvm.tcl` com o PATH completo da VM (igual ao do `CLAUDE.md`) | ✅ | Pedido do Lukas; o recortado não tinha o IMC |

---

## 2026-09-30 — 4ª sessão: ✅ regressão no Xcelium (VM)

Resultados em `resultados/2026-09-30_uvm_regressao/` (commit `e88aeb3` do
Lukas, trazidos com `sim/traz_uvm.sh`). Blocos 0 a 3 do
`run_first_uvm.tcl`, semente 1. Tabelas para slide:
`doc/tabelas_uvm.md`.

**Pedido do Lukas:** só registrar e fazer as tabelas; melhorias ficam para
depois (lista no fim desta sessão).

### O que a 1ª sessão deixou em aberto sobre o Xcelium — respondido

| Dúvida | Resposta | Fonte |
|---|---|---|
| Versão do UVM do `-uvm` | **CDNS-UVM-1.1d** (23.09-s013) — nem 1.2 nem IEEE 1800.2. O código rodou sem mudança | linha `[TESTE] UVM:` dos logs |
| `${UVM_DIR}`/`${UVM_WORK}` dentro do `.f` | expandidos pelo `xrun` | `compila.log` sem `*E` |
| `-coverage all` com classes UVM | funcionou; covergroups aparecem no IMC | `cobertura_funcional.txt` |
| Sintaxe do IMC (`merge`, `report`) | funcionou (IMC 24.09; aviso de versão × 23.09 e `REPDEP`, inofensivos) | `imc.log` |
| Lista do DUT (U13) | 58 do `frontend/` + 2 macros + referência, gerada na VM | `isfft_dut.f` |

### Regressão

| Teste | Palavras bit a bit | Pior erro numérico | Tempo simulado | Resultado |
|---|---|---|---|---|
| `fumaca` | 32 | 2,79 LSB | 7 µs | ✅ |
| `registradores` | — | — | 3 µs | ✅ |
| `kria` | 96 | 1,48 LSB | 10 µs | ✅ EVM 3,4122 / 0,7822 / 0,5965 % = placa |
| `aleatorio` | 1.280 | 2,97 LSB | 123 µs | ✅ |
| `truncado` | 1.280 | 2,95 LSB | 123 µs | ✅ |
| `contrapressao` | 1.920 | 2,97 LSB | 183 µs | ✅ |
| `soft_reset` | 256 (2 épocas) | 2,81 LSB | 29 µs | ✅ |
| `kria_regressao` | 1.280 | 2,94 LSB (informativo) | 187 µs | ✅ |

**8/8**, 192 matrizes / 6.144 palavras, 0 erros de dado e de `tlast`, 0
`UVM_ERROR`/`UVM_WARNING`/`UVM_FATAL`. ~1 s por teste.
(`reports/regressao.txt`, `[SB_RESUMO]` de cada log)

Os percentuais de cobertura por teste e os tempos simulados diferem dos do
Verilator (2ª sessão): o sorteio não é o mesmo entre simuladores. O que
precisa bater (passou, EVM, palavras comparadas nos testes determinísticos)
bate.

### Cobertura (IMC, merge das 8 rodadas)

| Métrica | Resultado | Fonte |
|---|---|---|
| Funcional | **94,4 %** (51/54 bins): saída 6/6, registradores 19/19, ocupação 15/15, entrada 11/14 | `cobertura_funcional.txt` |
| Asserções (por `bind`) | 8/8 exercitadas, 0 falhas | idem |
| Código, núcleo `top_isfft` (local) | 99,6 % (279/280); estágios da FFT/IFFT 99,3–99,9 % | `cobertura_resumo.txt` |
| Código, wrapper `isfft_axi_v4` (local) | 70,7 % (848/1.200), média 81,5 % | idem |
| Código, modelos das macros (OpenRAM) | 57,5 % / 58,5 % | idem |

Bins não cobertos:

| Bin | Por que faltou (leitura, não conferida) |
|---|---|
| `cg_ent.cp_esperas.curta` (DUT segura `tready` 1–3 ciclos) | o buffer de entrada só enche com a saída travada; a espera aí é longa |
| `cg_ent.cp_pos_trunc.primeira` (truncado de 1 palavra) | tamanho sorteado de 1 a 31: ponta rara (8 truncados no total) |
| `cg_ent.cp_pos_trunc.penult` (truncado de 31 palavras) | idem |

### Avisos do Xcelium

| Aviso | O que é | Efeito |
|---|---|---|
| `*W,CGDEFN` (4 por teste) | os covergroups não têm nome de instância explícito; o Xcelium inventa um | nenhum; cosmético |
| `imc: *W,REPDEP` | `report` é o comando antigo do IMC; recomenda `report_metrics` | nenhum |

### Para depois (não mexido agora, pedido do Lukas)

| Item | Ideia |
|---|---|
| Truncado nas pontas (2 bins) | sortear o tamanho com peso em 1 e 31 |
| Espera curta na entrada (1 bin) | ver se é alcançável; se não, tirar o bin e justificar |
| Wrapper com 70,7 % de código | relatório de código detalhado no IMC para achar o que falta |
| Modelos da OpenRAM na cobertura de código | excluir (não são nossos) com um arquivo de configuração de cobertura |
| `CGDEFN` | `option.name` nos 4 grupos (conferido: o Verilator 5.052 aceita) |
| Mais sementes | bloco 2 com `SEMENTES` > 1 |

**Vira slide?** Sim: `doc/tabelas_uvm.md` (8 tabelas).

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U18 | Regressão UVM no Xcelium aceita como referência (8/8, cobertura funcional 94,4 %) | 🟡 | Primeira rodada na VM; buracos conhecidos e listados |

---

## 2026-10-07 — 5ª sessão: a cobertura de 30/09 na GUI do IMC

**Pedido do Lukas:** abrir o merge da regressão de 30/09 na interface
gráfica do IMC e ver onde estão os buracos, antes de mexer em qualquer
coisa. Fonte desta sessão: telas do IMC 24.09 na VM (`work/cov_merged`,
o mesmo merge do `imc.log` de 30/09) e os relatórios em
`resultados/2026-09-30_uvm_regressao/reports/`.

### 🐛 `imc -load cov_merged`: procurou em `cov_work/scope/`

**Sintoma:** `*E,CNTRDDR: Cannot read directory 'cov_work/scope/cov_merged'`
e `*E,INVDM: Valid model file not found`, rodando de dentro de `work/`,
onde o `cov_merged` existe.
**Causa:** o IMC trata nome relativo como **nome de rodada** e procura em
`cov_work/scope/<nome>`, onde o Xcelium grava cada teste.
**Resolvi com:** caminho absoluto: `imc -load $PWD/cov_merged &`. O
comentário do bloco 3 já usava `${UVM_WORK}/cov_merged` (absoluto).
**Tempo gasto:** 2 min. **Vira slide?** Não.

### 🔑 A GUI soma a subárvore; o relatório em texto, só o módulo

| Instância | GUI (módulo + filhos) | `cobertura_resumo.txt` (só o módulo) |
|---|---|---|
| `isfft_axi_v4` | 87,05 % / 93,21 % (23.210 / 24.902) | 81,51 % / **70,67 % (848 / 1.200)** |
| `inst_isfft_matriz` | 94,52 % / 95,41 % (21.902 / 22.955) | 99,82 % / 99,64 % (279 / 280) |
| `inst_ifft_1d` | 92,08 % / 95,2 % (10.765 / 11.308) | 99,87 % / 99,87 % (781 / 782) |

O núcleo Spiral tem 22.955 dos 24.902 itens da subárvore do
`isfft_axi_v4`: o número de cima é quase só o núcleo, e esconde o
wrapper. **Leitura:** cobertura de código de um bloco se relata pelo
número **local** (U19).
**Vira slide?** Sim: "93 % ou 71 %? Depende de contar os filhos".

### `isfft_axi_v4` com os filhos, por métrica (Details → Metrics)

| Métrica | Coberto | % |
|---|---|---|
| Bloco | 657 / 731 | 89,88 % |
| Expressão | 28 / 38 | 73,68 % |
| Toggle | 22.509 / 24.117 | 93,33 % |
| FSM | 8 / 8 | 100 % |
| Asserções | 8 / 8 | 100 % |

Toggle é 97 % dos itens. No `inst_ifft_1d` (Details): 264 blocos (83,46 %),
10.528 toggles de ~11.300 (97,44 %), expressão e FSM 0/0.

| Visão "Verification Metrics" (tudo) | Coberto |
|---|---|
| Bloco | 1.131 / 1.228 (92,1 %) |
| Expressão | 56 / 76 (73,68 %) |
| Toggle | 39.191 / 41.990 (93,33 %) |
| FSM | 16 / 16 |
| Asserções | **15 / 15**: 8 dentro do DUT (`bind`) + 7 de protocolo nas interfaces do tb |
| Covergroups | 102 / 108 (94,44 %) |

(Essa visão soma "Types" e "Instances": o mesmo item aparece duas vezes.
Não usar para relatório.)

### O que conta como DUT e não é nosso

| Instância | Coberto (com filhos) | O que é |
|---|---|---|
| `u_in_mem` / `u_out_mem` | 59,25 % / 60,61 % | modelos `.v` da OpenRAM |
| `u_sva` (3: no wrapper e dentro das duas macros) | 88,37 % / 94,12 % / 95,24 % | **nossas asserções**: o `bind` as coloca dentro do `-covdut isfft_axi_v4`, e o código delas entra na cobertura de código do DUT |

O status das asserções é 100 % nas três. O que fica abaixo de 100 % é o
**código** delas, que não é RTL do chip. **Achado novo**, entra nas
exclusões junto com os modelos da OpenRAM (U20).

### Núcleo: o que falta é toggle de constante

Mais baixos: `stage3` 77,0 % (1.206 / 1.566) e `stage6` 94,9 %; dentro do
`codeBlockIsnt41913`, `instD8inst0`/`instD6inst0` com 16,67 % (9/54) e
`m41072…m41123` com 56 % (`cobertura_resumo.txt`). São os multiplicadores
pelos fatores de rotação da DFT8 (constantes): bits que não mudam por
construção. **Leitura, a conferir no Source:** não falta estímulo; é
exclusão justificada.

### Os 3 bins de entrada, com as contagens (`cobertura_funcional.txt`, l. 114–126)

| Bin | Acertos | Os vizinhos |
|---|---|---|
| `cp_esperas.curta` (1–3 ciclos) | 0 | `nenhuma` 6.298, `longa` **6** |
| `cp_pos_trunc.primeira` (posição 0) | 0 | `meio` **8** (8 truncados em toda a regressão) |
| `cp_pos_trunc.penult` (posição 30) | 0 | idem |

### O que as abas Block / Expression / Toggle mostraram (telas do IMC)

| Aba | Achado | Leitura |
|---|---|---|
| Expression | As **12** expressões da subárvore (28/38 itens) estão **todas** em `u_in_mem`/`u_out_mem` (modelo da OpenRAM, linhas 55–91; ex.: linha 70, `!csb0 && !web0 && !csb1 && (addr0 == addr1)`, 3/5) | O wrapper e o núcleo têm **0 expressões pontuadas**. O Xcelium, por padrão, só pontua condições com `&&`/`\|\|` dentro de `if`; o `isfft_axi_v4.v` usa `&` e `assign` (ex.: linha 161, `assign s00_axis_tready = ~dp_rst & (in_used != IN_DEPTH)`; linha 311, `else if (core_next_out & core_armado)`). Depois da U20, expressão fica 0/0 — **não é 100 %, é "não medido"** (U21) |
| Block | Bloco não coberto no `write_fsm.v` do núcleo, linha 55: `if (ifft_next_out == 1'b1)` com **0 %** — "a IFFT já está mandando a próxima matriz emendada" | Em toda a regressão, a FSM de escrita nunca viu duas matrizes **emendadas** saindo da IFFT. Buraco de **estímulo** (vazão máxima na entrada com a saída livre), não de código morto. A investigar |
| Toggle | `reset` dos `perm*` do Spiral com 0/1 (só uma das duas transições); `writeSel` dos `memMod` com 0 % | `writeSel` é `1'b1` fixo no Spiral (FE, 3ª sessão): constante, exclusão justificada. O `reset` sobe no começo e cai, mas nunca **volta a subir**: o soft reset (`dp_rst`) não chega ao núcleo pelo mesmo fio? A conferir no RTL |

### U20 aplicada: `scripts/cobertura.ccf`

**Decisão do Lukas:** excluir os modelos da OpenRAM e as 3 `u_sva`.

**Como:** na **compilação**, com um arquivo de configuração de cobertura
(`-covfile`), e não com refinamento no IMC:

| | `.ccf` (compilação) | Refinamento no IMC (`.vRefine`) |
|---|---|---|
| O que faz | o item **não entra** no modelo de cobertura | o item é medido e depois **marcado** como excluído, com comentário |
| Para quê | o que não é projeto (modelo de simulação, checker do tb) | o que é projeto mas é inalcançável (constantes do Spiral), com justificativa revisável |
| Custo | refazer a regressão (blocos 2 e 3; ~10 s por teste) | nenhum |

```
deselect_coverage -all -module sram_1rw1r_64x64_wpr2
deselect_coverage -all -module sram_1rw1r_64x256
deselect_coverage -all -module isfft_v4_sva
deselect_coverage -all -module sram_1rw1r_sva
```

Por **módulo** (nomes conferidos: `tb/isfft_tb_top.sv` linhas 118–127,
`tb/isfft_sva.sv` linhas 24 e 72), não por caminho. `-all` = bloco,
expressão, FSM e toggle; as asserções são cobertura funcional e
continuam contando.

Mudanças no `run_first_uvm.tcl`:
- `XRUN_OPTS` com `-covfile ${UVM_DIR}/scripts/cobertura.ccf`;
- bloco 0 mostra as linhas do log sobre o `.ccf`;
- bloco 2 apaga `cov_work/scope` antes da regressão (rodadas com o
  modelo antigo misturariam dois modelos no merge);
- bloco 3 mostra o que sobrou de `u_in_mem`/`u_out_mem`/`u_sva`.

**Não conferido aqui** (sem Xcelium na nuvem): a sintaxe do `.ccf`. O
bloco 0 mostra se o `xrun` aceitou. Se reclamar do `-module`, a saída é
`-instance isfft_axi_v4.u_in_mem...` etc.

**Esperado depois de refazer os blocos 0, 2 e 3:**

| Item | Antes | Esperado |
|---|---|---|
| Regressão | 8/8 | 8/8 (nada mudou no estímulo) |
| Funcional | 94,4 % (51/54) | igual |
| Asserções | 8/8 no DUT | 8/8 (se cair, o `-all` levou as asserções junto) |
| `u_in_mem`, `u_out_mem`, `u_sva` no código | 59–95 % | ausentes ou n/a |
| Expressão no `isfft_axi_v4` (subárvore) | 28/38 | **0/0** (ver U21) |
| Wrapper local | 848/1.200 | igual (a exclusão é só dos filhos) |

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U19 | Cobertura de código relatada pelo número **local** de cada módulo (wrapper: 848/1.200), não pela subárvore | 🟡 | A subárvore do wrapper é 92 % núcleo Spiral |
| U20 | Excluir da cobertura de código: modelos da OpenRAM e as 3 instâncias `u_sva` (bind), na compilação (`cobertura.ccf`); toggles constantes do Spiral só com justificativa (refinamento) | ✅ | Decisão do Lukas. Não são RTL do chip; o `bind` põe o tb dentro do `-covdut` |
| U21 | Ligar a pontuação de expressão para `&`, `\|` e `assign` (no `.ccf`) | 🟡 proposta | Hoje o wrapper tem 0 expressões medidas: a métrica não diz nada sobre ele |

---

## 2026-10-21 — 6ª sessão: a VM foi atualizada; PATH novo

### 🐛 `imc: command not found` (e `xrun` também)

**Sintoma:** com o PATH de sempre, `imc -load $PWD/cov_merged` →
`bash: imc: command not found`; `which xrun` também não acha.
**Causa:** a VM goku foi **atualizada** entre 07/10 e 21/10. O `/tools`
está montado, mas as pastas da Cadence têm outros nomes
(`ls /tools/cadence/`):

| Ferramenta | Até 07/10 | Agora | Para quê aqui |
|---|---|---|---|
| Xcelium | `XCELIUM2309` | **`XCELIUM2603`** | simulação, UVM |
| vManager (traz o `imc`) | `VMANAGER2409` | **`VMANAGER2603`** | cobertura |
| Conformal | `CONFRML232` | **`CONFRML261`** (há também `CONFRML251`) | LEC |
| Genus | `DDI221` | `DDI221` (igual; há também `DDI261`, `DDIEXPORT23`) | síntese |
| Modus | `MODUS231` | `MODUS261` | ATPG (DFT) |
| Tempus (SSV) / Quantus / Pegasus | `231`/`221`/`231` | `SSV261` / `QUANTUS261` / `PEGASUS261` | |
| PVS / Spectre | `PVS231` / `SPECTRE231` | `PVS251` / `SPECTRE251` | |
| Virtuoso | `ICADVM201` | `IC618` | |

O `imc` de 07/10 era o **24.09** (`imc.log` de 30/09), do vManager, não do
Xcelium: por isso foi o primeiro a sumir.
**Resolvi com:** PATH novo no `CLAUDE.md`, no `run_first_uvm.tcl` e no
`run_first.tcl` (este é do GDSII: só a linha do PATH; registrado lá, 32ª
sessão). Critério: a versão mais nova de cada ferramenta, **menos o
Genus**, que fica no 22.1 (`DDI221`), o mesmo de todas as sínteses.
Enquanto o pacote novo não chega: `/tools/cadence/VMANAGER2603/bin/imc`.
**Tempo gasto:** 10 min. **Vira slide?** Não (mas vale a lição: o PATH
fixo é um retrato da máquina; quando a máquina muda, o erro é "command
not found", não um erro da ferramenta).

### O que muda para a verificação

| Ponto | Por quê | Como conferir |
|---|---|---|
| Versão do UVM do `-uvm` | O Xcelium 23.09 escolheu o **1.1d**; o 26.03 pode escolher outra. O código roda em 1.2 e IEEE 1800.2 (U8) | linha `[TESTE] UVM:` dos logs |
| Regressão de 30/09 deixa de ser comparável ciclo a ciclo | outro simulador, outro sorteio | 8/8, EVM da Kria igual (3,4122 / 0,7822 / 0,5965 %) |
| Merge de cobertura | rodadas do 23.09 e do 26.03 não se misturam | o bloco 2 já apaga `cov_work/scope` (5ª sessão) |
| `cobertura.ccf` (U20) | nunca rodou: a 1ª rodada já é no 26.03 | bloco 0 |

A 1ª regressão no 26.03 é ao mesmo tempo a **requalificação do ambiente**
e a 1ª rodada com a U20.

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U22 | Ferramentas da VM: a versão mais nova de cada uma, menos o Genus (22.1) | 🟡 | As versões antigas sumiram; o Genus 22.1 continua e é o das sínteses |

---

## 2026-10-21 — 7ª sessão: os buracos de cobertura, e o núcleo estoura acima de 23.170

**Pedido do Lukas:** seguir com o UVM. Antes de mandar a regressão para a
VM, investigar na nuvem os buracos que o IMC mostrou (5ª sessão), para
que o que sair deles rode na mesma regressão.

Ferramentas na nuvem: Icarus 12 (apt) para o núcleo sozinho e o tb da
Kria com sondas; Verilator 5.052 (tag, compilado do fonte) para o UVM.
Scripts das sondas ficaram só na nuvem (não entram no repositório): o
que importa são os números abaixo.

### 🔍 `write_fsm.v:55` (0 %): o wrapper nunca emenda duas matrizes

**Sintoma:** bloco não coberto no núcleo: `if (ifft_next_out == 1'b1)`
dentro do fim da matriz — "a IFFT já está mandando a próxima matriz
emendada".
**Causa (lida no RTL e medida):** o liberador do `isfft_axi_v4.v`
(linhas 222–238) só dispara com `~launch_active`; quando a 32ª palavra
sai, `launch_active` cai, e só no ciclo seguinte o `launch_start` pode
subir. **Toda matriz custa 33 ciclos para 32 palavras**: o `next_out` da
matriz seguinte chega sempre 1 ciclo depois do fim da anterior, e a FSM
passa pelo `IDLE`. Sonda no `write_fsm` (Icarus, tb da Kria):

| Cenário | Instância | Matrizes | Emendadas (linha 55) | Ciclos entre o fim de uma e o `next_out` da seguinte |
|---|---|---|---|---|
| tb da Kria (pausas, `tready` 75 %) | wrapper da etapa 1 (referência) | 40 | **39** | 0 |
| idem | `isfft_axi_v4` (v3 igual) | 40 | **0** | mín. 8, máx. 4.040 |
| entrada a 1 palavra/ciclo, `tready` 100 % | `isfft_axi_v4` | 40 / 80 | **0** | **mín. = máx. = 1** |

O núcleo emenda (a referência da etapa 1 faz 39 de 40); o wrapper da Kria
(e a v4, que copiou o liberador) é que não deixa. **Inalcançável por
construção no chip** → exclusão justificada (refinamento no IMC), não
teste novo. Custo da bolha: 1/33 = 3 % de vazão.
**Vira slide?** Sim: "cobertura de código achou 1 ciclo perdido por
matriz no wrapper".

### 🔍 `cg_ent.cp_esperas.curta` (0 acertos): só a vazão máxima chega lá

A mesma bolha explica: com entrada a 1 palavra/ciclo e saída livre, o
buffer de entrada (64) ganha 1 palavra a cada 33 ciclos, enche, e o DUT
segura o `tready` por **1 ciclo**. Sonda no tb da Kria a vazão cheia:
**7 esperas curtas em 40 matrizes, 47 em 80**; 0 longas. Nenhum teste da
regressão tinha entrada sem pausa **e** `tready` 100 % por muitas matrizes.
**Resolvi com:** `isfft_vazao_test` (80 matrizes, sem pausa, `tready`
100 %, `PKT_MAT` 4).

### 🔍 `cp_pos_trunc.primeira` / `.penult`: sorteio uniforme de 1 a 31

Com 8 truncados na regressão inteira, as pontas (1 e 31 palavras) têm
~25 % de chance de aparecer. **Resolvi com:** `sorteia_trunc()` no
`isfft_aleatorio_vseq`: os 2 primeiros truncados são as pontas
(dirigido) e o resto tem peso 1/5 em cada ponta.

### 🐛 O `isfft_vazao_test` falhou: o núcleo Spiral estoura acima de 23.170

**Sintoma (Verilator):** 80 matrizes, **0 erros bit a bit**, mas
`SB_NUM matriz 39 (amplitude 32654): erro max 4096.73 LSB, medio 1024.70`.
**Causa:** bit a bit igual à referência e errado no numérico = defeito no
**núcleo** (o mesmo nos dois lados — a lição das mutações N1/N2, 1ª
sessão). Isolado no Icarus, núcleo sozinho (wrapper da etapa 1) e o modelo
do `evm.py`:

| Entrada | Amplitude | Matrizes | Estouraram |
|---|---|---|---|
| constante, impulso, rampa, senoide, aleatória | até 32.654 | 20 | 0 |
| aleatória uniforme | 16.384 / 24.576 / 28.672 | 150 cada | 0 / 0 / 0 |
| aleatória uniforme | 32.767 | 150 | **1** (0,7 %) |
| **±A em toda componente** | 16.384 / 22.000 / **23.170** | 200 cada | **0 / 0 / 0** |
| **±A em toda componente** | **23.500** / 24.576 / 28.672 | 200 cada | **47 / 36 / 43** |
| ±A em toda componente | 32.767 | 200 | **186** (93 %) |

Onde: o erro cai nas **colunas 1 e 5 da saída, nas 8 linhas** (16
elementos) → estouro na **1ª** transformada (IFFT das linhas), na
borboleta dos bins 1 e 5, espalhado pela FFT das colunas. Erro de
~4.096 = 32.768/8 (uma volta de 16 bits, dividida pelos estágios
seguintes). No RTL: as borboletas somam em 17 bits e descartam o bit de
baixo (`codeBlock40889.v`, `tm52[16:1]`): sem estouro. O estágio de
rotação multiplica pelo fator de 45° ((1−j)/√2): `re' = (a + b)/√2` chega
a **√2 · A** — e não há bit de guarda. Limite: **32.767/√2 = 23.170**,
exatamente onde a tabela vira.
**Por que a 1ª sessão disse "não há saturação em escala cheia":** a
medição foi com dado **uniforme** (59 matrizes de 8.193 a 32.767), onde o
estouro ocorre em ~0,7 % das matrizes cheias. Medir com o pior caso (±A)
mostrou o limite.
**Resolvi com (U23, decisão do Lukas):** a faixa válida da entrada do IP
passa a ser **|re|, |im| ≤ 23.170** (−3 dB da escala cheia). Sem tocar no
RTL (front-end fechado; o núcleo é o da Kria).
- `isfft_matriz.svh`: `FAIXA_MAX = 23170`; `AMP_CHEIA` vai até ela;
  faixa nova `AMP_FORA` (acima) e tipo novo `MAT_SINAIS` (±A), fora do
  sorteio geral.
- Scoreboard: matriz com amplitude > 23.170 continua cobrada **bit a
  bit**; o numérico só é **contado** (`SB_RESUMO`: "fora da faixa
  válida … N matrizes, M estouraram").
- `isfft_kria_regressao_test`: o dado cheio de 16 bits do tb da Kria vira
  `AMP_FORA` (lá o numérico já era só informativo).
- Teste novo **`isfft_estouro_test`**: 40 matrizes ±32.767; cobra bit a
  bit e registradores; mostra quantas estouram.
**Tempo gasto:** ~1 h 30 min (com a compilação do Verilator).
**Vira slide?** Sim, o melhor da verificação: "o bit a bit passou; só o
modelo independente viu" + a tabela do limiar 23.170 / 23.500 + a conta
√2 · A. E vale para o sistema OTFS: o firmware tem que escalar a matriz
para ≤ 23.170 antes de mandar ao IP.

### 🔍 `reset` do Spiral com uma transição só (toggle)

O soft reset chega ao núcleo: `dp_rst = ~aresetn | ctrl_soft_rst` (linha
127) → `core_rst_cnt` → `core_rst` (linhas 145–148) → `top_isfft.reset`.
Então, no `isfft_soft_reset_test`, o `reset` deveria subir de novo. **A
conferir na GUI**, antes de rodar o bloco 2 (que apaga
`cov_work/scope`): abrir só aquela rodada
(`imc -load isfft_soft_reset_test_s1`, nome relativo = rodada em
`cov_work/scope/`, 5ª sessão) e ver o toggle do `reset` dos `perm*`.

### U21 no `cobertura.ccf`

```
set_expr_coverable_operators -all
set_expr_coverable_statements -all
```
Põe `&`, `|` e `assign` na cobertura de expressão. **Não conferido**
(sem Xcelium na nuvem): o bloco 0 mostra se o `xrun` aceitou.

### Outras mudanças

| Arquivo | Mudança |
|---|---|
| `env/isfft_cobertura.svh` | contagem dos 3 bins que faltavam no `[COBERTURA]` do log (o Verilator só dá a % do grupo) |
| `sim/run_uvm_verilator.sh` | `O0=1`: C++ sem otimização. O maior arquivo do UVM passou de 5 GB com `-Os`/`-O1` e foi morto (OOM) na sessão de 7 GB |
| `run_first_uvm.tcl`, `run_uvm_verilator.sh` | 10 testes (+ `isfft_vazao_test`, `isfft_estouro_test`) |

### Regressão no Verilator 5.052 (com tudo acima)

`O0=1 JOBS=1 UVM_SRC=... bash sim/run_uvm_verilator.sh`, semente 1;
compilação 184 s (com `ccache` da tentativa anterior). Log:
`build/uvm_verilator/vm/verification/uvm_isfft/reports/`.

| Teste | Bit a bit | Numérico | Entrada (grupo) | Bins novos: curta / trunc. 1ª / trunc. 31ª | Resultado |
|---|---|---|---|---|---|
| `fumaca` | 32 | 1 matriz ok | 35,7 % | 0 / 0 / 0 | ✅ |
| `registradores` | — | — | 0 % | 0 / 0 / 0 | ✅ |
| `kria` | 96 | EVM 3,4122 / 0,7822 / 0,5965 % = placa | 50,0 % | 0 / 0 / 0 | ✅ |
| `aleatorio` | 1.280 | 40 ok | 57,1 % | 0 / 0 / 0 | ✅ |
| `truncado` | 1.280 | 40 ok | **85,7 %** (era 71,4 %) | 0 / **1** / **2** | ✅ |
| `contrapressao` | 1.920 | 60 ok | 64,3 % | 0 / 0 / 0 | ✅ |
| `soft_reset` | 256 (2 épocas) | 8 ok | 78,6 % | 0 / 0 / 0 | ✅ |
| `kria_regressao` | 1.280 | (informativo) | 71,4 % | 0 / 0 / 0 | ✅ |
| **`vazao`** | 2.560 | 80 ok | 57,1 % | **77** / 0 / 0 | ✅ |
| **`estouro`** | 1.280 | fora da faixa: **37 de 40 estouraram** (só contado) | 57,1 % | **37** / 0 / 0 | ✅ |

**10/10**, 0 `UVM_ERROR`. Somando os testes, os 3 bins que faltavam têm
acerto: a cobertura de entrada deve fechar 14/14 no merge do IMC (a
conferir na VM).

Mutações do núcleo de novo (o scoreboard mudou):
`sim/run_uvm_mutacoes.sh N1_nucleo_pingpong_linha N2_nucleo_re_im` →
versão correta PASSOU; **N1: `SB_NUM`(10); N2: `SB_NUM`(3) + `KRIA`(3)**.
A checagem numérica continua pegando o que o bit a bit não vê.

### 🐛 `%Error-BADVLTPRAGMA` num comentário

**Sintoma:** a compilação no Verilator parou em
`isfft_cobertura.svh:30: Unknown verilator comment`.
**Causa:** linha de comentário que **começa** com a palavra
`Verilator` (`// Verilator 5.052 so da ...`) é lida como diretiva
(*metacomment*, como `// verilator lint_off`).
**Resolvi com:** reescrever o comentário sem começar por essa palavra.
Regra no `CLAUDE.md`.
**Tempo:** 5 min (mais uma compilação). **Vira slide?** Não.

### Decisões da sessão

| # | Decisão | Status | Motivo |
|---|---|---|---|
| U21 | Pontuar expressões com `&`/`\|`/`assign` (`cobertura.ccf`) | ✅ | Decisão do Lukas; o wrapper tinha 0 expressões medidas |
| U23 | Faixa válida da entrada do IP: \|re\|, \|im\| ≤ 23.170; acima disso o numérico só é contado; `isfft_estouro_test` mostra o limite | ✅ | Decisão do Lukas. Núcleo sem bit de guarda no estágio de 45°: limiar medido entre 23.170 (0/200) e 23.500 (47/200) |
| U24 | `write_fsm.v:55` (matriz emendada) excluído com justificativa: o liberador nunca emenda (33 ciclos por matriz) | 🟡 | Inalcançável no chip; o núcleo emenda com o wrapper da etapa 1 |
| U25 | `isfft_vazao_test` (vazão máxima) e truncados com as pontas dirigidas | 🟡 | Únicos jeitos medidos de acertar `cp_esperas.curta` e `cp_pos_trunc.primeira/penult` |

---

## Índice de decisões

| # | Resumo | Status | Data |
|---|---|---|---|
| U1 | UVM só no IP; DUT = `frontend/` da VM | ✅ | 2026-09-26 |
| U2 | ~~`uvm/` + `monta_vm_uvm.sh`~~ → `vm/verification/uvm_isfft/` + `monta_vm.sh`; `run_first_uvm.tcl` separado; diário novo | ✅ | 2026-09-30 |
| U3 | Referência bit a bit = wrapper da etapa 1 | 🟡 | 2026-09-26 |
| U4 | Checagem numérica: ≤ 4 LSB máx., ≤ 1,5 LSB médio; EVM só na Kria | 🟡 | 2026-09-26 |
| U5 | RAL com predição explícita + `predict` dos contadores | ✅ | 2026-09-26 |
| U6 | Soft reset por épocas | ✅ | 2026-09-26 |
| U7 | Asserções com `` `uvm_error `` | ✅ | 2026-09-26 |
| U8 | Conferência no Verilator antes da VM | ✅ | 2026-09-26 |
| U9 | Clock de 50 MHz | ✅ | 2026-09-26 |
| U10 | Limites em ciclos (watchdog 500 mil), sem `set_timeout` | ✅ | 2026-09-26 |
| U11 | Limite de 20 erros por teste | ✅ | 2026-09-26 |
| U12 | 12 mutações, todas detectadas (de novo no 5.052, 2ª sessão) | ✅ | 2026-09-26 |
| U13 | Lista do DUT gerada na hora (`gera_dut_f.sh`) | 🟡 | 2026-09-30 |
| U14 | Wrapper da etapa 1 como cópia fixa em `ref/` | 🟡 | 2026-09-30 |
| U15 | Scripts do UVM no notebook em `sim/`; espelho mínimo da VM | 🟡 | 2026-09-30 |
| U16 | Cobertura por instância; Verilator 5.052 | ✅ | 2026-09-30 |
| U17 | PATH completo da VM no `run_first_uvm.tcl` | ✅ | 2026-09-30 |
| U18 | Regressão no Xcelium: 8/8, funcional 94,4 % | 🟡 | 2026-09-30 |
| U19 | Cobertura de código pelo número local de cada módulo | 🟡 | 2026-10-07 |
| U20 | Excluir modelos da OpenRAM e `u_sva` (bind) da cobertura de código (`cobertura.ccf`) | ✅ | 2026-10-07 |
| U21 | Pontuar expressões com `&`/`\|`/`assign` | ✅ | 2026-10-21 |
| U22 | Ferramentas da VM: as mais novas, menos o Genus (22.1) | 🟡 | 2026-10-21 |
| U23 | Faixa válida da entrada: \|re\|,\|im\| ≤ 23.170 (núcleo estoura acima) | ✅ | 2026-10-21 |
| U24 | `write_fsm.v:55` excluído com justificativa (wrapper nunca emenda) | 🟡 | 2026-10-21 |
| U25 | `isfft_vazao_test` + truncados nas pontas | 🟡 | 2026-10-21 |

---

## Pendências abertas

- [x] ~~Integrar no repositório e na pasta da VM~~ — 2ª sessão
- [x] ~~Refazer a conferência no Verilator na estrutura nova~~ — 8/8, 12/12
- [x] ~~Rodar na VM: blocos 0 a 3~~ — 4ª sessão: 8/8, IMC funcionou
- [x] ~~Fechar os 3 bins de entrada~~ — 7ª sessão: `isfft_vazao_test` + truncados dirigidos (a conferir no Xcelium)
- [ ] Cobertura de código do wrapper (70,7 %) e excluir os modelos da OpenRAM
- [x] ~~Ver a cobertura na GUI do IMC~~ — 5ª sessão
- [ ] VM (Xcelium 26.03): blocos 0, 2 e 3 com o `cobertura.ccf` (U20) — requalifica o ambiente — e trazer com `traz_uvm.sh`
- [ ] Wrapper por métrica, **local** (relatório do IMC, não print; falta a sintaxe: `help report`)
- [x] ~~Bloco 0% no `write_fsm.v:55`~~ — inalcançável: o liberador gasta 33 ciclos por matriz (U24)
- [ ] Refinamento no IMC: excluir `write_fsm.v:55` (U24) e os toggles constantes do Spiral, com comentário
- [ ] `reset` do Spiral só com uma transição: o caminho existe (linhas 127/145–148); conferir na GUI a rodada `isfft_soft_reset_test_s1` **antes** do bloco 2
- [ ] Confirmar U3, U4, U13, U14, U15, U19, U22, U24, U25
- [ ] Síntese com DFT só no IP da ISFFT (FE-D39) — depois do UVM
