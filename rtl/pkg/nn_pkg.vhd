library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package nn_pkg is
  constant NN_DATA_WIDTH : natural := 16;
  -- Match hls4ml precision ap_fixed<16,6> -> 16 total, 6 integer => 10 fractional
  constant NN_FRAC_WIDTH : natural := 10;

  subtype nn_data_t is signed(NN_DATA_WIDTH-1 downto 0);
end package;

package body nn_pkg is
end package body;
