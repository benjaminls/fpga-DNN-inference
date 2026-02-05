library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- uart_rx.vhd: 8N1 UART receiver with ready/valid byte output.
-- Used by uart_byte_stream to provide transport bytes to the protocol layer.

entity uart_rx is
  generic (
    G_CLKS_PER_BIT : natural := 868  -- e.g. 100MHz/115200
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;
    rx       : in  std_logic;

    out_valid: out std_logic;
    out_ready: in  std_logic;
    out_data : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of uart_rx is
  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state    : state_t := S_IDLE;
  signal clk_cnt  : unsigned(15 downto 0) := (others => '0');
  signal bit_idx  : unsigned(2 downto 0) := (others => '0');
  signal data_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal valid_reg: std_logic := '0';

  constant HALF_BIT : natural := G_CLKS_PER_BIT / 2;

begin
  out_valid <= valid_reg;
  out_data  <= data_reg;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= S_IDLE;
        clk_cnt   <= (others => '0');
        bit_idx   <= (others => '0');
        data_reg  <= (others => '0');
        valid_reg <= '0';
      else
        if valid_reg = '1' and out_ready = '1' then
          valid_reg <= '0';
        end if;

        case state is
          when S_IDLE =>
            clk_cnt <= (others => '0');
            bit_idx <= (others => '0');
            if rx = '0' then
              state <= S_START;
            end if;

          when S_START =>
            if clk_cnt = to_unsigned(HALF_BIT, clk_cnt'length) then
              if rx = '0' then
                clk_cnt <= (others => '0');
                state <= S_DATA;
              else
                state <= S_IDLE; -- false start
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_DATA =>
            if clk_cnt = to_unsigned(G_CLKS_PER_BIT-1, clk_cnt'length) then
              clk_cnt <= (others => '0');
              data_reg(to_integer(bit_idx)) <= rx;
              if bit_idx = 7 then
                bit_idx <= (others => '0');
                state <= S_STOP;
              else
                bit_idx <= bit_idx + 1;
              end if;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_STOP =>
            if clk_cnt = to_unsigned(G_CLKS_PER_BIT-1, clk_cnt'length) then
              clk_cnt <= (others => '0');
              if valid_reg = '0' then
                valid_reg <= '1';
              end if;
              state <= S_IDLE;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when others =>
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
