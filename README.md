# APB UART FIFO Peripheral

APB-controlled UART peripheral with asynchronous TX/RX FIFOs, configurable baud divisor, parity, stop bits, loopback and interrupt/status registers.

## Repository layout

- `rtl/` — synthesizable RTL design.
- `verification/stage1_basic_functional/` — Stage 1 directed functional testbench (T1–T10).
- `verification/stage2_apb_protocol/` — Stage 2 procedural APB protocol checker and explicit-instantiation wrapper.
- `verification/stage3_to_stage7_advanced_regression/` — advanced regression (T11–T30) and event-based functional coverage.
- `verification/scripts/` — local regression scripts.
- `.github/workflows/apb_uart_ci.yml` — GitHub Actions continuous-integration workflow.
- `results/` and `waveforms/` — simulation logs and VCD outputs.

## Run locally

Install Icarus Verilog and run:

```bash
bash verification/scripts/run_all.sh
```

The scripts compile each testbench, run the simulation, save logs under `results/`, and generate VCD files under `waveforms/`.

Open a waveform with GTKWave, for example:

```bash
gtkwave waveforms/stage1_basic.vcd
```

## Verification stages

1. Stage 1 — Basic functional verification, T1–T10.
2. Stage 2 — APB protocol checker: setup-to-access sequencing, PENABLE/PSEL relationship, setup-to-access signal stability, zero-wait PREADY, and PSLVERR phase legality.
3. Stage 3 — Advanced APB and UART verification, T11–T15.
4. Stage 4 — Randomized and reset verification, T16–T20.
5. Stage 5 — CDC and FIFO stress verification, T21–T24.
6. Stage 6 — Robustness and concurrency verification, T25–T29.
7. Stage 7 — Functional event-bin coverage and regression closure, T30.

Stage 2 is instantiated explicitly in its wrapper rather than using `bind`, to improve compatibility with open-source simulators. It remains a separate verification stage.

## Scope and limitations

- The supplied RTL and testbench source files are the project sources provided for this package.
- GitHub Actions uses Icarus Verilog. Simulator compatibility and results must be confirmed by running the workflow; a successful local XSim run does not automatically prove Icarus equivalence.
- Stage 7 reports selected event-bin coverage, not RTL code coverage or formal proof.
- The CDC tests are simulation stress tests, not formal CDC sign-off.
- No FPGA hardware or fabricated-silicon validation is claimed by this repository.
