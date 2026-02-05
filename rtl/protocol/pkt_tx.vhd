library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkt_pkg.all;

-- pkt_tx.vhd: Byte-stream packet emitter (header + payload + optional CRC).
-- Sits between internal payload streams and transport byte stream in the protocol layer.

entity pkt_tx is
  generic (
    G_CRC_EN : boolean := false
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    start      : in  std_logic; -- single-cycle pulse to begin frame
    pkt_type   : in  pkt_type_t;
    pkt_len    : in  std_logic_vector(15 downto 0);

    in_valid   : in  std_logic;
    in_ready   : out std_logic;
    in_data    : in  std_logic_vector(7 downto 0);

    out_valid  : out std_logic;
    out_ready  : in  std_logic;
    out_data   : out std_logic_vector(7 downto 0)
  );
end entity;

architecture rtl of pkt_tx is
  type state_t is (S_IDLE, S_HDR, S_PAYLOAD, S_CRC1, S_CRC2); -- byte-serial emitter
  signal state      : state_t := S_IDLE;
  signal hdr_idx    : unsigned(2 downto 0) := (others => '0'); -- 0..PKT_HDR_LEN-1
  signal len_reg    : std_logic_vector(15 downto 0) := (others => '0');
  signal type_reg   : pkt_type_t := (others => '0');
  signal remaining  : unsigned(15 downto 0) := (others => '0');

  signal crc_clear  : std_logic := '0';
  signal crc_en     : std_logic := '0';
  signal crc_out    : std_logic_vector(15 downto 0);

  signal out_valid_i : std_logic;
  signal in_ready_i  : std_logic;

begin
  out_valid <= out_valid_i;
  in_ready  <= in_ready_i;

  -- CRC over header+payload bytes
  crc_inst: entity work.crc16 
    port map (
      clk     => clk,
      rst     => rst,
      clear   => crc_clear,
      enable  => crc_en,
      data_in => out_data,
      crc_out => crc_out
    );

  process (all)
  begin
    out_valid_i <= '0';
    in_ready_i  <= '0';
    out_data    <= (others => '0');

    case state is
      when S_HDR =>
        out_valid_i <= '1';
        case to_integer(hdr_idx) is
          when 0 => out_data <= PKT_MAGIC(15 downto 8);
          when 1 => out_data <= PKT_MAGIC(7 downto 0);
          when 2 => out_data <= PKT_VERSION;
          when 3 => out_data <= type_reg;
          when 4 => out_data <= len_reg(15 downto 8);
          when others => out_data <= len_reg(7 downto 0);
        end case;
      when S_PAYLOAD =>
        out_valid_i <= in_valid;
        in_ready_i  <= out_ready;
        out_data    <= in_data;
      when S_CRC1 =>
        out_valid_i <= '1';
        out_data <= crc_out(15 downto 8);
      when S_CRC2 =>
        out_valid_i <= '1';
        out_data <= crc_out(7 downto 0);
      when others =>
        null;
    end case;
  end process;

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state     <= S_IDLE;
        hdr_idx   <= (others => '0');
        len_reg   <= (others => '0');
        type_reg  <= (others => '0');
        remaining <= (others => '0');
        crc_clear <= '1';
        crc_en    <= '0';
      else
        crc_clear <= '0';
        crc_en    <= '0';

        case state is
          when S_IDLE =>
            if start = '1' then
              type_reg <= pkt_type;
              len_reg  <= pkt_len;
              remaining <= unsigned(pkt_len);
              hdr_idx  <= (others => '0');
              state    <= S_HDR;
              crc_clear <= '1';
            end if;

          when S_HDR => -- emit header bytes (magic, ver, type, len)
            if out_ready = '1' then
              if G_CRC_EN then
                crc_en <= '1';
              end if;
              if hdr_idx = PKT_HDR_LEN-1 then -- header done
                if unsigned(len_reg) = 0 then
                  if G_CRC_EN then
                    state <= S_CRC1;
                  else
                    state <= S_IDLE;
                  end if;
                else
                  state <= S_PAYLOAD;
                end if;
              else
                hdr_idx <= hdr_idx + 1;
              end if;
            end if;

          when S_PAYLOAD =>
            if in_valid = '1' and out_ready = '1' then
              if G_CRC_EN then
                crc_en <= '1';
              end if;
              if remaining = 1 then
                if G_CRC_EN then
                  state <= S_CRC1;
                else
                  state <= S_IDLE;
                end if;
              end if;
              remaining <= remaining - 1;
            end if;

          when S_CRC1 =>
            if out_ready = '1' then
              state <= S_CRC2;
            end if;

          when S_CRC2 =>
            if out_ready = '1' then
              state <= S_IDLE;
            end if;

          when others =>
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
