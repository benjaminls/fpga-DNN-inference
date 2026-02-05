library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pkt_pkg.all;

-- tb_pkt_rx_tx.vhd: Unit test for packet TX->RX round-trip (no CRC).
-- Verifies header parsing and payload streaming in the protocol layer.

entity tb_pkt_rx_tx is
end entity;

architecture tb of tb_pkt_rx_tx is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 2 ms;

  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';

  signal tx_start  : std_logic := '0'; -- kick TX once
  signal tx_type   : pkt_type_t := INFER_REQ;
  signal tx_len    : std_logic_vector(15 downto 0) := x"0003";

  signal tx_in_valid : std_logic := '0';
  signal tx_in_ready : std_logic;
  signal tx_in_data  : std_logic_vector(7 downto 0) := (others => '0');

  signal link_valid : std_logic;
  signal link_ready : std_logic := '1';
  signal link_data  : std_logic_vector(7 downto 0); -- byte stream between TX and RX

  signal rx_out_valid : std_logic;
  signal rx_out_ready : std_logic := '1';
  signal rx_out_data  : std_logic_vector(7 downto 0);
  signal rx_out_last  : std_logic;

  signal rx_pkt_type  : pkt_type_t;
  signal rx_pkt_len   : std_logic_vector(15 downto 0);
  signal rx_pkt_valid : std_logic;
  signal rx_pkt_error : std_logic;

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant PAYLOAD : byte_arr_t := (x"11", x"22", x"33"); -- expected payload bytes
  signal rx_count : integer := 0; -- payload bytes observed

  procedure send_byte(
    signal s_data  : out std_logic_vector(7 downto 0);
    signal s_valid : out std_logic;
    signal s_ready : in  std_logic;
    signal s_clk   : in  std_logic;
    b              : std_logic_vector(7 downto 0)
  ) is
  begin
    s_data  <= b;
    s_valid <= '1';
    wait until rising_edge(s_clk);
    while s_ready = '0' loop
      wait until rising_edge(s_clk);
    end loop;
    s_valid <= '0';
  end procedure;

begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process -- prevent hangs if RX/TX deadlock
  begin
    wait for TIMEOUT;
    assert false report "tb_pkt_rx_tx timeout" severity failure;
  end process;

  u_tx: entity work.pkt_tx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk,
      rst => rst,
      start => tx_start,
      pkt_type => tx_type,
      pkt_len => tx_len,
      in_valid => tx_in_valid,
      in_ready => tx_in_ready,
      in_data => tx_in_data,
      out_valid => link_valid,
      out_ready => link_ready,
      out_data => link_data
    );

  u_rx: entity work.pkt_rx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk,
      rst => rst,
      in_valid => link_valid,
      in_ready => link_ready,
      in_data => link_data,
      out_valid => rx_out_valid,
      out_ready => rx_out_ready,
      out_data => rx_out_data,
      out_last => rx_out_last,
      pkt_type => rx_pkt_type,
      pkt_len => rx_pkt_len,
      pkt_valid => rx_pkt_valid,
      pkt_error => rx_pkt_error
    );

  monitor: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        rx_count <= 0;
      else
        if rx_pkt_valid = '1' then
          assert rx_pkt_type = tx_type report "pkt_type mismatch" severity failure;
          assert rx_pkt_len = tx_len report "pkt_len mismatch" severity failure;
          assert rx_pkt_error = '0' report "unexpected pkt_error" severity failure;
        end if;

        if rx_out_valid = '1' and rx_out_ready = '1' then
          assert rx_out_data = PAYLOAD(rx_count) report "payload mismatch" severity failure;
          rx_count <= rx_count + 1;
          if rx_count = PAYLOAD'length-1 then
            assert rx_out_last = '1' report "out_last not asserted" severity failure;
          end if;
        end if;
      end if;
    end if;
  end process;

  stim: process
  begin
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    tx_start <= '1';
    wait until rising_edge(clk);
    tx_start <= '0';

    for i in PAYLOAD'range loop
      send_byte(tx_in_data, tx_in_valid, tx_in_ready, clk, PAYLOAD(i));
    end loop;

    while rx_count < PAYLOAD'length loop
      wait until rising_edge(clk);
    end loop;

    report "tb_pkt_rx_tx completed" severity note;
    stop;
    wait;
  end process;
end architecture;
