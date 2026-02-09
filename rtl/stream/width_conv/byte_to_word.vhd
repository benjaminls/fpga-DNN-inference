library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity byte_to_word is
  generic (
    G_WORD_WIDTH : natural := 32
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(7 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(G_WORD_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of byte_to_word is
  constant WORD_BYTES : natural := G_WORD_WIDTH / 8;
  signal buf   : std_logic_vector(G_WORD_WIDTH-1 downto 0) := (others => '0');
  signal count : natural range 0 to WORD_BYTES := 0;

  function set_byte(
    value : std_logic_vector(G_WORD_WIDTH-1 downto 0);
    idx   : natural;
    b     : std_logic_vector(7 downto 0)
  ) return std_logic_vector is
    variable v : std_logic_vector(G_WORD_WIDTH-1 downto 0) := value;
    variable l : natural := idx * 8;
  begin
    v(l+7 downto l) := b;
    return v;
  end function;

  signal out_valid_i : std_logic;
  signal in_ready_i  : std_logic;
begin
  out_data  <= buf;
  out_valid <= out_valid_i;

  out_valid_i <= '1' when count = WORD_BYTES else '0';
  in_ready_i  <= '1' when count < WORD_BYTES else '0';
  in_ready    <= in_ready_i;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        buf   <= (others => '0');
        count <= 0;
      else
        if out_valid_i = '1' and out_ready = '1' then
          count <= 0;
        end if;

        if in_valid = '1' and in_ready_i = '1' then
          buf   <= set_byte(buf, count, in_data);
          count <= count + 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
