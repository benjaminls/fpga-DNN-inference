library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package nn_pkg is
  constant NN_DATA_WIDTH : natural := 16;
  constant NN_FRAC_WIDTH : natural := 8;

  subtype nn_data_t is signed(NN_DATA_WIDTH-1 downto 0);
end package;

package body nn_pkg is
end package body;
