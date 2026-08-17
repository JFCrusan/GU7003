#include "GU7003.h"
#include <avr/pgmspace.h>

GU7003::GU7003(uint8_t resetPin, uint8_t busyPin)
{
  _resetPin = resetPin;
  _busyPin = busyPin;
  _currentWindow = 0;
}

void GU7003::begin()
{
  pinMode(_resetPin, OUTPUT);
  pinMode(_busyPin, INPUT);
  digitalWrite(_resetPin, LOW);

  Serial.begin(38400);

  delay(1000);
  digitalWrite(_resetPin, HIGH);
  delay(500);

  _currentWindow = 0;
  clear();
  cursorOff();
  setBrightness(8);
  setFontSize(1, 1);
  setCharacterSpacing(1);
  setWriteMixtureMode(WriteMixtureMode::Normal);
}

void GU7003::write(uint8_t data)
{
  while (digitalRead(_busyPin) == HIGH) {}
  Serial.write(data);
}

void GU7003::clear()
{
  write(0x0C);
  delay(100);
}

void GU7003::home()
{
  write(0x0B);
  delay(20);
}

void GU7003::cursorOn()
{
  write(0x1F); write(0x43); write(0x01);
  delay(20);
}

void GU7003::cursorOff()
{
  write(0x1F); write(0x43); write(0x00);
  delay(20);
}

void GU7003::setBrightness(uint8_t level)
{
  if (level < 1) level = 1;
  if (level > 8) level = 8;
  write(0x1F); write(0x58); write(level);
  delay(50);
}

void GU7003::setFontSize(uint8_t width, uint8_t height)
{
  write(0x1F); write(0x28); write(0x67); write(0x40);
  write(width); write(height);
  delay(50);
}

void GU7003::setCharacterSpacing(uint8_t mode)
{
  if (mode > 3) mode = 3;
  write(0x1F); write(0x28); write(0x67); write(0x03); write(mode);
  delay(20);
}

void GU7003::setCursor(uint16_t x, uint16_t y)
{
  write(0x1F); write(0x24);
  write(x & 0xFF); write((x >> 8) & 0xFF);
  write(y & 0xFF); write((y >> 8) & 0xFF);
  delay(20);
}

void GU7003::defineUserWindow(uint8_t window, uint16_t x, uint16_t y,
                              uint16_t width, uint16_t heightBytes)
{
  if (window < 1 || window > 4 || width == 0 || heightBytes == 0) return;

  write(0x1F); write(0x28); write(0x77); write(0x02);
  write(window); write(0x01);
  write(x & 0xFF); write((x >> 8) & 0xFF);
  write(y & 0xFF); write((y >> 8) & 0xFF);
  write(width & 0xFF); write((width >> 8) & 0xFF);
  write(heightBytes & 0xFF); write((heightBytes >> 8) & 0xFF);
  delay(20);
}

void GU7003::selectWindow(uint8_t window)
{
  if (window > 4) return;

  write(0x1F); write(0x28); write(0x77); write(0x01); write(window);
  _currentWindow = window;
  delay(20);
}

void GU7003::cancelUserWindow(uint8_t window)
{
  if (window < 1 || window > 4) return;

  write(0x1F); write(0x28); write(0x77); write(0x02);
  write(window); write(0x00);
  delay(20);

  // The controller specification says canceling the current user window
  // selects the base window. Send that selection explicitly as well so the
  // library guarantees the same state on affected GU-7003 modules.
  if (_currentWindow == window) selectWindow(0);
}

void GU7003::screenMode(uint8_t mode)
{
  write(0x1F); write(0x28); write(0x61); write(0x40); write(mode);
  delay(20);
}

void GU7003::setWriteScreenMode(WriteScreenMode mode)
{
  uint8_t value = static_cast<uint8_t>(mode);
  if (value > static_cast<uint8_t>(WriteScreenMode::All))
    value = static_cast<uint8_t>(WriteScreenMode::Display);

  write(0x1F); write(0x28); write(0x77); write(0x10); write(value);
  delay(20);
}

void GU7003::powerSave(bool enable)
{
  screenMode(enable ? 0x00 : 0x01);
}

void GU7003::reverse(bool enable)
{
  write(0x1F); write(0x72); write(enable ? 0x01 : 0x00);
  delay(10);
}

void GU7003::setWriteMixtureMode(WriteMixtureMode mode)
{
  uint8_t value = static_cast<uint8_t>(mode);
  if (value > static_cast<uint8_t>(WriteMixtureMode::XOR))
    value = static_cast<uint8_t>(WriteMixtureMode::Normal);

  write(0x1F); write(0x77); write(value);
  delay(10);
}

void GU7003::setWriteMode(WriteMode mode)
{
  uint8_t value = static_cast<uint8_t>(mode);
  if (value < static_cast<uint8_t>(WriteMode::Overwrite) ||
      value > static_cast<uint8_t>(WriteMode::HorizontalScroll))
    value = static_cast<uint8_t>(WriteMode::Overwrite);

  write(0x1F); write(value);
  delay(10);
}

void GU7003::setHorizontalScrollSpeed(uint8_t speed)
{
  if (speed > 31) speed = 31;
  write(0x1F); write(0x73); write(speed);
  delay(10);
}

void GU7003::scrollDisplay(uint16_t shiftBytes, uint16_t cycles,
                           uint8_t speedTicks)
{
  if (shiftBytes >= DISPLAY_MEMORY_BYTES)
    shiftBytes = DISPLAY_MEMORY_BYTES - 1;
  if (cycles == 0) cycles = 1;

  write(0x1F); write(0x28); write(0x61); write(0x10);
  write(shiftBytes & 0xFF); write((shiftBytes >> 8) & 0xFF);
  write(cycles & 0xFF); write((cycles >> 8) & 0xFF);
  write(speedTicks);

  // Put the complete action command on the wire before returning so SBUSY
  // can protect any following write while the controller is scrolling.
  Serial.flush();
  delay(1);
}

void GU7003::sendBlinkCommand(uint8_t pattern, uint8_t normalTicks,
                              uint8_t alternateTicks, uint8_t cycles)
{
  if (normalTicks == 0) normalTicks = 1;
  if (alternateTicks == 0) alternateTicks = 1;

  write(0x1F); write(0x28); write(0x61); write(0x11);
  write(pattern); write(normalTicks); write(alternateTicks); write(cycles);

  // Ensure the complete command is on the wire before returning. This lets
  // SBUSY assert before a following write checks it, which is essential for
  // finite blink actions that temporarily stop command processing.
  Serial.flush();
  delay(1);
}

void GU7003::blink(BlinkMode mode, uint8_t normalTicks,
                   uint8_t alternateTicks, uint8_t cycles)
{
  if (cycles == 0) cycles = 1;

  sendBlinkCommand(static_cast<uint8_t>(mode), normalTicks,
                   alternateTicks, cycles);
}

void GU7003::blinkContinuous(BlinkMode mode, uint8_t normalTicks,
                             uint8_t alternateTicks)
{
  sendBlinkCommand(static_cast<uint8_t>(mode), normalTicks,
                   alternateTicks, 0);
}

void GU7003::stopBlink()
{
  // Pattern 0 selects normal display. A finite cycle value explicitly
  // terminates an active c=0 continuous action without clearing display RAM.
  sendBlinkCommand(0x00, 1, 1, 1);
  delay(20);
}

void GU7003::beginNativeBitmap(uint16_t x, uint8_t width, uint8_t heightBytes)
{
  // Hardware testing on GU112X16G-7003 established that reliable graphics
  // are anchored at display Y=0. Vertical placement is encoded in bitmap data.
  setCursor(x, 0);

  write(0x1F); write(0x28); write(0x66); write(0x11);
  write(width); write(0x00);
  write(heightBytes); write(0x00);
  write(0x01);
}

void GU7003::drawBitmapNativeRAM(uint16_t x, uint8_t width,
                                 uint8_t heightBytes, const uint8_t *data)
{
  if (!data || width == 0 || heightBytes == 0 || heightBytes > 2) return;
  if (x >= DISPLAY_MEMORY_WIDTH) return;
  if ((uint16_t)x + width > DISPLAY_MEMORY_WIDTH)
    width = DISPLAY_MEMORY_WIDTH - x;

  beginNativeBitmap(x, width, heightBytes);

  uint16_t count = (uint16_t)width * heightBytes;
  for (uint16_t i = 0; i < count; i++) write(data[i]);
}

void GU7003::drawBitmapNative_P(uint16_t x, uint8_t width,
                                uint8_t heightBytes, const uint8_t *data)
{
  if (!data || width == 0 || heightBytes == 0 || heightBytes > 2) return;
  if (x >= DISPLAY_MEMORY_WIDTH) return;
  if ((uint16_t)x + width > DISPLAY_MEMORY_WIDTH)
    width = DISPLAY_MEMORY_WIDTH - x;

  beginNativeBitmap(x, width, heightBytes);

  uint16_t count = (uint16_t)width * heightBytes;
  for (uint16_t i = 0; i < count; i++) write(pgm_read_byte(data + i));
}

void GU7003::drawBitmap_P(uint16_t x, uint8_t y,
                          uint8_t width, uint8_t height,
                          const uint8_t *rowMajorData)
{
  if (!rowMajorData || width == 0 || height == 0) return;
  if (x >= DISPLAY_WIDTH || y >= DISPLAY_HEIGHT) return;

  uint8_t clippedWidth = width;
  uint8_t clippedHeight = height;

  if ((uint16_t)x + clippedWidth > DISPLAY_WIDTH)
    clippedWidth = DISPLAY_WIDTH - x;

  if ((uint16_t)y + clippedHeight > DISPLAY_HEIGHT)
    clippedHeight = DISPLAY_HEIGHT - y;

  uint8_t sourceRowBytes = (width + 7) / 8;

  // Any arbitrary y placement can span both 8-dot native bands,
  // so always send a 16-dot-high native image. This hides the GU7003's
  // unusual vertical placement behavior from application code.
  beginNativeBitmap(x, clippedWidth, 2);

  for (uint8_t column = 0; column < clippedWidth; column++)
  {
    uint8_t upper = 0;
    uint8_t lower = 0;

    for (uint8_t row = 0; row < clippedHeight; row++)
    {
      uint8_t sourceByte =
        pgm_read_byte(rowMajorData + ((uint16_t)row * sourceRowBytes) + (column / 8));

      bool pixelOn = sourceByte & (0x80 >> (column & 7));
      if (!pixelOn) continue;

      uint8_t displayY = y + row;

      if (displayY < 8)
        upper |= (0x80 >> displayY);
      else
        lower |= (0x80 >> (displayY - 8));
    }

    write(upper);
    write(lower);
  }
}

void GU7003::print(const char *text)
{
  while (*text) write(*text++);
}

void GU7003::print(int number)
{
  char b[16]; ltoa((long)number, b, 10); print(b);
}

void GU7003::print(unsigned int number)
{
  char b[16]; ultoa((unsigned long)number, b, 10); print(b);
}

void GU7003::print(long number)
{
  char b[16]; ltoa(number, b, 10); print(b);
}

void GU7003::print(unsigned long number)
{
  char b[16]; ultoa(number, b, 10); print(b);
}

void GU7003::print(float number, uint8_t decimals)
{
  char b[24]; dtostrf(number, 0, decimals, b); print(b);
}

void GU7003::println(const char *text)
{
  print(text);
  setCursor(0, 8);
}
