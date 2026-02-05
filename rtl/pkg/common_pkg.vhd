library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package common_pkg is
  function clog2(n : natural) return natural;
  function bool_to_sl(b : boolean) return std_logic;
end package;

package body common_pkg is
  function clog2(n : natural) return natural is
    variable v : natural := 1;
    variable r : natural := 0;
  begin
    if n <= 1 then
      return 1;
    end if;
    while v < n loop
      v := v * 2;
      r := r + 1;
    end loop;
    return r;
  end function;

  function bool_to_sl(b : boolean) return std_logic is
  begin
    if b then
      return '1';
    else
      return '0';
    end if;
  end function;
end package body;
