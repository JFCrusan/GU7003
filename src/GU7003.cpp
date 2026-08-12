#include "GU7003.h"
#include <avr/pgmspace.h>

GU7003::GU7003(uint8_t resetPin, uint8_t busyPin)
{
  _resetPin = resetPin;
  _busyPin = busyPin;
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

  clear();
  cursorOff();
  setBrightness(8);
  setFontSize(1, 1);
  setCharacterSpacing(1);
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

void GU7003::screenMode(uint8_t mode)
{
  write(0x1F); write(0x28); write(0x61); write(0x40); write(mode);
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
  if (x >= DISPLAY_WIDTH) return;
  if ((uint16_t)x + width > DISPLAY_WIDTH) width = DISPLAY_WIDTH - x;

  beginNativeBitmap(x, width, heightBytes);

  uint16_t count = (uint16_t)width * heightBytes;
  for (uint16_t i = 0; i < count; i++) write(data[i]);
}

void GU7003::drawBitmapNative_P(uint16_t x, uint8_t width,
                                uint8_t heightBytes, const uint8_t *data)
{
  if (!data || width == 0 || heightBytes == 0 || heightBytes > 2) return;
  if (x >= DISPLAY_WIDTH) return;
  if ((uint16_t)x + width > DISPLAY_WIDTH) width = DISPLAY_WIDTH - x;

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
