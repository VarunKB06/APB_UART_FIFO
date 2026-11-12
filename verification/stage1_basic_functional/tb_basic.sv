
`timescale 1ns/1ps

// Stage-1 directed, self-checking testbench for APB UART.
// Tests T1-T10. Simulation is required to confirm DUT behavior.

module tb_basic;

    localparam integer DIV = 16;
    localparam real UCLK_NS = 8.0;
    localparam real BIT_NS  = DIV * UCLK_NS;

    localparam [7:0] A_TXDATA = 8'h00,
                     A_RXDATA = 8'h04,
                     A_CTRL   = 8'h08,
                     A_BAUD   = 8'h0C,
                     A_STATUS = 8'h10,
                     A_INTEN  = 8'h14,
                     A_INTST  = 8'h18,
                     A_ERR    = 8'h1C;

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

    apb_uart_top dut (
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

    always #5 pclk = ~pclk;
    always #4 uclk = ~uclk;

    integer errors = 0;
    integer checks = 0;

    reg [31:0] rd_data;
    reg rd_err;

    // ------------------------------------------------
    // CHECK TASK
    // ------------------------------------------------

    task check;
        input [511:0] name;
        input [31:0] got;
        input [31:0] exp;
        begin
            checks = checks + 1;

            if (got !== exp) begin
                errors = errors + 1;
                $display(
                    "[FAIL] %0s: got=0x%0h expected=0x%0h at %0t",
                    name, got, exp, $time
                );
            end
            else begin
                $display("[PASS] %0s", name);
            end
        end
    endtask

    // ------------------------------------------------
    // APB WRITE TASK
    // ------------------------------------------------

    task apb_write;
        input [7:0] a;
        input [31:0] d;
        begin
            // Setup phase
            @(negedge pclk);
            psel    = 1;
            pwrite  = 1;
            paddr   = a;
            pwdata  = d;
            penable = 0;

            // Access phase
            @(negedge pclk);
            penable = 1;

            // Sample during access phase
            @(posedge pclk);
            #1;
            rd_err = pslverr;

            // End transaction
            @(negedge pclk);
            psel    = 0;
            penable = 0;
            pwrite  = 0;
        end
    endtask

    // ------------------------------------------------
    // APB READ TASK
    // ------------------------------------------------

    task apb_read;
        input [7:0] a;
        begin
            // Setup phase
            @(negedge pclk);
            psel    = 1;
            pwrite  = 0;
            paddr   = a;
            penable = 0;

            // Access phase
            @(negedge pclk);
            penable = 1;

            // Sample during access phase
            #1;
            rd_data = prdata;
            rd_err  = pslverr;

            // End transaction
            @(negedge pclk);
            psel    = 0;
            penable = 0;
        end
    endtask

    // ------------------------------------------------
    // RESET TASK
    // ------------------------------------------------

    task do_reset;
        begin
            @(negedge pclk);
            presetn = 0;
            uart_rxd = 1;

            repeat (5) @(negedge pclk);

            presetn = 1;

            // Allow reset synchronizers to release
            repeat (10) @(posedge pclk);
        end
    endtask

    // ------------------------------------------------
    // UART RX SERIAL DATA GENERATOR
    // ------------------------------------------------

    task rx_send;
        input [7:0] d;
        input with_par;
        input par_bit;
        input stop_val;

        integer k;

        begin
            uart_rxd = 0;
            #(BIT_NS);

            for (k = 0; k < 8; k = k + 1) begin
                uart_rxd = d[k];
                #(BIT_NS);
            end

            if (with_par) begin
                uart_rxd = par_bit;
                #(BIT_NS);
            end

            uart_rxd = stop_val;
            #(BIT_NS);

            uart_rxd = 1;
            #(BIT_NS);
        end
    endtask

    // ------------------------------------------------
    // UART TX INDEPENDENT MONITOR
    // ------------------------------------------------

    task tx_expect;
        input [7:0] exp;
        input with_par;
        input par_bit;

        integer k;
        reg [7:0] got;

        begin
            @(negedge uart_txd);

            #(BIT_NS/2.0);

            check("TX start bit", uart_txd, 0);

            for (k = 0; k < 8; k = k + 1) begin
                #(BIT_NS);
                got[k] = uart_txd;
            end

            check("TX data", got, exp);

            if (with_par) begin
                #(BIT_NS);
                check("TX parity bit", uart_txd, par_bit);
            end

            #(BIT_NS);
            check("TX stop bit", uart_txd, 1);
        end
    endtask

    // ------------------------------------------------
    // LOOPBACK REFERENCE QUEUE
    // ------------------------------------------------

    reg [7:0] ref_q [0:63];

    integer q_wr = 0;
    integer q_rd = 0;

    integer i;
    integer seed;

    reg [7:0] b;

    // ------------------------------------------------
    // GLOBAL TIMEOUT
    // ------------------------------------------------

    initial begin
        #2_000_000;
        $display("[FAIL] GLOBAL TIMEOUT at %0t", $time);
        $display("Checks completed: %0d", checks);
        $display("Errors: %0d", errors);
        $finish;
    end

    // ------------------------------------------------
    // MAIN TEST SEQUENCE
    // ------------------------------------------------

    initial begin

        seed = 1;

        $display("");
        $display("========================================");
        $display(" APB UART STAGE-1 TESTBENCH");
        $display(" Random seed = %0d", seed);
        $display("========================================");

        do_reset;

        // ============================================
        // T1: RESET VALUES
        // ============================================

        $display("\nT1: RESET VALUES");

        apb_read(A_CTRL);
        check("Reset CTRL", rd_data, 0);

        apb_read(A_BAUD);
        check("Reset BAUD", rd_data, 16);

        apb_read(A_ERR);
        check("Reset ERR", rd_data, 0);

        repeat (6) @(posedge pclk);

        apb_read(A_STATUS);
        check("Reset STATUS", rd_data, 32'h0A);

        check("IRQ low after reset", irq, 0);

        // ============================================
        // T2: REGISTER READ/WRITE AND INVALID ACCESS
        // ============================================

        $display("\nT2: REGISTER RW / INVALID ACCESS");

        apb_write(A_BAUD, 32'h0000_1234);
        apb_read(A_BAUD);
        check("BAUD read/write", rd_data, 32'h1234);

        apb_write(A_BAUD, DIV);

        apb_write(A_INTEN, 32'h7);
        apb_read(A_INTEN);
        check("INTEN read/write", rd_data, 32'h7);

        apb_write(A_INTEN, 0);

        apb_read(8'h40);
        check("Unmapped read PSLVERR", rd_err, 1);

        apb_write(A_STATUS, 32'h1);
        check("Write RO PSLVERR", rd_err, 1);

        apb_read(A_ERR);
        check("Invalid access sticky bit", rd_data[5], 1);

        apb_write(A_ERR, 32'h3F);
        apb_read(A_ERR);
        check("ERR write-one-to-clear", rd_data, 0);

        // ============================================
        // T3: UART TX BASIC 8N1
        // ============================================

        $display("\nT3: UART TX BASIC 8N1");

        apb_write(A_CTRL, 32'h01);

        fork
            tx_expect(8'hA5, 0, 0);

            begin
                repeat (4) @(posedge pclk);
                apb_write(A_TXDATA, 32'hA5);
            end
        join

        #(BIT_NS * 3);

        // ============================================
        // T3B: UART TX EVEN PARITY
        // ============================================

        $display("\nT3B: UART TX EVEN PARITY");

        // A5 contains four ones, so even parity bit = 0.
        apb_write(A_CTRL, 32'h05);

        fork
            tx_expect(8'hA5, 1, 0);

            begin
                repeat (4) @(posedge pclk);
                apb_write(A_TXDATA, 32'hA5);
            end
        join

        #(BIT_NS * 3);

        // ============================================
        // T4: UART RX BASIC
        // ============================================

        $display("\nT4: UART RX BASIC");

        do_reset;

        apb_write(A_CTRL, 32'h02);

        repeat (10) @(posedge uclk);

        rx_send(8'h3C, 0, 0, 1);

        apb_read(A_STATUS);
        check("RX not empty", rd_data[3], 0);

        apb_read(A_RXDATA);
        check("RXDATA", rd_data, 32'h3C);

        apb_read(A_STATUS);
        check("RX empty after read", rd_data[3], 1);

        // ============================================
        // T5: RANDOM LOOPBACK
        // ============================================

        $display("\nT5: RANDOM LOOPBACK");

        do_reset;

        apb_write(A_CTRL, 32'h23);

        q_wr = 0;
        q_rd = 0;

        for (i = 0; i < 10; i = i + 1) begin

            // Correct use of the $urandom seed argument.
            // The seed is updated internally by $urandom.
            b = $urandom(seed);

            ref_q[q_wr] = b;
            q_wr = q_wr + 1;

            apb_write(A_TXDATA, b);
        end

        // Allow all 10 UART frames to complete.
        #(BIT_NS * 10 * 12 + 2000);

        for (i = 0; i < 10; i = i + 1) begin

            apb_read(A_RXDATA);

            check(
                "Loopback byte",
                rd_data,
                {24'b0, ref_q[q_rd]}
            );

            q_rd = q_rd + 1;
        end

        apb_read(A_STATUS);
        check("RX empty after loopback drain", rd_data[3], 1);

        // ============================================
        // T6: UART RX PARITY ERROR
        // ============================================

        $display("\nT6: UART RX PARITY ERROR");

        do_reset;

        apb_write(A_CTRL, 32'h06);

        repeat (10) @(posedge uclk);

        // 0x01 has one '1'. Even parity should be 1.
        // Send 0 to deliberately cause parity error.
        rx_send(8'h01, 1, 0, 1);

        apb_read(A_RXDATA);

        check("RX parity error flag", rd_data[8], 1);
        check("RX data still delivered", rd_data[7:0], 8'h01);

        apb_read(A_ERR);
        check("ERR parity bit", rd_data[0], 1);

        // ============================================
        // T7: UART RX FRAMING ERROR
        // ============================================

        $display("\nT7: UART RX FRAMING ERROR");

        do_reset;

        apb_write(A_CTRL, 32'h02);

        repeat (10) @(posedge uclk);

        rx_send(8'hFF, 0, 0, 0);

        apb_read(A_RXDATA);
        check("RX framing error flag", rd_data[9], 1);

        apb_read(A_ERR);
        check("ERR framing bit", rd_data[1], 1);

        // ============================================
        // T8: TX FIFO FULL AND OVERFLOW
        // ============================================

        $display("\nT8: TX FIFO FULL / OVERFLOW");

        do_reset;

        // TX disabled, so FIFO will not drain.
        apb_write(A_CTRL, 32'h00);

        for (i = 0; i < 16; i = i + 1)
            apb_write(A_TXDATA, i);

        apb_read(A_STATUS);
        check("TX FIFO full", rd_data[0], 1);

        apb_read(A_ERR);
        check("No overflow before extra write", rd_data[3], 0);

        apb_write(A_TXDATA, 32'hEE);

        apb_read(A_ERR);
        check("TX overflow sticky", rd_data[3], 1);

        // ============================================
        // T9: RX FIFO UNDERFLOW
        // ============================================

        $display("\nT9: RX FIFO UNDERFLOW");

        do_reset;

        apb_read(A_RXDATA);
        check("Empty RX read returns zero", rd_data, 0);

        apb_read(A_ERR);
        check("RX underflow sticky", rd_data[4], 1);

        // ============================================
        // T10: RX INTERRUPT
        // ============================================

        $display("\nT10: RX INTERRUPT");

        do_reset;

        apb_write(A_CTRL, 32'h02);
        apb_write(A_INTEN, 32'h1);

        repeat (10) @(posedge uclk);

        check("IRQ low before RX data", irq, 0);

        rx_send(8'h55, 0, 0, 1);

        repeat (4) @(posedge pclk);

        check("IRQ high with RX data", irq, 1);

        apb_read(A_RXDATA);

        repeat (4) @(posedge pclk);

        check("IRQ low after RX drain", irq, 0);

        // ============================================
        // FINAL SUMMARY
        // ============================================

        $display("");
        $display("========================================");
        $display("          TESTBENCH SUMMARY");
        $display("========================================");

        $display("Total checks : %0d", checks);
        $display("Total errors : %0d", errors);

        if (errors == 0)
            $display("TB RESULT: PASS");
        else
            $display("TB RESULT: FAIL");

        $display("========================================");

        $finish;

    end

    // ------------------------------------------------
    // WAVEFORM DUMP
    // ------------------------------------------------

    initial begin
        $dumpfile("waveforms/stage1_basic.vcd");
        $dumpvars(0, tb_basic);
    end

endmodule
