# Verification Plan

| Stage | Scope | Source |
|---|---|---|
| 1 | Directed functional tests T1–T10 | `tb_basic.sv` |
| 2 | Five procedural APB protocol rules | `apb_assertions.sv` + `tb_stage2_wrapper.sv` |
| 3 | Advanced APB/UART tests T11–T15 | `tb_stage7.sv` |
| 4 | Randomized/reset tests T16–T20 | `tb_stage7.sv` |
| 5 | CDC/FIFO tests T21–T24 | `tb_stage7.sv` |
| 6 | Robustness/concurrency tests T25–T29 | `tb_stage7.sv` |
| 7 | Two-stop-bit test T30 and 18 event bins | `tb_stage7.sv` |

Stage 2 checker rules:
1. Setup phase is followed by access.
2. PENABLE implies PSEL.
3. PADDR, PWRITE and PWDATA remain stable from setup to access.
4. PREADY remains high for this zero-wait-state DUT.
5. PSLVERR is asserted only during an APB access phase.

The event-bin count is not RTL code coverage. The CDC scenarios are simulation tests, not formal CDC verification.
