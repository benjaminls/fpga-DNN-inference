library ieee;
use ieee.std_logic_1164.all;

entity skid_buffer is
  generic (
    G_DATA_WIDTH : natural := 32
  );
  port (
    clk       : in  std_logic;
    rst       : in  std_logic;
    in_valid  : in  std_logic;
    in_ready  : out std_logic;
    in_data   : in  std_logic_vector(G_DATA_WIDTH-1 downto 0);
    out_valid : out std_logic;
    out_ready : in  std_logic;
    out_data  : out std_logic_vector(G_DATA_WIDTH-1 downto 0)
  );
end entity;

architecture rtl of skid_buffer is
  signal reg_valid : std_logic := '0';
  signal reg_data  : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal in_ready_i : std_logic := '0';
begin
  in_ready_i <= out_ready or (not reg_valid);
  in_ready  <= in_ready_i;
  out_valid <= reg_valid;
  out_data  <= reg_data;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        reg_valid <= '0';
        reg_data  <= (others => '0');
      else
        if in_ready_i = '1' then
          reg_valid <= in_valid;
          if in_valid = '1' then
            reg_data <= in_data;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
