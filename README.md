# GU7003 Arduino Library

A small, straightforward Arduino library for driving Noritake Itron GU-7003 VFD displays over the serial interface.

This project grew from porting the Noritake GU-7000 LargeTextDemo to an Arduino Duemilanove and simplifying the working command set into a reusable Arduino library.

## Tested hardware

- Noritake Itron 7003 03G14L F100
- Arduino Duemilanove / ATmega328P
- 38400 baud, 8N1

## Wiring

```text
Arduino Duemilanove     GU-7003
-------------------     -------
D1 / TX              -> Pin 2  SIN
D10                  -> Pin 6  RESET
D12                  -> Pin 4  SBUSY
5V                   -> Pin 1  VCC
GND                  -> Pin 3  GND
```

See [`docs/wiring.md`](docs/wiring.md) for details.

## Quick start

```cpp
#include <GU7003.h>

GU7003 vfd(10, 12);

void setup()
{
  vfd.begin();
  vfd.setBrightness(8);
  vfd.setFontSize(1, 1);
  vfd.setCursor(0, 0);
  vfd.print("Hello World");
}

void loop()
{
}
```

## Functions

- `begin()`
- `clear()`
- `home()`
- `cursorOn()`
- `cursorOff()`
- `setBrightness(1..8)`
- `setFontSize(width, height)`
- `setCursor(x, y)`
- `powerSave(true/false)`
- `print(const char *)`
- `print(int)`
- `print(unsigned int)`
- `print(long)`
- `print(unsigned long)`
- `print(float, decimals)`
- `println(const char *)`

## Examples

### Basic

A minimal "Hello World" example.

### CompleteDemo

Cycles through the available library functions continuously. It demonstrates:

- clear
- home
- cursor on/off
- brightness 1–8
- font sizes 1x1, 2x2, and 3x2
- cursor positioning
- string output
- integer output
- unsigned integer output
- floating-point output
- println
- display power save / wake
- combined operation

The demo repeats from `loop()` so it can be left running while testing the display.

## Status

This library is intentionally small. The command set is based on the working commands tested on the hardware listed above. Additional GU-7000 features can be added as they are verified.

## License

MIT License. See [LICENSE](LICENSE).

## Contributions

Pull requests and issue reports are welcome, especially from users with other GU-7000-series displays who can verify compatibility.
