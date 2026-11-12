`timescale 1ns / 1ps

// Stage 2 wrapper: instantiates the DUT and procedural APB checker.
// Explicit instantiation is used instead of "bind" for Icarus portability.
module tb_stage2_wrapper;

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
    wire uart_txd;
    wire irq;
    reg uart_rxd = 1;

    integer checks = 0;
    integer errors = 0;

    always #5 pclk = ~pclk;
    always #4 uclk = ~uclk;

    apb_uart_top #(.FIFO_AW(4)) dut (
        .pclk(pclk), .presetn(presetn),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr),
        .uclk(uclk), .uart_rxd(uart_rxd),
        .uart_txd(uart_txd), .irq(irq)
    );

    apb_assertions u_apb_protocol_checker (
        .pclk(pclk), .presetn(presetn),
        .paddr(paddr), .psel(psel), .penable(penable),
        .pwrite(pwrite), .pwdata(pwdata),
        .pready(pready), .pslverr(pslverr)
    );

    task apb_write;
        input [7:0] address;
        input [31:0] data;
        begin
            @(negedge pclk);
            psel = 1;
            penable = 0;
            pwrite = 1;
            paddr = address;
            pwdata = data;

            @(negedge pclk);
            penable = 1;

            @(posedge pclk);
            #1;
            checks = checks + 1;
            if (pslverr !== 1'b0) begin
                errors = errors + 1;
                $display("[FAIL] Valid APB write unexpectedly asserted PSLVERR");
            end else
                $display("[PASS] Valid APB write");

            @(negedge pclk);
            psel = 0;
            penable = 0;
            pwrite = 0;
            pwdata = 0;
        end
    endtask

    task apb_read;
        input [7:0] address;
        input expected_error;
        begin
            @(negedge pclk);
            psel = 1;
            penable = 0;
            pwrite = 0;
            paddr = address;

            @(negedge pclk);
            penable = 1;
            #1;
            checks = checks + 1;
            if (pslverr !== expected_error) begin
                errors = errors + 1;
                $display("[FAIL] APB read PSLVERR mismatch at address 0x%0h", address);
            end else
                $display("[PASS] APB read PSLVERR check at address 0x%0h", address);

            @(negedge pclk);
            psel = 0;
            penable = 0;
        end
    endtask

    initial begin
        $dumpfile("waveforms/stage2_apb.vcd");
        $dumpvars(0, tb_stage2_wrapper);
    end

    initial begin
        $display("========================================");
        $display(" STAGE 2: APB PROTOCOL VERIFICATION");
        $display("========================================");

        repeat (4) @(negedge pclk);
        presetn = 1;
        repeat (6) @(posedge pclk);

        // Legal writes/reads exercise normal APB setup/access phases.
        apb_write(8'h0C, 32'd16); // BAUD
        apb_write(8'h08, 32'd3);  // CTRL
        apb_read(8'h0C, 1'b0);    // BAUD read
        apb_read(8'h10, 1'b0);    // STATUS read

        // Unmapped read exercises PSLVERR during the access phase.
        apb_read(8'h40, 1'b1);

        repeat (4) @(posedge pclk);

        $display("Stage 2 stimulus checks : %0d", checks);
        $display("Stage 2 stimulus errors : %0d", errors);
        if (errors == 0)
            $display("STAGE 2 TEST RESULT: PASS");
        else
            $display("STAGE 2 TEST RESULT: FAIL");

        #20;
        $finish;
    end

    initial begin
        #100000;
        $display("[FAIL] STAGE 2 TIMEOUT");
        $finish;
    end

endmodule
