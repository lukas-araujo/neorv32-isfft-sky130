# CLAUDE.md — instruções para qualquer chat que trabalhe neste repositório

Este arquivo é lido automaticamente quando o repositório é anexado a uma
sessão. Ele diz **como trabalhar aqui**; o **estado do projeto** está nos
diários.

## Quem e o quê

- Dono: Lukas Araújo da Silva (Engenharia Eletrônica, UnB). Conversa em
  **português**; arquivos, comentários e diários também.
- Projeto: SoC NEORV32 + acelerador ISFFT em SkyWater 130 nm, macros
  SRAM da OpenRAM, do RTL ao GDSII. Não vai para tapeout: é aprendizado,
  vira aula e relatório — **prefira a opção que ensina mais** e explique
  o porquê.

## Antes de fazer qualquer coisa

1. `README.md` — mapa de pastas, **donos de cada pasta**, dependências.
2. O diário da sua frente (a última sessão diz onde parou):

| Frente | Diário | Prefixo das decisões | Pastas que são suas |
|---|---|---|---|
| Front-end (fechado) | `DIARIO.md` | D (citado como FE-Dn) | — (só correções) |
| Back-end / GDSII | `DIARIO_GDSII.md` | L | `macros/`, `openram/`, `tech/`, `vm/backend/synthesis/`, `layout/` |
| UVM do IP da ISFFT | `DIARIO_UVM.md` (criar) | U | `vm/verification/uvm_isfft/` |
| DFT do IP da ISFFT | `DIARIO_DFT.md` (criar) | T | `vm/backend/dft_isfft/` |

Fora das suas pastas: **só leitura**. Se precisar mudar algo de outra
frente (ex.: RTL), registre o motivo no **seu** diário, rode as
regressões (`sim/run_tb_isfft_ref.sh`, `sim/run_tb_evm.sh`) e avise o
Lukas.

## Regras de trabalho (pedidas pelo Lukas)

- **Atualize o diário a cada etapa**, no formato dele (🐛 Sintoma /
  Causa / Resolvi com / Tempo / Vira slide?; tabela de decisões da sessão
  + índice no fim). Decisão nova = 🟡 até o Lukas confirmar.
- **Números vêm de arquivo, não de memória.** Leia o relatório/log antes
  de afirmar; diga de onde veio.
- Comandos do Genus, Xcelium e Conformal vão **dentro do `run_first.tcl`**
  (blocos comentados), nunca em `.sh` separados.
- **A pasta da VM nunca é editada à mão**: edite `vm/` e rode
  `bash sim/monta_vm.sh` (copia tudo o que está em `vm/`). Na VM o Lukas
  só comenta/descomenta blocos.
- Resultado que volta da VM ou do LibreLane vai para
  `resultados/<AAAA-MM-DD>_<etapa>/` (relatórios, netlist, logs úteis
  compactados; nada de `xcelium.d/`, `work/`, `.sdf`, `runs/`).
  **Da VM, quem traz é o Lukas, pelo git:** ele copia a pasta da VM para
  o notebook, roda `bash sim/traz_vm.sh <pasta> <etapa>` e dá push. Ao
  começar, `git pull` e procure resultado novo em `resultados/` antes de
  pedir arquivo no chat.
- Antes de mandar algo para a VM, confira o que der com ferramentas
  abertas (`sim/run_gls_yosys.sh`: RTL e portas com Yosys + Icarus).

## Git (a sessão do Claude tem permissão de push)

O repositório é `lukas-araujo/neorv32-isfft-sky130` (privado). Numa
sessão nova do Claude: anexar com a ferramenta de repositório (acesso
**push**), clonar **uma vez** e registrar a raiz. O clone é raso e de
**um ramo só**: `origin/main` **não existe** como referência local —
use sempre `git pull --rebase origin main` (ou `git fetch origin main`
+ `FETCH_HEAD`). Antes de dar push, traga o `main` remoto (senão o push
reenvia tudo e o GitHub recusa com HTTP 413).

```bash
git pull --rebase origin main              # sempre antes de começar
bash macros/descompacta_gds.sh             # .gds.gz -> .gds (fora do git)
# ... trabalho ...
git add <arquivos das suas pastas + seu diário>
git -c user.name="Lukas Araújo da Silva" -c user.email="texugomatoso@gmail.com" \
    commit -m "<frente>: <o quê> (<decisão>)"
git pull --rebase origin main && git push origin main
```

- Prefixos de mensagem: `fe:`, `gdsii:`, `uvm:`, `dft:`, `doc:`.
- Mensagem de commit termina com as linhas de atribuição
  (`Co-Authored-By: ...`) que a sessão indicar.
- **Nunca** versionar `.gds` descompactado (o de 8 kB tem 61 MB; o
  GitHub recusa acima de 100 MB). Macros só como `.gds.gz`.
- Mudou algo que o Lukas usa no notebook ou na VM? Diga no fim da
  resposta: "rode `git pull`" e, se for o caso, mande o `.tgz` da pasta
  da VM montada.

## Ambiente

| Onde | O quê |
|---|---|
| Notebook (Linux-Batata) | Ubuntu 24.04, i7-1165G7 (4 núcleos / 8 threads), 32 GB, 3 TB. OSS CAD Suite (GHDL, Icarus, Yosys), OpenRAM, LibreLane (Nix). Repositório em `~/Projects/neorv32-isfft-sky130` |
| VM goku (aluno12) | Genus 22.1, Xcelium 23.09, Conformal 23.2, Tempus. **Sem** PVS/Pegasus/Quantus. Sem permissão de instalação; só envia arquivos e roda ferramentas |
| Sessão do Claude (nuvem) | Sem ferramentas EDA de fábrica: `pip install --break-system-packages yowasp-yosys` e `apt-get install -y iverilog` resolvem Yosys e Icarus. NEORV32 (commit `8bdbe48`) clonável do GitHub se precisar do `sim/convert.sh` |

## Armadilhas já pagas (não repita)

- Simulação de portas: `-define FUNCTIONAL -define 'UNIT_DELAY=#1'`
  (o `sky130_fd_sc_hd.v` não tem `specify`; sem isso tudo fica em X).
- Macros de 1 porta: **33 bits + `spare_wen0`** em tudo (`.lib` corrigido
  por `macros/lib_33bits.py`). `SRAM_LIB_VIEW` não existe mais.
- Variável colada em texto no bash: `${m}_TT...`, nunca `$m_TT...`.
- Mutação só prova algo quando a versão correta passa primeiro.
- `.gitignore` não aceita comentário no fim da linha.
