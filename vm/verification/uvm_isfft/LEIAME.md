# verification/uvm_isfft/ — verificação UVM do IP da ISFFT (`isfft_axi_v4`)

Ambiente UVM do **IP da ISFFT que vai no chip** (`isfft_axi_v4`, com
`in_mem` e `out_mem` nas macros OpenRAM). Fica numa pasta própria, com um
script próprio (`scripts/run_first_uvm.tcl`), para não mexer no que já foi
feito na síntese (`backend/synthesis/`, `run_first.tcl`).

O DUT **não é copiado**: a lista `work/isfft_dut.f` é gerada na hora
(`scripts/gera_dut_f.sh`) a partir de `frontend/isfft_axi_v4.v` e
`frontend/isfft/*.v`, o mesmo RTL que o Genus sintetizou. As macros vêm
de `tech/verilog/` (modelo `.v` da OpenRAM).

Fonte de verdade: `vm/verification/uvm_isfft/` do repositório; a pasta
vem para a VM pelo `sim/monta_vm.sh` (que copia tudo o que está em `vm/`).
**Não edite aqui**: mude no repositório e monte de novo.

## Como rodar (VM)

```bash
cd /prj/ci/workarea/aluno12/projetos/neorv32_isfft_soc/verification/uvm_isfft/scripts
source run_first_uvm.tcl        # bloco 1 (fumaça) já vem descomentado
```

Depois, **um bloco por vez** (comente o atual, descomente o próximo):

| Bloco | O quê | Esperado |
|---|---|---|
| 0 | Compilar e elaborar | nenhum `*E` |
| 1 | Teste de fumaça (1 matriz) | `TESTE PASSOU`, 32 palavras comparadas |
| 2 | Regressão (8 testes; `SEMENTES=n`) | todos `PASSOU` |
| 3 | Cobertura no IMC (junta as rodadas do bloco 2) | `reports/cobertura_resumo.txt` |
| 4 | Depurar um teste no SimVision | abre a GUI |

## O que tem aqui

| Pasta | Conteúdo |
|---|---|
| `tb/` | topo (`isfft_tb_top.sv`), interfaces AXI4-Lite e AXI4-Stream com asserções de protocolo, sonda e asserções internas (`bind`) |
| `agents/axil/` | agente AXI4-Lite (driver, monitor, adaptador do RAL) |
| `agents/axis/` | agente AXI4-Stream (mestre na entrada, escravo na saída) |
| `env/` | RAL (7 registradores), modelo de referência, scoreboard, cobertura, env |
| `seq/` | sequências (palavras, pacotes, truncado, soft reset, registradores) |
| `tests/` | 8 testes |
| `ref/` | `isfft_axi_wrapper.v` — wrapper da **etapa 1**, a referência bit a bit |
| `scripts/` | `run_first_uvm.tcl`, `isfft_uvm.f` (tb), `gera_dut_f.sh` (escreve a lista do DUT) |
| `work/` | onde o xrun roda (`xcelium.d`, `cov_work`, `isfft_dut.f` gerado) — criada pelo script |
| `reports/` | um log por teste, `regressao.txt`, cobertura — criada pelo script. Volta para o repositório com `bash sim/traz_uvm.sh` |

## Como o ambiente decide se passou

Cada matriz passa por **duas checagens independentes**:

1. **Bit a bit** contra o wrapper da etapa 1 (a mesma referência da
   regressão da Kria). Pega erro no wrapper novo: buffers, macros,
   pré-busca, commit/rollback, `tlast`.
2. **Numérica** contra a ISFFT em ponto flutuante (erro máximo em LSB e
   EVM). Pega erro na matemática — que a checagem 1 não vê, porque o
   núcleo Spiral é o mesmo nos dois lados.

Mais: registradores pelo RAL (contadores previstos pelo modelo), bits do
`STATUS`, asserções de protocolo AXI e invariantes internas (sem overflow,
reserva ≤ 256, pré-busca ≤ 2, macro nunca lê e escreve o mesmo endereço).
Qualquer falha vira `UVM_ERROR` e o teste termina em `TESTE FALHOU`.

## Conferido antes de vir para a VM

`sim/run_uvm_verilator.sh` roda **o mesmo ambiente, o mesmo `.f` e o
mesmo `gera_dut_f.sh`** no Verilator (≥ 5.052, UVM 2020-3.2);
`sim/run_uvm_mutacoes.sh` planta defeitos no DUT e confere que o ambiente
os pega. Resultados no `DIARIO_UVM.md` (na raiz desta pasta da VM).
