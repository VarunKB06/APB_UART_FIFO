# Register Map

| Address | Register | Access |
|---:|---|---|
| 0x00 | TXDATA | Write |
| 0x04 | RXDATA | Read |
| 0x08 | CTRL | Read/write |
| 0x0C | BAUD | Read/write |
| 0x10 | STATUS | Read |
| 0x14 | INTEN | Read/write |
| 0x18 | INTST | Read |
| 0x1C | ERR | Read/write, write-one-to-clear |

CTRL bits: TX enable [0], RX enable [1], parity enable [2], odd parity [3], two stop bits [4], loopback [5].
