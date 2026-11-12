#!/usr/bin/env bash
set -euo pipefail
mkdir -p build results waveforms
iverilog -g2012 -s tb_basic -o build/stage1.vvp rtl/apb_uart_rtl.v verification/stage1_basic_functional/tb_basic.sv
vvp build/stage1.vvp | tee results/stage1_results.txt
grep -q "TB RESULT: PASS" results/stage1_results.txt
grep -Eq "Total errors *: 0" results/stage1_results.txt
