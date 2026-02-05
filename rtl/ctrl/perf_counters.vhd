library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- perf_counters.vhd: Simple cycle/stall/inference counters for STATUS reporting.
-- Used by mmio_status to snapshot performance metrics.

entity perf_counters is
  generic (
    G_WIDTH : natural := 32
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    stall_pulse: in  std_logic; -- increments stall counter
    infer_pulse: in  std_logic; -- increments inference counter
    cycles     : out std_logic_vector(G_WIDTH-1 downto 0);
    stalls     : out std_logic_vector(G_WIDTH-1 downto 0);
    infers     : out std_logic_vector(G_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of perf_counters is
  signal cycles_reg : unsigned(G_WIDTH-1 downto 0) := (others => '0');
  signal stalls_reg : unsigned(G_WIDTH-1 downto 0) := (others => '0');
  signal infers_reg : unsigned(G_WIDTH-1 downto 0) := (others => '0');
begin
  cycles <= std_logic_vector(cycles_reg);
  stalls <= std_logic_vector(stalls_reg);
  infers <= std_logic_vector(infers_reg);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        cycles_reg <= (others => '0');
        stalls_reg <= (others => '0');
        infers_reg <= (others => '0');
      else
        cycles_reg <= cycles_reg + 1; -- free-running cycles
        if stall_pulse = '1' then
          stalls_reg <= stalls_reg + 1;
        end if;
        if infer_pulse = '1' then
          infers_reg <= infers_reg + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
