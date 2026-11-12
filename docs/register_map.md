# Register Map

All addresses are byte addresses on the 8-bit `PADDR` input. Register read data is returned on the 32-bit `PRDATA` bus. The implementation decodes the eight addresses listed below.

## 1. Register summary

| Address | Register | Access | Reset value / behavior |
|---:|---|---|---|
| `0x00` | `TXDATA` | Write | Write `PWDATA[7:0]` into TX FIFO |
| `0x04` | `RXDATA` | Read | Returns `{framing_error, parity_error, data[7:0]}` in `PRDATA[9:0]`; empty read returns zero |
| `0x08` | `CTRL` | Read/write | `0x00000000` |
| `0x0C` | `BAUD` | Read/write | `0x00000010` (decimal 16) |
| `0x10` | `STATUS` | Read-only | Status bits described below |
| `0x14` | `INTEN` | Read/write | `0x00000000` |
| `0x18` | `INTST` | Read-only | Live interrupt-status sources |
| `0x1C` | `ERR` | Read/write, W1C | `0x00000000` |

`PREADY` is always high. Unmapped accesses and writes to read-only registers assert `PSLVERR`.

## 2. CTRL — `0x08`

Only `PWDATA[5:0]` are stored.

| Bit | Name | Meaning |
|---:|---|---|
| 0 | `tx_en` | Enables UART transmitter |
| 1 | `rx_en` | Enables UART receiver |
| 2 | `parity_en` | Enables parity processing |
| 3 | `parity_odd` | Selects odd parity when parity is enabled; otherwise even parity |
| 4 | `stop2` | Selects two TX stop bits when set; one when clear |
| 5 | `loopback` | Selects internal TX output as RX input when set |

Reset: all bits zero.

## 3. BAUD — `0x0C`

- Width: 16 bits (`PWDATA[15:0]`).
- Reset value: 16.
- The value is passed to the UART TX/RX timing logic as the divisor.
- The exact bit period depends on the implementation's counter convention; use the RTL and simulation timing when calculating baud rate rather than assuming a generic UART divisor formula.

## 4. STATUS — `0x10`

Read-only, `PRDATA[4:0]`:

| Bit | Name | Meaning |
|---:|---|---|
| 0 | `tx_full` | TX FIFO full |
| 1 | `tx_empty` | TX FIFO empty status synchronized into PCLK |
| 2 | `rx_full` | RX FIFO full status synchronized into PCLK |
| 3 | `rx_empty` | RX FIFO empty |
| 4 | `tx_busy` | UART transmitter busy status synchronized into PCLK |

Bits `[31:5]` read as zero.

## 5. INTEN — `0x14`

Only `PWDATA[2:0]` are stored. Reset value is zero.

| Bit | Interrupt source enabled |
|---:|---|
| 0 | RX FIFO not empty |
| 1 | TX FIFO empty |
| 2 | Any sticky error in `ERR` |

`irq = |(INTST & INTEN)`.

## 6. INTST — `0x18`

Read-only live interrupt-status sources in `PRDATA[2:0]`:

| Bit | Source |
|---:|---|
| 0 | RX FIFO not empty |
| 1 | TX FIFO empty |
| 2 | Any bit in `ERR` is set |

This register reports source status; `INTEN` masks which sources contribute to `irq`.

## 7. ERR — `0x1C`

Six sticky error bits. Write one to a bit to clear it; writing zero leaves that bit unchanged. A new error event takes priority over a simultaneous clear.

| Bit | Name | Set condition |
|---:|---|---|
| 0 | Parity error | A received entry with parity error is read from RX FIFO |
| 1 | Framing error | A received entry with framing error is read from RX FIFO |
| 2 | RX overflow | RX FIFO overflow event |
| 3 | TX overflow | TXDATA write while TX FIFO is full |
| 4 | RX underflow | RXDATA read while RX FIFO is empty |
| 5 | Invalid access | Unmapped APB access or write to read-only register |

Reset value: zero. Bits `[31:6]` read as zero.

## 8. Access notes

- `TXDATA` is write-only; a read is not listed as a supported register operation by the RTL decode.
- `RXDATA`, `STATUS` and `INTST` are read-only; writes to them return `PSLVERR`.
- `CTRL`, `BAUD`, `INTEN` and `ERR` are writable.
- `ERR` is the only write-one-to-clear register.
- FIFO depth defaults to 16 entries (`FIFO_AW=4`) and can be changed by overriding the top-level parameter, subject to the FIFO implementation's parameter constraints.
