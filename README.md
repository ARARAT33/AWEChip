# AWEChip X8 — 64-Lane Reconfigurable Digital Accelerator

AWEChip X8 is a **purely digital 8×8-tile Tiny Tapeout IHP 26b design** targeting the IHP SG13G2 process.

The design is intentionally a reusable compute fabric rather than a single fixed-function circuit.

## Architecture

- **64 parallel 8-bit SIMD lanes**
- Per-lane A/B registers
- Per-lane 24-bit MAC accumulators
- Integer add/subtract/multiply
- AND/OR/XOR/shift/compare
- Waveform/phase engine and LFSR generator
- 32-sample programmable streaming delay
- 8-neuron leaky integrate-and-fire bank
- 8-sample CFAR-style adaptive detector
- Deterministic ROM/constant source
- Fabric reduction network
- Deterministic BIST/signature interface

## Control modes

| Mode | Function |
|---:|---|
| 0 | 64-lane SIMD + reductions |
| 1 | DSP / waveform / LFSR |
| 2 | MAC / arithmetic |
| 3 | 8-neuron LIF bank |
| 4 | 32-sample delay |
| 5 | CFAR-style detector |
| 6 | ROM / constants |
| 7 | BIST / diagnostics |

`ui_in[7:4]` selects the mode and `ui_in[3:0]` selects the operation. `uio_in` supplies data/configuration and `uo_out` returns the selected result. The bidirectional pins are deliberately kept disabled in this digital-only revision.

## Why 8×8?

The IHP 26b shuttle uses the IHP SG13G2 digital flow. AWEChip X8 is configured as `8x8` in `info.yaml`, giving the implementation substantially more physical area than a 1×1 educational example. The RTL uses that budget for a real parallel compute fabric instead of padding the design with unused geometry.

The goal is **useful digital logic density**, not a claim of a record transistor count. Final cell count, utilization, timing, congestion and routing are determined by synthesis and physical implementation.

## Verification

The repository includes a cocotb test suite covering:

- SIMD/reduction diagnostics
- waveform/LFSR operation
- arithmetic/MAC operations
- neuron dynamics
- delay memory
- CFAR behavior
- ROM determinism
- BIST/fabric markers
- safe digital-only GPIO configuration

## Tiny Tapeout flow

The project is based on the Tiny Tapeout IHP Verilog template and uses the IHP 26b GDS action with the `ihp-sg13g2` PDK. GitHub Actions build the GDS and then run Tiny Tapeout precheck and gate-level verification.

## Important

The 8×8 allocation is a project allocation request; the shuttle's remaining capacity and any Tiny Tapeout allocation/submission limits are controlled by the IHP 26b shuttle. A successful RTL commit does **not** by itself mean that fabrication acceptance has been granted. The GDS, precheck, timing and gate-level results must pass before submission.

License: Apache-2.0
