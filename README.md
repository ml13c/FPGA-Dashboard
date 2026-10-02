# FPGA Vehicle Dashboard — Nexys 4 DDR

A **Verilog-based VGA dashboard** built on the Digilent Nexys 4 DDR (Xilinx Artix-7) using Vivado. This project started as a VGA timing and color-output test, then expanded into a hardware-rendered vehicle dashboard controlled by the FPGA board's switches and pushbuttons.

**Current status:** Stages 1 and 2 have been programmed onto the FPGA and visually tested on an external monitor. The camera, frame buffer, and DDR2 interface have **not** been implemented yet.

## Hardware and tools

- **FPGA:** Digilent Nexys 4 DDR, Artix-7 `XC7A100T-1CSG324C`
- **Development:** Verilog, AMD Vivado (tested with Vivado 2025.2)
- **Display connection:** Nexys VGA output → active VGA-to-HDMI converter → HDMI monitor
- **Inputs:** Onboard switches `SW[15:0]` and buttons `BTNC`, `BTNL`, `BTNR`
- **Future camera:** HiLetgo OV7670 parallel camera module

The project uses the **Nexys 4 DDR Master XDC** for physical pin assignments. Do not substitute constraints from the similarly named original Nexys 4: that earlier board's memory hardware is different.

## To be added