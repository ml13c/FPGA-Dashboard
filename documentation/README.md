# FPGA Vehicle Dashboard — Engineering Documentation

These documents cover the **implemented Stage 1 VGA test pattern** and **implemented Stage 2 switch/button-controlled dashboard** running on the **Digilent Nexys 4 DDR (Artix-7 XC7A100T)** in Verilog/Vivado. The OV7670 live camera feed, BRAM frame buffers, and DDR2 are **planned**, not currently part of these versions.

| Page | What it documents |
|---|---|
| [Architecture](architecture.md) | System block diagram, RTL module roles, and pixel data flow |
| [VGA Controller](vga_controller.md) | Pixel-enable logic, timing values, sync generation, and alternatives |
| [Dashboard](dashboard.md) | Inputs, coordinate-based drawing, digits, scaling, and layer priority |
| [Hardware and Pinout](hardware.md) | Board interfaces, relevant XDC pin assignments, and setup |
| [Verification](verification.md) | Actual hardware evidence, photos, and a clearly labeled test plan |
| [Design Decisions](design_decisions.md) | Reasoning, limitations, alternatives, and future camera integration |
| [Diagrams and UML](uml_diagrams.md) | All figures plus editable Mermaid state/dataflow examples |
