library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.pkt_pkg.all;

-- pkt_rx.vhd: Byte-stream packet parser (magic/version/type/length + payload).
-- Sits between transport byte stream and internal payload streams in the protocol layer.

entity pkt_rx is
  generic (
    G_CRC_EN : boolean := false
  );
  port (
    clk        : in  std_logic;
    rst        : in  std_logic;

    in_valid   : in  std_logic;
    in_ready   : out std_logic;
    in_data    : in  std_logic_vector(7 downto 0);

    out_valid  : out std_logic;
    out_ready  : in  std_logic;
    out_data   : out std_logic_vector(7 downto 0);
    out_last   : out std_logic; -- asserted with final payload byte

    pkt_type   : out pkt_type_t;
    pkt_len    : out std_logic_vector(15 downto 0);
    pkt_valid  : out std_logic; -- pulses when header is accepted
    pkt_error  : out std_logic  -- pulses on bad version/CRC
  );
end entity;

architecture rtl of pkt_rx is
  type state_t is (S_IDLE, S_MAGIC2, S_VER, S_TYPE, S_LEN_H, S_LEN_L, S_PAYLOAD, S_CRC1, S_CRC2); -- byte-serial parser
  signal state      : state_t := S_IDLE;
  signal type_reg   : pkt_type_t := (others => '0');
  signal len_reg    : unsigned(15 downto 0) := (others => '0');
  signal remaining  : unsigned(15 downto 0) := (others => '0');
  signal pkt_valid_i : std_logic := '0';
  signal pkt_error_i : std_logic := '0';

  signal crc_clear  : std_logic := '0';
  signal crc_en     : std_logic := '0';
  signal crc_out    : std_logic_vector(15 downto 0);
  signal crc_hi     : std_logic_vector(7 downto 0) := (others => '0'); -- CRC MSB latch

  function to_u16(hi, lo : std_logic_vector(7 downto 0)) return unsigned is
  begin
    return unsigned(hi & lo);
  end function;

  signal in_ready_i : std_logic;
  signal out_valid_i : std_logic;
  signal out_last_i : std_logic;
begin
  pkt_type  <= type_reg;
  pkt_len   <= std_logic_vector(len_reg);
  pkt_valid <= pkt_valid_i;
  pkt_error <= pkt_error_i;

  in_ready  <= in_ready_i;
  out_valid <= out_valid_i;
  out_data  <= in_data; -- pass-through payload bytes
  out_last  <= out_last_i;

  -- CRC computed over header+payload bytes
  crc_inst: entity work.crc16
    port map (
      clk     => clk,
      rst     => rst,
      clear   => crc_clear,
      enable  => crc_en,
      data_in => in_data,
      crc_out => crc_out
    );

  -- ready/valid handling
  out_valid_i <= '1' when state = S_PAYLOAD and in_valid = '1' else '0';
  in_ready_i  <= out_ready when state = S_PAYLOAD else '1'; -- backpressure only during payload
  out_last_i  <= '1' when state = S_PAYLOAD and remaining = 1 and in_valid = '1' and out_ready = '1' else '0';

  process (clk)
  begin
    if rising_edge(clk) then
      if rst = '1' then
        state       <= S_IDLE;
        type_reg    <= (others => '0');
        len_reg     <= (others => '0');
        remaining   <= (others => '0');
        pkt_valid_i <= '0';
        pkt_error_i <= '0';
        crc_clear   <= '1';
        crc_en      <= '0';
        crc_hi      <= (others => '0');
      else
        pkt_valid_i <= '0';
        pkt_error_i <= '0';
        crc_clear   <= '0';
        crc_en      <= '0';

        case state is
          when S_IDLE => -- scan for magic[15:8]
            if in_valid = '1' then
              if in_data = PKT_MAGIC(15 downto 8) then
                state <= S_MAGIC2;
              end if;
            end if;

          when S_MAGIC2 => -- scan for magic[7:0]
            if in_valid = '1' then
              if in_data = PKT_MAGIC(7 downto 0) then
                state <= S_VER;
              elsif in_data = PKT_MAGIC(15 downto 8) then
                state <= S_MAGIC2; -- possible overlap
              else
                state <= S_IDLE;
              end if;
            end if;

          when S_VER => -- version gate
            if in_valid = '1' then
              if in_data = PKT_VERSION then
                state <= S_TYPE;
                crc_clear <= '1';
                if G_CRC_EN then
                  crc_en <= '1';
                end if;
              else
                state <= S_IDLE;
                pkt_error_i <= '1';
              end if;
            end if;

          when S_TYPE => -- capture pkt_type
            if in_valid = '1' then
              type_reg <= in_data;
              state <= S_LEN_H;
              if G_CRC_EN then
                crc_en <= '1';
              end if;
            end if;

          when S_LEN_H => -- length[15:8]
            if in_valid = '1' then
              len_reg(15 downto 8) <= unsigned(in_data);
              state <= S_LEN_L;
              if G_CRC_EN then
                crc_en <= '1';
              end if;
            end if;

          when S_LEN_L => -- length[7:0]
            if in_valid = '1' then
              len_reg(7 downto 0) <= unsigned(in_data);
              remaining <= to_u16(std_logic_vector(len_reg(15 downto 8)), in_data); -- payload byte count
              pkt_valid_i <= '1';
              if G_CRC_EN then
                crc_en <= '1';
              end if;
              if to_u16(std_logic_vector(len_reg(15 downto 8)), in_data) = 0 then
                if G_CRC_EN then
                  state <= S_CRC1;
                else
                  state <= S_IDLE;
                end if;
              else
                state <= S_PAYLOAD;
              end if;
            end if;

          when S_PAYLOAD =>
            if in_valid = '1' and out_ready = '1' then
              if remaining = 1 then
                if G_CRC_EN then
                  state <= S_CRC1;
                else
                  state <= S_IDLE;
                end if;
              end if;
              remaining <= remaining - 1;
              if G_CRC_EN then
                crc_en <= '1';
              end if;
            end if;

          when S_CRC1 =>
            if in_valid = '1' then
              crc_hi <= in_data;
              state <= S_CRC2;
            end if;

          when S_CRC2 =>
            if in_valid = '1' then
              if (crc_hi & in_data) /= crc_out then
                pkt_error_i <= '1';
              end if;
              state <= S_IDLE;
            end if;

          when others =>
            state <= S_IDLE;
        end case;
      end if;
    end if;
  end process;
end architecture;
