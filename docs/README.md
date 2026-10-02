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

**Diagram files:** [`diagrams/`](diagrams/) contains SVGs (ready to embed in GitHub), Graphviz `.dot` sources (editable), timing PNG, and Mermaid `.mmd` examples. **Hardware photos:** [`images/`](images/) contains the two demonstrations.

If your code is kept in a different GitHub folder layout, these documents still work: source filenames are written as code identifiers rather than hyperlinks to an assumed `rtl/` directory.

For the repository's main `README.md`, add:

```markdown
## Engineering documentation

See the [documentation index](docs/README.md) for architecture, VGA timing,
RTL design decisions, pinouts, verified results, and diagrams.
```

**References:** [Digilent Nexys 4 DDR Master XDC](https://github.com/Digilent/digilent-xdc/blob/master/Nexys-4-DDR-Master.xdc) · [Nexys 4 DDR reference manual](https://digilent.com/reference/programmable-logic/nexys-4-ddr/reference-manual)

**Board naming:** The previously uploaded PDF titled *Nexys-4-DDR-Master Manual.pdf* actually labels itself **Nexys 4 Rev. B** and describes CellularRAM. This documentation instead uses the uploaded **Nexys 4 DDR Master XDC** for the project's package-pin mappings and does not assume that the original Nexys 4 has DDR2.
