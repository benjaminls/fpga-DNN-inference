library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- uart_byte_stream.vhd: UART <-> internal byte stream bridge.
-- Exposes ready/valid byte streams for protocol layer integration.

entity uart_byte_stream is
  generic (
    G_CLKS_PER_BIT : natural := 868
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    uart_rx    : in  std_logic;
    uart_tx    : out std_logic;

    rx_valid   : out std_logic;
    rx_ready   : in  std_logic;
    rx_data    : out std_logic_vector(7 downto 0);

    tx_valid   : in  std_logic;
    tx_ready   : out std_logic;
    tx_data    : in  std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of uart_byte_stream is
begin
  u_rx: entity work.uart_rx
    generic map (G_CLKS_PER_BIT => G_CLKS_PER_BIT)
    port map (
      clk => clk,
      rst => rst,
      rx => uart_rx,
      out_valid => rx_valid,
      out_ready => rx_ready,
      out_data => rx_data
    );

  u_tx: entity work.uart_tx
    generic map (G_CLKS_PER_BIT => G_CLKS_PER_BIT)
    port map (
      clk => clk,
      rst => rst,
      in_valid => tx_valid,
      in_ready => tx_ready,
      in_data => tx_data,
      tx => uart_tx
    );
end architecture;
