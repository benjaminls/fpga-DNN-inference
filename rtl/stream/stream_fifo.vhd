library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.common_pkg.all;

entity stream_fifo is
  generic (
    G_DATA_WIDTH : natural := 32;
    G_DEPTH      : natural := 4
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

architecture rtl of stream_fifo is
  constant ADDR_WIDTH : natural := clog2(G_DEPTH);
  type mem_t is array (0 to G_DEPTH-1) of std_logic_vector(G_DATA_WIDTH-1 downto 0);
  signal mem    : mem_t := (others => (others => '0'));
  signal rd_ptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal wr_ptr : unsigned(ADDR_WIDTH-1 downto 0) := (others => '0');
  signal count  : unsigned(ADDR_WIDTH downto 0) := (others => '0');

  signal do_read    : std_logic;
  signal do_write   : std_logic;
  signal in_ready_i : std_logic;
  signal out_valid_i : std_logic;
begin
  in_ready_i  <= '1' when to_integer(count) < G_DEPTH else '0';
  out_valid_i <= '1' when to_integer(count) > 0 else '0';
  in_ready  <= in_ready_i;
  out_valid <= out_valid_i;
  out_data  <= mem(to_integer(rd_ptr));

  do_write <= in_valid and in_ready_i;
  do_read  <= out_valid_i and out_ready;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        rd_ptr <= (others => '0');
        wr_ptr <= (others => '0');
        count  <= (others => '0');
      else
        if do_write = '1' then
          mem(to_integer(wr_ptr)) <= in_data;
          wr_ptr <= wr_ptr + 1;
        end if;

        if do_read = '1' then
          rd_ptr <= rd_ptr + 1;
        end if;

        if do_write = '1' and do_read = '0' then
          count <= count + 1;
        elsif do_write = '0' and do_read = '1' then
          count <= count - 1;
        end if;
      end if;
    end if;
  end process;
end architecture;
