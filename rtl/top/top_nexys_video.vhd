library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkt_pkg.all;
use work.nn_pkg.all;

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
  signal rx_ready_core : std_logic;
  signal rx_ready_uart : std_logic;
  signal rx_data  : std_logic_vector(7 downto 0);
  signal tx_valid : std_logic;
  signal tx_valid_core : std_logic;
  signal tx_ready : std_logic;
  signal tx_data  : std_logic_vector(7 downto 0);
  signal tx_data_core  : std_logic_vector(7 downto 0);

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
  signal infer_start : std_logic := '0';
  signal status_start : std_logic := '0';
  signal status_mode : std_logic := '0';

  signal status_out_valid : std_logic;
  signal status_out_ready : std_logic;
  signal status_out_data  : std_logic_vector(7 downto 0);
  signal status_out_last  : std_logic;
  signal status_len       : std_logic_vector(15 downto 0);

  signal tx_in_valid : std_logic;
  signal tx_in_ready : std_logic;
  signal tx_in_data  : std_logic_vector(7 downto 0);

  signal tx_pkt_type : pkt_type_t;
  signal tx_pkt_len  : std_logic_vector(15 downto 0);
  signal infer_rsp_len : std_logic_vector(15 downto 0);

  -- Tensor path
  signal t_valid : std_logic;
  signal t_ready : std_logic := '1';
  signal t_data  : signed(15 downto 0);
  signal t_last  : std_logic;
  signal t_out_valid : std_logic;
  signal t_out_ready : std_logic;
  signal t_out_data  : signed(15 downto 0);
  signal t_out_last  : std_logic;

  -- Perf counters for STATUS
  signal cycles : std_logic_vector(31 downto 0);
  signal stalls : std_logic_vector(31 downto 0);
  signal infers : std_logic_vector(31 downto 0);

  -- Debug-only signals (temporary)
  signal rx_pulse : std_logic := '0';
  signal led_i    : std_logic_vector(7 downto 0) := (others => '0');
  constant DBG_ECHO_EN : boolean := false;

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

  process (counter, uart_rx, rx_pulse)
  begin
    led_i <= (others => '0');
    led_i(0) <= std_logic(counter(counter'high));
    led_i(6) <= uart_rx; -- mirror raw RX pin
    led_i(7) <= rx_pulse; -- toggle on rx_valid
  end process;
  led <= led_i;

  u_uart: entity work.uart_byte_stream
    generic map (G_CLKS_PER_BIT => 868)
    port map (
      clk => clk_100mhz,
      rst => rst,
      uart_rx => uart_rx,
      uart_tx => uart_tx,
      rx_valid => rx_valid,
      rx_ready => rx_ready_uart,
      rx_data => rx_data,
      tx_valid => tx_valid,
      tx_ready => tx_ready,
      tx_data => tx_data
    );

  -- Debug: toggle LED on every received byte
  process (clk_100mhz)
  begin
    if rising_edge(clk_100mhz) then
      if rst = '1' then
        rx_pulse <= '0';
      else
        if rx_valid = '1' then
          rx_pulse <= not rx_pulse;
        end if;
      end if;
    end if;
  end process;

  u_rx: entity work.pkt_rx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk_100mhz,
      rst => rst,
      in_valid => rx_valid,
      in_ready => rx_ready_core,
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

  u_status: entity work.mmio_status
    port map (
      clk => clk_100mhz,
      rst => rst,
      start => status_start,
      cycles => cycles,
      stalls => stalls,
      infers => infers,
      out_valid => status_out_valid,
      out_ready => status_out_ready,
      out_data => status_out_data,
      out_last => status_out_last,
      payload_len => status_len
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

  -- respond to INFER_REQ and STATUS_REQ
  process (clk_100mhz)
  begin
    if rising_edge(clk_100mhz) then
      if rst = '1' then
        tx_start <= '0';
        infer_start <= '0';
        status_start <= '0';
        status_mode <= '0';
      else
        tx_start <= '0';
        infer_start <= '0';
        status_start <= '0';

        if pkt_valid = '1' and pkt_error = '0' then
          if pkt_type = STATUS_REQ then
            status_start <= '1';
            tx_start <= '1';
            status_mode <= '1';
          elsif pkt_type = INFER_REQ then
            infer_start <= '1';
            tx_start <= '1';
          end if;
        end if;

        if status_mode = '1' and status_out_valid = '1' and status_out_ready = '1' and status_out_last = '1' then
          status_mode <= '0';
        end if;
      end if;
    end if;
  end process;

  infer_rsp_len <= std_logic_vector(to_unsigned(NN_DATA_WIDTH / 8, 16));
  tx_pkt_type <= STATUS_RSP when status_start = '1' else INFER_RSP;
  tx_pkt_len  <= status_len when status_start = '1' else infer_rsp_len;

  tx_in_valid <= status_out_valid when status_mode = '1' else p_tx_valid;
  tx_in_data  <= status_out_data  when status_mode = '1' else p_tx_data;
  status_out_ready <= tx_in_ready when status_mode = '1' else '0';
  p_tx_ready <= tx_in_ready when status_mode = '0' else '0';

  u_tx: entity work.pkt_tx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk_100mhz,
      rst => rst,
      start => tx_start,
      pkt_type => tx_pkt_type,
      pkt_len => tx_pkt_len,
      in_valid => tx_in_valid,
      in_ready => tx_in_ready,
      in_data => tx_in_data,
      out_valid => tx_valid_core,
      out_ready => tx_ready,
      out_data => tx_data_core
    );

  u_cnt: entity work.perf_counters
    port map (
      clk => clk_100mhz,
      rst => rst,
      stall_pulse => '0',
      infer_pulse => t_out_valid and t_out_ready and t_out_last,
      cycles => cycles,
      stalls => stalls,
      infers => infers
    );

  -- Debug echo path (temporary): bypass protocol and echo UART RX bytes
  rx_ready_uart <= '1' when DBG_ECHO_EN else rx_ready_core;
  tx_valid <= rx_valid when DBG_ECHO_EN else tx_valid_core;
  tx_data  <= rx_data  when DBG_ECHO_EN else tx_data_core;

end architecture;
