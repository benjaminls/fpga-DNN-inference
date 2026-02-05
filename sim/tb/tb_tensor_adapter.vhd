library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;

-- tb_tensor_adapter.vhd: Unit test for tensor_adapter packing/unpacking.
-- Verifies little-endian byte order and element boundaries.

entity tb_tensor_adapter is
end entity;

architecture tb of tb_tensor_adapter is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 2 ms;

  signal clk   : std_logic := '0';
  signal rst   : std_logic := '1';

  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal in_data  : std_logic_vector(7 downto 0) := (others => '0');
  signal in_last  : std_logic := '0';

  signal t_valid : std_logic;
  signal t_ready : std_logic := '1';
  signal t_data  : signed(15 downto 0);
  signal t_last  : std_logic;

  signal t_out_valid : std_logic := '0';
  signal t_out_ready : std_logic;
  signal t_out_data  : signed(15 downto 0) := (others => '0');
  signal t_out_last  : std_logic := '0';

  signal out_valid : std_logic;
  signal out_ready : std_logic := '1';
  signal out_data  : std_logic_vector(7 downto 0);
  signal out_last  : std_logic;

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant IN_BYTES : byte_arr_t := (x"02", x"01", x"80", x"FF"); -- 0x0102, 0xFF80

  signal t_count  : integer := 0;
  signal out_count: integer := 0;

  procedure send_byte(
    signal s_data  : out std_logic_vector(7 downto 0);
    signal s_valid : out std_logic;
    signal s_ready : in  std_logic;
    signal s_last  : out std_logic;
    signal s_clk   : in  std_logic;
    b              : std_logic_vector(7 downto 0);
    last           : std_logic
  ) is
  begin
    s_data  <= b;
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
    assert false report "tb_tensor_adapter timeout" severity failure;
  end process;

  uut: entity work.tensor_adapter
    generic map (G_DATA_WIDTH => 16)
    port map (
      clk => clk,
      rst => rst,
      in_valid => in_valid,
      in_ready => in_ready,
      in_data => in_data,
      in_last => in_last,
      tensor_valid => t_valid,
      tensor_ready => t_ready,
      tensor_data => t_data,
      tensor_last => t_last,
      tensor_out_valid => t_out_valid,
      tensor_out_ready => t_out_ready,
      tensor_out_data => t_out_data,
      tensor_out_last => t_out_last,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data,
      out_last => out_last
    );

  monitor_in: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        t_count <= 0;
      else
        if t_valid = '1' and t_ready = '1' then
          if t_count = 0 then
            assert t_data = to_signed(16#0102#, 16) report "tensor 0 mismatch" severity failure;
            assert t_last = '0' report "tensor 0 last mismatch" severity failure;
          else
            assert t_data = to_signed(16#FF80#, 16) report "tensor 1 mismatch" severity failure;
            assert t_last = '1' report "tensor 1 last mismatch" severity failure;
          end if;
          t_count <= t_count + 1;
        end if;
      end if;
    end if;
  end process;

  monitor_out: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_count <= 0;
      else
        if out_valid = '1' and out_ready = '1' then
          assert out_data = IN_BYTES(out_count) report "out byte mismatch" severity failure;
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

    -- Drive input payload bytes
    send_byte(in_data, in_valid, in_ready, in_last, clk, IN_BYTES(0), '0');
    send_byte(in_data, in_valid, in_ready, in_last, clk, IN_BYTES(1), '0');
    send_byte(in_data, in_valid, in_ready, in_last, clk, IN_BYTES(2), '0');
    send_byte(in_data, in_valid, in_ready, in_last, clk, IN_BYTES(3), '1');

    -- Drive output tensor stream (same values)
    wait for 2*CLK_PERIOD;
    t_out_valid <= '1';
    t_out_data  <= to_signed(16#0102#, 16);
    t_out_last  <= '0';
    wait until rising_edge(clk) and t_out_ready = '1';
    t_out_valid <= '0';

    t_out_valid <= '1';
    t_out_data  <= to_signed(16#FF80#, 16);
    t_out_last  <= '1';
    wait until rising_edge(clk) and t_out_ready = '1';
    t_out_valid <= '0';
    t_out_last  <= '0';

    while t_count < 2 loop
      wait until rising_edge(clk);
    end loop;

    while out_count < 4 loop
      wait until rising_edge(clk);
    end loop;

    report "tb_tensor_adapter completed" severity note;
    stop;
    wait;
  end process;
end architecture;
