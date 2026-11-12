// APB UART peripheral with asynchronous TX/RX FIFOs.
//   pclk domain : APB slave, register bank, interrupt logic, TX FIFO write / RX FIFO read
//   uclk domain : UART TX/RX, TX FIFO read / RX FIFO write
// APB slave is zero-wait-state (PREADY = 1). Invalid accesses return PSLVERR.
// See docs/register_map.md.
module apb_uart_top #(
    parameter FIFO_AW = 4                     // FIFO depth = 2**FIFO_AW
) (
    input         pclk,
    input         presetn,
    input  [7:0]  paddr,
    input         psel,
    input         penable,
    input         pwrite,
    input  [31:0] pwdata,
    output reg [31:0] prdata,
    output        pready,
    output        pslverr,

    input         uclk,
    input         uart_rxd,
    output        uart_txd,
    output        irq
);
    localparam [7:0] A_TXDATA = 8'h00, A_RXDATA = 8'h04, A_CTRL = 8'h08, A_BAUD = 8'h0C,
                     A_STATUS = 8'h10, A_INTEN = 8'h14, A_INTST = 8'h18, A_ERR = 8'h1C;

    // ---------------- resets
    wire p_rst_n, u_rst_n;
    reset_synchronizer rs_p (.clk(pclk), .arst_n(presetn), .rst_n(p_rst_n));
    reset_synchronizer rs_u (.clk(uclk), .arst_n(presetn), .rst_n(u_rst_n));

    // ---------------- APB decode
    wire apb_access = psel & penable;
    wire wr = apb_access &  pwrite;
    wire rd = apb_access & ~pwrite;
    assign pready = 1'b1;

    reg addr_ok, addr_ro;
    always @* begin
        addr_ok = 1'b1; addr_ro = 1'b0;
        case (paddr)
            A_TXDATA, A_CTRL, A_BAUD, A_INTEN, A_ERR: ;
            A_RXDATA, A_STATUS, A_INTST:              addr_ro = 1'b1;
            default:                                  addr_ok = 1'b0;
        endcase
    end
    wire invalid_evt = apb_access & (~addr_ok | (pwrite & addr_ro));
    assign pslverr   = invalid_evt;

    // ---------------- registers (pclk)
    reg [5:0]  ctrl;       // [0]tx_en [1]rx_en [2]parity_en [3]parity_odd [4]stop2 [5]loopback
    reg [15:0] bauddiv;
    reg [2:0]  inten;      // [0]rx not empty [1]tx empty [2]error
    reg [5:0]  err_status; // [0]parity [1]framing [2]rx_overflow [3]tx_overflow [4]rx_underflow [5]invalid_access

    // ---------------- FIFOs
    wire        tx_full, tx_empty_u, tx_pop;
    wire [7:0]  tx_rdata;
    wire        tx_winc = wr & (paddr == A_TXDATA);
    async_fifo #(.DW(8), .AW(FIFO_AW)) u_txfifo (
        .wclk(pclk), .wrst_n(p_rst_n), .winc(tx_winc), .wdata(pwdata[7:0]), .wfull(tx_full),
        .rclk(uclk), .rrst_n(u_rst_n), .rinc(tx_pop),  .rdata(tx_rdata),    .rempty(tx_empty_u));

    wire        rx_full_u, rx_rempty, rx_valid;
    wire [9:0]  rx_rdata;
    wire [7:0]  rx_data;
    wire        rx_perr, rx_ferr;
    wire        rx_rinc = rd & (paddr == A_RXDATA);
    async_fifo #(.DW(10), .AW(FIFO_AW)) u_rxfifo (
        .wclk(uclk), .wrst_n(u_rst_n), .winc(rx_valid), .wdata({rx_ferr, rx_perr, rx_data}), .wfull(rx_full_u),
        .rclk(pclk), .rrst_n(p_rst_n), .rinc(rx_rinc),  .rdata(rx_rdata),                     .rempty(rx_rempty));

    // ---------------- config / status crossings
    wire [21:0] cfg_u;
    synchronizer #(.W(22)) u_cfg_sync (.clk(uclk), .rst_n(u_rst_n), .d({ctrl, bauddiv}), .q(cfg_u));
    wire [15:0] div_u    = cfg_u[15:0];
    wire        tx_en_u  = cfg_u[16];
    wire        rx_en_u  = cfg_u[17];
    wire        par_en_u = cfg_u[18];
    wire        par_od_u = cfg_u[19];
    wire        stop2_u  = cfg_u[20];
    wire        loop_u   = cfg_u[21];

    // ---------------- UART core (uclk)
    wire txd_w, tx_busy_u;
    uart_tx u_tx (.clk(uclk), .rst_n(u_rst_n), .en(tx_en_u), .div(div_u),
                  .parity_en(par_en_u), .parity_odd(par_od_u), .stop2(stop2_u),
                  .fifo_empty(tx_empty_u), .fifo_data(tx_rdata), .fifo_pop(tx_pop),
                  .txd(txd_w), .busy(tx_busy_u));
    assign uart_txd = txd_w;

    wire rxd_sel = loop_u ? txd_w : uart_rxd;
    uart_rx u_rx (.clk(uclk), .rst_n(u_rst_n), .en(rx_en_u), .div(div_u),
                  .parity_en(par_en_u), .parity_odd(par_od_u), .rxd(rxd_sel),
                  .valid(rx_valid), .data(rx_data), .perr(rx_perr), .ferr(rx_ferr));

    // RX overflow event (uclk) -> toggle -> pclk pulse
    reg  of_tgl;
    always @(posedge uclk or negedge u_rst_n)
        if (!u_rst_n) of_tgl <= 1'b0; else if (rx_valid & rx_full_u) of_tgl <= ~of_tgl;
    wire of_tgl_p;
    reg  of_tgl_d;
    synchronizer #(.W(1)) u_of_sync (.clk(pclk), .rst_n(p_rst_n), .d(of_tgl), .q(of_tgl_p));
    always @(posedge pclk or negedge p_rst_n)
        if (!p_rst_n) of_tgl_d <= 1'b0; else of_tgl_d <= of_tgl_p;
    wire rx_of_evt = of_tgl_p ^ of_tgl_d;

    // uclk-domain status levels -> pclk (these lag by ~2 pclk cycles)
    wire [2:0] st_p;
    synchronizer #(.W(3)) u_st_sync (.clk(pclk), .rst_n(p_rst_n), .d({tx_busy_u, rx_full_u, tx_empty_u}), .q(st_p));
    wire tx_empty_p = st_p[0];
    wire rx_full_p  = st_p[1];
    wire tx_busy_p  = st_p[2];

    // ---------------- error status
    wire rx_pop_ok = rx_rinc & ~rx_rempty;
    wire [5:0] err_set = {invalid_evt,
                          rx_rinc & rx_rempty,        // rx underflow
                          tx_winc & tx_full,          // tx overflow
                          rx_of_evt,                  // rx overflow
                          rx_pop_ok & rx_rdata[9],    // framing
                          rx_pop_ok & rx_rdata[8]};   // parity
    wire [5:0] err_clr = (wr & (paddr == A_ERR)) ? pwdata[5:0] : 6'b0;

    // ---------------- register writes
    always @(posedge pclk or negedge p_rst_n) begin
        if (!p_rst_n) begin
            ctrl <= 6'b0; bauddiv <= 16'd16; inten <= 3'b0; err_status <= 6'b0;
        end else begin
            err_status <= (err_status & ~err_clr) | err_set;   // set wins over clear
            if (wr) case (paddr)
                A_CTRL:  ctrl    <= pwdata[5:0];
                A_BAUD:  bauddiv <= pwdata[15:0];
                A_INTEN: inten   <= pwdata[2:0];
                default: ;
            endcase
        end
    end

    // ---------------- status / interrupts
    wire [4:0] status    = {tx_busy_p, rx_rempty, rx_full_p, tx_empty_p, tx_full};
    // STATUS bit order: [0]tx_full [1]tx_empty [2]rx_full [3]rx_empty [4]tx_busy
    wire [2:0] int_status = {|err_status, tx_empty_p, ~rx_rempty};
    assign irq = |(int_status & inten);

    always @* begin
        prdata = 32'b0;
        if (addr_ok) case (paddr)
            A_RXDATA: prdata = rx_rempty ? 32'b0 : {22'b0, rx_rdata};
            A_CTRL:   prdata = {26'b0, ctrl};
            A_BAUD:   prdata = {16'b0, bauddiv};
            A_STATUS: prdata = {27'b0, status};
            A_INTEN:  prdata = {29'b0, inten};
            A_INTST:  prdata = {29'b0, int_status};
            A_ERR:    prdata = {26'b0, err_status};
            default:  prdata = 32'b0;
        endcase
    end
endmodule
// Dual-clock FIFO, Gray-coded pointers, first-word-fall-through read data.
// Depth = 2**AW. wfull is registered in the write domain, rempty in the read domain.
// Writes while full and reads while empty are ignored (data is not corrupted).
module async_fifo #(parameter DW = 8, parameter AW = 4) (
    input               wclk,
    input               wrst_n,
    input               winc,
    input  [DW-1:0]     wdata,
    output reg          wfull,

    input               rclk,
    input               rrst_n,
    input               rinc,
    output [DW-1:0]     rdata,
    output reg          rempty
);
    reg [DW-1:0] mem [0:(1<<AW)-1];

    reg  [AW:0] wbin, wgray, rbin, rgray;
    wire [AW:0] rgray_w, wgray_r;       // synchronized opposite-domain pointers

    synchronizer #(.W(AW+1)) sync_r2w (.clk(wclk), .rst_n(wrst_n), .d(rgray), .q(rgray_w));
    synchronizer #(.W(AW+1)) sync_w2r (.clk(rclk), .rst_n(rrst_n), .d(wgray), .q(wgray_r));

    // ---- write side
    wire          wen       = winc & ~wfull;
    wire [AW:0]   wbin_n    = wbin + {{AW{1'b0}}, wen};
    wire [AW:0]   wgray_n   = (wbin_n >> 1) ^ wbin_n;
    wire          wfull_n   = (wgray_n == {~rgray_w[AW:AW-1], rgray_w[AW-2:0]});

    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n) begin wbin <= 0; wgray <= 0; wfull <= 1'b0; end
        else         begin wbin <= wbin_n; wgray <= wgray_n; wfull <= wfull_n; end

    always @(posedge wclk)
        if (wen) mem[wbin[AW-1:0]] <= wdata;

    // ---- read side
    wire          ren       = rinc & ~rempty;
    wire [AW:0]   rbin_n    = rbin + {{AW{1'b0}}, ren};
    wire [AW:0]   rgray_n   = (rbin_n >> 1) ^ rbin_n;
    wire          rempty_n  = (rgray_n == wgray_r);

    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) begin rbin <= 0; rgray <= 0; rempty <= 1'b1; end
        else         begin rbin <= rbin_n; rgray <= rgray_n; rempty <= rempty_n; end

    assign rdata = mem[rbin[AW-1:0]];
endmodule
// Asynchronous assertion, synchronous de-assertion.
module reset_synchronizer (
    input  clk,
    input  arst_n,
    output rst_n
);
    reg s1, s2;
    always @(posedge clk or negedge arst_n)
        if (!arst_n) begin s1 <= 1'b0; s2 <= 1'b0; end
        else         begin s1 <= 1'b1; s2 <= s1;   end
    assign rst_n = s2;
endmodule
// Two-flop synchronizer for quasi-static levels or Gray-coded pointers.
module synchronizer #(parameter W = 1) (
    input              clk,
    input              rst_n,
    input  [W-1:0]     d,
    output [W-1:0]     q
);
    reg [W-1:0] s1, s2;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) begin s1 <= {W{1'b0}}; s2 <= {W{1'b0}}; end
        else        begin s1 <= d;         s2 <= s1;        end
    assign q = s2;
endmodule
// UART receiver: 2-FF input synchronizer, mid-bit sampling, parity and framing check.
// Emits a one-cycle 'valid' with data/perr/ferr. Only the first stop bit is checked.
module uart_rx (
    input         clk,
    input         rst_n,
    input         en,
    input  [15:0] div,
    input         parity_en,
    input         parity_odd,
    input         rxd,
    output reg    valid,
    output reg [7:0] data,
    output reg    perr,
    output reg    ferr
);
    localparam IDLE = 3'd0, START = 3'd1, DATA = 3'd2, PAR = 3'd3, STOP = 3'd4;

    wire rx_s;
    synchronizer #(.W(1)) u_sync (.clk(clk), .rst_n(rst_n), .d(rxd), .q(rx_s));
    // synchronizer resets to 0; the idle line is 1, so hold off until it has filled
    reg  rx_ready;
    always @(posedge clk or negedge rst_n)
        if (!rst_n) rx_ready <= 1'b0; else if (rx_s) rx_ready <= 1'b1;

    reg [2:0]  state;
    reg [15:0] cnt;
    reg [7:0]  sh;
    reg [2:0]  idx;
    reg        par;

    wire [15:0] d    = (div < 16'd4) ? 16'd4 : div;
    wire [15:0] half = d >> 1;
    wire        full_end = (cnt == d - 16'd1);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 0; sh <= 0; idx <= 0; par <= 0;
            valid <= 0; data <= 0; perr <= 0; ferr <= 0;
        end else begin
            valid <= 1'b0;
            case (state)
            IDLE: begin
                cnt <= 0;
                if (en && rx_ready && !rx_s) state <= START;
            end
            START: if (cnt == half - 16'd1) begin
                       cnt <= 0;
                       if (!rx_s) begin state <= DATA; idx <= 0; par <= 1'b0; perr <= 1'b0; end
                       else state <= IDLE;            // glitch, not a start bit
                   end else cnt <= cnt + 1'b1;
            DATA: if (full_end) begin
                      cnt <= 0; sh <= {rx_s, sh[7:1]}; par <= par ^ rx_s;
                      if (idx == 3'd7) state <= parity_en ? PAR : STOP;
                      else idx <= idx + 1'b1;
                  end else cnt <= cnt + 1'b1;
            PAR:  if (full_end) begin
                      cnt <= 0;
                      perr <= (rx_s != (parity_odd ? ~par : par));
                      state <= STOP;
                  end else cnt <= cnt + 1'b1;
            STOP: if (full_end) begin
                      cnt <= 0;
                      data <= sh; ferr <= ~rx_s; valid <= 1'b1;
                      state <= IDLE;
                  end else cnt <= cnt + 1'b1;
            default: state <= IDLE;
            endcase
        end
    end
endmodule
// UART transmitter: 8 data bits LSB first, optional parity, 1 or 2 stop bits.
// div = clock cycles per bit (values < 4 are clamped to 4).
module uart_tx (
    input         clk,
    input         rst_n,
    input         en,
    input  [15:0] div,
    input         parity_en,
    input         parity_odd,
    input         stop2,
    input         fifo_empty,
    input  [7:0]  fifo_data,
    output        fifo_pop,
    output        txd,
    output        busy
);
    localparam IDLE = 3'd0, START = 3'd1, DATA = 3'd2, PAR = 3'd3, STOP = 3'd4;

    reg [2:0]  state;
    reg [15:0] cnt;
    reg [7:0]  sh;
    reg [2:0]  idx;
    reg        par, stop_cnt, txd_r;

    wire [15:0] d       = (div < 16'd4) ? 16'd4 : div;
    wire        bit_end = (cnt == d - 16'd1);
    wire        par_bit = par ^ sh[0];                 // parity including current bit

    assign fifo_pop = (state == IDLE) && en && !fifo_empty;
    assign txd      = txd_r;
    assign busy     = (state != IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE; cnt <= 0; sh <= 0; idx <= 0; par <= 0; stop_cnt <= 0; txd_r <= 1'b1;
        end else begin
            case (state)
            IDLE: begin
                txd_r <= 1'b1; cnt <= 0;
                if (fifo_pop) begin
                    sh <= fifo_data; par <= 1'b0; idx <= 0; stop_cnt <= 1'b0;
                    txd_r <= 1'b0; state <= START;
                end
            end
            START: if (bit_end) begin cnt <= 0; txd_r <= sh[0]; state <= DATA; end
                   else cnt <= cnt + 1'b1;
            DATA: if (bit_end) begin
                    cnt <= 0; par <= par_bit; sh <= {1'b0, sh[7:1]};
                    if (idx == 3'd7) begin
                        if (parity_en) begin txd_r <= parity_odd ? ~par_bit : par_bit; state <= PAR; end
                        else           begin txd_r <= 1'b1; state <= STOP; end
                    end else begin
                        txd_r <= sh[1]; idx <= idx + 1'b1;
                    end
                  end else cnt <= cnt + 1'b1;
            PAR:  if (bit_end) begin cnt <= 0; txd_r <= 1'b1; state <= STOP; end
                  else cnt <= cnt + 1'b1;
            STOP: if (bit_end) begin
                    cnt <= 0;
                    if (stop2 && !stop_cnt) stop_cnt <= 1'b1;
                    else state <= IDLE;
                  end else cnt <= cnt + 1'b1;
            default: state <= IDLE;
            endcase
        end
    end
endmodule
