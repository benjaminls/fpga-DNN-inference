library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- uart_tx.vhd: 8N1 UART transmitter with ready/valid byte input.
-- Used by uart_byte_stream to send protocol bytes to the host.

entity uart_tx is
  generic (
    G_CLKS_PER_BIT : natural := 868  -- e.g. 100MHz/115200
  );
  port (
    clk      : in  std_logic;
    rst      : in  std_logic;

    in_valid : in  std_logic;
    in_ready : out std_logic;
    in_data  : in  std_logic_vector(7 downto 0);

    tx       : out std_logic
  );
end entity;

architecture rtl of uart_tx is
  type state_t is (S_IDLE, S_START, S_DATA, S_STOP);
  signal state    : state_t := S_IDLE;
  signal clk_cnt  : unsigned(15 downto 0) := (others => '0');
  signal bit_idx  : unsigned(2 downto 0) := (others => '0');
  signal data_reg : std_logic_vector(7 downto 0) := (others => '0');
  signal tx_reg   : std_logic := '1';

begin
  tx <= tx_reg;
  in_ready <= '1' when state = S_IDLE else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state   <= S_IDLE;
        clk_cnt <= (others => '0');
        bit_idx <= (others => '0');
        data_reg <= (others => '0');
        tx_reg  <= '1';
      else
        case state is
          when S_IDLE =>
            tx_reg <= '1';
            clk_cnt <= (others => '0');
            bit_idx <= (others => '0');
            if in_valid = '1' then
              data_reg <= in_data;
              state <= S_START;
            end if;

          when S_START =>
            tx_reg <= '0';
            if clk_cnt = to_unsigned(G_CLKS_PER_BIT-1, clk_cnt'length) then
              clk_cnt <= (others => '0');
              state <= S_DATA;
            else
              clk_cnt <= clk_cnt + 1;
            end if;

          when S_DATA =>
            tx_reg <= data_reg(to_integer(bit_idx));
            if clk_cnt = to_unsigned(G_CLKS_PER_BIT-1, clk_cnt'length) then
              clk_cnt <= (others => '0');
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
            tx_reg <= '1';
            if clk_cnt = to_unsigned(G_CLKS_PER_BIT-1, clk_cnt'length) then
              clk_cnt <= (others => '0');
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
