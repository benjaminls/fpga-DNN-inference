library ieee;
use ieee.std_logic_1164.all;

package pkt_pkg is
  constant PKT_MAGIC   : std_logic_vector(15 downto 0) := x"A55A";
  constant PKT_VERSION : std_logic_vector(7 downto 0)  := x"01";

  subtype pkt_type_t is std_logic_vector(7 downto 0);

  constant STATUS_REQ : pkt_type_t := x"01";
  constant STATUS_RSP : pkt_type_t := x"81";
  constant INFER_REQ  : pkt_type_t := x"02";
  constant INFER_RSP  : pkt_type_t := x"82";
end package;

package body pkt_pkg is
end package body;
