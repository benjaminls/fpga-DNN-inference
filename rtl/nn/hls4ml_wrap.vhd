library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.nn_pkg.all;

-- hls4ml_wrap.vhd: Stub/real wrapper for NN core.
-- Provides a ready/valid streaming interface for integration tests.

entity hls4ml_wrap is
  generic (
    G_DATA_WIDTH : natural := NN_DATA_WIDTH;
    G_STUB       : boolean := true
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    in_valid   : in  std_logic;
    in_ready   : out std_logic;
    in_data    : in  signed(G_DATA_WIDTH-1 downto 0);
    in_last    : in  std_logic;

    out_valid  : out std_logic;
    out_ready  : in  std_logic;
    out_data   : out signed(G_DATA_WIDTH-1 downto 0);
    out_last   : out std_logic
  );
end entity;

architecture rtl of hls4ml_wrap is
  signal hold_valid : std_logic := '0';
  signal hold_data  : signed(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal hold_last  : std_logic := '0';
begin
  -- Stub mode: 1-cycle latency passthrough
  in_ready <= '1' when hold_valid = '0' else '0';
  out_valid <= hold_valid;
  out_data  <= hold_data;
  out_last  <= hold_last;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        hold_valid <= '0';
        hold_data  <= (others => '0');
        hold_last  <= '0';
      else
        if hold_valid = '1' and out_ready = '1' then
          hold_valid <= '0';
        end if;

        if in_valid = '1' and in_ready = '1' then
          if G_STUB then
            hold_data  <= in_data; -- y = x
            hold_last  <= in_last;
            hold_valid <= '1';
          else
            -- TODO: instantiate real hls4ml core and map ports
            hold_data  <= in_data;
            hold_last  <= in_last;
            hold_valid <= '1';
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
