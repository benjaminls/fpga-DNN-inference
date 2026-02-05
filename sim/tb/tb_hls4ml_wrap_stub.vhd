library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- tb_hls4ml_wrap_stub.vhd: Unit test for stub NN wrapper.
-- Verifies ready/valid handshake and 1-cycle latency passthrough.

entity tb_hls4ml_wrap_stub is
end entity;

architecture tb of tb_hls4ml_wrap_stub is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 2 ms;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';

  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal in_data  : signed(15 downto 0) := (others => '0');
  signal in_last  : std_logic := '0';

  signal out_valid : std_logic;
  signal out_ready : std_logic := '1';
  signal out_data  : signed(15 downto 0);
  signal out_last  : std_logic;

  type word_arr_t is array (natural range <>) of signed(15 downto 0);
  constant VEC : word_arr_t := (to_signed(1, 16), to_signed(-2, 16));
  signal idx : integer := 0;

  procedure send_word(
    signal s_data  : out signed(15 downto 0);
    signal s_valid : out std_logic;
    signal s_ready : in  std_logic;
    signal s_last  : out std_logic;
    signal s_clk   : in  std_logic;
    w              : signed(15 downto 0);
    last           : std_logic
  ) is
  begin
    s_data  <= w;
    s_valid <= '1';
    s_last  <= last;
    wait until rising_edge(s_clk);
    while s_ready = '0' loop
      wait until rising_edge(s_clk);
    end loop;
    s_valid <= '0';
    s_last  <= '0';
  end procedure;

begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process
  begin
    wait for TIMEOUT;
    assert false report "tb_hls4ml_wrap_stub timeout" severity failure;
  end process;

  uut: entity work.hls4ml_wrap
    generic map (
      G_DATA_WIDTH => 16,
      G_STUB => true
    )
    port map (
      clk => clk,
      rst => rst,
      in_valid => in_valid,
      in_ready => in_ready,
      in_data => in_data,
      in_last => in_last,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data,
      out_last => out_last
    );

  monitor: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        idx <= 0;
      else
        if out_valid = '1' and out_ready = '1' then
          assert out_data = VEC(idx) report "stub output mismatch" severity failure;
          if idx = VEC'length-1 then
            assert out_last = '1' report "stub out_last mismatch" severity failure;
          end if;
          idx <= idx + 1;
        end if;
      end if;
    end if;
  end process;

  stim: process
  begin
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    send_word(in_data, in_valid, in_ready, in_last, clk, VEC(0), '0');
    send_word(in_data, in_valid, in_ready, in_last, clk, VEC(1), '1');

    while idx < VEC'length loop
      wait until rising_edge(clk);
    end loop;

    report "tb_hls4ml_wrap_stub completed" severity note;
    stop;
    wait;
  end process;
end architecture;
