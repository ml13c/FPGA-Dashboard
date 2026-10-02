# Verification and Hardware Results

## Verification scope

The current evidence is a **manual hardware demonstration** of Stage 1 and Stage 2. The monitor photographs show the expected video output for the pictured input settings. The images do **not** independently prove exhaustive functional correctness, timing closure, simulation coverage, or latency.

## Demonstrated results

| ID | Setup or stimulus | Expected behavior | Observed evidence | Status |
|---|---|---|---|---|
| HW-01 | Program Stage 1 and connect FPGA VGA through active converter | Eight distinct, correctly ordered vertical bars; stable picture | [Color-bar photo](images/stage1_colorbars.jpg) | Demonstrated |
| HW-02 | Program Stage 2 with lower eight speed switches on | Three digits display **255** and the speed bar approaches full width | [Dashboard photo](images/stage2_dashboard.jpg) | Demonstrated |
| HW-03 | Stage 2 with upper battery switches producing a high value | Large green battery fill | [Dashboard photo](images/stage2_dashboard.jpg) | Visible |
| HW-04 | Stage 2 with both turn buttons held | Two yellow indicators appear | [Dashboard photo](images/stage2_dashboard.jpg) | Visible |
| HW-05 | Stage 2 with center warning button held | Bottom warning rectangle appears in red with yellow border | [Dashboard photo](images/stage2_dashboard.jpg) | Visible |

### Stage 1 photographic evidence

![Actual Stage 1 color bars displayed on monitor](images/stage1_colorbars.jpg)

### Stage 2 photographic evidence

![Actual Stage 2 dashboard displayed with enabled inputs](images/stage2_dashboard.jpg)

## Planned simulation and timing checks — NOT YET VERIFIED

The following is a proposed test plan. Do not mark these as passing until testbenches and saved results exist.

| ID | Proposed check | Expected result | Evidence to collect |
|---|---|---|---|
| VGA-TB-01 | Advance the design across a horizontal boundary | `x` wraps `799→0` and increments `y` on the corresponding pixel enable | XSIM waveform and assertion log |
| VGA-TB-02 | Examine `x` from 655 through 752 | HSYNC is low exactly for `656..751` | XSIM waveform, automated check |
| VGA-TB-03 | Examine `y` from 489 through 492 | VSYNC is low exactly for lines `490` and `491` | XSIM waveform, automated check |
| UI-TB-01 | Exercise speeds 0, 9, 10, 99, 100, and 255 | Correct decimal display and reasonable speed-bar bounds | Self-checking testbench and waveforms |
| UI-TB-02 | Toggle each button separately and together | Correct overlay and turn-indicator regions | Simulation checks and test log |
| STA-01 | Generate a Vivado post-route timing report for Stage 2 | Timing constraints satisfied; document any remaining unconstrained paths | Saved timing report |
| UTIL-01 | Generate a Vivado utilization report | Actual LUT, register, DSP and BRAM usage recorded | Saved utilization report |

**Example proposed testbench assertion (not yet executed):**

```verilog
// Check after DUT coordinates have reached the indicated position.
if ((x == 10'd656) && (hsync !== 1'b0))
    $error("HSYNC should go low at x=656");
if ((x == 10'd752) && (hsync !== 1'b1))
    $error("HSYNC should return high at x=752");
```

## Report template for future commits

| Metric | Version / date | Result |
|---|---|---|
| Vivado version | Fill from local installation | Pending documentation |
| Part | `xc7a100tcsg324-1` | Specified |
| Worst negative slack (WNS) | Post-route report | Not recorded |
| LUTs / flip-flops | Utilization report | Not recorded |
| DSP / BRAM usage | Utilization report | Not recorded |
| RTL simulation | Testbench run | Not yet recorded |

When adding a report, record the commit/revision, exact constraints, Vivado version, and the test conditions so the evidence can be reproduced.
