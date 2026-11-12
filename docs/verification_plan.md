# Verification Plan

## 1. Verification structure

The repository contains three executable simulation targets:

1. Stage 1 directed functional testbench: `tb_basic.sv`.
2. Stage 2 APB procedural checker plus dedicated wrapper: `apb_assertions.sv` and `tb_stage2_wrapper.sv`.
3. Combined Stage 3–7 advanced regression: `tb_stage7.sv`.

The stage numbering describes the verification progression; Stages 3–7 are combined in one testbench and one run script.

## 2. Stage-by-stage plan

| Stage | Test IDs | Scope | Source |
|---|---|---|---|
| 1 | T1–T10 (including T3B) | Reset values; register read/write and invalid access; TX 8N1 and even parity; RX; random loopback; parity/framing errors; TX full/overflow; RX underflow; RX interrupt | `stage1_basic_functional/tb_basic.sv` |
| 2 | Protocol rules | APB setup/access sequencing, PENABLE/PSEL relationship, setup-to-access stability, PREADY high for this zero-wait DUT, PSLVERR phase legality | `stage2_apb_protocol/` |
| 3 | T11–T15 | Advanced APB/UART activity, back-to-back traffic, reset/clock-ratio scenarios | `stage3_to_stage7_advanced_regression/tb_stage7.sv` |
| 4 | T16–T20 | Deterministic pseudo-random loopback, TX FIFO full/overflow, back-to-back frames, reset during TX and recovery | Same |
| 5 | T21–T24 | Clock-ratio data-integrity checks, RX overflow, contiguous RX frames, valid/invalid parity | Same |
| 6 | T25–T29 | Framing-error recovery, asynchronous RX with APB status reads, RX FIFO drain/recovery, even/odd parity, invalid APB access and error clearing | Same |
| 7 | T30 | Two-stop-bit TX checks and selected event-bin coverage summary | Same |

For exact test messages and expected checks, consult the corresponding testbench and captured result logs.

## 3. Stage 2 procedural APB checker

The checker evaluates five implementation-specific protocol rules:

1. A setup phase is followed by an access phase.
2. `PENABLE` must not be asserted without `PSEL`.
3. `PADDR`, `PWRITE` and `PWDATA` remain stable from setup to access.
4. `PREADY` remains high because this DUT is implemented as zero-wait-state.
5. `PSLVERR` is asserted only during an APB access phase.

The checker is procedurally instantiated in `tb_stage2_wrapper.sv`; it is not native SVA bind-based formal verification.

## 4. Coverage interpretation

Stage 7 contains 18 selected event bins. The supplied result log reports 18/18 bins hit (100% selected event-bin coverage). Stage 4 and Stage 5 also report scenario counters. These are scenario/event indicators, not statement, branch, toggle or FSM code coverage.

## 5. CDC verification boundary

T21 applies clock-ratio variations and checks expected received data and error flags. Other tests exercise asynchronous FIFO traffic, overflow, reset and concurrency. These are simulation-based stress tests. They do not replace structural CDC analysis, synchronizer MTBF analysis, formal verification or silicon validation.

## 6. Reproduction

From the repository root:

```bash
bash verification/scripts/run_stage1.sh
bash verification/scripts/run_stage2.sh
bash verification/scripts/run_stage3_to_stage7.sh
```

Or run all targets:

```bash
bash verification/scripts/run_all.sh
```

The scripts compile with Icarus Verilog `-g2012`, execute with `vvp`, save text logs in `results/` and generate VCD files in `waveforms/`.

## 7. Recorded results in this repository snapshot

| Log | Recorded result |
|---|---|
| `stage1_results.txt` | 45 checks; PASS |
| `stage2_results.txt` | 5 stimulus checks; 88 total checks; APB protocol PASS |
| `advanced_regression_results.txt` | 199 checks; PASS; 18/18 selected event bins |

These values describe the included logs, not a promise that every future simulator/version/host will reproduce identical output. Re-run the scripts after changing RTL, testbench, simulator or environment.
