library ieee;
use ieee.std_logic_1164.all;

package stream_pkg is
  constant STREAM_WORD_WIDTH : natural := 32;

  subtype byte_t is std_logic_vector(7 downto 0);
  subtype word_t is std_logic_vector(STREAM_WORD_WIDTH-1 downto 0);

  type byte_stream_t is record
    data  : byte_t;
    valid : std_logic;
    ready : std_logic;
  end record;

  type word_stream_t is record
    data  : word_t;
    valid : std_logic;
    ready : std_logic;
  end record;
end package;

package body stream_pkg is
end package body;
