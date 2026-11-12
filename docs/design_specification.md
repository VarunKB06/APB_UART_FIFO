# Design Specification

## 1. Purpose

The design implements an APB-accessible UART peripheral with separate transmit and receive paths buffered by asynchronous FIFOs. It exposes control, baud-divisor, status, interrupt and error registers.

## 2. Top-level interface

Top module: `apb_uart_top`.

| Signal | Direction | Width | Description |
|---|---|---:|---|
| `pclk` | Input | 1 | APB/register clock |
| `presetn` | Input | 1 | Active-low asynchronous reset input |
| `paddr` | Input | 8 | APB address |
| `psel` | Input | 1 | APB select |
| `penable` | Input | 1 | APB enable/access phase |
| `pwrite` | Input | 1 | APB direction |
| `pwdata` | Input | 32 | APB write data |
| `prdata` | Output | 32 | APB read data |
| `pready` | Output | 1 | Always asserted by this implementation |
| `pslverr` | Output | 1 | Invalid access indication |
| `uclk` | Input | 1 | UART/FIFO-side clock |
| `uart_rxd` | Input | 1 | UART serial receive input |
| `uart_txd` | Output | 1 | UART serial transmit output |
| `irq` | Output | 1 | Masked interrupt output |

## 3. Parameters

| Parameter | Default | Description |
|---|---:|---|
| `FIFO_AW` | 4 | FIFO address width; nominal depth is `2**FIFO_AW` entries |

The asynchronous FIFO implementation uses Gray-coded pointers. Confirm parameter constraints in the RTL before changing `FIFO_AW`.

## 4. Functional behavior

- APB accesses occur when `PSEL && PENABLE`.
- `PREADY` is tied high; there is no wait-state insertion.
- `TXDATA` writes the low byte of `PWDATA` to the TX FIFO.
- `RXDATA` reads the 10-bit RX FIFO entry.
- UART configuration is held in `CTRL` and `BAUD`.
- Internal loopback selects the TX serial output as the RX serial input.
- Interrupt output is the OR of enabled interrupt-status sources.
- Error status is sticky and write-one-to-clear.

## 5. UART configuration

The `CTRL` register fields are documented in [`register_map.md`](register_map.md). They control TX enable, RX enable, parity enable/polarity, TX stop-bit count and internal loopback.

The `BAUD` register is a 16-bit divisor supplied to both UART blocks. Consult the RTL counter implementation for exact baud timing.

## 6. Out-of-scope items

This specification does not define analog behavior, physical implementation constraints, a standard-cell target, a clock-frequency target, or a signoff methodology. Those depend on the selected technology library and implementation setup.
