library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity word_to_byte is
  generic (
    G_WORD_WIDTH : natural := 32
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(G_WORD_WIDTH-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of word_to_byte is
  constant WORD_BYTES : natural := G_WORD_WIDTH / 8;
  signal buf   : std_logic_vector(G_WORD_WIDTH-1 downto 0) := (others => '0');
  signal idx   : natural range 0 to WORD_BYTES := 0;
  signal busy  : std_logic := '0';

  function get_byte(
    value : std_logic_vector(G_WORD_WIDTH-1 downto 0);
    i     : natural
  ) return std_logic_vector is
    variable l : natural := i * 8;
  begin
    return value(l+7 downto l);
  end function;
begin
  in_ready  <= '1' when busy = '0' else '0';
  out_valid <= busy;
  out_data  <= get_byte(buf, idx);

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        buf  <= (others => '0');
        idx  <= 0;
        busy <= '0';
      else
        if busy = '0' then
          if in_valid = '1' and in_ready = '1' then
            buf  <= in_data;
            idx  <= 0;
            busy <= '1';
          end if;
        else
          if out_ready = '1' then
            if idx = WORD_BYTES-1 then
              idx  <= 0;
              busy <= '0';
            else
              idx <= idx + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
