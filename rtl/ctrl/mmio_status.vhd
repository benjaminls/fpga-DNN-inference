library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.build_id_pkg.all;
use work.nn_pkg.all;

-- mmio_status.vhd: Emits STATUS payload bytes on request.
-- Sits below pkt_tx: start -> byte stream of build/counters/config.

entity mmio_status is
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;
    start      : in  std_logic; -- pulse to emit a STATUS payload

    cycles     : in  std_logic_vector(31 downto 0);
    stalls     : in  std_logic_vector(31 downto 0);
    infers     : in  std_logic_vector(31 downto 0);

    out_valid  : out std_logic;
    out_ready  : in  std_logic;
    out_data   : out std_logic_vector(7 downto 0);
    out_last   : out std_logic;
    payload_len: out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of mmio_status is
  constant LEN_BYTES : natural := 20; -- build_id(4) + cycles(4) + stalls(4) + infers(4) + nn widths(4)
  signal idx         : unsigned(4 downto 0) := (others => '0');
  signal active      : std_logic := '0';

  signal cycles_reg  : std_logic_vector(31 downto 0) := (others => '0');
  signal stalls_reg  : std_logic_vector(31 downto 0) := (others => '0');
  signal infers_reg  : std_logic_vector(31 downto 0) := (others => '0');

  signal nn_data_w : std_logic_vector(15 downto 0);
  signal nn_frac_w : std_logic_vector(15 downto 0);
  signal out_data_i : std_logic_vector(7 downto 0);

begin
  payload_len <= std_logic_vector(to_unsigned(LEN_BYTES, 16));

  out_valid <= active;
  out_data  <= out_data_i;
  out_last  <= '1' when active = '1' and idx = LEN_BYTES-1 else '0';

  nn_data_w <= std_logic_vector(to_unsigned(NN_DATA_WIDTH, 16));
  nn_frac_w <= std_logic_vector(to_unsigned(NN_FRAC_WIDTH, 16));

  -- Little-endian layout for all multi-byte fields
  process (all)
  begin
    case to_integer(idx) is
      when 0  => out_data_i <= BUILD_ID(7 downto 0);
      when 1  => out_data_i <= BUILD_ID(15 downto 8);
      when 2  => out_data_i <= BUILD_ID(23 downto 16);
      when 3  => out_data_i <= BUILD_ID(31 downto 24);
      when 4  => out_data_i <= cycles_reg(7 downto 0);
      when 5  => out_data_i <= cycles_reg(15 downto 8);
      when 6  => out_data_i <= cycles_reg(23 downto 16);
      when 7  => out_data_i <= cycles_reg(31 downto 24);
      when 8  => out_data_i <= stalls_reg(7 downto 0);
      when 9  => out_data_i <= stalls_reg(15 downto 8);
      when 10 => out_data_i <= stalls_reg(23 downto 16);
      when 11 => out_data_i <= stalls_reg(31 downto 24);
      when 12 => out_data_i <= infers_reg(7 downto 0);
      when 13 => out_data_i <= infers_reg(15 downto 8);
      when 14 => out_data_i <= infers_reg(23 downto 16);
      when 15 => out_data_i <= infers_reg(31 downto 24);
      when 16 => out_data_i <= nn_data_w(7 downto 0);
      when 17 => out_data_i <= nn_data_w(15 downto 8);
      when 18 => out_data_i <= nn_frac_w(7 downto 0);
      when others => out_data_i <= nn_frac_w(15 downto 8);
    end case;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        active <= '0';
        idx <= (others => '0');
        cycles_reg <= (others => '0');
        stalls_reg <= (others => '0');
        infers_reg <= (others => '0');
      else
        if start = '1' then
          -- snapshot counters at request time
          cycles_reg <= cycles;
          stalls_reg <= stalls;
          infers_reg <= infers;
          idx <= (others => '0');
          active <= '1';
        elsif active = '1' and out_ready = '1' then
          if idx = LEN_BYTES-1 then
            active <= '0';
          else
            idx <= idx + 1;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
