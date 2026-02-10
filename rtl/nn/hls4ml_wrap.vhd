library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.nn_pkg.all;

-- hls4ml_wrap.vhd: Stub/real wrapper for NN core.
-- Provides a ready/valid streaming interface for integration tests.

entity hls4ml_wrap is
  generic (
    G_DATA_WIDTH : natural := NN_DATA_WIDTH;
    G_IN_DIM     : natural := 8;
    G_STUB       : boolean := true
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    in_valid   : in  std_logic;
    in_ready   : out std_logic;
    in_data    : in  signed(G_DATA_WIDTH-1 downto 0);
    in_last    : in  std_logic;

    out_valid  : out std_logic;
    out_ready  : in  std_logic;
    out_data   : out signed(G_DATA_WIDTH-1 downto 0);
    out_last   : out std_logic
  );
end entity;

architecture rtl of hls4ml_wrap is
  constant IN_BITS : natural := G_DATA_WIDTH * G_IN_DIM;

  signal hold_valid : std_logic := '0';
  signal hold_data  : signed(G_DATA_WIDTH-1 downto 0) := (others => '0');
  signal hold_last  : std_logic := '0';

  signal pack_buf    : std_logic_vector(IN_BITS-1 downto 0) := (others => '0');
  signal pack_idx    : natural range 0 to G_IN_DIM := 0;
  signal pack_full   : std_logic := '0';
  signal in_ready_i  : std_logic := '0';

  signal hls_in_valid  : std_logic := '0';
  signal hls_in_ready  : std_logic := '0';
  signal hls_out_valid : std_logic := '0';
  signal hls_out_ready : std_logic := '0';
  signal hls_out_data  : std_logic_vector(G_DATA_WIDTH-1 downto 0) := (others => '0');

  signal ap_rst_n : std_logic := '1';

  function set_elem(
    value : std_logic_vector(IN_BITS-1 downto 0);
    idx   : natural;
    elem  : std_logic_vector(G_DATA_WIDTH-1 downto 0)
  ) return std_logic_vector is
    variable v : std_logic_vector(IN_BITS-1 downto 0) := value;
    variable l : natural := idx * G_DATA_WIDTH;
  begin
    v(l+G_DATA_WIDTH-1 downto l) := elem;
    return v;
  end function;

  component myproject is
    port (
      input_1_TDATA    : in  std_logic_vector(IN_BITS-1 downto 0);
      layer6_out_TDATA : out std_logic_vector(G_DATA_WIDTH-1 downto 0);
      ap_clk           : in  std_logic;
      ap_rst_n         : in  std_logic;
      input_1_TVALID   : in  std_logic;
      input_1_TREADY   : out std_logic;
      ap_start         : in  std_logic;
      layer6_out_TVALID: out std_logic;
      layer6_out_TREADY: in  std_logic;
      ap_done          : out std_logic;
      ap_ready         : out std_logic;
      ap_idle          : out std_logic
    );
  end component;
begin
  -- Stub mode: 1-cycle latency passthrough
  ap_rst_n <= not rst;

  in_ready_i <= '1' when G_STUB and hold_valid = '0' else
              '1' when (not G_STUB) and pack_full = '0' else
              '0';
  in_ready <= in_ready_i;
  out_valid <= hold_valid when G_STUB else hls_out_valid;
  out_data  <= hold_data when G_STUB else signed(hls_out_data);
  out_last  <= hold_last when G_STUB else '1';

  hls_out_ready <= out_ready;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        hold_valid <= '0';
        hold_data  <= (others => '0');
        hold_last  <= '0';
        pack_buf   <= (others => '0');
        pack_idx   <= 0;
        pack_full  <= '0';
        hls_in_valid <= '0';
      else
        if hold_valid = '1' and out_ready = '1' then
          hold_valid <= '0';
        end if;

        if in_valid = '1' and in_ready_i = '1' then
          if G_STUB then
            hold_data  <= in_data; -- y = x
            hold_last  <= in_last;
            hold_valid <= '1';
          else
            pack_buf <= set_elem(pack_buf, pack_idx, std_logic_vector(in_data));
            if pack_idx = G_IN_DIM-1 then
              pack_full <= '1';
              pack_idx  <= 0;
            else
              pack_idx <= pack_idx + 1;
            end if;
          end if;
        end if;

        if G_STUB = false then
          if pack_full = '1' then
            hls_in_valid <= '1';
          end if;
          if hls_in_valid = '1' and hls_in_ready = '1' then
            hls_in_valid <= '0';
            pack_full <= '0';
          end if;
        end if;
      end if;
    end if;
  end process;

  hls_inst : if G_STUB = false generate
    hls_core : myproject
      port map (
        input_1_TDATA     => pack_buf,
        layer6_out_TDATA  => hls_out_data,
        ap_clk            => clk,
        ap_rst_n          => ap_rst_n,
        input_1_TVALID    => hls_in_valid,
        input_1_TREADY    => hls_in_ready,
        ap_start          => '1',
        layer6_out_TVALID => hls_out_valid,
        layer6_out_TREADY => hls_out_ready,
        ap_done           => open,
        ap_ready          => open,
        ap_idle           => open
      );
  end generate;
end architecture;
