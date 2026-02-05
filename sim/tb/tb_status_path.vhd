library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.build_id_pkg.all;
use work.nn_pkg.all;

-- tb_status_path.vhd: Unit test for mmio_status payload formatting.
-- Verifies byte order and length for STATUS response fields.

entity tb_status_path is
end entity;

architecture tb of tb_status_path is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 2 ms;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';
  signal start : std_logic := '0';

  signal cycles : std_logic_vector(31 downto 0) := x"01020304";
  signal stalls : std_logic_vector(31 downto 0) := x"A0A1A2A3";
  signal infers : std_logic_vector(31 downto 0) := x"0B0C0D0E";

  signal out_valid : std_logic;
  signal out_ready : std_logic := '1';
  signal out_data  : std_logic_vector(7 downto 0);
  signal out_last  : std_logic;
  signal payload_len : std_logic_vector(15 downto 0);

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant NN_DATA_W : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(NN_DATA_WIDTH, 16));
  constant NN_FRAC_W : std_logic_vector(15 downto 0) := std_logic_vector(to_unsigned(NN_FRAC_WIDTH, 16));

  constant EXPECTED : byte_arr_t := (
    BUILD_ID(7 downto 0), BUILD_ID(15 downto 8), BUILD_ID(23 downto 16), BUILD_ID(31 downto 24),
    x"04", x"03", x"02", x"01",
    x"A3", x"A2", x"A1", x"A0",
    x"0E", x"0D", x"0C", x"0B",
    NN_DATA_W(7 downto 0),
    NN_DATA_W(15 downto 8),
    NN_FRAC_W(7 downto 0),
    NN_FRAC_W(15 downto 8)
  );

  signal idx : integer := 0;

begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process
  begin
    wait for TIMEOUT;
    assert false report "tb_status_path timeout" severity failure;
  end process;

  uut: entity work.mmio_status
    port map (
      clk => clk,
      rst => rst,
      start => start,
      cycles => cycles,
      stalls => stalls,
      infers => infers,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data,
      out_last => out_last,
      payload_len => payload_len
    );

  monitor: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        idx <= 0;
      else
        if out_valid = '1' and out_ready = '1' then
          assert out_data = EXPECTED(idx) report "status byte mismatch" severity failure;
          if idx = EXPECTED'length-1 then
            assert out_last = '1' report "out_last not asserted" severity failure;
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

    assert payload_len = std_logic_vector(to_unsigned(EXPECTED'length, 16))
      report "payload_len mismatch" severity failure;

    start <= '1';
    wait until rising_edge(clk);
    start <= '0';

    while idx < EXPECTED'length loop
      wait until rising_edge(clk);
    end loop;

    report "tb_status_path completed" severity note;
    stop;
    wait;
  end process;
end architecture;
