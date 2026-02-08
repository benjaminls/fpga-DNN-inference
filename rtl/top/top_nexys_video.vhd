library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkt_pkg.all;

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

  -- UART transport
  signal rx_valid : std_logic;
  signal rx_ready : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal tx_valid : std_logic;
  signal tx_ready : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0);

  -- Protocol
  signal p_rx_valid : std_logic;
  signal p_rx_ready : std_logic;
  signal p_rx_data  : std_logic_vector(7 downto 0);
  signal p_rx_last  : std_logic;
  signal pkt_type   : pkt_type_t;
  signal pkt_len    : std_logic_vector(15 downto 0);
  signal pkt_valid  : std_logic;
  signal pkt_error  : std_logic;

  signal p_tx_valid : std_logic;
  signal p_tx_ready : std_logic;
  signal p_tx_data  : std_logic_vector(7 downto 0);
  signal p_tx_last  : std_logic;

  signal tx_start : std_logic := '0';

  -- Tensor path
  signal t_valid : std_logic;
  signal t_ready : std_logic := '1';
  signal t_data  : signed(15 downto 0);
  signal t_last  : std_logic;
  signal t_out_valid : std_logic;
  signal t_out_ready : std_logic;
  signal t_out_data  : signed(15 downto 0);
  signal t_out_last  : std_logic;

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

  u_uart: entity work.uart_byte_stream
    generic map (G_CLKS_PER_BIT => 868)
    port map (
      clk => clk_100mhz,
      rst => rst,
      uart_rx => uart_rx,
      uart_tx => uart_tx,
      rx_valid => rx_valid,
      rx_ready => rx_ready,
      rx_data => rx_data,
      tx_valid => tx_valid,
      tx_ready => tx_ready,
      tx_data => tx_data
    );

  u_rx: entity work.pkt_rx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk_100mhz,
      rst => rst,
      in_valid => rx_valid,
      in_ready => rx_ready,
      in_data => rx_data,
      out_valid => p_rx_valid,
      out_ready => p_rx_ready,
      out_data => p_rx_data,
      out_last => p_rx_last,
      pkt_type => pkt_type,
      pkt_len => pkt_len,
      pkt_valid => pkt_valid,
      pkt_error => pkt_error
    );

  u_tensor: entity work.tensor_adapter
    generic map (G_DATA_WIDTH => 16)
    port map (
      clk => clk_100mhz,
      rst => rst,
      in_valid => p_rx_valid,
      in_ready => p_rx_ready,
      in_data => p_rx_data,
      in_last => p_rx_last,
      tensor_valid => t_valid,
      tensor_ready => t_ready,
      tensor_data => t_data,
      tensor_last => t_last,
      tensor_out_valid => t_out_valid,
      tensor_out_ready => t_out_ready,
      tensor_out_data => t_out_data,
      tensor_out_last => t_out_last,
      out_valid => p_tx_valid,
      out_ready => p_tx_ready,
      out_data => p_tx_data,
      out_last => p_tx_last
    );

  u_nn: entity work.hls4ml_wrap
    generic map (G_DATA_WIDTH => 16, G_IN_DIM => 8, G_STUB => false)
    port map (
      clk => clk_100mhz,
      rst => rst,
      in_valid => t_valid,
      in_ready => t_ready,
      in_data => t_data,
      in_last => t_last,
      out_valid => t_out_valid,
      out_ready => t_out_ready,
      out_data => t_out_data,
      out_last => t_out_last
    );

  -- respond to INFER_REQ only (STATUS path added later in milestone 3+)
  process (clk_100mhz)
  begin
    if rising_edge(clk_100mhz) then
      if rst = '1' then
        tx_start <= '0';
      else
        tx_start <= '0';
        if pkt_valid = '1' and pkt_type = INFER_REQ and pkt_error = '0' then
          tx_start <= '1';
        end if;
      end if;
    end if;
  end process;

  u_tx: entity work.pkt_tx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk_100mhz,
      rst => rst,
      start => tx_start,
      pkt_type => INFER_RSP,
      pkt_len => pkt_len,
      in_valid => p_tx_valid,
      in_ready => p_tx_ready,
      in_data => p_tx_data,
      out_valid => tx_valid,
      out_ready => tx_ready,
      out_data => tx_data
    );

end architecture;
