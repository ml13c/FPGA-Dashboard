# FPGA Vehicle Dashboard — Nexys 4 DDR

This project implements a real-time automotive dashboard and video-mixing pipeline on a Xilinx Artix-7 FPGA. The system captures RGB565 video from an OV7670 camera, crosses asynchronous clock domains using a custom Gray-code FIFO, buffers frames in external DDR2, arbitrates multiple memory clients, and composites live video with graphics using fixed-point alpha blending and prioritized alert overlays. The final design outputs a 640×480 VGA dashboard and closes timing with +1.316 ns WNS and zero failing endpoints.

## Hardware and tools

- **FPGA:** Digilent Nexys 4 DDR, Artix-7 `XC7A100T-1CSG324C`
- **Development:** Verilog, AMD Vivado (tested with Vivado 2025.2)
- **Display connection:** Nexys VGA output → active VGA-to-HDMI converter → HDMI monitor
- **Inputs:** Onboard switches `SW[15:0]` and buttons `BTNC`, `BTNL`, `BTNR`
- **Future camera:** HiLetgo OV7670 parallel camera module

The project uses the **Nexys 4 DDR Master XDC** for physical pin assignments. Do not substitute constraints from the similarly named original Nexys 4: that earlier board's memory hardware is different.

## To be added
