library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity top_nexys_video is
  port (
    clk_100mhz : in  std_logic;
    reset_btn  : in  std_logic;
    uart_rx    : in  std_logic;
    uart_tx    : out std_logic;
    led        : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of top_nexys_video is
  signal rst_sync : std_logic_vector(1 downto 0) := (others => '0');
  signal rst      : std_logic := '0';
  signal counter  : unsigned(25 downto 0) := (others => '0');
begin
  -- Simple 2-FF reset synchronizer (reset_btn assumed active-high)
  process (clk_100mhz)
  begin
    if rising_edge(clk_100mhz) then
      rst_sync <= rst_sync(0) & reset_btn;
    end if;
  end process;
  rst <= rst_sync(1);

  process (clk_100mhz)
  begin
    if rising_edge(clk_100mhz) then
      if rst = '1' then
        counter <= (others => '0');
      else
        counter <= counter + 1;
      end if;
    end if;
  end process;

  led <= (others => '0');
  led(0) <= std_logic(counter(counter'high));

  -- Idle UART TX high
  uart_tx <= '1';

  -- uart_rx is unused in the hello-world top
  -- (kept to satisfy top-level ports and constraints)
end architecture;
