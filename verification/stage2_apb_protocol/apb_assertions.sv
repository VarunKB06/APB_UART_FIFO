`timescale 1ns / 1ps

// ============================================================
// APB UART PROCEDURAL PROTOCOL CHECKER
// Five procedural protocol checks.
// Instantiated explicitly by tb_stage2_wrapper.sv for simulator portability.
// ============================================================

module apb_assertions (
    input wire        pclk,
    input wire        presetn,
    input wire [7:0]  paddr,
    input wire        psel,
    input wire        penable,
    input wire        pwrite,
    input wire [31:0] pwdata,
    input wire        pready,
    input wire        pslverr
);

    integer checks;
    integer errors;

    reg setup_seen;
    reg [7:0] saved_addr;
    reg saved_write;
    reg [31:0] saved_wdata;

    reg previous_psel;
    reg previous_penable;

    initial begin
        checks = 0;
        errors = 0;
        setup_seen = 0;
        saved_addr = 0;
        saved_write = 0;
        saved_wdata = 0;
        previous_psel = 0;
        previous_penable = 0;

        $display("========================================");
        $display("APB UART PROCEDURAL CHECKER STARTED");
        $display("5 PROTOCOL CHECKS ENABLED");
        $display("========================================");
    end

    always @(posedge pclk) begin
        if (!presetn) begin
            setup_seen <= 0;
            previous_psel <= 0;
            previous_penable <= 0;
        end
        else begin
            // CHECK 1: SETUP MUST BE FOLLOWED BY ACCESS
            if (setup_seen) begin
                checks = checks + 1;
                if (!(psel && penable)) begin
                    errors = errors + 1;
                    $error("CHECK 1 FAIL: Setup not followed by access");
                end
                setup_seen <= 0;
            end

            if (psel && !penable)
                setup_seen <= 1;

            // CHECK 2: PENABLE REQUIRES PSEL
            checks = checks + 1;
            if (penable && !psel) begin
                errors = errors + 1;
                $error("CHECK 2 FAIL: PENABLE asserted without PSEL");
            end

            // CHECK 3: ADDRESS AND CONTROL STABILITY
            if (previous_psel && !previous_penable) begin
                checks = checks + 1;
                if (!(psel && penable &&
                      paddr == saved_addr &&
                      pwrite == saved_write &&
                      pwdata == saved_wdata)) begin
                    errors = errors + 1;
                    $error("CHECK 3 FAIL: APB signals changed during setup-to-access");
                end
            end

            if (psel && !penable) begin
                saved_addr <= paddr;
                saved_write <= pwrite;
                saved_wdata <= pwdata;
            end

            // CHECK 4: PREADY MUST ALWAYS BE HIGH FOR THIS ZERO-WAIT DUT
            checks = checks + 1;
            if (!pready) begin
                errors = errors + 1;
                $error("CHECK 4 FAIL: PREADY is low");
            end

            // CHECK 5: PSLVERR ONLY DURING ACCESS
            checks = checks + 1;
            if (pslverr && !(psel && penable)) begin
                errors = errors + 1;
                $error("CHECK 5 FAIL: PSLVERR outside access phase");
            end

            previous_psel <= psel;
            previous_penable <= penable;
        end
    end

    final begin
        $display("");
        $display("========================================");
        $display(" APB PROTOCOL CHECKER SUMMARY");
        $display("========================================");
        $display("Total checks : %0d", checks);
        $display("Total errors : %0d", errors);
        if (errors == 0)
            $display("APB PROTOCOL RESULT: PASS");
        else
            $display("APB PROTOCOL RESULT: FAIL");
        $display("========================================");
    end
endmodule
