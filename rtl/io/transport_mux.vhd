library ieee;
use ieee.std_logic_1164.all;

-- transport_mux.vhd: Selects UART vs DPTI byte streams by generic.
-- Keeps protocol layer transport-agnostic.

entity transport_mux is
  generic (
    G_USE_UART : boolean := true
  );
  port (
    uart_rx_valid : in  std_logic;
    uart_rx_ready : out std_logic;
    uart_rx_data  : in  std_logic_vector(7 downto 0);
    uart_tx_valid : out std_logic;
    uart_tx_ready : in  std_logic;
    uart_tx_data  : out std_logic_vector(7 downto 0);

    dpti_rx_valid : in  std_logic;
    dpti_rx_ready : out std_logic;
    dpti_rx_data  : in  std_logic_vector(7 downto 0);
    dpti_tx_valid : out std_logic;
    dpti_tx_ready : in  std_logic;
    dpti_tx_data  : out std_logic_vector(7 downto 0);

    rx_valid      : out std_logic;
    rx_ready      : in  std_logic;
    rx_data       : out std_logic_vector(7 downto 0);
    tx_valid      : in  std_logic;
    tx_ready      : out std_logic;
    tx_data       : in  std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of transport_mux is
begin
  -- RX selection
  rx_valid <= uart_rx_valid when G_USE_UART else dpti_rx_valid;
  rx_data  <= uart_rx_data  when G_USE_UART else dpti_rx_data;
  uart_rx_ready <= rx_ready when G_USE_UART else '0';
  dpti_rx_ready <= rx_ready when (not G_USE_UART) else '0';

  -- TX selection
  uart_tx_valid <= tx_valid when G_USE_UART else '0';
  dpti_tx_valid <= tx_valid when (not G_USE_UART) else '0';
  tx_ready <= uart_tx_ready when G_USE_UART else dpti_tx_ready;
  uart_tx_data <= tx_data when G_USE_UART else (others => '0');
  dpti_tx_data <= tx_data when (not G_USE_UART) else (others => '0');
end architecture;
