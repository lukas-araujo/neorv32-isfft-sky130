// =============================================================================
// hello -- primeiro programa do NEORV32 com IMEM/DMEM em macro OpenRAM
//
// Projeto: NEORV32 + ISFFT em ASIC (sky130)
//
// Prova, em simulacao do Verilog convertido:
//   1. a CPU busca instrucoes da IMEM (macro) -- senao nada roda
//   2. a DMEM (macro) aceita escrita/leitura de palavra, meia-palavra e byte
//   3. a UART0 transmite (o testbench decodifica a linha serial)
//   4. com a IMEM de 8 kB: uma tabela de 1 kB em .rodata fica acima de
//      0x1000 e e conferida palavra a palavra -- prova a metade de CIMA da
//      macro (busca de instrucao e leitura de dado usam a mesma porta da
//      IMEM, entao o caminho de endereco e o mesmo)
// Termina com a linha "#FIM#", que o testbench usa para encerrar.
// =============================================================================
#include <neorv32.h>

#define BAUD 115200   // rapido o bastante para a simulacao (8,7 us por bit)

static volatile uint32_t buf[64];   // .bss -> DMEM

// Tabela de 1 kB com padrao conhecido. Vai para .rodata, depois do codigo:
// fica acima de 0x1000, na metade de CIMA da macro de 8 kB. Se o bit 12 do
// endereco da IMEM se perder, a leitura cai na metade de baixo e a
// conferencia falha.
#define PADRAO(n) ((uint32_t)(n) * 2654435761u ^ 0x5A5AA5A5u)
#define T4(n)   PADRAO(n), PADRAO(n+1), PADRAO(n+2), PADRAO(n+3)
#define T16(n)  T4(n), T4(n+4), T4(n+8), T4(n+12)
#define T64(n)  T16(n), T16(n+16), T16(n+32), T16(n+48)
#define T256(n) T64(n), T64(n+64), T64(n+128), T64(n+192)
static const uint32_t tabela[256] = { T256(0) };

// Com 4 kB de IMEM o printf nao cabia (estouro de 32 bytes). Com 8 kB ele
// volta -- e e de proposito: empurra o codigo para acima de 0x1000.

int main(void) {

  neorv32_rte_setup();                 // tratador de excecoes
  neorv32_uart0_setup(BAUD, 0);

  neorv32_uart0_puts("\nOla do NEORV32 com IMEM/DMEM em macro OpenRAM!\n");
  neorv32_uart0_printf("clk = %u Hz\n", neorv32_sysinfo_get_clk());

  // ---- teste da DMEM: palavra, meia-palavra e byte ----
  uint32_t i, erros = 0;
  for (i = 0; i < 64; i++) {
    buf[i] = 0xA5000000u | (i << 8) | i;
  }
  volatile uint8_t  *b8  = (volatile uint8_t  *)buf;
  volatile uint16_t *b16 = (volatile uint16_t *)buf;
  b8[1]  = 0x5A;                       // byte 1 da palavra 0
  b16[3] = 0x1234;                     // meia-palavra alta da palavra 1
  if (buf[0] != 0xA5005A00u) erros++;
  if (buf[1] != 0x12340101u) erros++;
  for (i = 2; i < 64; i++) {
    if (buf[i] != (0xA5000000u | (i << 8) | i)) erros++;
  }
  neorv32_uart0_printf("DMEM erros = %u\n", erros);

  // ---- metade de cima da IMEM (8 kB) ----
  const volatile uint32_t *t = tabela;   // volatile: o compilador nao pode dobrar a conta
  uint32_t erros_rom = 0;
  for (i = 0; i < 256; i++) {
    if (t[i] != PADRAO(i)) erros_rom++;
  }
  neorv32_uart0_printf("tabela na IMEM: 0x%x..0x%x, erros = %u\n",
                       (uint32_t)&tabela[0], (uint32_t)&tabela[255], erros_rom);
  erros += erros_rom;

  // ---- ciclos (Zicntr) ----
  uint32_t c0 = neorv32_cpu_csr_read(CSR_MCYCLE);
  for (i = 0; i < 100; i++) { asm volatile ("nop"); }
  uint32_t c1 = neorv32_cpu_csr_read(CSR_MCYCLE);
  neorv32_uart0_printf("100 nops = %u ciclos\n", c1 - c0);

  neorv32_uart0_puts(erros ? "RESULTADO: FALHOU\n" : "RESULTADO: OK\n");
  neorv32_uart0_puts("#FIM#\n");
  while (neorv32_uart0_tx_busy());
  return 0;
}
