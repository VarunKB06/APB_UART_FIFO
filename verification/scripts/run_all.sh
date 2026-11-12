#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"
echo "========== STAGE 1 =========="
bash verification/scripts/run_stage1.sh
echo "========== STAGE 2 =========="
bash verification/scripts/run_stage2.sh
echo "========== STAGES 3-7 =========="
bash verification/scripts/run_stage3_to_stage7.sh
echo "========================================"
echo "APB UART FIFO: ALL CI REGRESSIONS PASSED"
echo "========================================"
