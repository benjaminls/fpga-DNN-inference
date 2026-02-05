library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- crc16.vhd: CRC-16/CCITT-FALSE byte-wise engine used by packet RX/TX.
-- Fits into the protocol layer to optionally validate packet integrity.

entity crc16 is
  generic (
    G_INIT : std_logic_vector(15 downto 0) := x"FFFF"
  );
  port (
    clk     : in  std_logic;
    rst     : in  std_logic;
    clear   : in  std_logic; -- synchronous re-init
    enable  : in  std_logic; -- step per input byte
    data_in : in  std_logic_vector(7 downto 0);
    crc_out : out std_logic_vector(15 downto 0)
  );
end entity;

architecture rtl of crc16 is
  signal crc_reg : std_logic_vector(15 downto 0) := G_INIT; -- running CRC

  function next_crc(
    crc  : std_logic_vector(15 downto 0);
    data : std_logic_vector(7 downto 0)
  ) return std_logic_vector is
    variable c : std_logic_vector(15 downto 0) := crc;
    variable d : std_logic_vector(7 downto 0) := data;
    constant POLY : std_logic_vector(15 downto 0) := x"1021"; -- CRC-16/CCITT-FALSE polynomial
  begin
    for i in 0 to 7 loop -- MSB-first, bitwise update per byte
      if (c(15) xor d(7-i)) = '1' then
        c := (c(14 downto 0) & '0') xor POLY;
      else
        c := c(14 downto 0) & '0';
      end if;
    end loop;
    return c;
  end function;
begin
  crc_out <= crc_reg; -- current CRC (no post-xor)

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' or clear = '1' then
        crc_reg <= G_INIT;
      elsif enable = '1' then
        crc_reg <= next_crc(crc_reg, data_in);
      end if;
    end if;
  end process;
end architecture;
