## Nexys Video constraints (subset for Milestone 0)

## System clock (100 MHz)
set_property -dict { PACKAGE_PIN R4 IOSTANDARD LVCMOS33 } [get_ports { clk_100mhz }]
create_clock -add -name sys_clk -period 10.00 -waveform {0 5} [get_ports { clk_100mhz }]

## Reset button (use center button)
set_property -dict { PACKAGE_PIN B22 IOSTANDARD LVCMOS12 } [get_ports { reset_btn }]

## UART
# Board silkscreen: UART RX/TX via USB-UART.
# Map FPGA RX to FTDI TX (uart_tx_in), FPGA TX to FTDI RX (uart_rx_out).
# Nexys Video master XDC labels (DTE/PC perspective):
#   uart_tx_in = V18 (PC -> FPGA)  => FPGA uart_rx
#   uart_rx_out = AA19 (FPGA -> PC) => FPGA uart_tx
set_property -dict { PACKAGE_PIN V18 IOSTANDARD LVCMOS33 } [get_ports { uart_rx }]
set_property -dict { PACKAGE_PIN AA19 IOSTANDARD LVCMOS33 } [get_ports { uart_tx }]

## LEDs (use a few for sanity)
set_property -dict { PACKAGE_PIN T14 IOSTANDARD LVCMOS25 } [get_ports { led[0] }]
set_property -dict { PACKAGE_PIN T15 IOSTANDARD LVCMOS25 } [get_ports { led[1] }]
set_property -dict { PACKAGE_PIN T16 IOSTANDARD LVCMOS25 } [get_ports { led[2] }]
set_property -dict { PACKAGE_PIN U16 IOSTANDARD LVCMOS25 } [get_ports { led[3] }]
set_property -dict { PACKAGE_PIN V15 IOSTANDARD LVCMOS25 } [get_ports { led[4] }]
set_property -dict { PACKAGE_PIN W16 IOSTANDARD LVCMOS25 } [get_ports { led[5] }]
set_property -dict { PACKAGE_PIN W15 IOSTANDARD LVCMOS25 } [get_ports { led[6] }]
set_property -dict { PACKAGE_PIN Y13 IOSTANDARD LVCMOS25 } [get_ports { led[7] }]
