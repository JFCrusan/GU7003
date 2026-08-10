# Wiring

Tested with an Arduino Duemilanove / ATmega328P and a Noritake Itron 7003 03G14L F100.

| Arduino | VFD | Function |
|---|---:|---|
| D1 / TX | Pin 2 | SIN / serial data |
| D10 | Pin 6 | RESET |
| D12 | Pin 4 | SBUSY |
| 5V | Pin 1 | VCC |
| GND | Pin 3 | GND |

Serial: **38400 baud, 8N1**.

The library uses the Duemilanove hardware `Serial` port for the VFD data line, so D1/TX is dedicated to the display while the library is active.
