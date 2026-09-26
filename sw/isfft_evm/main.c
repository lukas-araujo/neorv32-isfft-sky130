// =============================================================================
// isfft_evm -- validacao numerica: as 3 matrizes do notebook da Kria pelo
//              caminho DMEM -> DMA -> SLINK -> ISFFT -> SLINK -> DMA -> DMEM
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Para cada matriz:
//   1. DMA TX: 63 palavras em SLINK.DATA + 1 palavra em SLINK.DATA_LAST
//      (o 'last' vira o tlast da ISFFT -- D29)
//   2. espera a FIFO RX do SLINK encher (64 palavras = 1 matriz de saida)
//   3. DMA RX: 64 palavras de SLINK.DATA para a DMEM
//   4. imprime "CHK <m> <soma>" -- o testbench compara com a referencia
//   5. imprime "DUMP <m> <endereco>" -- o testbench copia as 64 palavras
//      da DMEM para saida_<m>.hex e o evm.py calcula o EVM
// Termina com "#FIM#".
//
// vetores.h e gerado por evm.py (python3 evm.py gera vetores.h).
//
// Registradores da ISFFT: os mesmos da Kria (0x4001_0000).
// Sem printf: nao cabe em 4 kB (ver DIARIO).
// =============================================================================
#include <neorv32.h>
#include "vetores.h"   // N_MAT e matriz[][] (evm.py)

#define BAUD 1000000   // 1 Mbaud: so para simulacao (texto rapido)

// ---- ISFFT (mapa da Kria) ----
#define ISFFT_BASE     0x40010000UL
#define ISFFT_REG(o)   (*(volatile uint32_t *)(ISFFT_BASE + (o)))
#define ISFFT_CTRL     ISFFT_REG(0x00)
#define ISFFT_STATUS   ISFFT_REG(0x04)
#define ISFFT_MAT_IN   ISFFT_REG(0x08)
#define ISFFT_MAT_OUT  ISFFT_REG(0x0C)
#define ISFFT_ERR_CNT  ISFFT_REG(0x10)
#define ISFFT_ID       ISFFT_REG(0x14)
#define ISFFT_PKT_MAT  ISFFT_REG(0x18)
#define ISFFT_ID_OK    0x15FF0300UL

#define PALAVRAS 64               // 32 palavras de 64 bits = 64 de 32

static uint32_t entrada[PALAVRAS];
static uint32_t saida[PALAVRAS];

static void put_hex(uint32_t v) {
  const char *h = "0123456789abcdef";
  neorv32_uart0_puts("0x");
  for (int s = 28; s >= 0; s -= 4) neorv32_uart0_putc(h[(v >> s) & 0xf]);
}

static void falha(const char *msg) {
  neorv32_uart0_puts("ERRO: "); neorv32_uart0_puts(msg);
  neorv32_uart0_puts("\nRESULTADO: FALHOU\n#FIM#\n");
  while (neorv32_uart0_tx_busy());
  while (1);
}

// espera o DMA terminar os descritores da fila
static void dma_espera(void) {
  int st;
  do { st = neorv32_dma_status(); } while (st == DMA_STATUS_BUSY);
  if (st == DMA_STATUS_ERROR) falha("DMA");
}

int main(void) {

  neorv32_uart0_setup(BAUD, 0);
  neorv32_uart0_puts("\nisfft_evm: matrizes da Kria pelo chip\n");

  if (ISFFT_ID != ISFFT_ID_OK) falha("ID da ISFFT");

  // ISFFT: reset do caminho de dados, 1 matriz por pacote, liga
  ISFFT_CTRL = 1u << 1;
  ISFFT_CTRL = 0;
  ISFFT_PKT_MAT = 1;
  ISFFT_CTRL = 1u << 0;

  NEORV32_SLINK->CTRL = 1u << SLINK_CTRL_EN;
  neorv32_dma_enable();

  for (uint32_t m = 0; m < N_MAT; m++) {

    // matriz de entrada: da ROM para a DMEM (na Kria ela estava na DDR)
    for (int i = 0; i < PALAVRAS; i++) entrada[i] = matriz[m][i];

    uint32_t t0 = neorv32_cpu_csr_read(CSR_MCYCLE);

    // 1. TX: 63 palavras + a ultima com 'last'
    //    (a fila de descritores precisa caber 2: IO_DMA_DSC_FIFO = 8 -- D30)
    if (neorv32_dma_program((uint32_t)&entrada[0], (uint32_t)&NEORV32_SLINK->DATA,
                            (PALAVRAS - 1) | DMA_SRC_INC_WORD | DMA_DST_CONST_WORD)) falha("DMA desc TX 1");
    if (neorv32_dma_program((uint32_t)&entrada[PALAVRAS - 1], (uint32_t)&NEORV32_SLINK->DATA_LAST,
                            1 | DMA_SRC_INC_WORD | DMA_DST_CONST_WORD)) falha("DMA desc TX 2");
    neorv32_dma_start();
    dma_espera();

    // 2. espera a matriz de saida inteira na FIFO RX
    uint32_t n = 0;
    while (!(NEORV32_SLINK->CTRL & (1u << SLINK_CTRL_RX_FULL))) {
      if (++n > 100000) falha("timeout RX");
    }

    // 3. RX: 64 palavras para a DMEM
    if (neorv32_dma_program((uint32_t)&NEORV32_SLINK->DATA, (uint32_t)&saida[0],
                            PALAVRAS | DMA_SRC_CONST_WORD | DMA_DST_INC_WORD)) falha("DMA desc RX");
    neorv32_dma_start();
    dma_espera();

    uint32_t t1 = neorv32_cpu_csr_read(CSR_MCYCLE);

    // a ultima palavra lida tem que ter vindo com 'last'
    if (!(NEORV32_SLINK->CTRL & (1u << SLINK_CTRL_RX_LAST))) falha("sem last na saida");

    uint32_t soma = 0;
    for (int i = 0; i < PALAVRAS; i++) soma = (soma << 1 | soma >> 31) ^ saida[i];

    neorv32_uart0_puts("CHK "); neorv32_uart0_putc('0' + m);
    neorv32_uart0_puts(" "); put_hex(soma);
    neorv32_uart0_puts(" ciclos "); put_hex(t1 - t0);
    neorv32_uart0_puts("\n");
    neorv32_uart0_puts("DUMP "); neorv32_uart0_putc('0' + m);
    neorv32_uart0_puts(" "); put_hex((uint32_t)&saida[0]);
    neorv32_uart0_puts("\n");
    while (neorv32_uart0_tx_busy());   // testbench le a DMEM antes da proxima matriz
  }

  neorv32_uart0_puts("MAT_IN "); put_hex(ISFFT_MAT_IN);
  neorv32_uart0_puts(" MAT_OUT "); put_hex(ISFFT_MAT_OUT);
  neorv32_uart0_puts(" ERR "); put_hex(ISFFT_ERR_CNT);
  neorv32_uart0_puts("\n");

  if (ISFFT_MAT_OUT != N_MAT || ISFFT_ERR_CNT != 0) falha("contadores da ISFFT");

  neorv32_uart0_puts("RESULTADO: OK\n#FIM#\n");
  while (neorv32_uart0_tx_busy());
  return 0;
}
