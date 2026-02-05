library ieee;
library std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.pkt_pkg.all;

-- tb_top_e2e.vhd: End-to-end sim (pkt_rx -> tensor_adapter -> stub NN -> pkt_tx).
-- Drives an INFER_REQ packet and checks the INFER_RSP bytes.

entity tb_top_e2e is
end entity;

architecture tb of tb_top_e2e is
  constant CLK_PERIOD : time := 10 ns;
  constant TIMEOUT    : time := 5 ms;

  signal clk : std_logic := '0';
  signal rst : std_logic := '1';

  -- Input byte stream to pkt_rx
  signal in_valid : std_logic := '0';
  signal in_ready : std_logic;
  signal in_data  : std_logic_vector(7 downto 0) := (others => '0');

  -- pkt_rx payload stream
  signal rx_out_valid : std_logic;
  signal rx_out_ready : std_logic;
  signal rx_out_data  : std_logic_vector(7 downto 0);
  signal rx_out_last  : std_logic;

  signal rx_pkt_type  : pkt_type_t;
  signal rx_pkt_len   : std_logic_vector(15 downto 0);
  signal rx_pkt_valid : std_logic;
  signal rx_pkt_error : std_logic;

  -- tensor_adapter -> NN
  signal t_valid : std_logic;
  signal t_ready : std_logic := '1';
  signal t_data  : signed(15 downto 0);
  signal t_last  : std_logic;

  -- NN -> tensor_adapter
  signal t_out_valid : std_logic;
  signal t_out_ready : std_logic;
  signal t_out_data  : signed(15 downto 0);
  signal t_out_last  : std_logic;

  -- tensor_adapter -> pkt_tx payload
  signal tx_in_valid : std_logic;
  signal tx_in_ready : std_logic;
  signal tx_in_data  : std_logic_vector(7 downto 0);
  signal tx_in_last  : std_logic;

  -- pkt_tx output byte stream
  signal out_valid : std_logic;
  signal out_ready : std_logic := '1';
  signal out_data  : std_logic_vector(7 downto 0);

  signal tx_start : std_logic := '0';

  -- perf counters (optional for Milestone 6)
  signal cycles : std_logic_vector(31 downto 0);
  signal stalls : std_logic_vector(31 downto 0);
  signal infers : std_logic_vector(31 downto 0);

  type byte_arr_t is array (natural range <>) of std_logic_vector(7 downto 0);
  constant PAYLOAD : byte_arr_t := (x"02", x"01", x"80", x"FF"); -- 0x0102, 0xFF80
  constant REQ_PKT : byte_arr_t := (
    x"A5", x"5A", x"01", x"02", x"00", x"04",
    x"02", x"01", x"80", x"FF"
  );
  constant RSP_PKT : byte_arr_t := (
    x"A5", x"5A", x"01", x"82", x"00", x"04",
    x"02", x"01", x"80", x"FF"
  );

  signal out_count : integer := 0;

  procedure send_byte(
    signal s_data  : out std_logic_vector(7 downto 0);
    signal s_valid : out std_logic;
    signal s_ready : in  std_logic;
    signal s_clk   : in  std_logic;
    b              : std_logic_vector(7 downto 0)
  ) is
  begin
    s_data  <= b;
    s_valid <= '1';
    wait until rising_edge(s_clk);
    while s_ready = '0' loop
      wait until rising_edge(s_clk);
    end loop;
    s_valid <= '0';
  end procedure;

begin
  clk <= not clk after CLK_PERIOD/2;

  watchdog: process
  begin
    wait for TIMEOUT;
    assert false report "tb_top_e2e timeout" severity failure;
  end process;

  u_rx: entity work.pkt_rx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk,
      rst => rst,
      in_valid => in_valid,
      in_ready => in_ready,
      in_data => in_data,
      out_valid => rx_out_valid,
      out_ready => rx_out_ready,
      out_data => rx_out_data,
      out_last => rx_out_last,
      pkt_type => rx_pkt_type,
      pkt_len => rx_pkt_len,
      pkt_valid => rx_pkt_valid,
      pkt_error => rx_pkt_error
    );

  u_tensor: entity work.tensor_adapter
    generic map (G_DATA_WIDTH => 16)
    port map (
      clk => clk,
      rst => rst,
      in_valid => rx_out_valid,
      in_ready => rx_out_ready,
      in_data => rx_out_data,
      in_last => rx_out_last,
      tensor_valid => t_valid,
      tensor_ready => t_ready,
      tensor_data => t_data,
      tensor_last => t_last,
      tensor_out_valid => t_out_valid,
      tensor_out_ready => t_out_ready,
      tensor_out_data => t_out_data,
      tensor_out_last => t_out_last,
      out_valid => tx_in_valid,
      out_ready => tx_in_ready,
      out_data => tx_in_data,
      out_last => tx_in_last
    );

  u_nn: entity work.hls4ml_wrap
    generic map (G_DATA_WIDTH => 16, G_STUB => true)
    port map (
      clk => clk,
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

  u_tx: entity work.pkt_tx
    generic map (G_CRC_EN => false)
    port map (
      clk => clk,
      rst => rst,
      start => tx_start,
      pkt_type => INFER_RSP,
      pkt_len => rx_pkt_len,
      in_valid => tx_in_valid,
      in_ready => tx_in_ready,
      in_data => tx_in_data,
      out_valid => out_valid,
      out_ready => out_ready,
      out_data => out_data
    );

  u_cnt: entity work.perf_counters
    port map (
      clk => clk,
      rst => rst,
      stall_pulse => '0',
      infer_pulse => t_out_valid and t_out_ready and t_out_last,
      cycles => cycles,
      stalls => stalls,
      infers => infers
    );

  -- start response when request header is accepted
  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        tx_start <= '0';
      else
        tx_start <= '0';
        if rx_pkt_valid = '1' and rx_pkt_type = INFER_REQ and rx_pkt_error = '0' then
          tx_start <= '1';
        end if;
      end if;
    end if;
  end process;

  monitor: process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        out_count <= 0;
      else
        if out_valid = '1' and out_ready = '1' then
          assert out_data = RSP_PKT(out_count) report "RSP byte mismatch" severity failure;
          out_count <= out_count + 1;
        end if;
      end if;
    end if;
  end process;

  stim: process
  begin
    wait for 3*CLK_PERIOD;
    rst <= '0';
    wait for CLK_PERIOD;

    for i in REQ_PKT'range loop
      send_byte(in_data, in_valid, in_ready, clk, REQ_PKT(i));
    end loop;

    while out_count < RSP_PKT'length loop
      wait until rising_edge(clk);
    end loop;

    report "tb_top_e2e completed" severity note;
    stop;
    wait;
  end process;
end architecture;
