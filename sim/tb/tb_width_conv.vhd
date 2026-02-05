library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

entity tb_width_conv is
end entity;

architecture tb of tb_width_conv is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 1 ms;
  signal clk       : std_logic := '0';
  signal rst       : std_logic := '1';

  signal in_valid  : std_logic := '0';
  signal in_ready  : std_logic;
  signal in_data   : std_logic_vector(7 downto 0) := (others => '0');

  signal w_valid   : std_logic;
  signal w_ready   : std_logic := '1';
  signal w_data    : std_logic_vector(31 downto 0);

  signal out_valid : std_logic;
  signal out_ready : std_logic := '1';
  signal out_data  : std_logic_vector(7 downto 0);
  signal reset_count : std_logic := '0';
  signal check_expected : std_logic := '1';

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant TEST_BYTES : byte_arr_t := (
    x"01", x"02", x"03", x"04",
    x"05", x"06", x"07", x"08"
  );
  signal out_count : integer := 0;

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
begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process
  begin
    wait for TIMEOUT;
    assert false report "tb_width_conv timeout" severity failure;
  end process;

  u_pack: entity work.byte_to_word
    generic map (G_WORD_WIDTH => 32)
    port map (
      clk => clk,
      rst => rst,
      in_valid => in_valid,
      in_ready => in_ready,
      in_data => in_data,
      out_valid => w_valid,
      out_ready => w_ready,
      out_data => w_data
    );

  u_unpack: entity work.word_to_byte
    generic map (G_WORD_WIDTH => 32)
    port map (
      clk => clk,
      rst => rst,
      in_valid => w_valid,
      in_ready => w_ready,
      in_data => w_data,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data
    );

  monitor: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or reset_count = '1' then
        out_count <= 0;
      else
        if out_valid = '1' and out_ready = '1' then
          if check_expected = '1' then
            assert out_data = TEST_BYTES(out_count) report "byte mismatch" severity failure;
          end if;
          out_count <= out_count + 1;
        end if;
      end if;
    end if;
  end process;

  stim: process
  begin
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    for i in TEST_BYTES'range loop
      send_byte(in_data, in_valid, in_ready, clk, TEST_BYTES(i));
    end loop;

    -- wait until all bytes are observed
    while out_count < TEST_BYTES'length loop
      wait until rising_edge(clk);
    end loop;

    -- odd-length test: send 5 bytes, expect only 4 out (no data check)
    reset_count <= '1';
    wait until rising_edge(clk);
    reset_count <= '0';
    check_expected <= '0';
    for i in 0 to 4 loop
      send_byte(in_data, in_valid, in_ready, clk, std_logic_vector(to_unsigned(i, 8)));
    end loop;
    wait for 20*CLK_PERIOD;
    assert out_count = 4 report "unexpected byte count for partial word" severity failure;

    report "tb_width_conv completed" severity note;
    stop;
    wait;
  end process;
end architecture;
