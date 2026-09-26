-- =====================================================================
-- neorv32_asic.vhd
--
-- Wrapper de conversao do NEORV32 para o ASIC (sky130).
-- Projeto: NEORV32 + ISFFT em ASIC
--
-- Este arquivo e o que o GHDL converte em UM Verilog unico
-- (sim/convert.sh). Por isso:
--   - nada de generics na entidade: a configuracao fica fixa aqui dentro;
--   - portas so com std_ulogic / std_ulogic_vector de largura fixa.
--
-- Contem: neorv32_top + xbus2axi4_bridge. A ISFFT (Verilog) liga-se por
-- fora, no topo Verilog, pelas portas AXI4-Lite e SLINK daqui.
--
-- IMEM e DMEM NAO sao compiladas do VHDL: neorv32_imem.vhd e
-- neorv32_dmem.vhd ficam de fora da conversao e viram caixas-pretas,
-- preenchidas pelos nossos rtl/neorv32_imem.v e rtl/neorv32_dmem.v
-- (macro OpenRAM). Ver DIARIO.md, D13.
-- =====================================================================
--
-- CONFIGURACAO -- o que mudou em relacao a Kria, e por que
--
--   CLOCK_FREQUENCY   100 MHz -> 50 MHz   periodo que fechou na sintese
--   BOOT_MODE_SELECT  1 -> 2              programa na IMEM (ROM) (D28)
--   IMEM_EN           false -> true       IMEM = macro OpenRAM (D13)
--   IMEM_SIZE         -> 8 kB             macro OpenRAM de 8 kB (D27)
--   DMEM_SIZE         32 kB -> 4 kB       macro OpenRAM de 4 kB (D13)
--   CPU_RF_ARCH_SEL   1 -> 2              flip-flops (D9)
--   IO_UART0_*_FIFO   64/64 -> 1/1        FIFO em flip-flop so para log (D6)
--   IO_DMA_EN         false -> true       substitui o AXI DMA (D19)
--   IO_DMA_DSC_FIFO   4 -> 8              4 entradas = 1 descritor so! (D30)
--   IO_SLINK_EN       false -> true       stream para a ISFFT (D19)
--   IO_SLINK_*_FIFO   -> 64               uma matriz inteira (D19)
--
--   Igual a Kria: RISCV_ISA_C/M/Zicntr, sem caches, sem burst, sem OCD.
-- =====================================================================

library ieee;
use ieee.std_logic_1164.all;

library neorv32;
use neorv32.neorv32_package.all;

entity neorv32_asic is
  port (
    clk_i          : in  std_ulogic;
    rstn_i         : in  std_ulogic;
    -- UART0 (log) --
    uart0_txd_o    : out std_ulogic;
    uart0_rxd_i    : in  std_ulogic;
    -- AXI4-Lite para a ISFFT (controle) --
    m_axi_awaddr   : out std_ulogic_vector(31 downto 0);
    m_axi_awprot   : out std_ulogic_vector(2 downto 0);
    m_axi_awvalid  : out std_ulogic;
    m_axi_awready  : in  std_ulogic;
    m_axi_wdata    : out std_ulogic_vector(31 downto 0);
    m_axi_wstrb    : out std_ulogic_vector(3 downto 0);
    m_axi_wvalid   : out std_ulogic;
    m_axi_wready   : in  std_ulogic;
    m_axi_bresp    : in  std_ulogic_vector(1 downto 0);
    m_axi_bvalid   : in  std_ulogic;
    m_axi_bready   : out std_ulogic;
    m_axi_araddr   : out std_ulogic_vector(31 downto 0);
    m_axi_arprot   : out std_ulogic_vector(2 downto 0);
    m_axi_arvalid  : out std_ulogic;
    m_axi_arready  : in  std_ulogic;
    m_axi_rdata    : in  std_ulogic_vector(31 downto 0);
    m_axi_rresp    : in  std_ulogic_vector(1 downto 0);
    m_axi_rvalid   : in  std_ulogic;
    m_axi_rready   : out std_ulogic;
    -- SLINK (dados para/da ISFFT) --
    slink_rx_dat_i : in  std_ulogic_vector(31 downto 0);
    slink_rx_val_i : in  std_ulogic;
    slink_rx_lst_i : in  std_ulogic;
    slink_rx_rdy_o : out std_ulogic;
    slink_tx_dat_o : out std_ulogic_vector(31 downto 0);
    slink_tx_val_o : out std_ulogic;
    slink_tx_lst_o : out std_ulogic;
    slink_tx_rdy_i : in  std_ulogic
  );
end entity;

architecture neorv32_asic_rtl of neorv32_asic is

  -- XBUS entre o processador e a ponte --
  signal xbus_adr, xbus_dat_w, xbus_dat_r : std_ulogic_vector(31 downto 0);
  signal xbus_cti, xbus_tag               : std_ulogic_vector(2 downto 0);
  signal xbus_sel                         : std_ulogic_vector(3 downto 0);
  signal xbus_we, xbus_stb, xbus_cyc, xbus_ack, xbus_err : std_ulogic;

  -- sinais AXI4 da ponte que nao existem em AXI4-Lite --
  signal awaddr, araddr, wdata : std_logic_vector(31 downto 0);
  signal awprot, arprot        : std_logic_vector(2 downto 0);
  signal wstrb                 : std_logic_vector(3 downto 0);
  signal awvalid, wvalid, bready, arvalid, rready : std_logic;

begin

  -- -------------------------------------------------------------------
  -- Processador
  -- -------------------------------------------------------------------
  neorv32_top_inst: neorv32_top
  generic map (
    CLOCK_FREQUENCY  => 50_000_000,
    BOOT_MODE_SELECT => 2,               -- IMEM como ROM (D28)
    RISCV_ISA_C      => true,
    RISCV_ISA_M      => true,
    RISCV_ISA_Zicntr => true,
    CPU_RF_ARCH_SEL  => 2,               -- flip-flops (D9)
    IMEM_EN          => true,
    IMEM_SIZE        => 8*1024,          -- macro de 8 kB (D27)
    IMEM_OUTREG_EN   => false,
    DMEM_EN          => true,
    DMEM_SIZE        => 4*1024,
    DMEM_OUTREG_EN   => false,
    ICACHE_EN        => false,
    DCACHE_EN        => false,
    XBUS_EN          => true,
    XBUS_TIMEOUT     => 2048,
    XBUS_REGSTAGE_EN => false,
    IO_UART0_EN      => true,
    IO_UART0_RX_FIFO => 1,
    IO_UART0_TX_FIFO => 1,
    IO_DMA_EN        => true,
    IO_DMA_DSC_FIFO  => 8,               -- 1 descritor = 3 entradas: 8 cabe 2 (D30)
    IO_SLINK_EN      => true,
    IO_SLINK_RX_FIFO => 64,
    IO_SLINK_TX_FIFO => 64
  )
  port map (
    clk_i          => clk_i,
    rstn_i         => rstn_i,
    xbus_adr_o     => xbus_adr,
    xbus_dat_o     => xbus_dat_w,
    xbus_cti_o     => xbus_cti,
    xbus_tag_o     => xbus_tag,
    xbus_we_o      => xbus_we,
    xbus_sel_o     => xbus_sel,
    xbus_stb_o     => xbus_stb,
    xbus_cyc_o     => xbus_cyc,
    xbus_dat_i     => xbus_dat_r,
    xbus_ack_i     => xbus_ack,
    xbus_err_i     => xbus_err,
    slink_rx_dat_i => slink_rx_dat_i,
    slink_rx_src_i => (others => '0'),
    slink_rx_val_i => slink_rx_val_i,
    slink_rx_lst_i => slink_rx_lst_i,
    slink_rx_rdy_o => slink_rx_rdy_o,
    slink_tx_dat_o => slink_tx_dat_o,
    slink_tx_dst_o => open,
    slink_tx_val_o => slink_tx_val_o,
    slink_tx_lst_o => slink_tx_lst_o,
    slink_tx_rdy_i => slink_tx_rdy_i,
    uart0_txd_o    => uart0_txd_o,
    uart0_rxd_i    => uart0_rxd_i
  );

  -- -------------------------------------------------------------------
  -- Ponte XBUS -> AXI4 (a mesma validada na Kria), sem burst (D2)
  --
  -- AXI4 -> AXI4-Lite so por ligacao (D16): sem burst a ponte ja emite
  -- 1 beat por transacao. awlen/awsize/awburst/awcache/wlast e os de
  -- leitura ficam abertos; rlast = '1' (o escravo Lite nao tem).
  -- -------------------------------------------------------------------
  xbus2axi4_bridge_inst: entity neorv32.xbus2axi4_bridge
  generic map (
    BURST_EN  => false,
    BURST_LEN => 4
  )
  port map (
    clk           => std_logic(clk_i),
    resetn        => std_logic(rstn_i),
    xbus_adr_i    => xbus_adr,
    xbus_dat_i    => xbus_dat_w,
    xbus_cti_i    => xbus_cti,
    xbus_tag_i    => xbus_tag,
    xbus_we_i     => xbus_we,
    xbus_sel_i    => xbus_sel,
    xbus_stb_i    => xbus_stb,
    xbus_cyc_i    => xbus_cyc,
    xbus_ack_o    => xbus_ack,
    xbus_err_o    => xbus_err,
    xbus_dat_o    => xbus_dat_r,
    m_axi_awaddr  => awaddr,
    m_axi_awlen   => open,
    m_axi_awsize  => open,
    m_axi_awburst => open,
    m_axi_awcache => open,
    m_axi_awprot  => awprot,
    m_axi_awvalid => awvalid,
    m_axi_awready => std_logic(m_axi_awready),
    m_axi_wdata   => wdata,
    m_axi_wstrb   => wstrb,
    m_axi_wlast   => open,
    m_axi_wvalid  => wvalid,
    m_axi_wready  => std_logic(m_axi_wready),
    m_axi_araddr  => araddr,
    m_axi_arlen   => open,
    m_axi_arsize  => open,
    m_axi_arburst => open,
    m_axi_arcache => open,
    m_axi_arprot  => arprot,
    m_axi_arvalid => arvalid,
    m_axi_arready => std_logic(m_axi_arready),
    m_axi_rdata   => std_logic_vector(m_axi_rdata),
    m_axi_rresp   => std_logic_vector(m_axi_rresp),
    m_axi_rlast   => '1',
    m_axi_rvalid  => std_logic(m_axi_rvalid),
    m_axi_rready  => rready,
    m_axi_bresp   => std_logic_vector(m_axi_bresp),
    m_axi_bvalid  => std_logic(m_axi_bvalid),
    m_axi_bready  => bready
  );

  m_axi_awaddr  <= std_ulogic_vector(awaddr);
  m_axi_awprot  <= std_ulogic_vector(awprot);
  m_axi_awvalid <= std_ulogic(awvalid);
  m_axi_wdata   <= std_ulogic_vector(wdata);
  m_axi_wstrb   <= std_ulogic_vector(wstrb);
  m_axi_wvalid  <= std_ulogic(wvalid);
  m_axi_bready  <= std_ulogic(bready);
  m_axi_araddr  <= std_ulogic_vector(araddr);
  m_axi_arprot  <= std_ulogic_vector(arprot);
  m_axi_arvalid <= std_ulogic(arvalid);
  m_axi_rready  <= std_ulogic(rready);

end architecture;
