#!/usr/bin/env bash
set -euo pipefail
mkdir -p build results waveforms
iverilog -g2012 -s tb_stage2_wrapper -o build/stage2.vvp \
  rtl/apb_uart_rtl.v \
  verification/stage2_apb_protocol/apb_assertions.sv \
  verification/stage2_apb_protocol/tb_stage2_wrapper.sv
vvp build/stage2.vvp | tee results/stage2_results.txt
grep -q "STAGE 2 TEST RESULT: PASS" results/stage2_results.txt
grep -q "APB PROTOCOL RESULT: PASS" results/stage2_results.txt
grep -Eq "Total errors *: 0" results/stage2_results.txt
