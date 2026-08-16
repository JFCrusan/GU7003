# GU7003 Arduino Library

A small Arduino library for driving Noritake Itron GU-7003-series VFD displays over the serial interface.

The library began as a compact wrapper around the commands needed by the Noritake GU-7000 LargeTextDemo and has since been extended with hardware-validated graphics support for the GU112X16G-7003.

## Version 1.1.0

Version 1.1.0 adds graphics and display-control features while keeping the original text API compatible.

New in 1.1.0:

- row-major bitmap drawing with normal pixel coordinates
- separate native bitmap functions for RAM and PROGMEM data
- arbitrary vertical placement from Y=0 through Y=15 on the tested 112x16 display
- reverse video
- GU-7000 screen mode control
- character-spacing control
- `DISPLAY_WIDTH` / `DISPLAY_HEIGHT` constants for the tested 112x16 module
- GraphicsShowcase example

The friendly bitmap function hides the GU7003 native two-band bitmap layout from application code.

## Tested hardware

Primary graphics-validation hardware:

- Noritake Itron GU112X16G-7003
- 112 x 16 dot graphic VFD
- Arduino Duemilanove / ATmega328P
- serial interface at 38400 baud

Original text/control development hardware:

- Noritake Itron 7003 03G14L F100
- Arduino Duemilanove / ATmega328P
- 38400 baud, 8N1

## Wiring

```text
Arduino Duemilanove     GU-7003
-------------------     -------
D1 / TX              -> SIN
D10                  -> RESET
D12                  -> SBUSY
5V                   -> VCC
GND                  -> GND
```

See `docs/wiring.md` in the repository for the original wiring notes.

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

## Friendly bitmap drawing

`drawBitmap_P()` accepts normal row-major bitmap data stored in PROGMEM.

```cpp
const uint8_t arrow[] PROGMEM = {
  0x10,
  0x18,
  0xFE,
  0xFE,
  0x18,
  0x10,
  0x00
};

vfd.drawBitmap_P(30, 3, 7, 7, arrow);
```

The arguments are:

```cpp
drawBitmap_P(x, y, width, height, data);
```

- `x` and `y` are normal display pixel coordinates.
- `width` and `height` are pixel dimensions.
- each source row occupies `ceil(width / 8)` bytes.
- within each source byte, bit 7 is the left-most pixel.

On the tested GU112X16G-7003, the library translates this row-major data into the display's native 8-dot vertical-band representation.

## Native bitmap functions

For applications that already have GU-7000-native bitmap data:

```cpp
vfd.drawBitmapNative_P(x, width, heightBytes, dataInProgmem);
vfd.drawBitmapNativeRAM(x, width, heightBytes, dataInRam);
```

`heightBytes` is the GU-7000 native vertical size in 8-dot units:

- `1` = 8 pixels high
- `2` = 16 pixels high

The explicit RAM and PROGMEM functions avoid silently reading data from the wrong memory space on AVR.

## Display controls

Version 1.1.0 adds:

```cpp
vfd.setCharacterSpacing(mode);
vfd.reverse(true);
vfd.reverse(false);
vfd.screenMode(mode);
```

The original functions remain available:

- `begin()`
- `clear()`
- `home()`
- `cursorOn()`
- `cursorOff()`
- `setBrightness(1..8)`
- `setFontSize(width, height)`
- `setCursor(x, y)`
- `powerSave(true/false)`
- `print(...)`
- `println(...)`

## Character spacing

The tested display supports both standard and narrow fixed spacing:

```cpp
vfd.setCharacterSpacing(1);  // standard fixed spacing
vfd.setCharacterSpacing(0);  // narrow fixed spacing
```

On the GU112X16G-7003 hardware used for validation, these produced 16 and 18 characters per row respectively at 1x1 font size.

## Graphics notes

The GU112X16G-7003 was validated as a 112x16 display.

Hardware testing established that reliable real-time graphics are best treated as a 16-pixel-high native canvas anchored at display Y=0. `drawBitmap_P()` handles this internally, so application code may use normal Y coordinates without dealing with the native upper/lower 8-dot bands.

## Examples

### Basic

Minimal text output.

### CompleteDemo

Demonstrates the original text/control API.

### GraphicsShowcase

Demonstrates:

- row-major bitmap drawing
- arbitrary vertical placement
- multiple icons
- mixed bitmap and text output
- an edit-pointer style UI element

## Compatibility

The library currently targets AVR Arduino boards and uses the hardware `Serial` interface.

Graphics behavior has been hardware-validated on the GU112X16G-7003. Other GU-7000 / GU-7003 displays may use compatible commands, but their geometry and behavior should be verified before relying on the 112x16-specific constants.

## License

MIT License. See `LICENSE`.

## Contributions

Pull requests and issue reports are welcome, especially from users with other GU-7000-series displays who can verify compatibility.

## Windows HIL automation

The bounded Codex HIL controller keeps feature editing inside a dedicated worktree while compilation, Arduino upload, C920 capture, and evidence collection run in the parent Windows process. It automatically feeds logs and camera images into the next Codex iteration and stops at verified `PASS` or a documented human-review boundary.

See [`docs/hil-automation.md`](docs/hil-automation.md) for the controller workflow, bench defaults, focused HIL script contract, safeguards, and the command that resumes the existing `feature/user-windows` worktree.
