# Hardware Setup and Nexys 4 DDR Pin Mapping

## Tested configuration

- **Board:** Digilent Nexys 4 DDR, Artix-7 `xc7a100tcsg324-1`.
- **Software:** Vivado (Verilog RTL project).
- **Clock:** onboard **100 MHz** oscillator.
- **Output:** board's **12-bit VGA** (4 bits each of red/green/blue, plus HSYNC and VSYNC).
- **User input (Stage 2):** slide switches and three pushbuttons.
- **Display used for demonstrations:** external monitor receiving the FPGA's VGA through an **active VGA-to-HDMI converter**. The converter is not implemented in RTL.

**Pin-reference note:** These mappings come from the user's **Nexys 4 DDR Master XDC**, not the older original Nexys 4 Rev. B manual that was also attached. For other board revisions, verify the exact hardware and official constraints before connecting or enabling peripherals.

## Clock and VGA pins

| HDL port | Artix-7 package pin | Standard |
|---|---|---|
| `CLK100MHZ` | E3 | LVCMOS33 |
| `VGA_R[0]`, `[1]`, `[2]`, `[3]` | A3, B4, C5, A4 | LVCMOS33 |
| `VGA_G[0]`, `[1]`, `[2]`, `[3]` | C6, A5, B6, A6 | LVCMOS33 |
| `VGA_B[0]`, `[1]`, `[2]`, `[3]` | B7, C7, D7, D8 | LVCMOS33 |
| `VGA_HS` | B11 | LVCMOS33 |
| `VGA_VS` | B12 | LVCMOS33 |

The physical VGA connector and analog resistor-network DAC are on the board. The RTL produces the digital RGB and synchronization values.

## Stage 2 user inputs

| Port | Package pin | Standard | Purpose |
|---|---|---|---|
| `SW[0]`–`SW[7]` | J15, L16, M13, R15, R17, T18, U18, R13 | LVCMOS33 | Raw 8-bit speed |
| `SW[8]`, `SW[9]` | T8, U8 | **LVCMOS18** | Constrained but not used by Stage 2 renderer |
| `SW[10]`, `SW[11]` | R16, T13 | LVCMOS33 | Constrained but unused |
| `SW[12]`–`SW[15]` | H6, U12, U11, V10 | LVCMOS33 | Battery level |
| `BTNC` | N17 | LVCMOS33 | Warning |
| `BTNL` | P17 | LVCMOS33 | Left indicator |
| `BTNR` | M17 | LVCMOS33 | Right indicator |

The different electrical standard on switches 8 and 9 is **intentional** and comes from the DDR board constraints; do not force every switch to LVCMOS33.

## Example XDC entries

```tcl
set_property -dict { PACKAGE_PIN E3 IOSTANDARD LVCMOS33 } [get_ports { CLK100MHZ }]
create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { CLK100MHZ }]
set_property -dict { PACKAGE_PIN B11 IOSTANDARD LVCMOS33 } [get_ports { VGA_HS }]
```

`PACKAGE_PIN` binds an RTL top-level port to a specific physical FPGA pin. `IOSTANDARD` describes the required electrical interface. `create_clock -period 10.00` defines the **10 ns** input-clock requirement for the timing analyzer; it does not produce the external clock.

## Rebuilding either stage

1. Create a Vivado Verilog RTL project for **`xc7a100tcsg324-1`**.
2. Add the shared `vga_timing.v` plus the Stage 1 or Stage 2 `top.v`. Add `dashboard_ui.v` only for Stage 2.
3. Use the **matching stage-specific XDC**. Disable or remove the other stage's XDC and other stage's `top.v` so constraints and top-module names do not conflict.
4. Run synthesis, implementation, and bitstream generation. These steps work without the FPGA physically connected.
5. Program the FPGA through Vivado Hardware Manager. Connect board **VGA OUT** to the monitor's VGA input, or through an **active VGA-to-HDMI adapter** in the VGA→HDMI direction. Supply adapter power if its instructions require it.

Once camera wiring begins, power off the board before changing Pmod connections. Camera pinout and supply-voltage compatibility must be checked for the **actual breakout module** before wiring it; no camera pinout is claimed in this completed-stage document.

Reference: [Digilent Nexys 4 DDR Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-4-DDR-Master.xdc).
