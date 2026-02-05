library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_stream_fifo is
end entity;

architecture tb of tb_stream_fifo is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 1 ms;
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';
  signal in_valid  : std_logic := '0';
  signal in_ready  : std_logic;
  signal in_data   : std_logic_vector(7 downto 0) := (others => '0');
  signal out_valid : std_logic;
  signal out_ready : std_logic := '0';
  signal out_data  : std_logic_vector(7 downto 0);

  procedure send_byte(
    signal s_in_data  : out std_logic_vector(7 downto 0);
    signal s_in_valid : out std_logic;
    signal s_in_ready : in  std_logic;
    signal s_clk      : in  std_logic;
    b                 : std_logic_vector(7 downto 0)
  ) is
  begin
    s_in_data  <= b;
    s_in_valid <= '1';
    wait until rising_edge(s_clk);
    while s_in_ready = '0' loop
      wait until rising_edge(s_clk);
    end loop;
    s_in_valid <= '0';
  end procedure;

  procedure expect_byte(
    signal s_out_data  : in  std_logic_vector(7 downto 0);
    signal s_out_valid : in  std_logic;
    signal s_out_ready : out std_logic;
    signal s_clk       : in  std_logic;
    b                  : std_logic_vector(7 downto 0)
  ) is
  begin
    s_out_ready <= '1';
    wait until rising_edge(s_clk);
    while s_out_valid = '0' loop
      wait until rising_edge(s_clk);
    end loop;
    assert s_out_data = b report "FIFO data mismatch" severity failure;
    s_out_ready <= '0';
  end procedure;
begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process
  begin
    wait for TIMEOUT;
    assert false report "tb_stream_fifo timeout" severity failure;
  end process;

  uut: entity work.stream_fifo
    generic map (
      G_DATA_WIDTH => 8,
      G_DEPTH => 4
    )
    port map (
      clk => clk,
      rst => rst,
      in_valid => in_valid,
      in_ready => in_ready,
      in_data => in_data,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data
    );

  stim: process
  begin
    -- reset
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    -- basic ordering
    send_byte(in_data, in_valid, in_ready, clk, x"11");
    send_byte(in_data, in_valid, in_ready, clk, x"22");
    send_byte(in_data, in_valid, in_ready, clk, x"33");

    expect_byte(out_data, out_valid, out_ready, clk, x"11");
    expect_byte(out_data, out_valid, out_ready, clk, x"22");
    expect_byte(out_data, out_valid, out_ready, clk, x"33");

    -- backpressure: fill FIFO (depth = 4)
    out_ready <= '0';
    send_byte(in_data, in_valid, in_ready, clk, x"AA");
    send_byte(in_data, in_valid, in_ready, clk, x"BB");
    send_byte(in_data, in_valid, in_ready, clk, x"CC");
    send_byte(in_data, in_valid, in_ready, clk, x"DD");
    wait until rising_edge(clk);
    assert in_ready = '0' report "FIFO should be full" severity failure;

    -- drain
    expect_byte(out_data, out_valid, out_ready, clk, x"AA");
    expect_byte(out_data, out_valid, out_ready, clk, x"BB");
    expect_byte(out_data, out_valid, out_ready, clk, x"CC");
    expect_byte(out_data, out_valid, out_ready, clk, x"DD");

    wait for 5*CLK_PERIOD;
    report "tb_stream_fifo completed" severity note;
    stop;
    wait;
  end process;
end architecture;
