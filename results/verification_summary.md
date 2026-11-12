# Verification Summary

This summary is transcribed from the three result logs included in this repository snapshot.

| Run | Recorded result |
|---|---|
| Stage 1 | 45 checks; `TB RESULT: PASS` |
| Stage 2 | 5 stimulus checks; 88 total checks; `APB PROTOCOL RESULT: PASS` |
| Stages 3–7 | 199 checks; `STAGE 7 REGRESSION RESULT: PASS`; 18/18 event bins |

## Interpretation

- Stage 1 and advanced regression logs report zero errors.
- Stage 2 reports the procedural APB protocol checker result as PASS.
- 18/18 is selected event-bin coverage, not RTL code coverage.
- The APB checker is procedural, not formal verification.
- CDC scenarios are simulation tests, not formal CDC sign-off.
- These logs do not establish FPGA-board operation, physical-design closure or silicon validation.

Re-run `bash verification/scripts/run_all.sh` to generate fresh logs for the current source and simulator environment.
