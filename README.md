# FPGA Automotive Video Compositor — Nexys 4 DDR

This project implements a real-time automotive dashboard and video-mixing pipeline on a Xilinx Artix-7 FPGA. The system captures RGB565 video from an OV7670 camera, crosses asynchronous clock domains using a custom Gray-code FIFO, buffers video and graphics through external DDR2 memory, arbitrates multiple memory clients, and composites live video with graphics using fixed-point alpha blending and prioritized alert overlays.

The final design outputs a 640×480 VGA dashboard and closes post-implementation timing with **+1.316 ns WNS, 0.000 ns TNS, and zero failing endpoints**.

---

## Hardware and Tools

- **FPGA Board:** Digilent Nexys 4 DDR
- **FPGA:** Xilinx Artix-7 `XC7A100T-1CSG324C`
- **Camera:** HiLetgo OV7670 parallel camera module
- **Camera Format:** RGB565
- **External Memory:** 128 MiB DDR2
- **Display Output:** 640×480 VGA
- **Monitor Connection:** Nexys VGA → active VGA-to-HDMI converter → HDMI monitor
- **HDL:** Verilog
- **Development Environment:** AMD Vivado 2025.2
- **User Inputs:** `SW[15:0]`, `BTNC`, `BTNL`, and `BTNR`

The project uses the **Nexys 4 DDR Master XDC** for physical pin assignments. Constraints from the original Nexys 4 should not be substituted because the memory hardware and several board connections differ.

---

## System Architecture

The design is separated into multiple hardware blocks operating across independent clock domains.

```text
                         OV7670 Camera
                              |
                         RGB565 Pixels
                              |
                         CAM_PCLK Domain
                              |
                              v
                    +--------------------+
                    |   Camera Capture   |
                    +--------------------+
                              |
                              v
                    +--------------------+
                    |  Gray-Code Async   |
                    |  FIFO / CDC Bridge |
                    +--------------------+
                              |
                              v
                     Memory / MIG Domain
                              |
          +-------------------+-------------------+
          |                   |                   |
          v                   v                   v
   Camera Writer       Graphics Writer      Display Reader
          \                   |                   /
           \                  |                  /
            +-----------------------------------+
            |      Custom DDR Memory Arbiter    |
            | Display Priority + Writer Fairness|
            +-----------------------------------+
                              |
                              v
                    +--------------------+
                    | 128 MiB DDR2 / MIG |
                    +--------------------+
                              |
                              v
                    +--------------------+
                    |   Display Cache    |
                    +--------------------+
                              |
                              v
                    +--------------------+
Camera Layer ------>|                    |
Graphics Layer ---->|   Alpha Blender    |
                    |   6 DSP Slices     |
                    +--------------------+
                              |
                              v
                    +--------------------+
                    | Priority Compositor|
                    |                    |
                    | NORMAL             |
                    | WARNING            |
                    | CRITICAL           |
                    +--------------------+
                              |
                              v
                         640×480 VGA
