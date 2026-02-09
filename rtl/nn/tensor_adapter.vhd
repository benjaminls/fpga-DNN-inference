library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.nn_pkg.all;

-- tensor_adapter.vhd: Converts payload bytes to tensor elements and back.
-- Sits between protocol payload streams and NN core tensor streams.

entity tensor_adapter is
  generic (
    G_DATA_WIDTH : natural := NN_DATA_WIDTH
  );
  port (
    clk          : in  std_logic;
    rst          : in  std_logic;

    -- Payload bytes from pkt_rx
    in_valid     : in  std_logic;
    in_ready     : out std_logic;
    in_data      : in  std_logic_vector(7 downto 0);
    in_last      : in  std_logic;

    -- Tensor stream to NN core
    tensor_valid : out std_logic;
    tensor_ready : in  std_logic;
    tensor_data  : out signed(G_DATA_WIDTH-1 downto 0);
    tensor_last  : out std_logic;

    -- Tensor stream from NN core
    tensor_out_valid : in  std_logic;
    tensor_out_ready : out std_logic;
    tensor_out_data  : in  signed(G_DATA_WIDTH-1 downto 0);
    tensor_out_last  : in  std_logic;

    -- Payload bytes to pkt_tx
    out_valid    : out std_logic;
    out_ready    : in  std_logic;
    out_data     : out std_logic_vector(7 downto 0);
    out_last     : out std_logic
  );
end entity;

architecture rtl of tensor_adapter is
  constant BYTES_PER_ELEM : natural := G_DATA_WIDTH / 8;

  -- Input packing
  signal in_buf       : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal in_idx       : natural range 0 to BYTES_PER_ELEM-1 := 0;
  signal hold_valid   : std_logic := '0';
  signal hold_data    : signed(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal hold_last    : std_logic := '0';
  signal in_ready_i   : std_logic := '0';

  -- Output unpacking
  signal out_buf      : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal out_idx      : natural range 0 to BYTES_PER_ELEM-1 := 0;
  signal out_busy     : std_logic := '0';
  signal out_last_reg : std_logic := '0';

  function set_byte(
    value : std_logic_vector(G_DATA_WIDTH-1 downto 0);
    idx   : natural;
    b     : std_logic_vector(7 downto 0)
  ) return std_logic_vector is
    variable v : std_logic_vector(G_DATA_WIDTH-1 downto 0) := value;
    variable l : natural := idx * 8;
  begin
    v(l+7 downto l) := b; -- little-endian
    return v;
  end function;

  function get_byte(
    value : std_logic_vector(G_DATA_WIDTH-1 downto 0);
    idx   : natural
  ) return std_logic_vector is
    variable l : natural := idx * 8;
  begin
    return value(l+7 downto l); -- little-endian
  end function;

begin
  -- Input side (bytes -> tensor element)
  in_ready_i  <= '1' when hold_valid = '0' else '0';
  in_ready    <= in_ready_i;
  tensor_valid <= hold_valid;
  tensor_data  <= hold_data;
  tensor_last  <= hold_last;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        in_buf     <= (others => '0');
        in_idx     <= 0;
        hold_valid <= '0';
        hold_data  <= (others => '0');
        hold_last  <= '0';
      else
        if hold_valid = '1' and tensor_ready = '1' then
          hold_valid <= '0';
        end if;

        if in_valid = '1' and in_ready_i = '1' then
          in_buf <= set_byte(in_buf, in_idx, in_data);
          if in_idx = BYTES_PER_ELEM-1 then
            hold_data  <= signed(set_byte(in_buf, in_idx, in_data));
            hold_last  <= in_last;
            hold_valid <= '1';
            in_idx     <= 0;
          else
            in_idx <= in_idx + 1;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Output side (tensor element -> bytes)
  tensor_out_ready <= '1' when out_busy = '0' else '0';
  out_valid <= out_busy;
  out_data  <= get_byte(out_buf, out_idx);
  out_last  <= '1' when out_busy = '1' and out_last_reg = '1' and out_idx = BYTES_PER_ELEM-1 else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_buf      <= (others => '0');
        out_idx      <= 0;
        out_busy     <= '0';
        out_last_reg <= '0';
      else
        if out_busy = '0' then
          if tensor_out_valid = '1' then
            out_buf      <= std_logic_vector(tensor_out_data);
            out_idx      <= 0;
            out_busy     <= '1';
            out_last_reg <= tensor_out_last;
          end if;
        else
          if out_ready = '1' then
            if out_idx = BYTES_PER_ELEM-1 then
              out_busy <= '0';
            else
              out_idx <= out_idx + 1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process;
end architecture;
