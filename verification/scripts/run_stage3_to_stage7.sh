#!/usr/bin/env bash
set -euo pipefail
mkdir -p build results waveforms
iverilog -g2012 -s tb_stage7 -o build/advanced.vvp rtl/apb_uart_rtl.v verification/stage3_to_stage7_advanced_regression/tb_stage7.sv
vvp build/advanced.vvp | tee results/advanced_regression_results.txt
grep -q "STAGE 7 REGRESSION RESULT: PASS" results/advanced_regression_results.txt
grep -Eq "Total errors *: 0" results/advanced_regression_results.txt
grep -q "Coverage bins hit" results/advanced_regression_results.txt
