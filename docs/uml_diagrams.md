# Hardware Diagrams and UML-Style Models

Hardware block and timing diagrams are the main artifacts for this FPGA project. UML-style state and sequence diagrams supplement them where they describe genuinely sequential control behavior; HDL modules are concurrent circuits rather than software objects, so traditional class diagrams are not a good architecture representation.

## 1. Implemented system block diagram

![Stage 1 and Stage 2 FPGA hardware blocks](diagrams/architecture.svg)

Edit the source file [`diagrams/architecture.dot`](diagrams/architecture.dot) using [Graphviz](https://graphviz.org/), or reuse the SVG directly in your README.

## 2. Implemented VGA timing diagram

![VGA timing figure](diagrams/vga_timing.svg)

This shows the exact timing used: horizontally 640 active + 16 front porch + 96 sync + 48 back porch; vertically 480 active + 10 front porch + 2 sync + 33 back porch.

## 3. UML-style state diagram: 2-bit pixel enable

This diagram models the actual four states of `pixel_cnt`, not the entire video system. GitHub renders the Mermaid code directly:

```mermaid
stateDiagram-v2
    [*] --> C0
    C0: pixel_cnt = 00
    C1: pixel_cnt = 01
    C2: pixel_cnt = 10
    C3: pixel_cnt = 11, pixel_tick = 1
    C0 --> C1: rising clock
    C1 --> C2: rising clock
    C2 --> C3: rising clock
    C3 --> C0: rising clock
```

Editable source: [`diagrams/pixel_enable_state.mmd`](diagrams/pixel_enable_state.mmd).

## 4. Data flow through implemented Stage 2

```mermaid
flowchart TD
  clock[Board 100 MHz oscillator] --> timing[vga_timing.v]
  timing -->|x, y, video_on| ui[dashboard_ui.v]
  input[Physical switches and buttons] --> ui
  ui -->|RGB444| top[top.v]
  timing -->|HSYNC and VSYNC| top
  top --> port[Board VGA connector]
  port --> conv[External VGA-to-HDMI converter]
  conv --> monitor[Monitor]
```

Editable source: [`diagrams/stage2_dataflow.mmd`](diagrams/stage2_dataflow.mmd).

## 5. Layer-priority diagram

![Actual Stage 2 renderer painting order](diagrams/render_layers.svg)

The process initializes a base color, then later true conditions overwrite the current `rgb` value. The warning block is intentionally evaluated late to make its graphics high priority.

Editable source: [`diagrams/render_layers.dot`](diagrams/render_layers.dot).

## What to add with the camera later

After hardware capture is implemented and verified, add a **timing waveform** for the OV7670's PCLK, VSYNC, HREF and pixel-data bus, and a UML-style **sequence diagram** for the actual SCCB register-write sequence. Do not treat an illustrative sequence diagram as proof of the real module's timing.
