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

## Índice de decisões

| # | Resumo | Status | Data |
|---|---|---|---|
| U1 | UVM só no IP; DUT = `frontend/` da VM | ✅ | 2026-09-26 |
| U2 | `uvm/` no projeto + `monta_vm_uvm.sh`; `run_first_uvm.tcl` separado; diário novo | ✅ | 2026-09-26 |
| U3 | Referência bit a bit = wrapper da etapa 1 | 🟡 | 2026-09-26 |
| U4 | Checagem numérica: ≤ 4 LSB máx., ≤ 1,5 LSB médio; EVM só na Kria | 🟡 | 2026-09-26 |
| U5 | RAL com predição explícita + `predict` dos contadores | ✅ | 2026-09-26 |
| U6 | Soft reset por épocas | ✅ | 2026-09-26 |
| U7 | Asserções com `` `uvm_error `` | ✅ | 2026-09-26 |
| U8 | Conferência no Verilator antes da VM | ✅ | 2026-09-26 |
| U9 | Clock de 50 MHz | ✅ | 2026-09-26 |
| U10 | Limites em ciclos (watchdog 500 mil), sem `set_timeout` | ✅ | 2026-09-26 |
| U11 | Limite de 20 erros por teste | ✅ | 2026-09-26 |
| U12 | 12 mutações, todas detectadas | ✅ | 2026-09-26 |

---

## Pendências abertas

- [ ] **Rodar na VM:** bloco 0 (compilar) e bloco 1 (fumaça)
- [ ] Bloco 2 (regressão) e bloco 3 (cobertura no IMC) — conferir a sintaxe do IMC na VM
- [ ] Confirmar U3 e U4
- [ ] Olhar os buracos de cobertura depois do merge (bloco 3)
- [ ] Síntese com DFT só no IP da ISFFT (FE-D39) — depois do UVM
