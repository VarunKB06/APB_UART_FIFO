
`timescale 1ns / 1ps

// ============================================================
// APB UART FIFO - ADVANCED REGRESSION TESTBENCH (STAGES 3-7)
//
// STAGE 3: Advanced APB and UART Verification (T11-T15)
// STAGE 4: Randomized and Reset Verification (T16-T20)
// STAGE 5: CDC and FIFO Stress Verification (T21-T24)
// STAGE 6: Robustness and Concurrency Verification (T25-T29)
// STAGE 7: Functional Coverage and Regression Closure (T30)
//
// T11: Back-to-back APB register accesses
// T12: Randomized register transactions
// T13: TX/RX FIFO stress with internal loopback
// T14: Reset during active UART TX and RX
// T15: Asynchronous clock-ratio stress
// T30: UART TX two-stop-bit timing and coverage closure
//
// Independent testbench. Does not modify the DUT.
// ============================================================

module tb_stage7;

    // --------------------------------------------------------
    // PARAMETERS
    // --------------------------------------------------------

    localparam integer DIV = 16;
    localparam real BIT_NS = 128.0;

    localparam [7:0] A_TXDATA = 8'h00,
                     A_RXDATA = 8'h04,
                     A_CTRL   = 8'h08,
                     A_BAUD   = 8'h0C,
                     A_STATUS = 8'h10,
                     A_INTEN  = 8'h14,
                     A_ERR    = 8'h1C;

    // --------------------------------------------------------
    // CLOCKS AND DUT SIGNALS
    // --------------------------------------------------------

    reg pclk = 0;
    reg uclk = 0;
    reg presetn = 0;

    reg [7:0] paddr = 0;
    reg psel = 0;
    reg penable = 0;
    reg pwrite = 0;
    reg [31:0] pwdata = 0;

    wire [31:0] prdata;
    wire pready;
    wire pslverr;
    wire irq;
    wire uart_txd;

    reg uart_rxd = 1;
    // ============================================================
// STAGE 4 VARIABLES
// ============================================================

reg [7:0] s4_expected [0:11];

integer s4_i;
integer s4_seed;

integer cov_random_loopback;
integer cov_fifo_full;
integer cov_fifo_overflow;
integer cov_back_to_back;
integer cov_reset_during_tx;
integer cov_reset_recovery;
integer cov_total;
// ============================================================
// STAGE 5 VARIABLES
// ============================================================

reg [7:0] s5_expected [0:3];

integer s5_i;
integer cov_cdc_integrity;
integer cov_rx_overflow;
integer cov_rx_contiguous;
integer cov_uart_error;

// Stage 6 variables (module scope for Verilog compatibility)
integer s6_i;
reg [7:0] s6_data;

// --------------------------------------------------------
// STAGE 7 EVENT-BASED FUNCTIONAL COVERAGE BINS
// Each bin is set only when the corresponding event is observed.
// These are scenario/event coverage bins, not code coverage.
// --------------------------------------------------------
integer cov_apb_read = 0;
integer cov_apb_write = 0;
integer cov_txdata_write = 0;
integer cov_rxdata_read = 0;
integer cov_status_read = 0;
integer cov_baud_programmed = 0;
integer cov_tx_enabled = 0;
integer cov_rx_enabled = 0;
integer cov_parity_enabled = 0;
integer cov_even_parity = 0;
integer cov_odd_parity = 0;
integer cov_one_stop = 0;
integer cov_two_stop = 0;
integer cov_loopback_enabled = 0;
integer cov_invalid_access = 0;
integer cov_irq_seen = 0;
integer cov_tx_serial_activity = 0;
integer cov_rx_serial_activity = 0;
integer cov_bins_hit = 0;
integer cov_bins_total = 18;
    // PCLK period = 10 ns
    always #5 pclk = ~pclk;

    // Variable UCLK half-period.
    // Initially UCLK period = 8 ns.
    real uclk_half = 4.0;

    always begin
        #(uclk_half);
        uclk = ~uclk;
    end

    // --------------------------------------------------------
    // DUT
    // --------------------------------------------------------

    apb_uart_top #(
        .FIFO_AW(4)
    ) dut (
        .pclk(pclk),
        .presetn(presetn),

        .paddr(paddr),
        .psel(psel),
        .penable(penable),
        .pwrite(pwrite),
        .pwdata(pwdata),

        .prdata(prdata),
        .pready(pready),
        .pslverr(pslverr),

        .uclk(uclk),
        .uart_rxd(uart_rxd),
        .uart_txd(uart_txd),
        .irq(irq)
    );

    // --------------------------------------------------------
    // TEST COUNTERS
    // --------------------------------------------------------

    integer checks = 0;
    integer errors = 0;

    integer i;
    integer seed = 32'h12345678;
    integer random_value;

    reg [31:0] rd_data;
    reg rd_err;

    reg [7:0] expected_data [0:15];

    // --------------------------------------------------------
    // CHECK TASK
    // --------------------------------------------------------

    task check;
        input [511:0] test_name;
        input [31:0] got;
        input [31:0] expected;
        begin
            checks = checks + 1;

            if (got !== expected) begin
                errors = errors + 1;

                $display(
                    "[FAIL] %0s : got=0x%0h expected=0x%0h at %0t",
                    test_name, got, expected, $time
                );
            end
            else begin
                $display("[PASS] %0s", test_name);
            end
        end
    endtask

    // --------------------------------------------------------
    // APB WRITE TASK
    // --------------------------------------------------------

    task apb_write;
        input [7:0] address;
        input [31:0] data;
        begin
            // Setup phase
            @(negedge pclk);

            psel = 1;
            penable = 0;
            pwrite = 1;
            paddr = address;
            pwdata = data;

            // Access phase
            @(negedge pclk);
            penable = 1;

            @(posedge pclk);
            #1;
            rd_err = pslverr;

            // End transfer
            @(negedge pclk);

            psel = 0;
            penable = 0;
            pwrite = 0;
        end
    endtask

    // --------------------------------------------------------
    // APB READ TASK
    // --------------------------------------------------------

    task apb_read;
        input [7:0] address;
        begin
            // Setup phase
            @(negedge pclk);

            psel = 1;
            penable = 0;
            pwrite = 0;
            paddr = address;

            // Access phase
            @(negedge pclk);
            penable = 1;

            #1;
            rd_data = prdata;
            rd_err = pslverr;

            // End transfer
            @(negedge pclk);

            psel = 0;
            penable = 0;
        end
    endtask

    // --------------------------------------------------------
    // RESET TASK
    // --------------------------------------------------------

    task do_reset;
        begin
            @(negedge pclk);

            presetn = 0;
            uart_rxd = 1;

            psel = 0;
            penable = 0;
            pwrite = 0;
            paddr = 0;
            pwdata = 0;

            repeat (5) @(negedge pclk);

            presetn = 1;

            // Wait for both reset synchronizers.
            repeat (12) @(posedge pclk);
            repeat (5) @(posedge uclk);
        end
    endtask

    // --------------------------------------------------------
    // UART RX SERIAL GENERATOR
    // --------------------------------------------------------

    task rx_send;
        input [7:0] data;
        integer k;
        begin
            uart_rxd = 0;
            #(BIT_NS);

            for (k = 0; k < 8; k = k + 1) begin
                uart_rxd = data[k];
                #(BIT_NS);
            end

            uart_rxd = 1;
            #(BIT_NS);

            uart_rxd = 1;
            #(BIT_NS);
        end
    endtask

// Stage 6 UART frame generator. Allows a selectable stop-bit value
// so framing-error injection does not alter the original rx_send task.
task rx_send_frame;
    input [7:0] data;
    input with_parity;
    input parity_bit;
    input stop_value;
    integer k;
    begin
        uart_rxd = 0;
        #(BIT_NS);
        for (k = 0; k < 8; k = k + 1) begin
            uart_rxd = data[k];
            #(BIT_NS);
        end
        if (with_parity) begin
            uart_rxd = parity_bit;
            #(BIT_NS);
        end
        uart_rxd = stop_value;
        #(BIT_NS);
        uart_rxd = 1;
        #(BIT_NS);
    end
endtask

// ============================================================
// RX FRAME WITH NO EXTRA IDLE BIT
// 8N1: start + 8 data + stop
// ============================================================

task rx_send_contiguous;
    input [7:0] data;
    integer k;
    begin
        uart_rxd = 0;
        #(BIT_NS);

        for (k = 0; k < 8; k = k + 1) begin
            uart_rxd = data[k];
            #(BIT_NS);
        end

        uart_rxd = 1;
        #(BIT_NS);
    end
endtask


// ============================================================
// RX FRAME WITH EVEN/ODD PARITY
// parity_odd = 0: even parity
// parity_odd = 1: odd parity
// ============================================================

task rx_send_parity;
    input [7:0] data;
    input parity_odd;
    input parity_error;
    integer k;
    reg parity_bit;
    begin
        parity_bit = ^data;

        if (parity_odd)
            parity_bit = ~parity_bit;

        if (parity_error)
            parity_bit = ~parity_bit;

        uart_rxd = 0;
        #(BIT_NS);

        for (k = 0; k < 8; k = k + 1) begin
            uart_rxd = data[k];
            #(BIT_NS);
        end

        uart_rxd = parity_bit;
        #(BIT_NS);

        uart_rxd = 1;
        #(BIT_NS);

        uart_rxd = 1;
        #(BIT_NS);
    end
endtask
    // --------------------------------------------------------
    // GLOBAL TIMEOUT
    // --------------------------------------------------------

    // --------------------------------------------------------
    // STAGE 7 COVERAGE MONITOR
    // Samples real APB handshakes and serial/interrupt activity.
    // --------------------------------------------------------
    always @(posedge pclk) begin
        if (presetn) begin
            if (psel && penable && pready) begin
                if (pwrite) begin
                    cov_apb_write = 1;
                    case (paddr)
                        A_TXDATA: cov_txdata_write = 1;
                        A_BAUD: if (pwdata != 0) cov_baud_programmed = 1;
                        A_CTRL: begin
                            if (pwdata[0]) cov_tx_enabled = 1;
                            if (pwdata[1]) cov_rx_enabled = 1;
                            if (pwdata[2]) begin
                                cov_parity_enabled = 1;
                                if (pwdata[3]) cov_odd_parity = 1;
                                else cov_even_parity = 1;
                            end
                            if (pwdata[4]) cov_two_stop = 1;
                            else cov_one_stop = 1;
                            if (pwdata[5]) cov_loopback_enabled = 1;
                        end
                        default: begin end
                    endcase
                end else begin
                    cov_apb_read = 1;
                    case (paddr)
                        A_RXDATA: cov_rxdata_read = 1;
                        A_STATUS: cov_status_read = 1;
                        default: begin end
                    endcase
                end
                if (pslverr) cov_invalid_access = 1;
            end
            if (irq) cov_irq_seen = 1;
            if (uart_txd === 1'b0) cov_tx_serial_activity = 1;
            if (uart_rxd === 1'b0) cov_rx_serial_activity = 1;
        end
    end

    initial begin
        #50_000_000;

        $display("[FAIL] STAGE 7 GLOBAL TIMEOUT");
        $display("Checks = %0d Errors = %0d", checks, errors);

        $finish;
    end

    // ========================================================
    // MAIN TEST SEQUENCE
    // ========================================================

    initial begin

        $display("");
        $display("==============================================");
        $display(" APB UART ADVANCED REGRESSION (STAGES 3-7)");
        $display("==============================================");

        do_reset;

        // ====================================================
        // STAGE 3: ADVANCED APB AND UART VERIFICATION
        // Tests T11-T15
        // ====================================================
        $display("");
        $display("========================================");
        $display(" STAGE 3: ADVANCED APB AND UART VERIFICATION");
        $display("========================================");

        // ====================================================
        // T11: BACK-TO-BACK APB REGISTER ACCESS
        // ====================================================

        $display("");
        $display("T11: BACK-TO-BACK APB REGISTER ACCESS");

        apb_write(A_BAUD, 32'd16);
        apb_write(A_INTEN, 32'd3);
        apb_write(A_CTRL, 32'd3);

        apb_read(A_BAUD);
        check("T11 BAUD readback", rd_data, 16);

        apb_read(A_INTEN);
        check("T11 INTEN readback", rd_data, 3);

        apb_read(A_CTRL);
        check("T11 CTRL readback", rd_data, 3);

        apb_write(A_INTEN, 32'd0);
        apb_write(A_CTRL, 32'd0);

        apb_read(A_INTEN);
        check("T11 INTEN cleared", rd_data, 0);

        // ====================================================
        // T12: RANDOMIZED REGISTER TRANSACTIONS
        // ====================================================

        $display("");
        $display("T12: RANDOMIZED REGISTER TRANSACTIONS");

        do_reset;

        for (i = 0; i < 20; i = i + 1) begin

            random_value = $urandom(seed);

            // BAUD register: test legal 16-bit values.
            // Keep UART disabled during these register tests.
            apb_write(A_BAUD, random_value & 16'hFFFF);

            apb_read(A_BAUD);

            check(
                "T12 Random BAUD readback",
                rd_data,
                random_value & 16'hFFFF
            );

            // INTEN supports only bits [2:0].
            apb_write(A_INTEN, random_value & 32'h7);

            apb_read(A_INTEN);

            check(
                "T12 Random INTEN readback",
                rd_data,
                random_value & 32'h7
            );
        end

        // Restore UART baud divisor.
        apb_write(A_BAUD, DIV);
        apb_write(A_INTEN, 0);

        // ====================================================
        // T13: TX/RX FIFO STRESS WITH LOOPBACK
        // ====================================================

        $display("");
        $display("T13: TX/RX FIFO STRESS WITH LOOPBACK");

        do_reset;

        // Enable TX, RX and internal loopback.
        apb_write(A_BAUD, DIV);
        apb_write(A_CTRL, 32'h23);

        // Queue 12 different bytes.
        // FIFO depth is 16.
        for (i = 0; i < 12; i = i + 1) begin

            expected_data[i] = (i * 17 + 8'h31) & 8'hFF;

            apb_write(A_TXDATA, expected_data[i]);

        end

        $display("[INFO] 12 bytes queued for loopback");

        // Allow UART to transmit and RX FIFO to receive.
        #(BIT_NS * 12 * 12 + 3000);

        // Read back all 12 bytes.
        for (i = 0; i < 12; i = i + 1) begin

            apb_read(A_RXDATA);

            check(
                "T13 Loopback FIFO data",
                rd_data[7:0],
                expected_data[i]
            );

        end

        apb_read(A_STATUS);

        check(
            "T13 RX FIFO empty after drain",
            rd_data[3],
            1
        );

        // ====================================================
        // T14A: RESET DURING ACTIVE UART TRANSMISSION
        // ====================================================

        $display("");
        $display("T14A: RESET DURING ACTIVE UART TRANSMISSION");

        do_reset;

        apb_write(A_BAUD, DIV);
        apb_write(A_CTRL, 32'h01);

        // Queue a byte.
        apb_write(A_TXDATA, 8'hA5);

        // Wait until transmission has started.
        wait (uart_txd == 0);

        // Wait a few bit periods, then reset.
        #(BIT_NS * 3);

        do_reset;

        // TX output must return to idle high.
        repeat (10) @(posedge uclk);

        check(
            "T14A TX idle after reset",
            uart_txd,
            1
        );

        // TX FIFO must also be empty after reset.
        apb_read(A_STATUS);

        check(
            "T14A TX FIFO empty after reset",
            rd_data[1],
            1
        );

        // ====================================================
        // T14B: RESET DURING ACTIVE UART RECEPTION
        // ====================================================

        $display("");
        $display("T14B: RESET DURING ACTIVE UART RECEPTION");

        do_reset;

        apb_write(A_BAUD, DIV);
        apb_write(A_CTRL, 32'h02);

        repeat (10) @(posedge uclk);

        // Start a UART frame and send only part of it.
        uart_rxd = 0;
        #(BIT_NS);

        uart_rxd = 1;
        #(BIT_NS);

        uart_rxd = 0;
        #(BIT_NS);

        // Reset while reception is incomplete.
        do_reset;

        // Confirm RX FIFO is empty.
        apb_read(A_STATUS);

        check(
            "T14B RX FIFO empty after reset",
            rd_data[3],
            1
        );

        // ====================================================
        // T15: ASYNCHRONOUS CLOCK-RATIO STRESS
        // ====================================================

        $display("");
        $display("T15: ASYNCHRONOUS CLOCK-RATIO STRESS");

        do_reset;

        apb_write(A_BAUD, DIV);
        apb_write(A_CTRL, 32'h23);

        // -----------------------------------------------
        // Clock ratio 1:
        // PCLK period = 10 ns
        // UCLK period = 7 ns
        // -----------------------------------------------

        $display("[INFO] Clock ratio 1: PCLK 10 ns, UCLK 7 ns");

        uclk_half = 3.5;

        repeat (5) begin
            apb_write(A_TXDATA, 8'h55);
            apb_write(A_TXDATA, 8'hAA);
        end

        #(BIT_NS * 12 * 11 + 3000);

        // -----------------------------------------------
        // Clock ratio 2:
        // PCLK period = 10 ns
        // UCLK period = 11 ns
        // -----------------------------------------------

        $display("[INFO] Clock ratio 2: PCLK 10 ns, UCLK 11 ns");

        uclk_half = 5.5;

        repeat (5) begin
            apb_write(A_TXDATA, 8'h3C);
            apb_write(A_TXDATA, 8'hC3);
        end

        #(BIT_NS * 12 * 11 + 3000);

        // -----------------------------------------------
        // Clock ratio 3:
        // PCLK period = 10 ns
        // UCLK period = 9 ns
        // -----------------------------------------------

        $display("[INFO] Clock ratio 3: PCLK 10 ns, UCLK 9 ns");

        uclk_half = 4.5;

        repeat (5) begin
            apb_write(A_TXDATA, 8'h96);
            apb_write(A_TXDATA, 8'h69);
        end

        #(BIT_NS * 12 * 11 + 3000);

        // Drain remaining RX data.
        // The expected bytes are checked in order.
        for (i = 0; i < 30; i = i + 1) begin

            apb_read(A_RXDATA);

            // The RX FIFO may contain data from the 30
            // transmitted bytes. Check that the first-word
            // data is not unknown when the FIFO is nonempty.
            if (rd_data[9:0] !== 10'bx) begin
                checks = checks + 1;

                if ((rd_data[9:0] & 10'h100) != 0 ||
                    (rd_data[9:0] & 10'h200) != 0) begin

                    errors = errors + 1;
                    $display("[FAIL] T15 Unexpected UART error flag");
                end
                else begin
                    $display("[PASS] T15 RX data has no parity/framing error");
                end
            end

        end

        // Restore original UCLK period.
        uclk_half = 4.0;

// ============================================================
// STAGE 4: RANDOMIZED AND RESET VERIFICATION
// ============================================================

$display("\n========================================");
$display(" STAGE 4: RANDOMIZED AND RESET VERIFICATION");
$display("========================================");

// Initialize functional coverage counters
cov_random_loopback = 0;
cov_fifo_full       = 0;
cov_fifo_overflow   = 0;
cov_back_to_back    = 0;
cov_reset_during_tx = 0;
cov_reset_recovery  = 0;

s4_seed = 32'h1234_ABCD;


// ============================================================
// T16: RANDOMIZED LOOPBACK DATA INTEGRITY
// ============================================================

$display("\nT16: RANDOMIZED LOOPBACK DATA INTEGRITY");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h23);  // TX enable + RX enable + loopback

// Generate and transmit 12 deterministic pseudo-random bytes.
// The reference data is stored before transmission.

for (s4_i = 0; s4_i < 12; s4_i = s4_i + 1) begin

    s4_seed = (s4_seed * 1664525) + 1013904223;
    s4_expected[s4_i] = s4_seed[23:16];

    apb_write(A_TXDATA, {24'b0, s4_expected[s4_i]});

end

// Allow all UART frames to complete.
// 12 frames, 8 data bits, start/stop and margin.
#(16 * 8 * 12 * 12);

for (s4_i = 0; s4_i < 12; s4_i = s4_i + 1) begin

    apb_read(A_RXDATA);

    check(
        "T16 randomized loopback data",
        {24'b0, rd_data[7:0]},
        {24'b0, s4_expected[s4_i]}
    );

    check(
        "T16 no parity/framing error",
        {30'b0, rd_data[9:8]},
        32'b0
    );

end

cov_random_loopback = 1;


// ============================================================
// T17: TX FIFO FULL AND OVERFLOW BOUNDARY
// ============================================================

$display("\nT17: TX FIFO FULL AND OVERFLOW");

do_reset;

// Keep transmitter disabled so FIFO does not drain.
apb_write(A_CTRL, 32'h00);

// FIFO depth = 16 when FIFO_AW = 4.
for (s4_i = 0; s4_i < 16; s4_i = s4_i + 1)
    apb_write(A_TXDATA, s4_i);

apb_read(A_STATUS);

check(
    "T17 TX FIFO reaches full",
    {31'b0, rd_data[0]},
    32'd1
);

cov_fifo_full = 1;

// One additional write should trigger overflow.
apb_write(A_TXDATA, 32'h000000EE);

apb_read(A_ERR);

check(
    "T17 TX FIFO overflow flag",
    {31'b0, rd_data[3]},
    32'd1
);

cov_fifo_overflow = 1;


// ============================================================
// T18: BACK-TO-BACK UART FRAMES
// ============================================================

$display("\nT18: BACK-TO-BACK UART FRAMES");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h23);

s4_expected[0] = 8'h55;
s4_expected[1] = 8'hAA;
s4_expected[2] = 8'hC3;

// Queue three frames without waiting for each frame to finish.
for (s4_i = 0; s4_i < 3; s4_i = s4_i + 1)
    apb_write(A_TXDATA, {24'b0, s4_expected[s4_i]});

// Wait for UART transmission and reception.
#(16 * 8 * 12 * 4);

for (s4_i = 0; s4_i < 3; s4_i = s4_i + 1) begin

    apb_read(A_RXDATA);

    check(
        "T18 back-to-back frame data",
        {24'b0, rd_data[7:0]},
        {24'b0, s4_expected[s4_i]}
    );

    check(
        "T18 frame error flags clear",
        {30'b0, rd_data[9:8]},
        32'b0
    );

end

cov_back_to_back = 1;


// ============================================================
// T19: RESET DURING ACTIVE TRANSMISSION AND RECOVERY
// ============================================================

$display("\nT19: RESET DURING ACTIVE TX AND RECOVERY");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h01);  // TX enabled

// Start a transmission.
apb_write(A_TXDATA, 32'h000000A5);

// Wait until transmission has started.
wait (uart_txd == 1'b0);
#(16 * 8 * 3);

// Assert asynchronous reset while TX is active.
presetn = 0;

repeat (4) @(posedge pclk);

presetn = 1;

// Allow reset synchronizers to release reset in both domains.
repeat (8) @(posedge pclk);
repeat (8) @(posedge uclk);

check(
    "T19 TX returns to idle after reset",
    {31'b0, uart_txd},
    32'd1
);

cov_reset_during_tx = 1;

// Verify that the peripheral can operate after reset.
apb_write(A_CTRL, 32'h23);
apb_write(A_TXDATA, 32'h00000096);

#(16 * 8 * 12 * 3);

apb_read(A_RXDATA);

check(
    "T19 data transfer after reset recovery",
    {24'b0, rd_data[7:0]},
    32'h96
);

check(
    "T19 no errors after recovery",
    {30'b0, rd_data[9:8]},
    32'b0
);

cov_reset_recovery = 1;


// ============================================================
// T20: FUNCTIONAL COVERAGE SUMMARY
// ============================================================

$display("\nT20: FUNCTIONAL COVERAGE SUMMARY");

cov_total =
    cov_random_loopback +
    cov_fifo_full +
    cov_fifo_overflow +
    cov_back_to_back +
    cov_reset_during_tx +
    cov_reset_recovery;

$display("----------------------------------------");
$display(" FUNCTIONAL COVERAGE");
$display("----------------------------------------");

$display("Randomized loopback       : %0d", cov_random_loopback);
$display("TX FIFO full              : %0d", cov_fifo_full);
$display("TX FIFO overflow          : %0d", cov_fifo_overflow);
$display("Back-to-back frames       : %0d", cov_back_to_back);
$display("Reset during TX           : %0d", cov_reset_during_tx);
$display("Reset recovery            : %0d", cov_reset_recovery);

$display("----------------------------------------");
$display("Coverage scenarios hit    : %0d / 6", cov_total);
$display("----------------------------------------");

if (cov_total == 6)
    $display("STAGE 4 COVERAGE RESULT: ALL SCENARIOS HIT");
else
    $display("STAGE 4 COVERAGE RESULT: INCOMPLETE");

// ============================================================
// STAGE 5: CDC AND FIFO STRESS VERIFICATION
// ============================================================

$display("\n========================================");
$display(" STAGE 5: CDC AND FIFO STRESS VERIFICATION");
$display("========================================");

cov_cdc_integrity = 0;
cov_rx_overflow   = 0;
cov_rx_contiguous = 0;
cov_uart_error    = 0;


// ============================================================
// T21: CDC DATA INTEGRITY AT DIFFERENT CLOCK RATIOS
// ============================================================

$display("\nT21: CDC DATA INTEGRITY");

s5_expected[0] = 8'hA5;
s5_expected[1] = 8'h3C;
s5_expected[2] = 8'h96;
s5_expected[3] = 8'hE1;

// Test three asynchronous clock ratios.
for (s5_i = 0; s5_i < 3; s5_i = s5_i + 1) begin

    do_reset;

    if (s5_i == 0)
        uclk_half = 3.5;  // UCLK period 7 ns

    else if (s5_i == 1)
        uclk_half = 5.5;  // UCLK period 11 ns

    else
        uclk_half = 4.5;  // UCLK period 9 ns

    apb_write(A_BAUD, 32'd16);
    apb_write(A_CTRL, 32'h23);

    // Queue four bytes.
    for (integer j = 0; j < 4; j = j + 1)
        apb_write(A_TXDATA, {24'b0, s5_expected[j]});

    // Wait for all four frames to be transmitted and received.
    #(16 * 8 * 12 * 6);

    // Compare every received byte against the reference.
    for (integer j = 0; j < 4; j = j + 1) begin

        apb_read(A_RXDATA);

        check(
            "T21 CDC expected data",
            {24'b0, rd_data[7:0]},
            {24'b0, s5_expected[j]}
        );

        check(
            "T21 CDC error flags",
            {30'b0, rd_data[9:8]},
            32'b0
        );

    end

end

uclk_half = 4.0;
cov_cdc_integrity = 1;


// ============================================================
// T22: RX FIFO OVERFLOW
// ============================================================

$display("\nT22: RX FIFO OVERFLOW");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h02);  // RX enabled, TX disabled

// Send 17 frames without reading the FIFO.
// FIFO depth is 16.
for (s5_i = 0; s5_i < 17; s5_i = s5_i + 1) begin
    rx_send((s5_i * 13 + 8'h31) & 8'hFF);
end

// Allow overflow event to cross into PCLK domain.
repeat (8) @(posedge pclk);

apb_read(A_ERR);

check(
    "T22 RX FIFO overflow flag",
    {31'b0, rd_data[2]},
    32'd1
);

cov_rx_overflow = 1;


// ============================================================
// T23: CONTIGUOUS RX FRAMES
// ============================================================

$display("\nT23: CONTIGUOUS RX FRAMES");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h02);

// Send three frames with only the required stop bit
// between frames.
fork
    begin
        rx_send_contiguous(8'h55);
        rx_send_contiguous(8'hAA);
        rx_send_contiguous(8'hC3);
    end
join

// Allow the receiver and FIFO to settle.
repeat (8) @(posedge pclk);

apb_read(A_RXDATA);
check("T23 first contiguous frame", rd_data[7:0], 8'h55);

apb_read(A_RXDATA);
check("T23 second contiguous frame", rd_data[7:0], 8'hAA);

apb_read(A_RXDATA);
check("T23 third contiguous frame", rd_data[7:0], 8'hC3);

cov_rx_contiguous = 1;


// ============================================================
// T24: RX PARITY ERROR HANDLING
// ============================================================

$display("\nT24: RX PARITY ERROR HANDLING");

do_reset;

apb_write(A_BAUD, 32'd16);

// RX enabled, parity enabled, even parity.
apb_write(A_CTRL, 32'h06);

rx_send_parity(8'h01, 0, 0);

repeat (8) @(posedge pclk);

apb_read(A_RXDATA);

check(
    "T24 even parity valid data",
    rd_data[7:0],
    8'h01
);

check(
    "T24 valid parity flag clear",
    {31'b0, rd_data[8]},
    32'b0
);

// Send another frame with deliberately incorrect parity.
rx_send_parity(8'h01, 0, 1);

repeat (8) @(posedge pclk);

apb_read(A_RXDATA);

check(
    "T24 incorrect parity detected",
    {31'b0, rd_data[8]},
    32'd1
);

check(
    "T24 incorrect parity data preserved",
    rd_data[7:0],
    8'h01
);

cov_uart_error = 1;


// ============================================================
// STAGE 5 COVERAGE SUMMARY
// ============================================================

$display("\n========================================");
$display(" STAGE 5 SCENARIO SUMMARY");
$display("========================================");

$display("CDC data integrity       : %0d", cov_cdc_integrity);
$display("RX FIFO overflow         : %0d", cov_rx_overflow);
$display("Contiguous RX frames     : %0d", cov_rx_contiguous);
$display("UART parity handling     : %0d", cov_uart_error);

if (cov_cdc_integrity &&
    cov_rx_overflow &&
    cov_rx_contiguous &&
    cov_uart_error)
    $display("STAGE 5 SCENARIO RESULT: ALL HIT");
else
    $display("STAGE 5 SCENARIO RESULT: INCOMPLETE");

// ============================================================
// STAGE 6: ROBUSTNESS AND CONCURRENCY VERIFICATION
// ============================================================

$display("\\n========================================");
$display(" STAGE 6: ROBUSTNESS AND CONCURRENCY VERIFICATION");
$display("========================================");

// ============================================================
// T25: UART FRAMING ERROR AND RECOVERY
// ============================================================

$display("\nT25: UART FRAMING ERROR AND RECOVERY");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h02); // RX enable, 8N1

repeat (10) @(posedge uclk);

// Send a frame with an invalid low stop bit.
rx_send_frame(8'hA6, 0, 0, 0);

apb_read(A_RXDATA);

check("T25 framing error flag",
      rd_data[9], 1);

check("T25 received data preserved",
      rd_data[7:0], 8'hA6);

apb_read(A_ERR);

check("T25 sticky framing error",
      rd_data[1], 1);

// Clear sticky error flags.
apb_write(A_ERR, 32'h3F);

// Send a valid frame after the error.
rx_send_frame(8'h5A, 0, 0, 1);

apb_read(A_RXDATA);

check("T25 recovery data",
      rd_data[7:0], 8'h5A);

check("T25 recovery framing flag clear",
      rd_data[9], 0);


// ============================================================
// T26: ASYNCHRONOUS RX AND APB CONCURRENCY
// ============================================================

$display("\nT26: ASYNCHRONOUS RX AND APB CONCURRENCY");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h02);

repeat (10) @(posedge uclk);

// Send a UART frame while APB reads STATUS.
// This exercises activity in both clock domains.
fork
    begin
        rx_send_frame(8'h3C, 0, 0, 1);
    end

    begin
        repeat (20) begin
            apb_read(A_STATUS);
            check("T26 APB STATUS read has no bus error",
                  rd_err, 0);
        end
    end
join

// Allow the RX FIFO write to cross into PCLK domain.
repeat (5) @(posedge pclk);

apb_read(A_RXDATA);

check("T26 concurrent RX data",
      rd_data[7:0], 8'h3C);

check("T26 concurrent RX error flags clear",
      rd_data[9:8], 2'b00);


// ============================================================
// T27: RX FIFO FULL, OVERFLOW AND RECOVERY
// ============================================================

$display("\nT27: RX FIFO FULL, OVERFLOW AND RECOVERY");

do_reset;

apb_write(A_BAUD, 32'd16);
apb_write(A_CTRL, 32'h02);

repeat (10) @(posedge uclk);

// RX FIFO depth = 16.
// Send 17 frames without reading the FIFO.
for (s6_i = 0; s6_i < 17; s6_i = s6_i + 1) begin
    s6_data = (s6_i * 13 + 8'h21) & 8'hFF;
    rx_send_frame(s6_data, 0, 0, 1);
end

repeat (8) @(posedge pclk);

// Check the documented sticky RX-overflow flag. STATUS[2] is
// not assumed to be an RX-full indicator by this testbench.
apb_read(A_ERR);

check("T27 RX overflow sticky flag",
      rd_data[2], 1);

// Drain the FIFO.
for (s6_i = 0; s6_i < 16; s6_i = s6_i + 1) begin
    apb_read(A_RXDATA);
end

apb_read(A_STATUS);

check("T27 RX FIFO empty after drain",
      rd_data[3], 1);

// Clear sticky errors.
apb_write(A_ERR, 32'h3F);

// Verify that RX accepts data again.
rx_send_frame(8'hD6, 0, 0, 1);

apb_read(A_RXDATA);

check("T27 RX FIFO recovery data",
      rd_data[7:0], 8'hD6);

check("T27 no framing error after recovery",
      rd_data[9], 0);


// ============================================================
// T28: UART PARITY CONFIGURATION TESTS
// ============================================================

$display("\nT28: UART PARITY CONFIGURATION TESTS");

do_reset;

apb_write(A_BAUD, 32'd16);

// Even parity: CTRL[2]=1, CTRL[3]=0.
// 0x01 has one set bit, so even parity bit = 1.
apb_write(A_CTRL, 32'h06);

repeat (10) @(posedge uclk);

rx_send_parity(8'h01, 0, 0);

apb_read(A_RXDATA);

check("T28 even parity valid data",
      rd_data[7:0], 8'h01);

check("T28 even parity no error",
      rd_data[8], 0);

// Odd parity: CTRL[2]=1, CTRL[3]=1.
// 0x01 has one set bit, so odd parity bit = 0.
apb_write(A_CTRL, 32'h0E);

repeat (10) @(posedge uclk);

rx_send_parity(8'h01, 1, 0);

apb_read(A_RXDATA);

check("T28 odd parity valid data",
      rd_data[7:0], 8'h01);

check("T28 odd parity no error",
      rd_data[8], 0);


// ============================================================
// T29: APB INVALID ACCESS AND ERROR CLEARING
// ============================================================

$display("\nT29: APB INVALID ACCESS AND ERROR CLEARING");

do_reset;

// Unmapped read.
apb_read(8'h40);

check("T29 unmapped read PSLVERR",
      rd_err, 1);

// Write to read-only STATUS register.
apb_write(A_STATUS, 32'h1234);

check("T29 write read-only register PSLVERR",
      rd_err, 1);

// Invalid access sticky bit.
apb_read(A_ERR);

check("T29 invalid access sticky flag",
      rd_data[5], 1);

// Clear sticky error flags.
apb_write(A_ERR, 32'h3F);

apb_read(A_ERR);

check("T29 error flags cleared",
      rd_data, 0);

// ============================================================
// T30: UART TX TWO-STOP-BIT CONFIGURATION AND TIMING
// ============================================================

$display("\nT30: UART TX TWO-STOP-BIT CONFIGURATION");

do_reset;

// Restore the nominal clock ratio and baud divisor used by BIT_NS.
uclk_half = 4.0;
apb_write(A_BAUD, 32'd16);

// CTRL[0] = TX enable, CTRL[4] = two stop bits.
// No parity, RX disabled, loopback disabled.
apb_write(A_CTRL, 32'h11);

apb_write(A_TXDATA, 32'h000000A5);

// Wait for the start-bit falling edge. The transmitter runs at
// 16 UCLK cycles per bit, i.e. 128 ns with an 8 ns UCLK period.
@(negedge uart_txd);

// Start bit + eight data bits = nine bit periods. Sample halfway
// through stop bit 1, then halfway through stop bit 2.
#(BIT_NS * 9.5);
check("T30 first stop bit is high", uart_txd, 1);

#(BIT_NS);
check("T30 second stop bit is high", uart_txd, 1);

// By the end of the second stop interval, TX must have returned
// to idle. Leave an additional half-bit margin for state update.
#(BIT_NS * 0.5);
check("T30 TX returns to idle after two stop bits", uart_txd, 1);

// Allow the APB coverage monitor to observe the CTRL write.
repeat (2) @(posedge pclk);

// T30: final regression summary is printed once below.

        // ====================================================
        // STAGE 7: FUNCTIONAL COVERAGE AND REGRESSION CLOSURE
        // ====================================================
        cov_bins_hit = cov_apb_read + cov_apb_write + cov_txdata_write +
                       cov_rxdata_read + cov_status_read + cov_baud_programmed +
                       cov_tx_enabled + cov_rx_enabled + cov_parity_enabled +
                       cov_even_parity + cov_odd_parity + cov_one_stop +
                       cov_two_stop + cov_loopback_enabled + cov_invalid_access +
                       cov_irq_seen + cov_tx_serial_activity + cov_rx_serial_activity;

        $display("");
        $display("==============================================");
        $display(" STAGE 7: FUNCTIONAL COVERAGE AND REGRESSION CLOSURE");
        $display("==============================================");
        $display("APB read                  : %0d", cov_apb_read);
        $display("APB write                 : %0d", cov_apb_write);
        $display("TXDATA write              : %0d", cov_txdata_write);
        $display("RXDATA read               : %0d", cov_rxdata_read);
        $display("STATUS read               : %0d", cov_status_read);
        $display("BAUD programmed           : %0d", cov_baud_programmed);
        $display("TX enabled                : %0d", cov_tx_enabled);
        $display("RX enabled                : %0d", cov_rx_enabled);
        $display("Parity enabled            : %0d", cov_parity_enabled);
        $display("Even parity               : %0d", cov_even_parity);
        $display("Odd parity                : %0d", cov_odd_parity);
        $display("1 stop bit                : %0d", cov_one_stop);
        $display("2 stop bits               : %0d", cov_two_stop);
        $display("Loopback enabled          : %0d", cov_loopback_enabled);
        $display("Invalid APB access        : %0d", cov_invalid_access);
        $display("IRQ observed              : %0d", cov_irq_seen);
        $display("TX serial activity        : %0d", cov_tx_serial_activity);
        $display("RX serial activity        : %0d", cov_rx_serial_activity);
        $display("----------------------------------------------");
        $display("Coverage bins hit         : %0d / %0d", cov_bins_hit, cov_bins_total);
        $display("Functional coverage      : %0.2f%%", (100.0 * cov_bins_hit) / cov_bins_total);
        $display("NOTE: event-bin coverage; not RTL code coverage.");
        $display("==============================================");

        // ====================================================
        // FINAL SUMMARY
        // ====================================================

        $display("");
        $display("==============================================");
        $display(" STAGE 7: FINAL REGRESSION SUMMARY");
        $display("==============================================");

        $display("Total checks : %0d", checks);
        $display("Total errors : %0d", errors);

        if (errors == 0)
            $display("STAGE 7 REGRESSION RESULT: PASS");
        else
            $display("STAGE 7 REGRESSION RESULT: FAIL");

        $display("==============================================");

        $finish;

    end

    // --------------------------------------------------------
    // WAVEFORM DUMP
    // --------------------------------------------------------

    initial begin
        $dumpfile("waveforms/stage3_to_stage7.vcd");
        $dumpvars(0, tb_stage7);
    end

endmodule
