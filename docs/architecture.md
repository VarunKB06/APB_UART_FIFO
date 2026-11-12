# Architecture

The APB interface and register bank operate in the PCLK domain. UART TX/RX and their FIFO-side interfaces operate in the UCLK domain. TX and RX use asynchronous FIFOs with Gray-coded pointers and synchronizers. Reset deassertion is synchronized independently in each clock domain.

The APB slave is zero-wait-state (`PREADY=1`). Invalid accesses assert `PSLVERR`.
