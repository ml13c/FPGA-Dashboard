# set priority to LATE in FILE PROPERTIES
# Camera PCLK and MIG/UI clock are asynchronous.
# Crossing is handled by the custom Gray-code async FIFO.
set_clock_groups -asynchronous \
    -group [get_clocks cam_pclk_pin] \
    -group [get_clocks clk_pll_i]

# MIG/UI clock and 100 MHz display/system clock are asynchronous.
# Crossing is handled by synchronizers / dual-clock display cache.
set_clock_groups -asynchronous \
    -group [get_clocks clk_pll_i] \
    -group [get_clocks sys_clk_pin]